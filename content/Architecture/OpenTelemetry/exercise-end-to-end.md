---
title: OpenTelemetry End-to-End Exercise
description: "Instrument Golang order service and Python invoice service with OTel — traces, metrics, logs — flowing to SigNoz"
tags:
  - opentelemetry
  - exercise
  - golang
  - python
  - signoz
  - kubernetes
date: 2025-01-01
draft: false
---

# OpenTelemetry End-to-End Exercise

Go order service → Python invoice service via HTTP. OTel Agent sidecar. SigNoz as backend. All three signals (traces, metrics, logs) plus custom metrics.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  K8s Cluster                                                            │
│                                                                          │
│  ┌──────────────┐         ┌──────────────┐                               │
│  │ go-order-svc │────HTTP──▶│py-invoice-svc│                              │
│  │  (Golang)    │         │  (Python)    │                              │
│  └──────┬───────┘         └──────┬───────┘                               │
│         │                        │                                        │
│         ▼                        ▼                                        │
│  ┌──────────────┐         ┌──────────────┐                               │
│  │ OTel Agent   │         │ OTel Agent   │                               │
│  │ (sidecar)    │         │ (sidecar)    │                               │
│  │ :4317/:4318  │         │ :4317/:4318  │                               │
│  └──────┬───────┘         └──────┬───────┘                               │
│         └────────────┬───────────┘                                        │
│                      │                                                    │
│                      ▼                                                    │
│              ┌──────────────┐                                             │
│              │ OTel Gateway │ (Deployment)                                │
│              │  (Collector) │                                             │
│              └──────┬───────┘                                             │
│                     │ OTLP gRPC                                           │
└─────────────────────┼───────────────────────────────────────────────────┘
                      │
                      ▼
              ┌──────────────┐
              │   SigNoz     │
              │  (OTel-Stack)│
              │  HPA/certmgr │
              └──────────────┘
```

## Before: Base Services (No OTel)

### Go — Order Service (uninstrumented)

`order-service/main.go`
```go
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"
)

type Order struct {
    OrderID  string  `json:"order_id"`
    Amount   float64 `json:"amount"`
    Customer string  `json:"customer"`
}

func main() {
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
    })

    http.HandleFunc("/orders", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "POST only", http.StatusMethodNotAllowed)
            return
        }
        var order Order
        if err := json.NewDecoder(r.Body).Decode(&order); err != nil {
            http.Error(w, err.Error(), http.StatusBadRequest)
            return
        }

        log.Printf("ORDER RECEIVED: order_id=%s amount=%.2f customer=%s",
            order.OrderID, order.Amount, order.Customer)

        // Call invoice service
        resp, err := http.Post(
            fmt.Sprintf("http://invoice-service.default.svc.cluster.local:8080/invoice"),
            "application/json",
            bytes.NewBuffer([]byte(fmt.Sprintf(`{"order_id":"%s","amount":%.2f}`, order.OrderID, order.Amount))),
        )
        if err != nil {
            log.Printf("FAILURE: could not call invoice service: %v", err)
            w.WriteHeader(http.StatusInternalServerError)
            return
        }
        defer resp.Body.Close()
        log.Printf("INVOICE RESPONSE: status=%d", resp.StatusCode)

        w.WriteHeader(http.StatusCreated)
        json.NewEncoder(w).Encode(map[string]string{"status": "order placed"})
    })

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    log.Printf("Order service listening on :%s", port)
    log.Fatal(http.ListenAndServe(":"+port, nil))
}
```

### Python — Invoice Service (uninstrumented)

`invoice-service/app.py`
```python
import json
import logging
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("invoice-service")

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/invoice":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            data = json.loads(body)

            order_id = data.get("order_id")
            amount = data.get("amount")

            log.info(f"INVOICE GENERATED: order_id={order_id} amount={amount}")
            log.info(f"Invoice for customer on order {order_id}")

            self.send_response(201)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "invoice_created", "invoice_id": f"INV-{order_id}"}).encode())
        elif self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # suppress default logging

if __name__ == "__main__":
    port = os.environ.get("PORT", "8080")
    server = HTTPServer(("0.0.0.0", int(port)), Handler)
    log.info(f"Invoice service listening on :{port}")
    server.serve_forever()
```

### K8s Deployments (uninstrumented)

`k8s/base.yaml`
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: otel-demo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-order-service
  namespace: otel-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: go-order-service
  template:
    metadata:
      labels:
        app: go-order-service
    spec:
      containers:
        - name: order-service
          image: order-service:latest
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: PORT
              value: "8080"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: py-invoice-service
  namespace: otel-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: py-invoice-service
  template:
    metadata:
      labels:
        app: py-invoice-service
    spec:
      containers:
        - name: invoice-service
          image: invoice-service:latest
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: PORT
              value: "8080"
---
apiVersion: v1
kind: Service
metadata:
  name: invoice-service
  namespace: otel-demo
spec:
  selector:
    app: py-invoice-service
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: go-order-service
  namespace: otel-demo
spec:
  selector:
    app: go-order-service
  ports:
    - port: 8080
      targetPort: 8080
```

Save these as `order-service/`, `invoice-service/`, `k8s/base.yaml`. Confirm they work before adding OTel.

---

## Step 1 — SigNoz from Scratch

### Install SigNoz via Helm

```bash
# Add SigNoz Helm repo
helm repo add signoz https://charts.signoz.com
helm repo update

# Install the full otel-collector stack (OTLP receiver + Query frontend + Alertmanager)
helm install signoz signoz/otel-otel-stack \
  --namespace signoz \
  --create-namespace \
  --set otelCollector.enabled=true \
  --set otelCollector.config.mode=deployment \
  --set queryFrontend.enabled=true \
  --set alertmanager.enabled=true

# Wait for pods
kubectl get pods -n signoz -w
```

### Key SigNoz Components

```bash
kubectl get pods -n signoz
# NAME                                             READY
# signoz-otel-collector-0                          1/1     Running  ← OTLP receiver
# signoz-query-service-0                           1/1     Running  ← Query API
# signoz-frontend-6d9f4b8f9-xxxx                  1/1     Running
# signoz-alertmanager-0                           1/1     Running
```

### Expose the UI

```bash
# Port-forward to access SigNoz UI locally
kubectl port-forward -n signoz svc/signoz-frontend 3000:3301
# Open: http://localhost:3000
```

The OTLP receiver endpoint inside the cluster:

| Signal | Endpoint | Port |
|--------|----------|------|
| Traces + Metrics + Logs | `signoz-otel-collector.signoz.svc.cluster.local` | **4317** (gRPC) |
| HTTP/JSON | `signoz-otel-collector.signoz.svc.cluster.local` | **4318** (HTTP) |

Use `4317` (gRPC) for production. SigNoz accepts all three signals on the same OTLP endpoint.

### Verify SigNoz is Receiving Data

After instrumentation (Step 2–3), open the SigNoz UI at `http://localhost:3000`. You should see:

- **Application** tab: services appearing with traces
- **Traces** tab: spans from Go and Python services
- **Metrics** tab: custom metrics and SDK metrics
- **Logs** tab: correlated logs

---

## Step 2 — OTel Agent as Sidecar (DaemonSet mode)

Each node runs an OTel Agent. The agent receives OTLP from local pods, then forwards to SigNoz via the central gateway.

### OTel Agent ConfigMap

`k8s/otel-agent-cm.yaml`
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-agent-conf
  namespace: otel-demo
data:
  otel-config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch:
        timeout: 1s
        send_batch_size: 1024
    exporters:
      otlp:
        endpoint: signoz-otel-collector.signoz.svc.cluster.local:4317
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlp]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlp]
        logs:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlp]
```

### OTel Agent DaemonSet

`k8s/otel-agent-ds.yaml`
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-agent
  namespace: otel-demo
spec:
  selector:
    matchLabels:
      app: otel-agent
  template:
    metadata:
      labels:
        app: otel-agent
    spec:
      containers:
        - name: otel-agent
          image: otel/opentelemetry-collector-contrib:0.117.0
          args:
            - --config=/conf/otel-config.yaml
          ports:
            - containerPort: 4317
              name: otlp-grpc
              protocol: TCP
            - containerPort: 4318
              name: otlp-http
              protocol: TCP
          resources:
            limits:
              cpu: 250m
              memory: 512Mi
            requests:
              cpu: 50m
              memory: 128Mi
          volumeMounts:
            - name: otel-agent-config
              mountPath: /conf
      volumes:
        - name: otel-agent-config
          configMap:
            name: otel-agent-conf
```

Apply:

```bash
kubectl apply -f k8s/otel-agent-cm.yaml
kubectl apply -f k8s/otel-agent-ds.yaml
```

### How the App Finds the Agent

The agent runs on the same node as the pod. Use the node IP:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "$(NODE_IP):4317"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "grpc"
```

The OTel Operator auto-injects this correctly. Without the operator, use the Kubernetes downward API as shown in the manifest below.

---

## Step 3 — Go Order Service: Instrumented

### Required Packages

```bash
go get go.opentelemetry.io/otel \
  go.opentelemetry.io/otel/sdk \
  go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc \
  go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc \
  go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc \
  go.opentelemetry.io/otel/sdk/resource \
  go.opentelemetry.io/otel/semconv/v1.26.0 \
  go.opentelemetry.io/otel/propagation \
  go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp \
  go.opentelemetry.io/contrib/instrumentation/net/http/otelgrpc
```

### Instrumented Go Code

`order-service/main.go`
```go
package main

import (
    "bytes"
    "context"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"

    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
    "go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
    "go.opentelemetry.io/otel/metric"
    "go.opentelemetry.io/otel/propagation"
    "go.opentelemetry.io/otel/sdk/metric"
    "go.opentelemetry.io/otel/sdk/resource"
    "go.opentelemetry.io/otel/sdk/trace"
    logsdk "go.opentelemetry.io/otel/sdk/log"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

var (
    tracer           trace.Tracer
    meter            metric.Meter
    ordersCounter    metric.Int64Counter
    orderLatency     metric.Float64Histogram
    orderAmountGauge metric.Float64ObservableGauge
    currentAmount    float64

    logger          *log.Logger
    handler          logsdk.Handler
)

func initOTel(ctx context.Context) (func(), error) {
    // --- Tracing ---
    traceExporter, err := otlptracegrpc.New(ctx)
    if err != nil {
        return nil, fmt.Errorf("trace exporter: %w", err)
    }

    res, err := resource.New(ctx,
        resource.WithAttributes(
            semconv.ServiceName("order-service"),
            semconv.ServiceVersion("1.0.0"),
            attribute.String("environment", "production"),
        ),
    )
    if err != nil {
        return nil, fmt.Errorf("resource: %w", err)
    }

    tp := trace.NewTracerProvider(
        trace.WithBatcher(traceExporter),
        trace.WithResource(res),
        trace.WithSampler(trace.AlwaysSample()),
    )

    otel.SetTracerProvider(tp)
    otel.SetTextMapPropagator(propagation.NewCompositePropagator(
        propagation.TraceContext{},
        propagation.Baggage{},
    ))
    tracer = tp.Tracer("order-service")

    // --- Metrics ---
    metricExporter, err := otlpmetricgrpc.New(ctx)
    if err != nil {
        return nil, fmt.Errorf("metric exporter: %w", err)
    }

    mp := metric.NewMeterProvider(
        metric.WithResource(res),
        metric.WithReader(metric.NewPeriodicBatchReader(metricExporter,
            metric.WithInterval(10*time.Second),
        )),
    )
    otel.SetMeterProvider(mp)
    meter = mp.Meter("order-service")

    ordersCounter, err = meter.Int64Counter(
        "orders_processed_total",
        metric.WithDescription("Total number of orders processed"),
        metric.WithUnit("orders"),
    )
    if err != nil {
        return nil, fmt.Errorf("orders counter: %w", err)
    }

    orderLatency, err = meter.Float64Histogram(
        "order_processing_duration_ms",
        metric.WithDescription("Order processing latency in milliseconds"),
        metric.WithUnit("ms"),
    )
    if err != nil {
        return nil, fmt.Errorf("order latency histogram: %w", err)
    }

    _, err = meter.Float64ObservableGauge(
        "order_amount_usd",
        metric.WithDescription("Current order amount in USD"),
        metric.WithUnit("USD"),
        metric.WithCallback(func(_ context.Context, o metric.Float64Observer) error {
            o.Observe(currentAmount)
            return nil
        }),
    )
    if err != nil {
        return nil, fmt.Errorf("order amount gauge: %w", err)
    }

    // --- Logging ---
    logExporter, err := otlploggrpc.New(ctx)
    if err != nil {
        return nil, fmt.Errorf("log exporter: %w", err)
    }

    loggerProvider := logsdk.NewLoggerProvider(
        logsdk.WithResource(res),
        logsdk.WithProcessor(logsdk.NewBatchProcessorProcessor(logExporter)),
    )
    otel.SetLoggerProvider(loggerProvider)
    logger = log.New(&logWriter{loggerProvider.Logger("order-service")}, "", 0)
    handler = logsdk.NewLoggerProvider(loggerProvider).Logger("order-service").Handler()

    return func() {
        tp.Shutdown(ctx)
        mp.Shutdown(ctx)
        loggerProvider.Shutdown(ctx)
    }, nil
}

// logWriter bridges standard logger to OTel logs
type logWriter struct {
    l *logsdk.Logger
}

func (lw *logWriter) Write(p []byte) (int, error) {
    lw.l.Emit(logsdk.Record().ObserveBody(string(p)))
    return len(p), nil
}

// Provider returns OTEL_EXPORTER_OTLP_ENDPOINT — the agent sidecar
func getOtelEndpoint() string {
    if ep := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"); ep != "" {
        return ep
    }
    // fallback: localhost for local dev
    return "localhost:4317"
}

type Order struct {
    OrderID  string  `json:"order_id"`
    Amount   float64 `json:"amount"`
    Customer string  `json:"customer"`
}

func main() {
    ctx := context.Background()
    shutdown, err := initOTel(ctx)
    if err != nil {
        log.Fatalf("failed to init OTel: %v", err)
    }
    defer shutdown()

    // Wrap the HTTP handler with OTel HTTP instrumentation
    otelHandler := otelhttp.NewHandler(
        http.DefaultServeMux,
        "order-service",
        otelhttp.WithPropagators(propagation.NewCompositePropagator(
            propagation.TraceContext{},
            propagation.Baggage{},
        )),
    )
    http.Handle("/health", otelhttp.HandlerFunc(
        func(w http.ResponseWriter, r *http.Request) {
            json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
        },
    ))
    http.Handle("/orders", otelhttp.HandlerFunc(handleOrders))

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    log.Printf("Order service (instrumented) listening on :%s → SigNoz via OTel Agent", port)
    log.Fatal(http.ListenAndServe(":"+port, otelHandler))
}

func handleOrders(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "POST only", http.StatusMethodNotAllowed)
        return
    }

    ctx := r.Context()
    start := time.Now()

    var order Order
    if err := json.NewDecoder(r.Body).Decode(&order); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    currentAmount = order.Amount

    // ─── Manual Span ─────────────────────────────────────────────
    ctx, span := tracer.Start(ctx, "handle Orders POST")
    defer span.End()

    span.SetAttributes(
        attribute.String("order.id", order.OrderID),
        attribute.Float64("order.amount", order.Amount),
        attribute.String("order.customer", order.Customer),
    )
    span.AddEvent("order received")

    // ─── Custom Metrics (counter + histogram) ────────────────────
    ordersCounter.Add(ctx, 1,
        metric.WithAttributes(
            attribute.String("customer_tier", "standard"),
        ),
    )
    orderLatency.Record(ctx, float64(time.Since(start).Milliseconds()),
        metric.WithAttributes(
            attribute.String("method", "POST"),
            attribute.String("path", "/orders"),
        ),
    )

    logger.Printf("ORDER RECEIVED: order_id=%s amount=%.2f customer=%s",
        order.OrderID, order.Amount, order.Customer)

    // ─── HTTP Call to Invoice Service ────────────────────────────
    invoiceSpanCtx, invoiceSpan := tracer.Start(ctx, "POST invoice-service")
    defer invoiceSpan.End()

    invoiceSpan.SetAttributes(
        attribute.String("http.method", "POST"),
        attribute.String("http.url", "http://invoice-service.default.svc.cluster.local:8080/invoice"),
        attribute.String("http.target", "/invoice"),
    )

    invoicePayload, _ := json.Marshal(map[string]interface{}{
        "order_id": order.OrderID,
        "amount":   order.Amount,
    })
    req, err := http.NewRequestWithContext(invoiceSpanCtx,
        http.MethodPost,
        "http://invoice-service.default.svc.cluster.local:8080/invoice",
        bytes.NewBuffer(invoicePayload),
    )
    if err != nil {
        invoiceSpan.SetAttributes(attribute.Bool("error", true))
        w.WriteHeader(http.StatusInternalServerError)
        return
    }
    req.Header.Set("Content-Type", "application/json")

    // otelhttp client auto-injects trace context into the request
    client := otelhttp.NewClient(
        otelhttp.WithPropagators(propagation.NewCompositePropagator(
            propagation.TraceContext{},
            propagation.Baggage{},
        )),
    )
    resp, err := client.Do(req)
    if err != nil {
        invoiceSpan.SetAttributes(attribute.Bool("error", true))
        logger.Printf("FAILURE: could not call invoice service: %v", err)
        w.WriteHeader(http.StatusInternalServerError)
        return
    }
    defer resp.Body.Close()

    invoiceSpan.SetAttributes(
        attribute.Int("http.status_code", resp.StatusCode),
        attribute.Bool("error", resp.StatusCode >= 400),
    )

    logger.Printf("INVOICE RESPONSE: status=%d", resp.StatusCode)

    // ─── Finalize span ──────────────────────────────────────────
    span.SetAttributes(
        attribute.Int("http.status_code", http.StatusCreated),
        attribute.Float64("order.total_latency_ms", float64(time.Since(start).Milliseconds())),
    )

    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(map[string]string{"status": "order placed"})
}
```

### SDK Environment Variables

`order-service` deployment needs these env vars:

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "order-service"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "grpc"
  - name: NODE_IP
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "$(NODE_IP):4317"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT_BACKUP
    value: "localhost:4317"   # local dev fallback
```

---

## Step 4 — Python Invoice Service: Instrumented

### Required Packages

```bash
pip install opentelemetry-api \
  opentelemetry-sdk \
  opentelemetry-exporter-otlp-proto-grpc \
  opentelemetry-instrumentation-httpx \
  opentelemetry-sdk-extension-aws \
  opentelemetry-proto \
  opentelemetry-sem-conventions
```

Or via `requirements.txt`:

```
opentelemetry-api==1.27.0
opentelemetry-sdk==1.27.0
opentelemetry-exporter-otlp-proto-grpc==1.27.0
opentelemetry-instrumentation-httpx==0.48b0
opentelemetry-instrumentation-logging==0.48b0
```

### Instrumented Python Code

`invoice-service/app.py`
```python
import json
import logging
import os
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

from opentelemetry import trace, metrics
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.log_exporter import OTLPLogExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
from opentelemetry.sdk.logging import LoggerProvider, LoggingHandler
from opentelemetry.propagate import set_global_textmap, get_global_textmap
from opentelemetry.propagator.trace_context import TraceContextPropagator
from opentelemetry.semconv.resource import ResourceAttributes
from opentelemetry.instrumentation.httpx import HTTPClientInstrumentor
importopentelemetry.api as api


logging.basicConfig(level=logging.INFO)
log = logging.getLogger("invoice-service")


def init_otel():
    # Determine OTLP endpoint
    node_ip = os.environ.get("NODE_IP", "localhost")
    otlp_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", f"{node_ip}:4317")

    resource = Resource.create({
        SERVICE_NAME: "invoice-service",
        SERVICE_VERSION: "1.0.0",
        "environment": "production",
    })

    # --- Tracing ---
    trace_exporter = OTLPSpanExporter(endpoint=f"http://{otlp_endpoint}", insecure=True)
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(trace_exporter))
    trace.set_tracer_provider(tracer_provider)

    # Propagator
    set_global_textmap(TraceContextPropagator())

    tracer = trace.get_tracer("invoice-service")

    # --- Metrics ---
    metric_reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=f"http://{otlp_endpoint}", insecure=True),
        export_interval_millis=10000,
    )
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)
    meter = metrics.get_meter("invoice-service")

    # Custom metric: invoice_generated_total (Counter)
    invoices_counter = meter.create_counter(
        name="invoices_generated_total",
        description="Total invoices generated",
        unit="invoices",
    )

    # Custom metric: invoice_generation_duration_ms (Histogram)
    invoice_duration = meter.create_histogram(
        name="invoice_generation_duration_ms",
        description="Invoice generation latency in ms",
        unit="ms",
    )

    # Custom metric: invoice_amount_usd (Histogram)
    invoice_amounts = meter.create_histogram(
        name="invoice_amount_usd_total",
        description="Total invoice amount in USD processed",
        unit="USD",
    )

    # --- Logging ---
    log_exporter = OTLPLogExporter(endpoint=f"http://{otlp_endpoint}", insecure=True)
    logger_provider = LoggerProvider(resource=resource)
    # Bridge stdlib logging to OTel logs
    handler = LoggingHandler(logger_provider=logger_provider)
    handler.setLevel(logging.INFO)
    logging.getLogger("invoice-service").addHandler(handler)

    return {
        "tracer": tracer,
        "invoices_counter": invoices_counter,
        "invoice_duration": invoice_duration,
        "invoice_amounts": invoice_amounts,
    }


otel = init_otel()
tracer = otel["tracer"]
invoices_counter = otel["invoices_counter"]
invoice_duration = otel["invoice_duration"]
invoice_amounts = otel["invoice_amounts"]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/invoice":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            data = json.loads(body)

            order_id = data.get("order_id")
            amount = data.get("amount", 0.0)

            # Extract trace context from incoming headers
            # OTel Python's propagator automatically extracts traceparent
            ctx = trace.set_span_in_context(
                trace.get_current_span()
            )

            start = time.time()
            with tracer.start_as_current_span("generate_invoice", context=ctx) as span:
                span.set_attribute("invoice.order_id", str(order_id))
                span.set_attribute("invoice.amount", amount)

                # Simulate invoice generation
                time.sleep(0.05)  # 50ms simulated work

                span.set_attribute("invoice.status", "created")

                # ─── Record custom metrics ─────────────────────────
                invoices_counter.add(1, {"customer_tier": "standard"})

                invoice_duration.record(
                    (time.time() - start) * 1000,
                    {"path": "/invoice"},
                )

                invoice_amounts.record(amount, {"currency": "usd"})

                log.info(f"INVOICE GENERATED: order_id={order_id} amount={amount}")
                log.info(f"Invoice for order {order_id}")

            self.send_response(201)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "invoice_created",
                "invoice_id": f"INV-{order_id}",
            }).encode())

        elif self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # silence default

    def do_GET(self):
        self.do_POST()


if __name__ == "__main__":
    port = os.environ.get("PORT", "8080")
    log.info(f"Invoice service (instrumented) listening on :{port} → SigNoz via OTel Agent")
    server = HTTPServer(("0.0.0.0", int(port)), Handler)
    server.serve_forever()
```

---

## Step 5 — Instrumented K8s Manifests

### Go Order Service with OTel Agent Sidecar

`k8s/order-service-instrumented.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-order-service
  namespace: otel-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: go-order-service
  template:
    metadata:
      labels:
        app: go-order-service
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8889"
    spec:
      # Service account for K8s metadata injection (if using k8sattributes)
      # serviceAccountName: otel-collector

      containers:
        # ── OTel Agent sidecar ──────────────────────────────────
        - name: otel-agent
          image: otel/opentelemetry-collector-contrib:0.117.0
          ports:
            - containerPort: 4317
              name: otlp-grpc
              protocol: TCP
            - containerPort: 4318
              name: otlp-http
              protocol: TCP
          args:
            - --config=/conf/agent.yaml
          resources:
            limits:
              cpu: 100m
              memory: 256Mi
          volumeMounts:
            - name: agent-config
              mountPath: /conf

        # ── Order Service ────────────────────────────────────────
        - name: order-service
          image: order-service:latest
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: PORT
              value: "8080"
            - name: OTEL_SERVICE_NAME
              value: "order-service"
            - name: OTEL_EXPORTER_OTLP_PROTOCOL
              value: "grpc"
            - name: NODE_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "localhost:4317"   # agent sidecar on same node
          resources:
            limits:
              cpu: 500m
              memory: 512Mi

      volumes:
        - name: agent-config
          configMap:
            name: otel-agent-conf
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-agent-conf
  namespace: otel-demo
data:
  agent.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch:
        timeout: 1s
        send_batch_size: 1024
      memory_limiter:
        limit_mib: 256
        spike_limit_mib: 64
        check_interval: 1s
    exporters:
      otlp:
        endpoint: signoz-otel-collector.signoz.svc.cluster.local:4317
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch, memory_limiter]
          exporters: [otlp]
        metrics:
          receivers: [otlp]
          processors: [batch, memory_limiter]
          exporters: [otlp]
        logs:
          receivers: [otlp]
          processors: [batch, memory_limiter]
          exporters: [otlp]
```

### Python Invoice Service with OTel Agent Sidecar

`k8s/invoice-service-instrumented.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: py-invoice-service
  namespace: otel-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: py-invoice-service
  template:
    metadata:
      labels:
        app: py-invoice-service
    spec:
      containers:
        # ── OTel Agent sidecar ──────────────────────────────────
        - name: otel-agent
          image: otel/opentelemetry-collector-contrib:0.117.0
          ports:
            - containerPort: 4317
              name: otlp-grpc
            - containerPort: 4318
              name: otlp-http
          args:
            - --config=/conf/agent.yaml
          resources:
            limits:
              cpu: 100m
              memory: 256Mi
          volumeMounts:
            - name: agent-config
              mountPath: /conf

        # ── Invoice Service ──────────────────────────────────────
        - name: invoice-service
          image: invoice-service:latest
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: PORT
              value: "8080"
            - name: OTEL_SERVICE_NAME
              value: "invoice-service"
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "localhost:4317"
          resources:
            limits:
              cpu: 300m
              memory: 512Mi

      volumes:
        - name: agent-config
          configMap:
            name: otel-agent-conf
```

---

## Step 6 — Verify Signals in SigNoz

### Trigger an Order

```bash
# Create an order
kubectl exec -n otel-demo deploy/go-order-service -- \
  curl -s -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"order_id":"ORD-001","amount":149.99,"customer":"acme-corp"}'

# Repeat a few times for metrics volume
for i in $(seq 1 10); do
  kubectl exec -n otel-demo deploy/go-order-service -- \
    curl -s -X POST http://localhost:8080/orders \
    -H "Content-Type: application/json" \
    -d "{\"order_id\":\"ORD-$i\",\"amount\":$((RANDOM % 500)).99,\"customer\":\"customer-$i\"}"
done
```

### In SigNoz UI — What to Look For

**Traces tab:**
- Service map showing `order-service` connected to `invoice-service`
- A trace for `ORD-001` should show:
  - `handle Orders POST` (root span, order-service)
  - `POST invoice-service` (child span, order-service)
  - `generate_invoice` (child span, invoice-service)
- Click any span to see attributes: `order.id`, `order.amount`, `http.status_code`, `invoice.status`

**Metrics tab:**
- `orders_processed_total` — counter, shows 11 total
- `order_processing_duration_ms` — histogram of latency per order
- `invoices_generated_total` — counter in invoice-service, shows 11
- `invoice_generation_duration_ms` — histogram in invoice-service
- `invoice_amount_usd_total` — histogram of invoice amounts

**Logs tab:**
- All `log.Info` calls from both services
- Click a span → correlated logs from that trace_id
- Fields visible: `trace_id`, `span_id`, `service.name`, `order_id`

**Application tab:**
- Service health → latency heatmaps, error rates

---

## Key Concepts Illustrated

### Context Propagation (Go → Python on HTTP)

```
┌──────────────────┐                          ┌──────────────────┐
│  order-service    │                          │ invoice-service   │
│                  │                          │                  │
│ Span: handle POST│                          │ Span: generate_  │
│   child: POST svc │──traceparent header───▶  │   invoice        │
│                  │  (auto-injected by       │                  │
│                  │   otelhttp.Client)       │                  │
└──────────────────┘                          └──────────────────┘
```

The `otelhttp.Client` in Go automatically injects the `traceparent` header into the HTTP request headers. The Python service's `TraceContextPropagator` extracts it and links the `generate_invoice` span as a child of the parent `POST invoice-service` span. Result: a single continuous trace across both services.

### Custom Metrics Defined

| Metric | Service | Type | Dimensions | Description |
|--------|---------|------|------------|-------------|
| `orders_processed_total` | Go | Counter | `customer_tier` | Total orders placed |
| `order_processing_duration_ms` | Go | Histogram | `method`, `path` | E2E order processing latency |
| `order_amount_usd` | Go | Observable Gauge | — | Live view of current order amount |
| `invoices_generated_total` | Python | Counter | `customer_tier` | Total invoices created |
| `invoice_generation_duration_ms` | Python | Histogram | `path` | Invoice gen latency |
| `invoice_amount_usd_total` | Python | Histogram | `currency` | Invoice amounts processed |

### Auto vs Manual Instrumentation

| What | Auto | Manual |
|------|------|--------|
| HTTP ingress spans | `otelhttp.Handler` wraps mux | `tracer.Start()` around handler |
| HTTP egress spans | `otelhttp.Client` auto-injects headers | `tracer.Start()` + otelhttp client |
| DB/rpc/client spans | auto-instrumentation packages | explicit `tracer.Start()` |
| Metrics (SDK metrics) | auto if using auto-instr packages | `meter.CreateCounter/Histogram` |
| Resource attrs | auto-injection (pod name, ns, etc.) | `resource.New()` with explicit attrs |
| Context propagation | handled by otelhttp | `propagator.Inject/Extract` |

In this exercise we used **manual spans** for the core order/invoice logic (explicit child span naming, custom attributes) AND **auto-instrumented HTTP** via `otelhttp` (wraps mux + client automatically). This is the recommended hybrid approach.

---

## Troubleshooting

### No data in SigNoz?

```bash
# Check agent logs
kubectl logs -n otel-demo -l app=otel-agent --tail=50

# Check if app is reaching the agent (agent sidecar)
kubectl exec -n otel-demo deploy/go-order-service -c otel-agent -- \
  curl -s http://localhost:4317/v1/traces -o /dev/null -w "%{http_code}"

# Check SigNoz OTLP endpoint connectivity from agent
kubectl exec -n otel-demo deploy/go-order-service -c otel-agent -- \
  telnet signoz-otel-collector.signoz.svc.cluster.local 4317
```

### Custom metrics not appearing?

- Histograms and counters need at least **one recording** before they appear in the metric explorer
- Set `export_interval_millis` in Python's `PeriodicExportingMetricReader` to `10000` (10s) minimum for testing
- In SigNoz → Metrics → type `orders_processed_total` in the search bar

### Spans not linked across services?

- Verify the agent sees the same cluster of both nodes
- Check `traceparent` is forwarded through your `invoice-service` HTTP handler (Python `TraceContextPropagator`)
- If using a service mesh (Istio), OTel HTTP traffic must be excluded from Istio instrumentation (add pod labels to skip)
