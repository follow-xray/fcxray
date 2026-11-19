package bridge

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"

	"golang.org/x/net/proxy"
)

func unusedPort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := l.Addr().(*net.TCPAddr).Port
	l.Close()
	return port
}

func TestCoreLifecycleAndRealSOCKSTraffic(t *testing.T) {
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "xray-data-path-ok") }))
	defer target.Close()
	port := unusedPort(t)
	config := fmt.Sprintf(`{"log":{"loglevel":"none"},"stats":{},"policy":{"system":{"statsInboundUplink":true,"statsInboundDownlink":true}},"inbounds":[{"tag":"socks-in","listen":"127.0.0.1","port":%d,"protocol":"socks","settings":{"auth":"noauth"}}],"outbounds":[{"tag":"proxy","protocol":"freedom"}]}`, port)
	if err := Validate(config); err != nil {
		t.Fatal(err)
	}
	for cycle := 0; cycle < 2; cycle++ {
		if err := Start(config, -1, nil); err != nil {
			t.Fatal(err)
		}
		if err := Start(config, -1, nil); err == nil {
			t.Fatal("duplicate start accepted")
		}
		dialer, err := proxy.SOCKS5("tcp", fmt.Sprintf("127.0.0.1:%d", port), nil, proxy.Direct)
		if err != nil {
			t.Fatal(err)
		}
		transport := &http.Transport{Dial: dialer.Dial, DisableKeepAlives: true}
		client := &http.Client{Transport: transport}
		response, err := client.Get(target.URL)
		if err != nil {
			Stop()
			t.Fatal(err)
		}
		body, err := io.ReadAll(response.Body)
		response.Body.Close()
		transport.CloseIdleConnections()
		if err != nil || string(body) != "xray-data-path-ok" {
			t.Fatalf("unexpected response: %q, %v", body, err)
		}
		var status struct {
			Running          bool
			Upload, Download int64
		}
		if err := json.Unmarshal([]byte(Snapshot()), &status); err != nil {
			t.Fatal(err)
		}
		if !status.Running || status.Upload == 0 || status.Download == 0 {
			t.Fatalf("invalid stats: %s", Snapshot())
		}
		if err := Stop(); err != nil {
			t.Fatal(err)
		}
		l, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
		if err != nil {
			t.Fatalf("listener leaked: %v", err)
		}
		l.Close()
	}
	if err := Stop(); err != nil {
		t.Fatal(err)
	}
}

func TestInvalidConfigCannotBecomeRunning(t *testing.T) {
	for _, config := range []string{"{", `{"inbounds":[{"protocol":"not-supported"}]}`} {
		if err := Start(config, -1, nil); err == nil {
			t.Fatal("invalid config accepted")
		}
	}
	if err := Start(`{}`, 5, nil); err == nil {
		t.Fatal("unprotected Android TUN accepted")
	}
	var result map[string]any
	json.Unmarshal([]byte(Snapshot()), &result)
	if result["running"] != false {
		t.Fatal("failure left running state")
	}
}

func TestImportedConfigCannotReadFilesOrRunScripts(t *testing.T) {
	for _, config := range []string{
		`{"outbounds":[{"streamSettings":{"finalmask":{"script":"/tmp/test.lua"}}}]}`,
		`{"outbounds":[{"streamSettings":{"tlsSettings":{"allowInsecure":true}}}]}`,
		`{"outbounds":[{"streamSettings":{"tlsSettings":{"certificates":[{"certificateFile":"/etc/private"}]}}}]}`,
	} {
		if err := Validate(config); err == nil {
			t.Fatal("unsafe import accepted")
		}
	}
}
