package bridge

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
	"golang.org/x/net/proxy"
)

// No cloud account is used: encrypted VLESS + Mux moves an actual HTTP response
// over xdrive's local-storage provider, exercising the complete data path.
func TestXDriveEncryptedVlessRoundTrip(t *testing.T) {
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	encode := base64.RawURLEncoding.EncodeToString
	folder := t.TempDir()
	stream := map[string]any{"network": "xdrive", "security": "none", "xdriveSettings": map[string]any{
		"service": "local", "remoteFolder": folder, "flushIntervalMs": 5, "pollIntervalMs": 5, "maxPollIntervalMs": 25,
	}}
	id := "11111111-1111-4111-8111-111111111111"
	serverConfig, _ := json.Marshal(map[string]any{
		"log": map[string]any{"loglevel": "none"},
		"inbounds": []any{map[string]any{"listen": "127.0.0.1", "port": unusedPort(t), "protocol": "vless",
			"settings": map[string]any{"decryption": "mlkem768x25519plus.native.600s." + encode(key.Bytes()), "clients": []any{map[string]any{"id": id}}}, "streamSettings": stream}},
		"outbounds": []any{map[string]any{"protocol": "freedom", "settings": map[string]any{"finalRules": []any{map[string]any{"action": "allow", "ip": []string{"127.0.0.1/32"}}}}}},
	})
	cfg, err := serial.LoadJSONConfig(strings.NewReader(string(serverConfig)))
	if err != nil {
		t.Fatal(err)
	}
	server, err := core.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	if err := server.Start(); err != nil {
		t.Fatal(err)
	}
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "fcxray-xdrive-ok") }))
	defer target.Close()
	port := unusedPort(t)
	clientConfig, _ := json.Marshal(map[string]any{
		"log":      map[string]any{"loglevel": "none"},
		"inbounds": []any{map[string]any{"listen": "127.0.0.1", "port": port, "protocol": "socks"}},
		"outbounds": []any{map[string]any{"tag": "proxy", "protocol": "vless", "settings": map[string]any{
			"address": "127.0.0.1", "port": 443, "id": id, "encryption": "mlkem768x25519plus.native.0rtt." + encode(key.PublicKey().Bytes()),
		}, "streamSettings": stream, "mux": map[string]any{"enabled": true, "concurrency": 128}}},
	})
	if err := Start(string(clientConfig), -1, nil); err != nil {
		t.Fatal(err)
	}
	defer Stop()
	dialer, err := proxy.SOCKS5("tcp", fmt.Sprintf("127.0.0.1:%d", port), nil, proxy.Direct)
	if err != nil {
		t.Fatal(err)
	}
	transport := &http.Transport{Dial: dialer.Dial, DisableKeepAlives: true}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 20 * time.Second}
	response, err := client.Get(target.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil || string(body) != "fcxray-xdrive-ok" {
		t.Fatalf("body %q, error %v", body, err)
	}
}
