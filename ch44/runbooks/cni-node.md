# Runbook: the Istio CNI agent is missing on a node

Alert: IstioCNIAgentMissing.

## Check
1. kubectl get pods -n istio-system -l k8s-app=istio-cni-node -o wide
2. kubectl get ds istio-cni-node -n istio-system -o yaml: affinity,
   tolerations and nodeSelector.
3. kubectl get pods -A -o wide --field-selector spec.nodeName=NODE:
   pods in Init:CrashLoopBackOff on that node.

## Act
1. Restore the agent on the node (taint, affinity, image, resources).
2. Pods with repairPods recover on their next restart; delete the
   others so that they start again.
3. If the node cannot be fixed: kubectl cordon NODE and drain it.

## Recovered when
- Every node has a ready istio-cni-node pod and no pod on the node
  waits in Init.
