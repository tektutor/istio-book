# Runbook: proxies reject config

Alert: IstioConfigRejected.

## Check
1. istioctl proxy-status -v 1: find ERROR in the CDS, LDS or RDS column.
2. kubectl logs -n istio-system -l app=istiod | grep "ACK ERROR"
   The message names the listener or cluster and the Envoy error.
3. kubectl get envoyfilter,sidecar,authorizationpolicy -A
   --sort-by=.metadata.creationTimestamp: the newest is the suspect.

## Act
1. Delete or revert the resource that the error names.
2. Watch the ERROR change to SYNCED, then send a test request.

## Recovered when
- pilot_total_xds_rejects stops increasing.
- A change made after the fix reaches the proxies.
