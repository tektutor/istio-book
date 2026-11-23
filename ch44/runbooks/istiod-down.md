# Runbook: istiod is down or unreachable

Alerts: IstiodDown, IstioInjectionWebhookFailing,
IstioWorkloadCertNotRenewed.

## What still works
- Running proxies keep their last config. Traffic continues.

## What breaks, and when
- At once: no config changes reach proxies; new pods in injected
  namespaces cannot be created; Istio resources cannot be applied.
- About 12 hours later: the first workload certificates expire.
  New mutual TLS connections from those pods fail.

## Check
1. kubectl get deploy,pods,hpa -n istio-system
2. kubectl describe pod -n istio-system -l app=istiod
3. kubectl logs -n istio-system -l app=istiod --tail=100
4. kubectl get events -n istio-system --sort-by=.lastTimestamp

## Act
1. If replicas are 0: kubectl scale deploy istiod -n istio-system
   --replicas=2. The HPA does not scale up from 0.
2. If pods crash: read the last logs, roll back the last change to
   istiod (image, values, mesh config), not the applications.
3. If pods are Pending: free capacity, or lower istiod's requests.
4. Do not change the injection webhook to Ignore.

## Recovered when
- istioctl proxy-status -v 1 shows every proxy as SYNCED.
- Pending rollouts finish; kubectl get rs shows no FailedCreate.
