# k8s-netperf

Originally forked from [k8s-netperf](https://github.com/leannetworking/k8s-netperf) but write in bash script.

## Prerequisites

- Kubernetes cluster should have 2 nodes at least.
- Fill in the `NODE_1` and `NODE_2` variables in the `east-west.sh` script with the names of the nodes you want to test.
- Because pod in service is random in nodes, so test to service can contain same node and different node.

## Usage

### East-West test

```bash
kubectl apply -f https://raw.githubusercontent.com/anngdinh/k8s-netperf/main/k8s-netperf.yaml
curl -OL https://raw.githubusercontent.com/anngdinh/k8s-netperf/main/east-west.sh && chmod +x east-west.sh
```

Run test:

```bash
./east-west.sh
```

### North-South test

## Clean up

```bash
kubectl delete -f https://raw.githubusercontent.com/anngdinh/k8s-netperf/main/k8s-netperf.yaml --ignore-not-found
rm -f east-west.sh
```
