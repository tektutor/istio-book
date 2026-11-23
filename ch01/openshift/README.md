# Lab 1.1 on OpenShift (project user)

These steps run TekTutor Shop without a mesh in your own OpenShift project.
Run them from the root of the companion repository.

Status: draft. Test on OpenShift Local before print.

## 1. Log in and create a project for this chapter

These steps use OpenShift Local from Chapter 8. The project has no mesh
labels, so its pods get no proxy even when the mesh is installed.

```console
$ eval $(crc oc-env)
$ oc login -u kubeadmin https://api.crc.testing:6443
$ oc new-project ch01
```

## 2. Build the two images inside OpenShift

Each build uploads the service folder and runs its Dockerfile. The result is
an image stream tag in the internal registry.

```console
$ oc new-build --binary --strategy=docker --name=inventory
$ oc start-build inventory --from-dir=shop/inventory --follow
$ oc new-build --binary --strategy=docker --name=orders
$ oc start-build orders --from-dir=shop/orders --follow
```

## 3. Deploy

The manifests in this folder do not name a namespace. The two service
manifests use the placeholder `PROJECT` in the image name. Replace it as you
apply them:

```console
$ export PROJECT=$(oc project -q)
$ for f in ch01/openshift/*.yaml; do
    sed "s/PROJECT/$PROJECT/" "$f" | oc apply -f -
  done
$ oc wait --for=condition=Ready pod --all --timeout=180s
```

The restricted-v2 SCC runs each container with a user ID from the
project's range and group 0. The images work with any user ID, because the
programs write no files. Check the SCC and user ID with
`oc get pod -l app=inventory -o yaml`.

## 4. Run the lab

Run Steps 1 to 4 and Step 6 from the chapter. Replace `kubectl exec -n shop`
with `oc exec`, and `kubectl logs -n shop` with `oc logs`. For example:

```console
$ oc exec deploy/curl -- curl -s http://orders:8080/api/orders/1001
```

Skip Step 5. The restricted-v2 SCC does not let a pod add the NET_ADMIN
and NET_RAW capabilities that tcpdump needs. Chapter 30 captures the
traffic from the node with oc debug node.

## 5. Clean up

```console
$ oc delete project ch01
```
