# Runbook: slow config pushes

Alert: IstioPushSlow.

## Check
1. sum by (type) (rate(pilot_push_triggers[5m])): what is changing?
2. sum by (type) (rate(pilot_xds_pushes[5m])), and istiod CPU.
3. Which namespace creates or changes objects in a loop?

## Act
1. Stop the loop: a controller, a CI job, a crash-looping workload.
2. Add Sidecar resources or discoverySelectors so that fewer proxies
   need each change.
3. Add istiod replicas if CPU is at its limit.

## Recovered when
- The p99 of pilot_proxy_convergence_time is below 10 seconds.
