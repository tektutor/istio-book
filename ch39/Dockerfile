# An OCI image that Istio can load: one layer with the file plugin.wasm.
# Build it from the folder of the module, for example:
#   podman build -t quay.io/tektutor/tenant-check:1.0.0 \
#     -f ../Dockerfile target/wasm32-unknown-unknown/release
FROM scratch
COPY tenant_check.wasm ./plugin.wasm
