// Tracing in the browser, for frontend 1.1. Every fetch() to the shop's
// own host carries a W3C traceparent header, and the browser's spans go
// to /v1/traces on the same host, which the gateway passes to Jaeger.
import { trace } from "@opentelemetry/api";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { registerInstrumentations } from "@opentelemetry/instrumentation";
import { FetchInstrumentation } from "@opentelemetry/instrumentation-fetch";
import { resourceFromAttributes } from "@opentelemetry/resources";
import {
  BatchSpanProcessor,
  WebTracerProvider,
} from "@opentelemetry/sdk-trace-web";
import { ATTR_SERVICE_NAME } from "@opentelemetry/semantic-conventions";

const provider = new WebTracerProvider({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: "shop-frontend",                    // (1)
  }),
  spanProcessors: [
    new BatchSpanProcessor(
      new OTLPTraceExporter({ url: "/v1/traces" }),          // (2)
      { scheduledDelayMillis: 1000 },
    ),
  ],
});
provider.register();                                          // (3)

registerInstrumentations({
  instrumentations: [new FetchInstrumentation()],             // (4)
});

export const tracer = trace.getTracer("shop-frontend");
