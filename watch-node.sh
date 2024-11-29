#!/bin/bash

usage() {
    echo "Usage: $0 <node-ip>"
    echo "Example: $0 111.222.333.444"
    echo "Monitors the status of a dYdX node, displaying block height, version, and sync status"
    exit 1
}

# Check if IP address is provided
[[ $# -ne 1 ]] && usage

probe () {
    NODE_IP="$1"
    STATUS=$(dydxprotocold status --node http://${NODE_IP}:26657)
    NODE_INFO=$(curl -s http://${NODE_IP}:1317/cosmos/base/tendermint/v1beta1/node_info)
    printf "%-18s %s\n" \
          "Node moniker:" "$(echo ${STATUS} | jq -r '.node_info.moniker')"
    printf "%-18s %s\n" \
          "Node ID:" "$(echo ${STATUS} | jq -r '.node_info.id')"
    printf "%-18s %s\n" \
          "Block height:" "$(echo ${STATUS} | jq -r '.sync_info.latest_block_height')"
    printf "%-18s %s\n" \
          "Protocol version:" "$(echo ${NODE_INFO} | jq -r '.application_version.version')"
    printf "%-18s %s\n" \
          "Is catching up:" "$(echo ${STATUS} | jq -r '.sync_info.catching_up')"
}

export -f probe
watch -n 0 "probe $1"
