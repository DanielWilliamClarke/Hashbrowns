# Using Envoy Proxy to load-balance gRPC services on GKE with header value based Session Affinity
- [Using Envoy Proxy to load-balance gRPC services on GKE with header value based Session Affinity](#using-envoy-proxy-to-load-balance-grpc-services-on-gke-with-header-value-based-session-affinity)
  - [Links](#links)
  - [Display the current project ID](#display-the-current-project-id)
  - [Set project id and region](#set-project-id-and-region)
  - [Create Cluster](#create-cluster)
  - [Deploy the gRPC services](#deploy-the-grpc-services)
  - [Deploy Custom metrics adapter](#deploy-custom-metrics-adapter)
  - [Set up Network Load Balancing](#set-up-network-load-balancing)
  - [Create a self-signed SSL/TLS certificate](#create-a-self-signed-ssltls-certificate)
  - [Deploy Envoy](#deploy-envoy)
  - [Test the gRPC services](#test-the-grpc-services)
  - [Envoy Admin](#envoy-admin)
  - [Session affinity test](#session-affinity-test)
  - [Remember to trash the cluster when done](#remember-to-trash-the-cluster-when-done)
  
---

This repository contains the code used in the tutorial
[Using Envoy Proxy to load-balance gRPC services on GKE](https://cloud.google.com/solutions/exposing-grpc-services-on-gke-using-envoy-proxy).
This tutorial demonstrates how to perform **session affinity** based on request header value to [gRPC](https://grpc.io/)
service instances deployed on
[Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine/)
via a single external IP address using
[Network Load Balancing](https://cloud.google.com/load-balancing/docs/network/)
and [Envoy Proxy](https://www.envoyproxy.io/). We use Envoy Proxy in this
tutorial to highlight some of the advanced features it provides for gRPC and hash based load balancing.

## Links

- GCP tutorial: https://cloud.google.com/solutions/exposing-grpc-services-on-gke-using-envoy-proxy 
- What is Envoy: https://www.envoyproxy.io/docs/envoy/latest/intro/what_is_envoy
- Envoy Load Balancers: https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/load_balancing/load_balancers
- Envoy v2 Api Reference: https://www.envoyproxy.io/docs/envoy/latest/api-v2/api
- Envoy cluster config: https://www.envoyproxy.io/docs/envoy/latest/api-v2/api/v2/cluster.proto
- Envoy route hash policy config: https://www.envoyproxy.io/docs/envoy/latest/api-v2/api/v2/route/route_components.proto#envoy-api-msg-route-routeaction-hashpolicy
- Envoy Ring hash config: https://www.envoyproxy.io/docs/envoy/latest/api-v2/api/v2/cluster.proto#envoy-api-msg-cluster-ringhashlbconfig


## Display the current project ID

```bash
gcloud config list --format 'value(core.project)'
```

## Set project id and region

```bash
gcloud config set project <project-id>

REGION=us-central1
ZONE=$REGION-c

GOOGLE_CLOUD_PROJECT=$(gcloud config list --format 'value(core.project)')
CLUSTER_NAME=grpc-cluster-dc
```

## Create Cluster

```bash
gcloud container clusters create $CLUSTER_NAME \
--zone $ZONE \
--workload-pool=$GOOGLE_CLOUD_PROJECT.svc.id.goog

# Check nodes
kubectl get nodes -o name
# ...
# node/gke-grpc-cluster-default-pool-c9a3c791-1kpt
# node/gke-grpc-cluster-default-pool-c9a3c791-qn92
# node/gke-grpc-cluster-default-pool-c9a3c791-wf2h



# Create K8S service account
KS_NAMESPACE=default
KSA_NAME=prometheus-to-sd-sa
kubectl create serviceaccount --namespace $KS_NAMESPACE $KSA_NAME

# Attach existing GCP service account to it
gcloud iam service-accounts add-iam-policy-binding --role \
  roles/iam.workloadIdentityUser --member \
  "serviceAccount:$GOOGLE_CLOUD_PROJECT.svc.id.goog[$KS_NAMESPACE/$KSA_NAME]" \
  $GOOGLE_CLOUD_PROJECT@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com

# Annotate the Custom Metrics - Stackdriver Adapter service account:
kubectl annotate serviceaccount --namespace=$KS_NAMESPACE \
  $KSA_NAME \
  iam.gke.io/gcp-service-account=$GOOGLE_CLOUD_PROJECT@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com

# Test workload identity
kubectl run -it \
  --image google/cloud-sdk:slim \
  --serviceaccount $KSA_NAME \
  --namespace $KS_NAMESPACE \
  workload-identity-test

# When prompt appears run
gcloud auth list

# Credentialed Accounts
# ACTIVE  ACCOUNT
# *       carbon-casper-team@carbon-casper-team.iam.gserviceaccount.com
```

## Deploy the gRPC services

```bash
# Build grpc service image
# You may also use docker locally and push to GCP registry

gcloud builds submit -t gcr.io/$GOOGLE_CLOUD_PROJECT/echo-grpc echo-grpc

gcloud container images list --repository gcr.io/$GOOGLE_CLOUD_PROJECT
# ...
# NAME
# gcr.io/GOOGLE_CLOUD_PROJECT/echo-grpc

# Deploy GRPC service deployment
sed s/GOOGLE_CLOUD_PROJECT/$GOOGLE_CLOUD_PROJECT/ \
    k8s/echo-deployment.yaml | kubectl apply -f -

kubectl get deployments
# ...
# NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
# echo-grpc      2         2         2            2           1m

# Deploy GRPC k8s service
kubectl apply -f k8s/echo-service.yaml

kubectl get services
# ...
# NAME           TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
# echo-grpc      ClusterIP   None         <none>        8081/TCP   35s
```

## Deploy Custom metrics adapter

```bash

kubectl apply -f k8s/metrics-adapter-deployment.yaml

gcloud iam service-accounts add-iam-policy-binding --role \
  roles/iam.workloadIdentityUser --member \
  "serviceAccount:$GOOGLE_CLOUD_PROJECT.svc.id.goog[custom-metrics/custom-metrics-stackdriver-adapter]" \
  $GOOGLE_CLOUD_PROJECT@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com

kubectl annotate serviceaccount --namespace custom-metrics \
  custom-metrics-stackdriver-adapter \
  iam.gke.io/gcp-service-account=$GOOGLE_CLOUD_PROJECT@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com

```

## Set up Network Load Balancing

```bash
kubectl apply -f k8s/envoy-service.yaml

# You may watch service deployment - ensure EXTERNAL-IP for the envoy service changes from <pending> to a public IP address:
kubectl get services envoy --watch
# Press Control+C to stop waiting.
```

## Create a self-signed SSL/TLS certificate

```bash
# Store Envoy external ip
EXTERNAL_IP=$(kubectl get service envoy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Generate public and private keys
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout privkey.pem -out cert.pem -subj "/CN=$EXTERNAL_IP"

# Upload keys and creates secrets in k8s
kubectl create secret tls envoy-certs \
    --key privkey.pem --cert cert.pem \
    --dry-run -o yaml | kubectl apply -f -
```

## Deploy Envoy

```bash
# Deploy Envoy configuration
kubectl apply -f k8s/envoy-configmap.yaml

# Deploy Envoy deployment
kubectl apply -f k8s/envoy-deployment.yaml

kubectl get deployment envoy
# ...
# NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
# envoy     2         2         2            2           1m
```

## Test the gRPC services

```bash
# Install grpcurl
go get github.com/fullstorydev/grpcurl
go install github.com/fullstorydev/grpcurl/cmd/grpcurl

# Make GRPC request to echo-rpc via Envoy
grpcurl.exe \
    -H "x-session-hash: test-header-1" \
    -d '{"content": "With a given header I will always hit the same Pod"}' \
    -proto echo-grpc/api/echo.proto \
    -insecure \
    -v $EXTERNAL_IP:443 api.Echo/Echo
# ...
# Resolved method descriptor:
# rpc Echo ( .api.EchoRequest ) returns ( .api.EchoResponse );

# Request metadata to send:
# x-session-hash: test-header-1

# Response headers received:
# content-type: application/grpc
# date: Fri, 11 Sep 2020 16:08:20 GMT
# hostname: echo-grpc-67458bf84f-87tf8
# server: envoy
# x-envoy-upstream-service-time: 0

# Response contents:
# {
#   "content": "With a given header I will always hit the same Pod"
# }

# Response trailers received:
# (empty)
# Sent 1 request and received 1 response
```

## Envoy Admin

```bash
kubectl port-forward \
    $(kubectl get pods -o name | grep envoy | head -n1) 8080:9901
# ...
# Forwarding from 127.0.0.1:8080 -> 8090
# Browse to 127.0.0.1:8080 to see the admin dashboard
```

## Session affinity test

```bash

# Ensure grpcurl.exe is in your PATH
./grpc_xxx.sh

# You then see for a given header value, all  calls are routed to the same hostname (Pod)

# ...
# FOR: test---nTfr6ftL
# hostname: echo-grpc-67458bf84f-vbzj5
# hostname: echo-grpc-67458bf84f-vbzj5
# hostname: echo-grpc-67458bf84f-vbzj5
# hostname: echo-grpc-67458bf84f-vbzj5
# hostname: echo-grpc-67458bf84f-vbzj5
# FOR: test---NJpVNN9x
# hostname: echo-grpc-67458bf84f-87tf8
# hostname: echo-grpc-67458bf84f-87tf8
# hostname: echo-grpc-67458bf84f-87tf8
# hostname: echo-grpc-67458bf84f-87tf8
# hostname: echo-grpc-67458bf84f-87tf8
# FOR: test---TE1F7T3L
# hostname: echo-grpc-67458bf84f-rx28f
# hostname: echo-grpc-67458bf84f-rx28f
# hostname: echo-grpc-67458bf84f-rx28f
# hostname: echo-grpc-67458bf84f-rx28f
# hostname: echo-grpc-67458bf84f-rx28f
```

## Remember to trash the cluster when done