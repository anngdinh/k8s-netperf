#!/bin/sh

PING_INTERVAL=0.001
PING_COUNT=30000

IPERF_TIME=60

NETPERF_TIME=60
NETPERF_REQUEST_PACKET_SIZE=1024
NETPERF_RESPONSE_PACKET_SIZE=1024

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

SERVICE="netperf-service"
SERVICE_IP=""

remove_all_whitespace() {
    echo "$1" | tr -d '[:space:]'
}

pingFunc() {
    local pod=$1
    local target_ip=$2
    local interval=$3
    local count=$4
    echo "- Running: kubectl exec -it $pod -- ping -c $count -i $interval -q $target_ip"
    local output=$(kubectl exec -it $pod -- ping -c $count -i $interval -q $target_ip)
    echo "$output" | tail -n 2
}

iperfFunc() {
    local pod=$1
    local target_ip=$2
    local time=$3
    echo "- Running: kubectl exec -it $pod -- iperf -c $target_ip -i 1 -t $time"
    local output=$(kubectl exec -it $pod -- iperf -c $target_ip -i 1 -t $time)
    echo "[ ID] Interval       Transfer     Bandwidth"
    echo "$output" | tail -n 1
}

netperfFunc() {
    local pod=$1
    local target_ip=$2
    local time=$3
    local type=$4
    local format=$5
    echo "- Running: kubectl exec -it $pod -- netperf -H $target_ip -p 12865 -l $time -t $type -- -P 10001,10002 -r $NETPERF_REQUEST_PACKET_SIZE,$NETPERF_RESPONSE_PACKET_SIZE -o \"$format\""
    local output=$(kubectl exec -it $pod -- netperf -H $target_ip -p 12865 -l $time -t $type -- -P 10001,10002 -r $NETPERF_REQUEST_PACKET_SIZE,$NETPERF_RESPONSE_PACKET_SIZE -o "$format")
    # echo "$output" | tail -n 2

    key=$(remove_all_whitespace "$format")
    value=$(remove_all_whitespace "$(echo "$output" | tail -n 1)")
    # echo "key: $key"
    # echo "value: $value"

    # Convert the comma-separated strings into arrays
    IFS=',' set -- $key
    keys="$@"

    IFS=',' set -- $value
    values="$@"

    # Print the header row
    for k in $keys; do
        printf "%-15s" "$k"
    done
    printf "\n"

    # Print the value row
    for v in $values; do
        printf "%-15s" "$v"
    done
    printf "\n"
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
    if [ -z "$NODE1" ]; then
        NODE1=$(echo "$nodes" | sed -n '1p')
    fi
    if [ -z "$NODE2" ]; then
        NODE2=$(echo "$nodes" | sed -n '2p')
    fi

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

    SERVICE_IP=$(kubectl get svc $SERVICE -o jsonpath='{.spec.clusterIP}')
    if [ -z "$SERVICE_IP" ]; then
        echo "Error: Could not get service IP"
        exit 1
    fi
}

getK8sInfo

echo "********** Ping Node to Node ********** $(date +"%Y-%m-%d %H:%M:%S")"
pingFunc $POD_LOCAL_1 $NODE_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_LOCAL_2 $NODE_1_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_LOCAL_1 $POD_LOCAL_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_LOCAL_2 $POD_LOCAL_1_IP $PING_INTERVAL $PING_COUNT
echo "***************************************"
echo ""

echo "********** Ping Node to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
pingFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_REMOTE_1 $NODE_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_REMOTE_2 $NODE_1_IP $PING_INTERVAL $PING_COUNT
echo "**************************************"
echo ""

echo "********** Ping Pod to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
pingFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $PING_INTERVAL $PING_COUNT
pingFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $PING_INTERVAL $PING_COUNT
echo "*************************************"
echo ""

# echo "********** Ping Pod to Service ********** $(date +"%Y-%m-%d %H:%M:%S")"
# can't ping service IP
# echo "*****************************************"
# echo ""

############ Iperf ############
echo "********** Iperf Node to Node ********** $(date +"%Y-%m-%d %H:%M:%S")"
iperfFunc $POD_LOCAL_1 $NODE_2_IP $IPERF_TIME
iperfFunc $POD_LOCAL_2 $NODE_1_IP $IPERF_TIME
echo "****************************************"
echo ""

echo "********** Iperf Node to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
iperfFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $IPERF_TIME
iperfFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $IPERF_TIME
echo "***************************************"
echo ""

echo "********** Iperf Pod to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
iperfFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $IPERF_TIME
iperfFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $IPERF_TIME
echo "**************************************"
echo ""

echo "********** Iperf Pod to Service ********** $(date +"%Y-%m-%d %H:%M:%S")"
iperfFunc $POD_REMOTE_1 $SERVICE_IP $IPERF_TIME
iperfFunc $POD_REMOTE_2 $SERVICE_IP $IPERF_TIME
echo "******************************************"
echo ""

############ Netperf long connection ############
echo "********** Netperf Long Node to Node ********** $(date +"%Y-%m-%d %H:%M:%S")"
netperfFunc $POD_LOCAL_1 $NODE_2_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
netperfFunc $POD_LOCAL_2 $NODE_1_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
echo "***********************************************"
echo ""

echo "********** Netperf Long Node to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
netperfFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
netperfFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
echo "**********************************************"
echo ""

echo "********** Netperf Long Pod to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
netperfFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
netperfFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
echo "*********************************************"
echo ""

echo "********** Netperf Long Pod to Service ********** $(date +"%Y-%m-%d %H:%M:%S")"
netperfFunc $POD_REMOTE_1 $SERVICE_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
netperfFunc $POD_REMOTE_2 $SERVICE_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
echo "*************************************************"
echo ""

# ############ Netperf short connection ############
echo "********** Netperf Short Node to Node ********** $(date +"%Y-%m-%d %H:%M:%S")"
netperfFunc $POD_LOCAL_1 $NODE_2_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
netperfFunc $POD_LOCAL_2 $NODE_1_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
echo "************************************************"
echo ""

echo "********** Netperf Short Node to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
netperfFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
netperfFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
echo "***********************************************"
echo ""

echo "********** Netperf Short Pod to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
netperfFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
netperfFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
echo "**********************************************"
echo ""

echo "********** Netperf Short Pod to Service ********** $(date +"%Y-%m-%d %H:%M:%S")"
netperfFunc $POD_REMOTE_1 $SERVICE_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
netperfFunc $POD_REMOTE_2 $SERVICE_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
echo "**************************************************"
echo ""
