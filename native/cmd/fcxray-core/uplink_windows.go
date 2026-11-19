package main

import "github.com/xtls/xray-core/proxy/tun"

// Referencing the overlay's hook also makes a Windows build without the
// session-safe TUN implementation fail at compile time.
var uplinkConflict = tun.FcxrayUplinkConflict
