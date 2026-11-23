# Istio Service Mesh in Practice: companion repository

This repository holds the code, manifests and lab files for the two-volume book
*Istio Service Mesh in Practice* by Jeganathan Swaminathan (TekTutor Press).

Every program in the books is printed in full. This repository gives you the
same files, so you can run the labs without typing them in.

## Get the code

```bash
git clone https://github.com/tektutor/istio-book.git
cd istio-book
```

## How the repository is organised

| Folder | What it contains |
| --- | --- |
| [`shop`](shop) | The TekTutor Shop services, each with its tests and Dockerfile |
| `ch01`, `ch02` and so on | One folder for each chapter that has code, with the files named in its listings |
| `chNN/openshift`, `chNN/ocp` | The OpenShift steps and manifests for that chapter's labs |
| `chNN/solutions` | Answers to the design exercises and lab questions |
| [`ambient-lab`](ambient-lab) | The ambient data plane lab from Chapter 36 |

The file names in the book's listing captions are relative to the root of this
repository. For example, `ch08/scripts/check-lab.sh` is the file `check-lab.sh`
in the folder `ch08/scripts`.

## Volume 1: Architecture, Foundations, Installation, Traffic Management and Resilience

| Folder | Chapter |
| --- | --- |
| [`ch01`](ch01) | Why a Service Mesh, and Where It Stops |
| [`ch02`](ch02) | Service Mesh Architecture |
| [`ch03`](ch03) | Design Decisions, Trade-offs and Distributions |
| [`ch04`](ch04) | Reference Architectures and Compliance |
| [`ch05`](ch05) | Adopting Istio: Operating Model, Governance and Platform Engineering |
| [`ch06`](ch06) | Envoy Proxy in Depth |
| [`ch07`](ch07) | Istio Architecture |
| [`ch08`](ch08) | Building the Lab Environment |
| [`ch09`](ch09) | Installing Istio |
| [`ch10`](ch10) | OpenShift Service Mesh 3 |
| [`ch11`](ch11) | Traffic Capture and the CNI Layer |
| [`ch12`](ch12) | Sidecar Injection and Pod Lifecycle |
| [`ch13`](ch13) | Ambient Mode Essentials |
| [`ch14`](ch14) | The Service Registry, Protocols and DNS |
| [`ch15`](ch15) | Kubernetes Gateway API with Istio |
| [`ch16`](ch16) | VirtualService in Depth |
| [`ch17`](ch17) | DestinationRule in Depth |
| [`ch18`](ch18) | Release Strategies |
| [`ch19`](ch19) | Ingress Gateways |
| [`ch20`](ch20) | Migrating from Ingress NGINX to Istio |
| [`ch21`](ch21) | Egress Traffic |
| [`ch22`](ch22) | TCP, gRPC, WebSocket and Other Protocols |
| [`ch23`](ch23) | Scoping Configuration |
| [`ch24`](ch24) | Timeouts and Retries |
| [`ch25`](ch25) | Circuit Breaking, Outlier Detection and Rate Limiting |
| [`ch26`](ch26) | Fault Injection and Chaos Testing |

## Volume 2: Applications, Security, Observability, Ambient in Production, Multi-cluster and Operations

| Folder | Chapter |
| --- | --- |
| [`ch27`](ch27) | Application Services in the Mesh: Spring Boot and Python |
| [`ch28`](ch28) | Workload Identity and Certificates |
| [`ch29`](ch29) | Root CA Lifecycle and Disaster Recovery |
| [`ch30`](ch30) | Mutual TLS |
| [`ch31`](ch31) | Authorization Policies |
| [`ch32`](ch32) | End-User Authentication and External Authorization |
| [`ch33`](ch33) | Hardening the Mesh |
| [`ch34`](ch34) | Metrics, Dashboards and Kiali |
| [`ch35`](ch35) | Tracing and Access Logs |
| [`ch36`](ch36) | Waypoints in Depth |
| [`ch37`](ch37) | Moving from Sidecars to Ambient Mode |
| [`ch38`](ch38) | Troubleshooting Ambient Mode |
| [`ch39`](ch39) | Extending Envoy: EnvoyFilter, WebAssembly and Lua |
| [`ch40`](ch40) | Multi-cluster Meshes |
| [`ch41`](ch41) | Locality, Failover and Virtual Machines |
| [`ch42`](ch42) | Cell-Based Architecture with Istio |
| [`ch43`](ch43) | Upgrading Istio |
| [`ch44`](ch44) | When the Mesh Fails |
| [`ch45`](ch45) | Performance, Capacity, Cost and Platform SLOs |
| [`ch46`](ch46) | The Troubleshooting Toolkit |
| [`ch47`](ch47) | Troubleshooting Playbook |
| [`ch48`](ch48) | Testing and Delivering Mesh Configuration |
| [`ch49`](ch49) | Migrating to Istio from Other Meshes and Libraries |
| [`ch50`](ch50) | Capstone Project |

## Versions the labs were tested with

| Track | Versions |
| --- | --- |
| Kubernetes | Istio 1.31.1, Kubernetes 1.37.0 on minikube 1.39, Gateway API v1.6.3 |
| OpenShift | OpenShift Service Mesh 3.4.4 (Istio 1.30.5) on OpenShift Local 2.65.0 |

Start with Chapter 8: `ch08/scripts/install-tools.sh` installs the tools, and
`ch08/scripts/check-lab.sh` (or `ch08/scripts/check-lab-ocp.sh` on OpenShift)
checks that your lab machine is ready.

## Build output is not stored here

You build some files yourself while you follow the labs, for example the Wasm
plugins in Chapter 39. The `.gitignore` file keeps those build results out of
the repository.

## Licence

The code is released under the Apache License 2.0. See [LICENSE](LICENSE).
You may use it in your own work.

## Feedback

If you find a mistake, or a lab that does not work on a newer release, write to
jegan@tektutor.org. Corrections for each printing are published on the companion
site, www.tektutor.org.
