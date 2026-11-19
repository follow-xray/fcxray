package bridge

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"strings"
	"time"

	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
)

// Probe is called exclusively in a disposable desktop helper or Android's
// private :latency process. Never register its instances in the VPN lifecycle.
func Probe(outbound string) (int64, error) {
	return probeURL(outbound, "https://www.gstatic.com/generate_204")
}

func probeURL(outbound, url string) (int64, error) {
	if err := validateInput(outbound); err != nil {
		return 0, err
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(outbound), &out); err != nil {
		return 0, err
	}
	switch out["protocol"] {
	case "vless", "vmess", "trojan", "shadowsocks", "http", "socks", "wireguard", "hysteria", "masque":
	default:
		return 0, errors.New("not a remote outbound")
	}
	data, err := json.Marshal(map[string]any{"log": map[string]string{"loglevel": "none"}, "outbounds": []any{out}})
	if err != nil {
		return 0, err
	}
	config, err := serial.LoadJSONConfig(strings.NewReader(string(data)))
	if err != nil {
		return 0, err
	}
	isolated, err := core.New(config)
	if err != nil {
		return 0, err
	}
	defer isolated.Close()
	if err := isolated.Start(); err != nil {
		return 0, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	transport := &http.Transport{DisableKeepAlives: true, DialContext: func(_ context.Context, network, address string) (net.Conn, error) {
		dest, err := xnet.ParseDestination("tcp:" + address)
		if err != nil {
			return nil, err
		}
		return core.Dial(ctx, isolated, dest)
	}}
	defer transport.CloseIdleConnections()
	client := http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return 0, err
	}
	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 204 {
		return 0, errors.New("unexpected probe response")
	}
	return max(int64(1), time.Since(start).Milliseconds()), nil
}
