#!/bin/sh

PING_INTERVAL=0.001
PING_COUNT=30000

NODE_1=""
NODE_2=""
POD_LOCAL_1=""
POD_LOCAL_2=""
POD_REMOTE_1=""
POD_REMOTE_2=""

NODE_1_IP=""
NODE_2_IP=""
POD_LOCAL_1_IP=""
POD_LOCAL_2_IP=""
POD_REMOTE_1_IP=""
POD_REMOTE_2_IP=""

pingFunc() {
    local pod=$1
    local target_ip=$2
    local interval=$3
    local count=$4
    echo "- Running: kubectl exec -it $pod -- ping -c $count -i $interval -q $target_ip"
    local output=$(kubectl exec -it $pod -- ping -c $count -i $interval -q $target_ip)
    echo "$output" | tail -n 2
}

getPodsWithPrefixOnNode() {
    local prefix=$1
    local node=$2
    kubectl get pods --no-headers --all-namespaces --field-selector spec.nodeName=$node | grep $prefix | head -n 1 | awk '{print $2}'
}

getPodIPByName() {
    local pod_name=$1
    kubectl get pod "$pod_name" -o jsonpath='{.status.podIP}'
}

getNodeIPByName() {
    local node_name=$1
    kubectl get node "$node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'
}

getK8sInfo() {
    local nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | head -n 2)
    NODE1=$(echo "$nodes" | sed -n '1p')
    NODE2=$(echo "$nodes" | sed -n '2p')

    if [ -z "$NODE1" ] || [ -z "$NODE2" ]; then
        echo "Error: Could not get the node names"
        exit 1
    fi

    NODE_1_IP=$(getNodeIPByName $NODE1)
    NODE_2_IP=$(getNodeIPByName $NODE2)

    if [ -z "$NODE_1_IP" ] || [ -z "$NODE_2_IP" ]; then
        echo "Error: Could not get the node IPs"
        exit 1
    fi

    POD_LOCAL_1=$(getPodsWithPrefixOnNode "netperf-host" $NODE1)
    POD_LOCAL_2=$(getPodsWithPrefixOnNode "netperf-host" $NODE2)
    POD_REMOTE_1=$(getPodsWithPrefixOnNode "netperf-pod" $NODE1)
    POD_REMOTE_2=$(getPodsWithPrefixOnNode "netperf-pod" $NODE2)

    if [ -z "$POD_LOCAL_1" ] || [ -z "$POD_LOCAL_2" ] || [ -z "$POD_REMOTE_1" ] || [ -z "$POD_REMOTE_2" ]; then
        echo "Error: Could not get the pod names"
        exit 1
    fi

    POD_LOCAL_1_IP=$(getPodIPByName $POD_LOCAL_1)
    POD_LOCAL_2_IP=$(getPodIPByName $POD_LOCAL_2)
    POD_REMOTE_1_IP=$(getPodIPByName $POD_REMOTE_1)
    POD_REMOTE_2_IP=$(getPodIPByName $POD_REMOTE_2)

    if [ -z "$POD_LOCAL_1_IP" ] || [ -z "$POD_LOCAL_2_IP" ] || [ -z "$POD_REMOTE_1_IP" ] || [ -z "$POD_REMOTE_2_IP" ]; then
        echo "Error: Could not get the pod IPs"
        exit 1
    fi
}

getK8sInfo

echo "********** Ping Node to Node **********"
pingFunc $POD_LOCAL_1 $NODE_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_LOCAL_2 $NODE_1_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_LOCAL_1 $POD_LOCAL_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_LOCAL_2 $POD_LOCAL_1_IP $PING_INTERVAL $PING_COUNT
echo "***************************************"
echo ""

echo "********** Ping Node to Pod **********"
pingFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_REMOTE_1 $NODE_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_REMOTE_2 $NODE_1_IP $PING_INTERVAL $PING_COUNT
echo "**************************************"
echo ""

echo "********** Ping Pod to Pod **********"
pingFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $PING_INTERVAL $PING_COUNT
echo "*************************************"
echo ""
