#!/usr/bin/env bash
# The three steps of Lab 49.1. Run them in order, and check after each.
#
# Usage: ch49/k8s/step.sh 0|1|2|3
#   0  build the images and deploy the Spring Cloud services, no mesh
#   1  add sidecars; Eureka and Spring Cloud LoadBalancer stay
#   2  call the catalog through its Kubernetes Service
#   3  remove Eureka, then require mutual TLS
set -euo pipefail
NS=springshop
wait_for() {
  for d in "$@"; do kubectl rollout status -n $NS "deploy/$d"; done
}

case $1 in
0)
  for m in eureka catalog storefront; do
    docker build -q -t "tektutor/springshop-$m:1.0" "ch49/spring/$m"
    minikube -p lab image load "tektutor/springshop-$m:1.0"
  done
  kubectl apply -f ch49/k8s/springshop.yaml
  wait_for eureka catalog storefront
  kubectl wait -n $NS pod/curl --for=condition=Ready
  ;;
1)
  kubectl label namespace $NS istio-injection=enabled               # (1)
  kubectl delete pod curl -n $NS --wait
  kubectl apply -f ch49/k8s/springshop.yaml
  kubectl rollout restart deploy -n $NS eureka catalog storefront
  wait_for eureka catalog storefront
  kubectl wait -n $NS pod/curl --for=condition=Ready
  ;;
2)
  kubectl set env -n $NS deploy/storefront \
    STOREFRONT_DISCOVERY=false CATALOG_URL=http://catalog:8080        # (2)
  wait_for storefront
  ;;
3)
  kubectl set env -n $NS deploy/catalog deploy/storefront \
    EUREKA_ENABLED=false                                            # (3)
  wait_for catalog storefront
  kubectl delete -n $NS deploy/eureka svc/eureka
  kubectl apply -f - <<'Y'
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: {name: default, namespace: springshop}
spec: {mtls: {mode: STRICT}}
Y
  ;;
*) echo "usage: $0 0|1|2|3" >&2; exit 2 ;;
esac
