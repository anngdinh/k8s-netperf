#!/bin/bash

CONTAINER_NAME="netperf"

PING_INTERVAL=0.001
PING_COUNT=30000

IPERF_TIME=60

NETPERF_TIME=60
NETPERF_REQUEST_PACKET_SIZE=1024
NETPERF_RESPONSE_PACKET_SIZE=1024

WRK_TIME=10
WRK_CONNECTIONS=100
WRK_THREADS=10

NODE_1="$NODE_1"
NODE_2="$NODE_2"
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
    echo "- Running: kubectl exec -it $pod -c $CONTAINER_NAME -- ping -c $count -i $interval -q $target_ip"
    local output=$(kubectl exec -it $pod -c $CONTAINER_NAME -- ping -c $count -i $interval -q $target_ip)
    echo "$output" | tail -n 2
}

iperfFunc() {
    local pod=$1
    local target_ip=$2
    local time=$3
    echo "- Running: kubectl exec -it $pod -c $CONTAINER_NAME -- iperf -c $target_ip -i 1 -t $time"
    local output=$(kubectl exec -it $pod -c $CONTAINER_NAME -- iperf -c $target_ip -i 1 -t $time)
    echo "[ ID] Interval       Transfer     Bandwidth"
    echo "$output" | tail -n 1
}

netperfFunc() {
    local pod=$1
    local target_ip=$2
    local time=$3
    local type=$4
    local format=$5
    echo "- Running: kubectl exec -it $pod -c $CONTAINER_NAME -- netperf -H $target_ip -p 12865 -l $time -t $type -- -P 10001,10002 -r $NETPERF_REQUEST_PACKET_SIZE,$NETPERF_RESPONSE_PACKET_SIZE -o \"$format\""
    local output=$(kubectl exec -it $pod -c $CONTAINER_NAME -- netperf -H $target_ip -p 12865 -l $time -t $type -- -P 10001,10002 -r $NETPERF_REQUEST_PACKET_SIZE,$NETPERF_RESPONSE_PACKET_SIZE -o "$format")
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

wrkFunc() {
    local pod=$1
    local target_ip=$2
    local time=$3
    local connections=$4
    local threads=$5
    local port=$6
    echo "- Running: kubectl exec -it $pod -c $CONTAINER_NAME -- wrk -t$threads -c$connections -d$time http://$target_ip:$port"
    local output=$(kubectl exec -it $pod -c $CONTAINER_NAME -- wrk -t$threads -c$connections -d$time http://$target_ip:$port)
    echo "$output"
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
    if [ -z "$NODE_1" ]; then
        NODE_1=$(echo "$nodes" | sed -n '1p')
    fi
    if [ -z "$NODE_2" ]; then
        NODE_2=$(echo "$nodes" | sed -n '2p')
    fi

    if [ -z "$NODE_1" ] || [ -z "$NODE_2" ]; then
        echo "Error: Could not get the node names"
        exit 1
    fi

    NODE_1_IP=$(getNodeIPByName $NODE_1)
    NODE_2_IP=$(getNodeIPByName $NODE_2)

    if [ -z "$NODE_1_IP" ] || [ -z "$NODE_2_IP" ]; then
        echo "Error: Could not get the node IPs"
        exit 1
    fi

    POD_LOCAL_1=$(getPodsWithPrefixOnNode "netperf-host" $NODE_1)
    POD_LOCAL_2=$(getPodsWithPrefixOnNode "netperf-host" $NODE_2)
    POD_REMOTE_1=$(getPodsWithPrefixOnNode "netperf-pod" $NODE_1)
    POD_REMOTE_2=$(getPodsWithPrefixOnNode "netperf-pod" $NODE_2)

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

    echo "NODE_1: $NODE_1"
    echo "NODE_2: $NODE_2"
    echo "POD_LOCAL_1: $POD_LOCAL_1"
    echo "POD_LOCAL_2: $POD_LOCAL_2"
    echo "POD_REMOTE_1: $POD_REMOTE_1"
    echo "POD_REMOTE_2: $POD_REMOTE_2"
}

getK8sInfo

get_avg_rtt() {
    local ping_output=$1
    echo "$ping_output" | grep "rtt min/avg/max/mdev" | awk -F'/' '{print $5}'
}

get_bandwidth_mbits() {
    local iperf_output=$1
    local bandwidth_value=$(echo "$iperf_output" | grep -Eo '[0-9]+\.[0-9]+ (Gbits/sec|Mbits/sec)|[0-9]+ (Gbits/sec|Mbits/sec)')
    local value=$(echo "$bandwidth_value" | awk '{print $1}')
    local unit=$(echo "$bandwidth_value" | awk '{print $2}')

    if [[ "$unit" == "Gbits/sec" ]]; then
        value=$(echo "$value * 1000" | bc)  # Convert Gbits/sec to Mbits/sec
    fi

    echo "$value"
}

get_p90_latency() {
    local data=$1
    echo "$data" | awk -F, 'NR==3 {print $4}'
}

get_avg_latency() {
    local data=$1

    # Extract average Latency
    avg_latency=$(echo "$data" | grep "Latency" | awk '{print $2}')

    echo "$avg_latency"
}

get_avg_req_per_sec() {
    local data=$1

    # Extract average Req/Sec
    avg_req_per_sec=$(echo "$data" | grep "Req/Sec" | awk '{print $2}')

    echo "$avg_req_per_sec"
}

echo "********** Ping Node to Node ********** $(date +"%Y-%m-%d %H:%M:%S")"
# pingFunc $POD_LOCAL_1 $NODE_2_IP $PING_INTERVAL $PING_COUNT
# pingFunc $POD_LOCAL_2 $NODE_1_IP $PING_INTERVAL $PING_COUNT
# pingFunc $POD_LOCAL_1 $POD_LOCAL_2_IP $PING_INTERVAL $PING_COUNT
# pingFunc $POD_LOCAL_2 $POD_LOCAL_1_IP $PING_INTERVAL $PING_COUNT

output=$(pingFunc $POD_LOCAL_1 $NODE_2_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_nn_1=$(get_avg_rtt "$output")

output=$(pingFunc $POD_LOCAL_2 $NODE_1_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_nn_2=$(get_avg_rtt "$output")

output=$(pingFunc $POD_LOCAL_1 $POD_LOCAL_2_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_nn_3=$(get_avg_rtt "$output")

output=$(pingFunc $POD_LOCAL_2 $POD_LOCAL_1_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_nn_4=$(get_avg_rtt "$output")
echo "***************************************"
echo ""

echo "********** Ping Node to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# pingFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $PING_INTERVAL $PING_COUNT
# pingFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $PING_INTERVAL $PING_COUNT
# pingFunc $POD_REMOTE_1 $NODE_2_IP $PING_INTERVAL $PING_COUNT
# pingFunc $POD_REMOTE_2 $NODE_1_IP $PING_INTERVAL $PING_COUNT

output=$(pingFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_np_1=$(get_avg_rtt "$output")

output=$(pingFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_np_2=$(get_avg_rtt "$output")

output=$(pingFunc $POD_REMOTE_1 $NODE_2_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_np_3=$(get_avg_rtt "$output")

output=$(pingFunc $POD_REMOTE_2 $NODE_1_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_np_4=$(get_avg_rtt "$output")
echo "**************************************"
echo ""

echo "********** Ping Pod to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# pingFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $PING_INTERVAL $PING_COUNT
# pingFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $PING_INTERVAL $PING_COUNT

output=$(pingFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_pp_1=$(get_avg_rtt "$output")

output=$(pingFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $PING_INTERVAL $PING_COUNT)
echo "$output"
annd2_ping_pp_2=$(get_avg_rtt "$output")
echo "*************************************"
echo ""

# echo "********** Ping Pod to Service ********** $(date +"%Y-%m-%d %H:%M:%S")"
# can't ping service IP
# echo "*****************************************"
# echo ""

############ Iperf ############
echo "********** Iperf Node to Node ********** $(date +"%Y-%m-%d %H:%M:%S")"
# iperfFunc $POD_LOCAL_1 $NODE_2_IP $IPERF_TIME
# iperfFunc $POD_LOCAL_2 $NODE_1_IP $IPERF_TIME

output=$(iperfFunc $POD_LOCAL_1 $NODE_2_IP $IPERF_TIME)
echo "$output"
annd2_iperf_nn_1=$(get_bandwidth_mbits "$output")

output=$(iperfFunc $POD_LOCAL_2 $NODE_1_IP $IPERF_TIME)
echo "$output"
annd2_iperf_nn_2=$(get_bandwidth_mbits "$output")
echo "****************************************"
echo ""

echo "********** Iperf Node to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# iperfFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $IPERF_TIME
# iperfFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $IPERF_TIME

output=$(iperfFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $IPERF_TIME)
echo "$output"
annd2_iperf_np_1=$(get_bandwidth_mbits "$output")

output=$(iperfFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $IPERF_TIME)
echo "$output"
annd2_iperf_np_2=$(get_bandwidth_mbits "$output")
echo "***************************************"
echo ""

echo "********** Iperf Pod to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# iperfFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $IPERF_TIME
# iperfFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $IPERF_TIME

output=$(iperfFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $IPERF_TIME)
echo "$output"
annd2_iperf_pp_1=$(get_bandwidth_mbits "$output")

output=$(iperfFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $IPERF_TIME)
echo "$output"
annd2_iperf_pp_2=$(get_bandwidth_mbits "$output")
echo "**************************************"
echo ""

echo "********** Iperf Pod to Service ********** $(date +"%Y-%m-%d %H:%M:%S")"
# iperfFunc $POD_REMOTE_1 $SERVICE_IP $IPERF_TIME
# iperfFunc $POD_REMOTE_2 $SERVICE_IP $IPERF_TIME

output=$(iperfFunc $POD_REMOTE_1 $SERVICE_IP $IPERF_TIME)
echo "$output"
annd2_iperf_ps_1=$(get_bandwidth_mbits "$output")

output=$(iperfFunc $POD_REMOTE_2 $SERVICE_IP $IPERF_TIME)
echo "$output"
annd2_iperf_ps_2=$(get_bandwidth_mbits "$output")
echo "******************************************"
echo ""

############ Netperf long connection ############
echo "********** Netperf Long Node to Node ********** $(date +"%Y-%m-%d %H:%M:%S")"
# netperfFunc $POD_LOCAL_1 $NODE_2_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
# netperfFunc $POD_LOCAL_2 $NODE_1_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"

output=$(netperfFunc $POD_LOCAL_1 $NODE_2_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_long_nn_1=$(get_p90_latency "$output")

output=$(netperfFunc $POD_LOCAL_2 $NODE_1_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_long_nn_2=$(get_p90_latency "$output")
echo "***********************************************"
echo ""

echo "********** Netperf Long Node to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# netperfFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
# netperfFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"

output=$(netperfFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_long_np_1=$(get_p90_latency "$output")

output=$(netperfFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_long_np_2=$(get_p90_latency "$output")
echo "**********************************************"
echo ""

echo "********** Netperf Long Pod to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# netperfFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
# netperfFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"

output=$(netperfFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_long_pp_1=$(get_p90_latency "$output")

output=$(netperfFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_long_pp_2=$(get_p90_latency "$output")
echo "*********************************************"
echo ""

echo "********** Netperf Long Pod to Service ********** $(date +"%Y-%m-%d %H:%M:%S")"
# netperfFunc $POD_REMOTE_1 $SERVICE_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
# netperfFunc $POD_REMOTE_2 $SERVICE_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"

output=$(netperfFunc $POD_REMOTE_1 $SERVICE_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_long_ps_1=$(get_p90_latency "$output")

output=$(netperfFunc $POD_REMOTE_2 $SERVICE_IP $NETPERF_TIME TCP_RR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_long_ps_2=$(get_p90_latency "$output")
echo "*************************************************"
echo ""

# ############ Netperf short connection ############
echo "********** Netperf Short Node to Node ********** $(date +"%Y-%m-%d %H:%M:%S")"
# netperfFunc $POD_LOCAL_1 $NODE_2_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
# netperfFunc $POD_LOCAL_2 $NODE_1_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"

output=$(netperfFunc $POD_LOCAL_1 $NODE_2_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_short_nn_1=$(get_p90_latency "$output")

output=$(netperfFunc $POD_LOCAL_2 $NODE_1_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_short_nn_2=$(get_p90_latency "$output")
echo "************************************************"
echo ""

echo "********** Netperf Short Node to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# netperfFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
# netperfFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"

output=$(netperfFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_short_np_1=$(get_p90_latency "$output")

output=$(netperfFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_short_np_2=$(get_p90_latency "$output")
echo "***********************************************"
echo ""

echo "********** Netperf Short Pod to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# netperfFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
# netperfFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"

output=$(netperfFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_short_pp_1=$(get_p90_latency "$output")

output=$(netperfFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_short_pp_2=$(get_p90_latency "$output")
echo "**********************************************"
echo ""

echo "********** Netperf Short Pod to Service ********** $(date +"%Y-%m-%d %H:%M:%S")"
# netperfFunc $POD_REMOTE_1 $SERVICE_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"
# netperfFunc $POD_REMOTE_2 $SERVICE_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY"

output=$(netperfFunc $POD_REMOTE_1 $SERVICE_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_short_ps_1=$(get_p90_latency "$output")

output=$(netperfFunc $POD_REMOTE_2 $SERVICE_IP $NETPERF_TIME TCP_CRR "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY")
echo "$output"
annd2_netperf_short_ps_2=$(get_p90_latency "$output")
echo "**************************************************"
echo ""

# ############ Wrk ############
echo "********** Wrk Node to Node ********** $(date +"%Y-%m-%d %H:%M:%S")"
# wrkFunc $POD_LOCAL_1 $NODE_2_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80
# wrkFunc $POD_LOCAL_2 $NODE_1_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80

output=$(wrkFunc $POD_LOCAL_1 $NODE_2_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80)
echo "$output"
annd2_wrk_latency_nn_1=$(get_avg_latency "$output")
annd2_wrk_reqpsec_nn_1=$(get_avg_req_per_sec "$output")

output=$(wrkFunc $POD_LOCAL_2 $NODE_1_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80)
echo "$output"
annd2_wrk_latency_nn_2=$(get_avg_latency "$output")
annd2_wrk_reqpsec_nn_2=$(get_avg_req_per_sec "$output")
echo "**************************************"
echo ""

echo "********** Wrk Node to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# wrkFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80
# wrkFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80

output=$(wrkFunc $POD_LOCAL_1 $POD_REMOTE_2_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80)
echo "$output"
annd2_wrk_latency_np_1=$(get_avg_latency "$output")
annd2_wrk_reqpsec_np_1=$(get_avg_req_per_sec "$output")

output=$(wrkFunc $POD_LOCAL_2 $POD_REMOTE_1_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80)
echo "$output"
annd2_wrk_latency_np_2=$(get_avg_latency "$output")
annd2_wrk_reqpsec_np_2=$(get_avg_req_per_sec "$output")
echo "*************************************"
echo ""

echo "********** Wrk Pod to Pod ********** $(date +"%Y-%m-%d %H:%M:%S")"
# wrkFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80
# wrkFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80

output=$(wrkFunc $POD_REMOTE_1 $POD_REMOTE_2_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80)
echo "$output"
annd2_wrk_latency_pp_1=$(get_avg_latency "$output")
annd2_wrk_reqpsec_pp_1=$(get_avg_req_per_sec "$output")

output=$(wrkFunc $POD_REMOTE_2 $POD_REMOTE_1_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80)
echo "$output"
annd2_wrk_latency_pp_2=$(get_avg_latency "$output")
annd2_wrk_reqpsec_pp_2=$(get_avg_req_per_sec "$output")
echo "************************************"
echo ""

echo "********** Wrk Pod to Service ********** $(date +"%Y-%m-%d %H:%M:%S")"
# wrkFunc $POD_REMOTE_1 $SERVICE_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80
# wrkFunc $POD_REMOTE_2 $SERVICE_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80

output=$(wrkFunc $POD_REMOTE_1 $SERVICE_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80)
echo "$output"
annd2_wrk_latency_ps_1=$(get_avg_latency "$output")
annd2_wrk_reqpsec_ps_1=$(get_avg_req_per_sec "$output")

output=$(wrkFunc $POD_REMOTE_2 $SERVICE_IP $WRK_TIME $WRK_CONNECTIONS $WRK_THREADS 80)
echo "$output"
annd2_wrk_latency_ps_2=$(get_avg_latency "$output")
annd2_wrk_reqpsec_ps_2=$(get_avg_req_per_sec "$output")
echo "***************************************"

echo "-------------------RESULT-------------------"
echo -n "$annd2_ping_nn_1,$annd2_ping_nn_2,$annd2_ping_nn_3,$annd2_ping_nn_4,"
echo -n "$annd2_ping_np_1,$annd2_ping_np_2,$annd2_ping_np_3,$annd2_ping_np_4,"
echo -n "$annd2_ping_pp_1,$annd2_ping_pp_2,"

echo -n "$annd2_iperf_nn_1,$annd2_iperf_nn_2,"
echo -n "$annd2_iperf_np_1,$annd2_iperf_np_2,"
echo -n "$annd2_iperf_pp_1,$annd2_iperf_pp_2,"
echo -n "$annd2_iperf_ps_1,$annd2_iperf_ps_2,"

echo -n "$annd2_netperf_long_nn_1,$annd2_netperf_long_nn_2,"
echo -n "$annd2_netperf_long_np_1,$annd2_netperf_long_np_2,"
echo -n "$annd2_netperf_long_pp_1,$annd2_netperf_long_pp_2,"
echo -n "$annd2_netperf_long_ps_1,$annd2_netperf_long_ps_2,"

echo -n "$annd2_netperf_short_nn_1,$annd2_netperf_short_nn_2,"
echo -n "$annd2_netperf_short_np_1,$annd2_netperf_short_np_2,"
echo -n "$annd2_netperf_short_pp_1,$annd2_netperf_short_pp_2,"
echo -n "$annd2_netperf_short_ps_1,$annd2_netperf_short_ps_2,"

echo -n "$annd2_wrk_latency_nn_1,$annd2_wrk_latency_nn_2,$annd2_wrk_reqpsec_nn_1,$annd2_wrk_reqpsec_nn_2,"
echo -n "$annd2_wrk_latency_np_1,$annd2_wrk_latency_np_2,$annd2_wrk_reqpsec_np_1,$annd2_wrk_reqpsec_np_2,"
echo -n "$annd2_wrk_latency_pp_1,$annd2_wrk_latency_pp_2,$annd2_wrk_reqpsec_pp_1,$annd2_wrk_reqpsec_pp_2,"
echo "$annd2_wrk_latency_ps_1,$annd2_wrk_latency_ps_2,$annd2_wrk_reqpsec_ps_1,$annd2_wrk_reqpsec_ps_2"
echo "-------------------------------------------"
