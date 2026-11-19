package bridge

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

// A synthetic HTTP proxy supplies the tunneled 204 response. The target name
// cannot resolve directly, so success proves the selected outbound was used.
func TestLatencyThroughCandidate(t *testing.T) {
	var hits atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect || r.Host != "probe.invalid:80" {
			http.Error(w, "wrong destination", 400)
			return
		}
		hits.Add(1)
		conn, rw, err := w.(http.Hijacker).Hijack()
		if err != nil {
			return
		}
		defer conn.Close()
		fmt.Fprint(rw, "HTTP/1.1 200 Connection established\r\n\r\n")
		rw.Flush()
		if _, err := http.ReadRequest(rw.Reader); err == nil {
			fmt.Fprint(rw, "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
			rw.Flush()
		}
	}))
	defer server.Close()
	address := server.Listener.Addr().(*net.TCPAddr)
	out, _ := json.Marshal(map[string]any{"protocol": "http", "settings": map[string]any{"address": "127.0.0.1", "port": address.Port}})
	ms, err := probeURL(string(out), "http://probe.invalid/path")
	if err != nil || ms < 1 || hits.Load() != 1 {
		t.Fatalf("ms=%d, hits=%d, err=%v", ms, hits.Load(), err)
	}
}
