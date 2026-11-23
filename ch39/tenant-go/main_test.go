// Unit tests for the tenant check. proxytest emulates Envoy's side of
// Proxy-Wasm, so the tests run with "go test", without Envoy.
package main

import (
	"testing"

	"github.com/proxy-wasm/proxy-wasm-go-sdk/proxywasm/proxytest"
	"github.com/proxy-wasm/proxy-wasm-go-sdk/proxywasm/types"
)

const good = `{"header": "x-tenant", "tenants": ["acme", "globex"]}`

func newHost(config string) (proxytest.HostEmulator, func()) {
	factory := func(uint32) types.PluginContext { return &plugin{} }
	opt := proxytest.NewEmulatorOption().WithPluginContext(factory) // (1)
	opt = opt.WithPluginConfiguration([]byte(config))
	return proxytest.NewHostEmulator(opt)
}

func TestRequests(t *testing.T) {
	cases := []struct {
		name    string
		headers [][2]string
		status  uint32 // 0: the request continues
		counter string
	}{
		{"no header", nil, 400, "tenant_check.missing"},
		{"known tenant", [][2]string{{"x-tenant", "acme"}}, 0, ""},
		{"unknown tenant", [][2]string{{"x-tenant", "evil"}}, 403,
			"tenant_check.unknown"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			host, reset := newHost(good)
			defer reset()
			if host.StartPlugin() != types.OnPluginStartStatusOK {
				t.Fatal("plugin did not start")
			}
			id := host.InitializeHttpContext()
			action := host.CallOnRequestHeaders(id, c.headers, false) // (2)
			reply := host.GetSentLocalResponse(id)
			if c.status == 0 {
				if action != types.ActionContinue || reply != nil {
					t.Fatalf("want continue, got %v %v", action, reply)
				}
				host.CallOnResponseHeaders(id, nil, false)
				got := host.GetCurrentResponseHeaders(id)
				if len(got) != 1 || got[0][1] != "acme" { // (3)
					t.Fatalf("want x-tenant-checked: acme, got %v", got)
				}
				return
			}
			if reply == nil || reply.StatusCode != c.status {
				t.Fatalf("want status %d, got %v", c.status, reply)
			}
			if n, _ := host.GetCounterMetric(c.counter); n != 1 { // (4)
				t.Fatalf("want %s = 1, got %d", c.counter, n)
			}
		})
	}
}

func TestBadConfiguration(t *testing.T) {
	host, reset := newHost(`{"tenants": "acme"}`)
	defer reset()
	if host.StartPlugin() != types.OnPluginStartStatusFailed { // (5)
		t.Fatal("plugin started with a bad configuration")
	}
}
