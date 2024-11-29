#!/bin/bash
#
# schedule-upgrade.sh - Schedules dYdX Protocol binary upgrades using Cosmovisor
#
# This script automates the upgrade process for dYdX Protocol validator nodes by:
# 1. Downloading the specified version of dydxprotocold from GitHub releases
# 2. Extracting the binary to a temporary location
# 3. Moving the binary to the daemon home directory
# 4. Scheduling an upgrade through Cosmovisor at current_height + blocks_ahead
#
# Requirements:
# - Cosmovisor must be installed and configured
# - Active validator node with RPC endpoint accessible at localhost:26657
# - Proper permissions to execute Cosmovisor commands

# Strict error handling
set -e

# Constants
readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
readonly DEFAULT_BLOCKS_AHEAD=100
readonly DEFAULT_DAEMON_HOME="${HOME}/.dydxprotocol"
readonly DEFAULT_DAEMON_NAME="dydxprotocold"

# Input variables
target_version=""
blocks_ahead=$DEFAULT_BLOCKS_AHEAD
daemon_home=${DAEMON_HOME:-"$DEFAULT_DAEMON_HOME"}
daemon_name=${DAEMON_NAME:-"$DEFAULT_DAEMON_NAME"}

# Temporary directory to be set after target version is set
temp_dir=""

# CPU architecture
ARCH=$(case $(uname -m) in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    *) echo "Unsupported architecture: $(uname -m). Only amd64 and arm64 are supported." && exit 1 ;;
esac)

###################
# Logging Functions
###################
log_info() { echo >&2 -e "[INFO] $*"; }
log_warn() { echo >&2 -e "[WARN] $*"; }
log_error() { echo >&2 -e "[ERROR] $*"; }
log_fatal() { echo >&2 -e "[FATAL] $*"; exit 1; }

###################
# Helper Functions
###################
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Schedules a dYdX Protocol binary upgrade using Cosmovisor.

Required:
    --target-version <string>   Version to upgrade to (e.g., v7.0.1)

Optional:
    --blocks-ahead <int>        Number of blocks to wait before upgrade (default: ${DEFAULT_BLOCKS_AHEAD})
    --daemon-home <string>      Daemon home directory (default: ${DEFAULT_DAEMON_HOME})
    --daemon-name <string>      Daemon binary name (default: ${DEFAULT_DAEMON_NAME})
    --help                      Show this help message

Environment Variables:
    DAEMON_HOME                 Override daemon home directory (default: ${DEFAULT_DAEMON_HOME})
    DAEMON_NAME                 Override daemon binary name (default: ${DEFAULT_DAEMON_NAME})

Example:
    $SCRIPT_NAME --target-version v7.0.1 --blocks-ahead 100
EOF
    exit 1
}

cleanup() {
    if [[ -n "${temp_dir}" && -d "${temp_dir}" ]]; then
        log_info "Cleaning up temporary directory"
        rm -rf "${temp_dir}"
    fi
}

validate_inputs() {
    if [[ -z "${target_version}" ]]; then
        log_error "--target-version is required"
        usage
    fi
    
    if [[ ! "${blocks_ahead}" =~ ^[0-9]+$ ]]; then
        log_error "--blocks-ahead must be a positive integer"
        usage
    fi
}

get_latest_block_height() {
    local height
    height=$(curl -s http://127.0.0.1:26657/status | jq -r '.result.sync_info.latest_block_height') || \
        log_fatal "Failed to fetch latest block height"
    echo "${height}"
}

download_and_verify_binary() {
    local binary_filename="dydxprotocold-${target_version}-linux-${ARCH}"
    local binary_url="https://github.com/dydxprotocol/v4-chain/releases/download/protocol%2F${target_version}/${binary_filename}.tar.gz"
    
    log_info "Downloading binary from: ${binary_url}"
    wget -q "${binary_url}" || log_fatal "Failed to download binary"
    
    log_info "Extracting binary..."
    tar xzf "${binary_filename}.tar.gz" || log_fatal "Failed to extract binary"
    
    local binary_path="${temp_dir}/build/${binary_filename}"
    [[ ! -f "${binary_path}" ]] && log_fatal "Binary not found after extraction"
    
    echo "${binary_path}"
}

schedule_upgrade() {
    local binary_path=$1
    local upgrade_height=$2
    
    log_info "Scheduling upgrade at block height ${upgrade_height}"
    DAEMON_HOME="${daemon_home}" DAEMON_NAME="${daemon_name}" \
    cosmovisor add-upgrade "${target_version}" "${binary_path}" \
        --upgrade-height "${upgrade_height}" --force || \
        log_fatal "Failed to schedule upgrade"
}

###################
# Main Logic
###################
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target-version) target_version="$2"; shift 2 ;;
            --blocks-ahead) blocks_ahead="$2"; shift 2 ;;
            --daemon-home) daemon_home="$2"; shift 2 ;;
            --daemon-name) daemon_name="$2"; shift 2 ;;
            --help) usage ;;
            *) log_fatal "Unknown option: $1" ;;
        esac
    done

    # Validate inputs
    validate_inputs

    # Setup cleanup trap
    temp_dir="/tmp/protocold-upgrade-${target_version}"
    trap cleanup EXIT
    
    # Create and enter temp directory
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"

    # Main upgrade process
    log_info "Starting upgrade process for version: ${target_version}"
    
    local binary_path
    binary_path=$(download_and_verify_binary)
    
    log_info "Moving binary to ${daemon_home}"
    mv "${binary_path}" "${daemon_home}/"
    
    local latest_height
    latest_height=$(get_latest_block_height)
    log_info "Latest block height: ${latest_height}"
    
    local scheduled_height=$((latest_height + blocks_ahead))
    schedule_upgrade "${daemon_home}/$(basename "${binary_path}")" "${scheduled_height}"
    
    log_info "Upgrade successfully scheduled"
}

main "$@"
