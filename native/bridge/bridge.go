// Package bridge embeds the unmodified Xray core. Its API is gomobile compatible.
package bridge

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	applog "github.com/xtls/xray-core/app/log"
	clog "github.com/xtls/xray-core/common/log"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
	"github.com/xtls/xray-core/transport/internet"
)

// Protector keeps Android outbound sockets outside VpnService's TUN routes.
type Protector interface{ Protect(fd int) bool }

var lifecycle sync.Mutex
var protection sync.RWMutex
var protector Protector
var instance *core.Instance
var started time.Time
var activeConfig, activeAssets string

func init() {
	// stdout belongs exclusively to the desktop JSON protocol.
	clog.RegisterHandler(clog.NewLogger(clog.CreateStderrLogWriter()))
	_ = applog.RegisterHandlerCreator(applog.LogType_Console, func(_ applog.LogType, _ applog.HandlerCreatorOptions) (clog.Handler, error) {
		return clog.NewLogger(clog.CreateStderrLogWriter()), nil
	})
	_ = internet.RegisterDialerController(func(_, _ string, c syscall.RawConn) error {
		protection.RLock()
		p := protector
		protection.RUnlock()
		if p == nil {
			return nil
		}
		var protectErr error
		if err := c.Control(func(fd uintptr) {
			if !p.Protect(int(fd)) {
				protectErr = errors.New("VPN socket protection failed")
			}
		}); err != nil {
			return err
		}
		return protectErr
	})
}

func Version() string { return core.Version() }

// Validate builds the protobuf configuration without opening listeners or a TUN.
func validateInput(config string) error {
	if len(config) > 1024*1024 {
		return errors.New("configuration exceeds 1 MiB")
	}
	var value any
	if err := json.Unmarshal([]byte(config), &value); err != nil {
		return err
	}
	var check func(any) error
	check = func(value any) error {
		switch v := value.(type) {
		case map[string]any:
			for key, child := range v {
				lower := strings.ToLower(key)
				// Imported node configurations may not execute scripts or read
				// files in an administrator helper's security context.
				if lower == "script" || lower == "masterkeylog" || strings.HasSuffix(lower, "file") {
					return fmt.Errorf("external file/script setting %q is not supported", key)
				}
				if lower == "allowinsecure" && child == true {
					return errors.New("TLS verification cannot be disabled")
				}
				if err := check(child); err != nil {
					return err
				}
			}
		case []any:
			for _, child := range v {
				if err := check(child); err != nil {
					return err
				}
			}
		}
		return nil
	}
	return check(value)
}

func Validate(config string) error { return ValidateWithAssets(config, "") }

func ValidateWithAssets(config, assetDirectory string) error {
	lifecycle.Lock()
	defer lifecycle.Unlock()
	if err := validateInput(config); err != nil {
		return err
	}
	if instance != nil {
		if assetDirectory != "" && assetDirectory != activeAssets {
			return errors.New("cannot switch asset directory while running")
		}
		_, err := serial.LoadJSONConfig(strings.NewReader(config))
		return err
	}
	previous, exists := os.LookupEnv("XRAY_LOCATION_ASSET")
	if err := setAssetDirectory(assetDirectory); err != nil {
		return err
	}
	defer func() {
		if exists {
			_ = os.Setenv("XRAY_LOCATION_ASSET", previous)
		} else {
			_ = os.Unsetenv("XRAY_LOCATION_ASSET")
		}
	}()
	_, err := serial.LoadJSONConfig(strings.NewReader(config))
	return err
}

// Start must be paired with Stop. A negative fd selects desktop native TUN mode.
// The Android caller retains ownership of fd; Xray duplicates it internally.
func Start(config string, fd int, p Protector) error { return StartWithAssets(config, fd, p, "") }

func StartWithAssets(config string, fd int, p Protector, assetDirectory string) error {
	lifecycle.Lock()
	defer lifecycle.Unlock()
	if instance != nil {
		return errors.New("core is already running")
	}
	if fd >= 0 && p == nil {
		return errors.New("Android TUN requires socket protection")
	}
	if err := validateInput(config); err != nil {
		return err
	}
	if err := setAssetDirectory(assetDirectory); err != nil {
		return err
	}
	cfg, err := serial.LoadJSONConfig(strings.NewReader(config))
	if err != nil {
		return fmt.Errorf("invalid configuration: %w", err)
	}
	if fd >= 0 {
		if err := os.Setenv("XRAY_TUN_FD", strconv.Itoa(fd)); err != nil {
			return err
		}
	} else {
		_ = os.Unsetenv("XRAY_TUN_FD")
	}
	protection.Lock()
	protector = p
	protection.Unlock()
	i, err := core.New(cfg)
	if err == nil {
		err = i.Start()
	}
	if err != nil {
		if i != nil {
			_ = i.Close()
		}
		protection.Lock()
		protector = nil
		protection.Unlock()
		_ = os.Unsetenv("XRAY_TUN_FD")
		return fmt.Errorf("start Xray: %w", err)
	}
	instance, started = i, time.Now()
	activeConfig, activeAssets = config, assetDirectory
	return nil
}

func Stop() error {
	lifecycle.Lock()
	defer lifecycle.Unlock()
	var err error
	if instance != nil {
		err = instance.Close()
		instance = nil
	}
	activeConfig, activeAssets = "", ""
	protection.Lock()
	protector = nil
	protection.Unlock()
	_ = os.Unsetenv("XRAY_TUN_FD")
	return err
}

// Snapshot returns monotonically increasing session counters, not fabricated speed.
func Snapshot() string {
	lifecycle.Lock()
	defer lifecycle.Unlock()
	result := map[string]any{"running": instance != nil, "version": Version(), "upload": int64(0), "download": int64(0), "uptime": int64(0), "sessionId": ""}
	if instance != nil {
		result["uptime"] = int64(time.Since(started).Seconds())
		result["sessionId"] = strconv.FormatInt(started.UnixNano(), 10)
		if manager, ok := instance.GetFeature(stats.ManagerType()).(stats.Manager); ok {
			for key, suffix := range map[string]string{"upload": "uplink", "download": "downlink"} {
				// Count at app-owned inbounds. Some upstream transport fast
				// paths bypass outbound counters for the first payload.
				var total int64
				for _, tag := range []string{"tun-in", "socks-in", "http-in"} {
					if counter := manager.GetCounter("inbound>>>" + tag + ">>>traffic>>>" + suffix); counter != nil {
						total += counter.Value()
					}
				}
				result[key] = total
			}
		}
	}
	b, _ := json.Marshal(result)
	return string(b)
}
