package bridge

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/xtls/xray-core/common/geodata"
	"google.golang.org/protobuf/proto"
)

func writeGeoFixture(t *testing.T, dir, name string, data proto.Message) string {
	t.Helper()
	bytes, err := proto.Marshal(data)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, bytes, 0600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestGeoValidationAndConfigLoading(t *testing.T) {
	dir := t.TempDir()
	ip := writeGeoFixture(t, dir, "geoip-test.dat", &geodata.GeoIPList{Entry: []*geodata.GeoIP{{Code: "TEST", Cidr: []*geodata.CIDR{{Ip: []byte{192, 0, 2, 0}, Prefix: 24}}}}})
	site := writeGeoFixture(t, dir, "geosite-test.dat", &geodata.GeoSiteList{Entry: []*geodata.GeoSite{{Code: "TEST", Domain: []*geodata.Domain{{Type: geodata.Domain_Full, Value: "example.com"}}}}})
	for kind, path := range map[string]string{"geoip": ip, "geosite": site} {
		value, err := InspectGeo(kind, path)
		if err != nil {
			t.Fatal(err)
		}
		var parsed struct {
			Kind    string
			Tags    []string
			Entries int
			SHA256  string
		}
		if err := json.Unmarshal([]byte(value), &parsed); err != nil {
			t.Fatal(err)
		}
		if parsed.Kind != kind || parsed.Entries != 1 || len(parsed.Tags) != 1 || parsed.Tags[0] != "test" || len(parsed.SHA256) != 64 {
			t.Fatal(value)
		}
	}
	for kind, path := range map[string]string{"geosite": ip, "geoip": site} {
		if _, err := InspectGeo(kind, path); err == nil {
			t.Fatalf("accepted wrong type: %s", kind)
		}
	}
	config := `{"log":{"loglevel":"none"},"outbounds":[{"tag":"direct","protocol":"freedom"}],"routing":{"rules":[{"type":"field","ip":["ext:geoip-test.dat:test"],"outboundTag":"direct"},{"type":"field","domain":["ext:geosite-test.dat:test"],"outboundTag":"direct"}]}}`
	if err := ValidateWithAssets(config, dir); err != nil {
		t.Fatal(err)
	}
	if err := StartWithAssets(config, -1, nil, dir); err != nil {
		t.Fatal(err)
	}
	defer Stop()
	// Validating a prospective configuration must not replace the running snapshot.
	if err := Validate(`{"outbounds":[{"protocol":"freedom"}]}`); err != nil {
		t.Fatal(err)
	}
	var snapshot struct {
		Running                bool
		Config, AssetDirectory string
	}
	if err := json.Unmarshal([]byte(Configuration()), &snapshot); err != nil {
		t.Fatal(err)
	}
	if !snapshot.Running || snapshot.Config != config || snapshot.AssetDirectory != dir {
		t.Fatal(Configuration())
	}
	if err := Stop(); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal([]byte(Configuration()), &snapshot); err != nil {
		t.Fatal(err)
	}
	if snapshot.Running || snapshot.Config != "" {
		t.Fatal("stale running config exposed")
	}
}

func TestGeoRejectsBrokenAndEmptyData(t *testing.T) {
	for _, value := range [][]byte{nil, []byte("<html>not a database</html>"), {0x0a, 0xff}} {
		path := filepath.Join(t.TempDir(), "bad.dat")
		if err := os.WriteFile(path, value, 0600); err != nil {
			t.Fatal(err)
		}
		for _, kind := range []string{"geoip", "geosite"} {
			if _, err := InspectGeo(kind, path); err == nil {
				t.Fatal("invalid data accepted")
			}
		}
	}
}
