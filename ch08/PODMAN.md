# Running the Chapter 8 lab with Podman

The scripts in `ch08/scripts` use minikube with the Docker driver and
build the shop images with `docker build`. To use Podman instead:

1. Start minikube with the Podman driver. It is experimental in
   minikube 1.39, and works best with rootful Podman on Linux:

       minikube start -p lab --driver=podman --container-runtime=docker \
         --kubernetes-version=v1.37.0 --nodes=3 --cpus=2 --memory=4g

   Then run `ch08/scripts/create-lab.sh` to label the nodes; it starts
   the existing cluster instead of creating a new one.

2. Build the images with Podman and load them from an archive:

       podman build -t docker.io/tektutor/inventory:1.0 shop/inventory
       podman save docker.io/tektutor/inventory:1.0 -o inventory.tar
       minikube -p lab image load inventory.tar

   Repeat for orders. Give the full name with `docker.io/`: Podman
   names a short image `localhost/...`, which the manifests do not use.

3. On macOS, give the Podman machine enough room for three nodes:

       podman machine init --cpus 6 --memory 14336
