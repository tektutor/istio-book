#!/usr/bin/env bash
# Starts a "virtual machine" for Lab 41.2: an Ubuntu container on the
# Docker network of the minikube profile "lab", with Istio's sidecar
# package, the where service and the files from istioctl.
#
# Usage: ch41/vm/setup-vm.sh [name]         (default: where-vm1)
set -euo pipefail

VM=${1:-where-vm1}
HERE=$(cd "$(dirname "$0")" && pwd)
NODE=$(minikube ip -p lab)
ISTIOD=$(kubectl get svc istiod -n istio-system \
  -o jsonpath='{.spec.clusterIP}')

docker run -d --name "$VM" --hostname "$VM" --network lab \
  --privileged ubuntu:24.04 sleep infinity                      # (1)
docker exec "$VM" sh -c 'apt-get update -qq &&
  apt-get install -y -qq curl iproute2 iptables python3 sudo >/dev/null'
docker exec "$VM" ip route add 10.244.0.0/16 via "$NODE"        # (2)
docker exec "$VM" ip route add 10.96.0.0/12 via "$NODE"

kubectl apply -f "$HERE/workloadgroup.yaml"
rm -rf vm-files
istioctl x workload entry configure --name where-vm -n zones \
  -o vm-files --clusterID Kubernetes --autoregister \
  --ingressIP "$ISTIOD"                                         # (3)
docker cp vm-files "$VM":/root/vm-files
docker cp "$HERE/where_vm.py" "$VM":/opt/where_vm.py

docker exec "$VM" bash -c '
  set -e
  deb=istio-sidecar.deb
  [ "$(dpkg --print-architecture)" = arm64 ] && deb=istio-sidecar-arm64.deb
  curl -fsSL -o istio-sidecar.deb \
    https://blob.istio.io/istio-release/releases/1.31.1/deb/$deb
  dpkg -i istio-sidecar.deb >/dev/null                          # (4)
  mkdir -p /etc/certs /var/run/secrets/tokens /etc/istio/proxy \
    /etc/istio/config
  cp /root/vm-files/root-cert.pem /etc/certs/root-cert.pem
  cp /root/vm-files/istio-token /var/run/secrets/tokens/istio-token
  cp /root/vm-files/cluster.env /var/lib/istio/envoy/cluster.env
  cp /root/vm-files/mesh.yaml /etc/istio/config/mesh
  cat /root/vm-files/hosts >> /etc/hosts
  chown -R istio-proxy /var/lib/istio /etc/certs /etc/istio \
    /var/run/secrets
  nohup python3 /opt/where_vm.py > /var/log/where.log 2>&1 &
  install -d -o istio-proxy /var/run/secrets
  cd / && nohup /usr/local/bin/istio-start.sh >/dev/null 2>&1 &  # (5)
'
echo "VM $VM started; its log: docker exec $VM tail /var/log/istio/istio.log"
