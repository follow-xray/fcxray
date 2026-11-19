package bridge

import (
	"encoding/json"
	"errors"
	"os"
	"reflect"
	"strconv"

	"github.com/xtls/xray-core/common/serial"
	"github.com/xtls/xray-core/features/routing"
	"github.com/xtls/xray-core/infra/conf"
)

// ApplyRules only accepts a replacement routing table for the same session.
// Xray builds every condition before atomically publishing the new rule list.
func ApplyRules(request, assets string) error {
	lifecycle.Lock()
	defer lifecycle.Unlock()
	var update struct {
		Session string
		Config  string
	}
	if err := json.Unmarshal([]byte(request), &update); err != nil {
		return err
	}
	if instance == nil || update.Session != strconv.FormatInt(started.UnixNano(), 10) {
		return errors.New("VPN session has changed")
	}
	if err := validateInput(update.Config); err != nil {
		return err
	}
	var current, next map[string]any
	if err := json.Unmarshal([]byte(activeConfig), &current); err != nil {
		return err
	}
	if err := json.Unmarshal([]byte(update.Config), &next); err != nil {
		return err
	}
	oldTable, _ := current["routing"].(map[string]any)
	table, ok := next["routing"].(map[string]any)
	if !ok || table["domainStrategy"] != oldTable["domainStrategy"] || len(table) != 2 {
		return errors.New("only the active rule list can be replaced")
	}
	if _, ok := table["rules"].([]any); !ok {
		return errors.New("missing rules")
	}
	delete(current, "routing")
	delete(next, "routing")
	if !reflect.DeepEqual(current, next) {
		return errors.New("outbounds and inbounds must match the running session")
	}
	feature, ok := instance.GetFeature(routing.RouterType()).(routing.Router)
	if !ok {
		return errors.New("active router unavailable")
	}
	raw, err := json.Marshal(table)
	if err != nil {
		return err
	}
	var cfg conf.RouterConfig
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return err
	}
	if assets != "" && activeAssets != "" && assets != activeAssets {
		return errors.New("unexpected asset directory")
	}
	previous, existed := os.LookupEnv("XRAY_LOCATION_ASSET")
	committed := false
	if assets != "" && activeAssets == "" {
		if err := setAssetDirectory(assets); err != nil {
			return err
		}
		defer func() {
			if !committed {
				if existed {
					_ = os.Setenv("XRAY_LOCATION_ASSET", previous)
				} else {
					_ = os.Unsetenv("XRAY_LOCATION_ASSET")
				}
			}
		}()
	}
	built, err := cfg.Build()
	if err != nil {
		return err
	}
	if err := feature.AddRule(serial.ToTypedMessage(built), false); err != nil {
		return err
	}
	committed = true
	activeConfig = update.Config
	if assets != "" {
		activeAssets = assets
	}
	return nil
}
