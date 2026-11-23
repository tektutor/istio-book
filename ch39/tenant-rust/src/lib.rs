//! tenant-check: a Proxy-Wasm HTTP filter for Envoy and Istio.
//!
//! Every request must carry a tenant header, x-tenant by default, with one
//! of the tenants from the plugin configuration. A request without it gets
//! 400, a request with an unknown tenant gets 403, and the tenant is copied
//! into the response header x-tenant-checked. Two counters count the
//! rejections.
//!
//! Plugin configuration (JSON):
//!   {"header": "x-tenant", "tenants": ["acme", "globex"]}

use proxy_wasm::traits::{Context, HttpContext, RootContext};
use proxy_wasm::types::{Action, ContextType, LogLevel, MetricType};
use serde::Deserialize;
use std::rc::Rc;

#[derive(Deserialize)]
struct Config {
    #[serde(default = "default_header")]
    header: String,
    tenants: Vec<String>,
}

fn default_header() -> String {
    "x-tenant".to_string()
}

proxy_wasm::main! {{                                            // (1)
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
        Box::new(Root { config: None, missing: 0, unknown: 0 })
    });
}}

/// One root context per plugin and worker thread: it reads the
/// configuration and creates an HTTP context for each request.
struct Root {
    config: Option<Rc<Config>>,
    missing: u32,
    unknown: u32,
}

impl Context for Root {}

impl RootContext for Root {
    fn on_configure(&mut self, _size: usize) -> bool {             // (2)
        let Some(bytes) = self.get_plugin_configuration() else {
            proxy_wasm::hostcalls::log(LogLevel::Error, "no configuration").ok();
            return false;
        };
        match serde_json::from_slice::<Config>(&bytes) {
            Ok(c) => {
                self.config = Some(Rc::new(c));
                self.missing = proxy_wasm::hostcalls::define_metric( // (3)
                    MetricType::Counter, "tenant_check.missing").unwrap();
                self.unknown = proxy_wasm::hostcalls::define_metric(
                    MetricType::Counter, "tenant_check.unknown").unwrap();
                true
            }
            Err(e) => {
                proxy_wasm::hostcalls::log(LogLevel::Error,
                    &format!("bad configuration: {e}")).ok();
                false                                               // (4)
            }
        }
    }

    fn create_http_context(&self, _id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(Request {
            config: self.config.clone()?,
            missing: self.missing,
            unknown: self.unknown,
            tenant: None,
        }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

/// One HTTP context per request.
struct Request {
    config: Rc<Config>,
    missing: u32,
    unknown: u32,
    tenant: Option<String>,
}

impl Request {
    fn reject(&self, status: u32, reason: &str, metric: u32) -> Action {
        proxy_wasm::hostcalls::increment_metric(metric, 1).ok();
        let body = format!("{{\"error\": \"{reason}\"}}\n");
        self.send_http_response(                                    // (5)
            status,
            vec![("content-type", "application/json")],
            Some(body.as_bytes()),
        );
        Action::Pause
    }
}

impl Context for Request {}

impl HttpContext for Request {
    fn on_http_request_headers(&mut self, _n: usize, _eos: bool) -> Action {
        match self.get_http_request_header(&self.config.header) {
            None => self.reject(400, "missing tenant header", self.missing),
            Some(t) if !self.config.tenants.contains(&t) => {
                self.reject(403, "unknown tenant", self.unknown)
            }
            Some(t) => {
                self.tenant = Some(t);
                Action::Continue                                    // (6)
            }
        }
    }

    fn on_http_response_headers(&mut self, _n: usize, _eos: bool) -> Action {
        if let Some(t) = &self.tenant {
            self.set_http_response_header("x-tenant-checked", Some(t));
        }
        Action::Continue
    }
}
