# k8s-netperf

Originally forked from [k8s-netperf](https://github.com/leannetworking/k8s-netperf) but write in bash script.

## Usage

```bash
kubectl apply -f https://raw.githubusercontent.com/anngdinh/k8s-netperf/main/k8s-netperf.yaml
curl -OL https://raw.githubusercontent.com/anngdinh/k8s-netperf/main/test.sh && chmod +x test.sh
```

Run test:

```bash
./test.sh
```

## Clean up

```bash
kubectl delete -f https://raw.githubusercontent.com/anngdinh/k8s-netperf/main/k8s-netperf.yaml --ignore-not-found
rm -f test.sh
```
