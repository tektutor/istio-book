// tenant-check: the Go version of the Rust plugin in ../tenant-rust.
//
// Every request must carry a tenant header, x-tenant by default, with one
// of the tenants from the plugin configuration. A request without it gets
// 400, a request with an unknown tenant gets 403, and the tenant is copied
// into the response header x-tenant-checked. Two counters count the
// rejections.
//
// Plugin configuration (JSON):
//
//	{"header": "x-tenant", "tenants": ["acme", "globex"]}
package main

import (
	"encoding/json"
	"slices"

	"github.com/proxy-wasm/proxy-wasm-go-sdk/proxywasm"
	"github.com/proxy-wasm/proxy-wasm-go-sdk/proxywasm/types"
)

type config struct {
	Header  string   `json:"header"`
	Tenants []string `json:"tenants"`
}

func main() {}

func init() { // (1)
	proxywasm.SetPluginContext(func(uint32) types.PluginContext {
		return &plugin{}
	})
}

// plugin reads the configuration and creates an HTTP context for each
// request.
type plugin struct {
	types.DefaultPluginContext
	cfg     config
	missing proxywasm.MetricCounter
	unknown proxywasm.MetricCounter
}

func (p *plugin) OnPluginStart(int) types.OnPluginStartStatus { // (2)
	p.missing = proxywasm.DefineCounterMetric("tenant_check.missing") // (3)
	p.unknown = proxywasm.DefineCounterMetric("tenant_check.unknown")
	data, err := proxywasm.GetPluginConfiguration()
	if err != nil {
		proxywasm.LogError("no configuration")
		return types.OnPluginStartStatusFailed
	}
	p.cfg = config{Header: "x-tenant"}
	if err := json.Unmarshal(data, &p.cfg); err != nil {
		proxywasm.LogErrorf("bad configuration: %v", err)
		return types.OnPluginStartStatusFailed // (4)
	}
	return types.OnPluginStartStatusOK
}

func (p *plugin) NewHttpContext(uint32) types.HttpContext {
	return &request{plugin: p}
}

// request is one HTTP context per request.
type request struct {
	types.DefaultHttpContext
	plugin *plugin
	tenant string
}

func (r *request) reject(status uint32, reason string,
	m proxywasm.MetricCounter) types.Action {
	m.Increment(1)
	body := []byte(`{"error": "` + reason + `"}` + "\n")
	proxywasm.SendHttpResponse(status, // (5)
		[][2]string{{"content-type", "application/json"}}, body, -1)
	return types.ActionPause
}

func (r *request) OnHttpRequestHeaders(int, bool) types.Action {
	t, err := proxywasm.GetHttpRequestHeader(r.plugin.cfg.Header)
	switch {
	case err != nil:
		return r.reject(400, "missing tenant header", r.plugin.missing)
	case !slices.Contains(r.plugin.cfg.Tenants, t):
		return r.reject(403, "unknown tenant", r.plugin.unknown)
	}
	r.tenant = t
	return types.ActionContinue // (6)
}

func (r *request) OnHttpResponseHeaders(int, bool) types.Action {
	if r.tenant != "" {
		proxywasm.ReplaceHttpResponseHeader("x-tenant-checked", r.tenant)
	}
	return types.ActionContinue
}
