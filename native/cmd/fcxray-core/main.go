// fcxray-core is a private stdio / macOS Unix-socket supervisor. No control TCP port is exposed.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/follow-xray/fcxray/native/bridge"
)

type request struct {
	ID             int    `json:"id"`
	Method         string `json:"method"`
	Config         string `json:"config"`
	AssetDirectory string `json:"assetDirectory"`
}

func main() {
	if len(os.Args) == 2 && os.Args[1] == "--version" {
		fmt.Println(bridge.Version())
		return
	}
	var input io.Reader = os.Stdin
	var output io.Writer = os.Stdout
	if len(os.Args) == 3 && os.Args[1] == "--socket" {
		// The GUI owns a socket in a freshly created 0700 directory. The
		// privileged helper only connects: it never creates/chowns user paths.
		connection, err := net.DialTimeout("unix", os.Args[2], 10*time.Second)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		defer connection.Close()
		input, output = connection, connection
	} else if len(os.Args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: fcxray-core [--version | --socket path]")
		os.Exit(2)
	}
	supervise(input, output)
}

func supervise(input io.Reader, output io.Writer) {
	// A broken reply pipe must allow the normal TUN cleanup path to run.
	signal.Ignore(syscall.SIGPIPE)
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(signals)

	requests := make(chan string)
	disconnected := make(chan struct{})
	go func() {
		defer close(disconnected)
		defer close(requests)
		scanner := bufio.NewScanner(input)
		scanner.Buffer(make([]byte, 64*1024), 2*1024*1024)
		for scanner.Scan() {
			requests <- scanner.Text()
		}
		if err := scanner.Err(); err != nil {
			fmt.Fprintln(os.Stderr, err)
		}
	}()

	finished := make(chan struct{})
	go func(finished chan struct{}) {
		defer close(finished)
		defer bridge.Stop()
		handleRequests(requests, output)
	}(finished)
	select {
	case <-finished:
		return
	case <-disconnected:
		// Detect parent death even if the one outstanding IPC request is
		// blocked inside Xray. Give it a short window to finish and clean up.
	case <-signals:
		finished = stopSession()
	case err := <-uplinkConflict:
		fmt.Fprintln(os.Stderr, err)
		finished = stopSession()
	}
	select {
	case <-finished:
	case <-time.After(6 * time.Second):
		// Returning from main releases process-owned device and WFP handles.
	}
}

func stopSession() chan struct{} {
	done := make(chan struct{})
	go func() {
		defer close(done)
		_ = bridge.Stop()
	}()
	return done
}

func handleRequests(requests <-chan string, output io.Writer) {
	encoder := json.NewEncoder(output)
	for line := range requests {
		var req request
		if err := json.Unmarshal([]byte(line), &req); err != nil {
			_ = encoder.Encode(map[string]any{"id": 0, "error": "invalid request"})
			continue
		}
		var err error
		var payload string
		switch req.Method {
		case "probe":
			var ms int64
			ms, err = bridge.Probe(req.Config)
			if err == nil {
				payload = fmt.Sprintf(`{"ms":%d}`, ms)
			} else {
				err = fmt.Errorf("latency probe failed")
			}
		case "start":
			err = bridge.StartWithAssets(req.Config, -1, nil, req.AssetDirectory)
		case "stop":
			err = bridge.Stop()
		case "applyRules":
			err = bridge.ApplyRules(req.Config, req.AssetDirectory)
		case "validate":
			err = bridge.ValidateWithAssets(req.Config, req.AssetDirectory)
		case "config":
			payload = bridge.Configuration()
		case "geo":
			var input struct {
				Kind string `json:"kind"`
				Path string `json:"path"`
			}
			if err = json.Unmarshal([]byte(req.Config), &input); err == nil {
				payload, err = bridge.InspectGeo(input.Kind, input.Path)
			}
		case "status":
		default:
			err = fmt.Errorf("unknown method: %s", req.Method)
		}
		response := map[string]any{"id": req.ID}
		if err != nil {
			response["error"] = err.Error()
		} else {
			if payload == "" {
				payload = bridge.Snapshot()
			}
			response["result"] = json.RawMessage(payload)
		}
		if encoder.Encode(response) != nil {
			return
		}
	}
}
