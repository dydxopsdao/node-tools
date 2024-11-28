#!/bin/bash

# This script follows the official guide at:
# https://docs.dydx.exchange/infrastructure_providers-validators/set_up_full_node
# It adds readability tweaks and comments.

# Strict error handling
set -e

# User constants
NODE_NAME=my-full-node-testnet-$RANDOM
PROTOCOLD_VERSION=v7.0.1

# Chain-specific constants (see: https://docs.dydx.exchange/infrastructure_providers-network/resources)
CHAIN_ID=dydx-testnet-4
BASE_SNAPSHOT_URL="https://snapshots.polkachu.com/snapshots/"
SEED_NODES=(
    "19d38bb5cea1378db3e16615e63594dc26119a1a@dydx-testnet4-seednode.allthatnode.com:26656"
    "87ee8de5f0f82af6ee6740a30f8844bbe6434413@seed.dydx-testnet.cros-nest.com:26656"
    "38e5a5ec34c578dc323cbdd9b98330abb448d586@tenderseed.ccvalidators.com:29104"
    "80a1a6cd086634c34008c6457d3f7441cfc05c47@seeds.kingnodes.com:27056"
    "182ab0015fb4b7d751b12a9c0162ac123445eac1@seed.dydx-testnet.stakingcabin.com:26656"
    "76b472b107ccf20c3d6c110c4a2a217306d2dedb@dydx-seed.staker.space:26656"
)

# Other constants
DAEMON_HOME=$HOME/.dydxprotocol
GO_VERSION=1.22.2
WHITE='\033[1;37m'
NC='\033[0m' # No Color
ARCH=$(case $(uname -m) in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    *) echo "Unsupported architecture: $(uname -m). Only amd64 and arm64 are supported." && exit 1 ;;
esac)

# ----------------------------

function install_dependencies() {
    cd $HOME
    sudo apt-get -y update
    sudo apt-get install -y curl jq lz4
}

function setup_golang() {
    wget https://golang.org/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-${ARCH}.tar.gz
    rm go${GO_VERSION}.linux-${ARCH}.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bashrc
    . ~/.bashrc
}

function setup_cosmovisor() {
    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
    mkdir -p $DAEMON_HOME/cosmovisor/genesis/bin
    mkdir -p $DAEMON_HOME/cosmovisor/upgrades
}

function setup_dydx_binary() {
    curl -L -O https://github.com/dydxprotocol/v4-chain/releases/download/protocol%2F${PROTOCOLD_VERSION}/dydxprotocold-${PROTOCOLD_VERSION}-linux-${ARCH}.tar.gz
    sudo tar -xzvf dydxprotocold-${PROTOCOLD_VERSION}-linux-${ARCH}.tar.gz
    sudo mv ./build/dydxprotocold-${PROTOCOLD_VERSION}-linux-${ARCH} $DAEMON_HOME/cosmovisor/genesis/bin/dydxprotocold
    rm dydxprotocold-${PROTOCOLD_VERSION}-linux-${ARCH}.tar.gz
    rm -rf build
    echo 'export PATH=$PATH:$DAEMON_HOME/cosmovisor/current/bin' >> $HOME/.bashrc
    . ~/.bashrc
}

function initialize_node() {
    $DAEMON_HOME/cosmovisor/genesis/bin/dydxprotocold init --chain-id=$CHAIN_ID $NODE_NAME
    sed -i 's/seeds = ""/seeds = "'"${SEED_NODES[*]}"'"/' $DAEMON_HOME/config/config.toml
}

function setup_snapshot() {
    cp $DAEMON_HOME/data/priv_validator_state.json $DAEMON_HOME/priv_validator_state.json.backup
    rm -rf $DAEMON_HOME/data

    SNAPSHOT_FILENAME=$(curl -s ${BASE_SNAPSHOT_URL} | grep -oP 'dydx_\d+\.tar\.lz4' | sort -V | tail -n 1)
    SNAPSHOT_URL="${BASE_SNAPSHOT_URL}/dydx/${SNAPSHOT_FILENAME}"

    cd $DAEMON_HOME
    wget $SNAPSHOT_URL
    SNAPSHOT_FILENAME=$(basename $SNAPSHOT_URL)
    lz4 -dc < $SNAPSHOT_FILENAME | tar xf -
    
    mv $DAEMON_HOME/priv_validator_state.json.backup $DAEMON_HOME/data/priv_validator_state.json
}

function setup_systemd() {
    sudo tee /etc/systemd/system/dydxprotocold.service > /dev/null << EOF
[Unit]
Description=dydxprotocol node service
After=network-online.target
 
[Service]
User=$USER
ExecStart=/$HOME/go/bin/cosmovisor run start --non-validating-full-node=true
WorkingDirectory=$DAEMON_HOME
Restart=always
RestartSec=5
LimitNOFILE=4096
Environment="DAEMON_HOME=$DAEMON_HOME"
Environment="DAEMON_NAME=dydxprotocold"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"
 
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable dydxprotocold
}

function main() {
    echo -e "${WHITE}🔧 Installing system dependencies...${NC}"
    install_dependencies

    echo -e "${WHITE}🚀 Setting up Golang ${GO_VERSION}...${NC}"
    setup_golang

    echo -e "${WHITE}📦 Installing Cosmovisor...${NC}"
    setup_cosmovisor

    echo -e "${WHITE}⚙️  Setting up dYdX binary...${NC}"
    setup_dydx_binary

    echo -e "${WHITE}🌟 Initializing node as '${NODE_NAME}'...${NC}"
    initialize_node

    echo -e "${WHITE}📥 Downloading and setting up snapshot...${NC}"
    setup_snapshot

    echo -e "${WHITE}🔄 Configuring systemd service...${NC}"
    setup_systemd
}

main

echo -e "${WHITE}✅ Setup complete! The node is ready to start.${NC}"
echo ""
echo -e "${WHITE}=== To start your node, run: ===${NC}"
echo "sudo systemctl start dydxprotocold"
echo ""
echo -e "${WHITE}=== Other handy commands: ===${NC}"
echo "# Stop the node:          sudo systemctl stop dydxprotocold"
echo "# Check the node status:  sudo systemctl status dydxprotocold" 
echo "# See logs:               sudo journalctl -u dydxprotocold -f"
echo "# See open ports:         sudo netstat -tpln"
echo "# See block height:       curl -s http://localhost:26657/status | jq -r '.result.sync_info.latest_block_height'"
echo "# See app version:        curl -s http://localhost:1317/cosmos/base/tendermint/v1beta1/node_info | jq -r '.application_version.version'"
echo "# See prometheus metrics: curl http://localhost:26660/metrics"
