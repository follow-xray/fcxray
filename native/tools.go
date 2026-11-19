//go:build tools

package tools

// Retain the exact gomobile/gobind runtime dependency across go mod tidy.
import _ "golang.org/x/mobile/bind"
