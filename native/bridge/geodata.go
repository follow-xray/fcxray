package bridge

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/xtls/xray-core/common/geodata"
	"google.golang.org/protobuf/proto"
)

const maxGeoBytes = 64 * 1024 * 1024

// InspectGeo validates the actual protobuf contents, not just the filename.
// Files are staged by the UI and only installed after this check succeeds.
func InspectGeo(kind, path string) (string, error) {
	if kind != "geoip" && kind != "geosite" {
		return "", errors.New("unknown geodata type")
	}
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() || info.Size() == 0 || info.Size() > maxGeoBytes {
		return "", errors.New("geodata must be a regular file between 1 byte and 64 MiB")
	}
	data, err := io.ReadAll(io.LimitReader(file, maxGeoBytes+1))
	if err != nil {
		return "", err
	}
	if len(data) > maxGeoBytes {
		return "", errors.New("geodata exceeds 64 MiB")
	}
	tags := make([]string, 0)
	seen := map[string]bool{}
	add := func(code string) error {
		code = strings.ToLower(code)
		if code == "" || len(code) > 128 || seen[code] {
			return errors.New("invalid or duplicate geodata category")
		}
		seen[code] = true
		tags = append(tags, code)
		if len(tags) > 20000 {
			return errors.New("too many geodata categories")
		}
		return nil
	}
	entries := 0
	if kind == "geoip" {
		var list geodata.GeoIPList
		if err := proto.Unmarshal(data, &list); err != nil {
			return "", fmt.Errorf("invalid GeoIP protobuf: %w", err)
		}
		for _, entry := range list.Entry {
			if err := add(entry.Code); err != nil {
				return "", err
			}
			for _, cidr := range entry.Cidr {
				bits := len(cidr.Ip) * 8
				if (bits != 32 && bits != 128) || cidr.Prefix > uint32(bits) {
					return "", errors.New("invalid GeoIP CIDR")
				}
				entries++
			}
		}
	} else {
		var list geodata.GeoSiteList
		if err := proto.Unmarshal(data, &list); err != nil {
			return "", fmt.Errorf("invalid GeoSite protobuf: %w", err)
		}
		for _, entry := range list.Entry {
			if err := add(entry.Code); err != nil {
				return "", err
			}
			for _, domain := range entry.Domain {
				if domain.Value == "" || domain.Type < 0 || domain.Type > 3 {
					return "", errors.New("invalid GeoSite domain")
				}
				entries++
			}
		}
	}
	if len(tags) == 0 || entries == 0 {
		return "", errors.New("empty or wrong-type geodata file")
	}
	sort.Strings(tags)
	sum := sha256.Sum256(data)
	result, _ := json.Marshal(map[string]any{"kind": kind, "size": len(data), "sha256": hex.EncodeToString(sum[:]), "tags": tags, "entries": entries})
	return string(result), nil
}

func setAssetDirectory(path string) error {
	if path == "" {
		return os.Unsetenv("XRAY_LOCATION_ASSET")
	}
	if !filepath.IsAbs(path) {
		return errors.New("asset directory must be absolute")
	}
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return errors.New("asset path is not a directory")
	}
	return os.Setenv("XRAY_LOCATION_ASSET", path)
}

// Configuration is the exact JSON accepted by the current running session.
func Configuration() string {
	lifecycle.Lock()
	defer lifecycle.Unlock()
	id := ""
	if instance != nil {
		id = strconv.FormatInt(started.UnixNano(), 10)
	}
	result, _ := json.Marshal(map[string]any{"running": instance != nil, "config": activeConfig, "assetDirectory": activeAssets, "sessionId": id})
	return string(result)
}
