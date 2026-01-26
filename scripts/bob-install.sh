#!/bin/bash
###############################################################################
# Bob Node Installation Script
# Installs the Qubic Bob Node (Indexer & REST API)
#
# Usage:
#   ./bob-install.sh [MODE] [OPTIONS]
#
# Modes:
#   docker-standalone   All-in-one Docker container (Bob + Redis + KVRocks)
#   docker-compose      Modular Docker setup (separate containers)
#   manual              Build from source with systemd service
#
# Options:
#   --peers <ip:port,...>   Trusted peers to sync from
#   --threads <n>           Max threads (0 = auto, default: 0)
#   --rpc-port <port>       REST API / JSON-RPC port (default: 40420)
#   --server-port <port>    P2P server port (default: 21842)
#   --data-dir <path>       Data directory (default: /opt/qubic-bob)
#
# Examples:
#   ./bob-install.sh docker-standalone
#   ./bob-install.sh docker-compose --peers 1.2.3.4:21841,5.6.7.8:21841
#   ./bob-install.sh manual --peers 1.2.3.4:21841 --threads 8
#
###############################################################################

set -e

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Defaults ────────────────────────────────────────────────────────────────
MODE=""
PEERS=""
MAX_THREADS=0
RPC_PORT=40420
SERVER_PORT=21842
DATA_DIR="/opt/qubic-bob"
REPO_URL="https://github.com/krypdkat/qubicbob.git"
DOCKER_IMAGE="j0et0m/qubic-bob:latest"

# ─── Functions ───────────────────────────────────────────────────────────────

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║          Bob Node Installation Script           ║"
    echo "║      Qubic Blockchain Indexer & REST API        ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_info "Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        log_info "Docker installed successfully"
    else
        log_info "Docker is already installed"
    fi

    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose plugin not found. Please install it."
        exit 1
    fi
}

parse_args() {
    MODE="$1"
    shift || true

    while [[ $# -gt 0 ]]; do
        case $1 in
            --peers)
                PEERS="$2"
                shift 2
                ;;
            --threads)
                MAX_THREADS="$2"
                shift 2
                ;;
            --rpc-port)
                RPC_PORT="$2"
                shift 2
                ;;
            --server-port)
                SERVER_PORT="$2"
                shift 2
                ;;
            --data-dir)
                DATA_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    if [ -z "$MODE" ]; then
        show_usage
        exit 1
    fi
}

show_usage() {
    echo "Usage: $0 [MODE] [OPTIONS]"
    echo ""
    echo "Modes:"
    echo "  docker-standalone   All-in-one Docker container"
    echo "  docker-compose      Modular Docker setup"
    echo "  manual              Build from source"
    echo ""
    echo "Options:"
    echo "  --peers <ip:port,...>   Trusted peers"
    echo "  --threads <n>          Max threads (0=auto)"
    echo "  --rpc-port <port>      REST API port (default: 40420)"
    echo "  --server-port <port>   P2P port (default: 21842)"
    echo "  --data-dir <path>      Data dir (default: /opt/qubic-bob)"
}

generate_config() {
    local config_file="$1"
    local keydb_host="${2:-127.0.0.1}"
    local kvrocks_host="${3:-127.0.0.1}"

    local trusted_nodes="[]"
    if [ -n "$PEERS" ]; then
        trusted_nodes="[$(echo "$PEERS" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/' )]"
    fi

    cat > "$config_file" << CONFIGEOF
{
  "p2p-node": [],
  "trusted-node": ${trusted_nodes},
  "request-cycle-ms": 100,
  "request-logging-cycle-ms": 30,
  "future-offset": 3,
  "log-level": "info",
  "keydb-url": "tcp://${keydb_host}:6379",
  "run-server": true,
  "server-port": ${SERVER_PORT},
  "rpc-port": ${RPC_PORT},
  "arbitrator-identity": "AFZPUAIYVPNUYGJRQVLUKOPPVLHAZQTGLYAAUUNBXFTVTAMSBKQBLEIEPCVJ",
  "tick-storage-mode": "kvrocks",
  "kvrocks-url": "tcp://${kvrocks_host}:6666",
  "tx-storage-mode": "kvrocks",
  "tx_tick_to_live": 10000,
  "max-thread": ${MAX_THREADS},
  "spam-qu-threshold": 100
}
CONFIGEOF

    log_info "Configuration written to ${config_file}"
}

# ─── Docker Standalone ───────────────────────────────────────────────────────

install_docker_standalone() {
    log_info "Installing Bob Node (Docker Standalone)..."
    check_docker

    mkdir -p "$DATA_DIR" && cd "$DATA_DIR"

    # Download docker-compose file
    curl -sSL -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.standalone.yml

    # Generate config
    generate_config "$DATA_DIR/bob.json" "127.0.0.1" "127.0.0.1"

    # Start
    docker compose -f docker-compose.standalone.yml up -d

    log_info "Bob Node (Standalone) is running!"
    log_info "P2P Port: ${SERVER_PORT}"
    log_info "RPC Port: ${RPC_PORT}"
    log_info "Data Dir: ${DATA_DIR}"
    echo ""
    log_info "Useful commands:"
    echo "  docker compose -f ${DATA_DIR}/docker-compose.standalone.yml logs -f"
    echo "  docker compose -f ${DATA_DIR}/docker-compose.standalone.yml restart"
    echo "  docker compose -f ${DATA_DIR}/docker-compose.standalone.yml down"
}

# ─── Docker Compose ──────────────────────────────────────────────────────────

install_docker_compose() {
    log_info "Installing Bob Node (Docker Compose)..."
    check_docker

    mkdir -p "$DATA_DIR" && cd "$DATA_DIR"

    # Download all required files
    curl -sSL -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.yml
    curl -sSL -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/keydb.conf
    curl -sSL -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/kvrocks.conf

    # Generate config with container hostnames
    generate_config "$DATA_DIR/bob.json" "keydb" "kvrocks"

    # Start
    docker compose up -d

    log_info "Bob Node (Docker Compose) is running!"
    log_info "P2P Port: ${SERVER_PORT}"
    log_info "RPC Port: ${RPC_PORT}"
    log_info "Data Dir: ${DATA_DIR}"
    echo ""
    log_info "Useful commands:"
    echo "  docker compose -C ${DATA_DIR} logs -f"
    echo "  docker compose -C ${DATA_DIR} restart"
    echo "  docker compose -C ${DATA_DIR} down"
}

# ─── Manual Build ────────────────────────────────────────────────────────────

install_manual() {
    log_info "Installing Bob Node (Build from Source)..."

    # Install dependencies
    log_info "Installing system dependencies..."
    apt update && apt upgrade -y
    apt install -y build-essential cmake git libjsoncpp-dev \
        uuid-dev libhiredis-dev zlib1g-dev unzip wget \
        net-tools tmux lsb-release

    # Install KeyDB
    log_info "Installing KeyDB..."
    if ! command -v keydb-server &> /dev/null; then
        echo "deb https://download.keydb.dev/open-source-dist $(lsb_release -sc) main" | \
            tee /etc/apt/sources.list.d/keydb.list
        wget -O /etc/apt/trusted.gpg.d/keydb.gpg https://download.keydb.dev/open-source-dist/keyring.gpg
        apt update
        apt install -y keydb
        systemctl enable keydb-server
        systemctl start keydb-server
    else
        log_info "KeyDB is already installed"
    fi

    # Install KVRocks
    log_info "Installing KVRocks..."
    if ! command -v kvrocks &> /dev/null; then
        cd /tmp
        git clone --branch v2.9.0 https://github.com/apache/kvrocks.git
        cd kvrocks
        mkdir -p build && cd build
        cmake .. -DCMAKE_BUILD_TYPE=Release
        make -j"$(nproc)"
        cp src/kvrocks /usr/local/bin/
        cd /tmp && rm -rf kvrocks

        # Create KVRocks systemd service
        cat > /etc/systemd/system/kvrocks.service << 'SERVICEEOF'
[Unit]
Description=KVRocks Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kvrocks --bind 0.0.0.0 --port 6666 --dir /var/lib/kvrocks
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

        mkdir -p /var/lib/kvrocks
        systemctl daemon-reload
        systemctl enable kvrocks
        systemctl start kvrocks
    else
        log_info "KVRocks is already installed"
    fi

    # Build Bob Node
    log_info "Building Bob Node..."
    mkdir -p "$DATA_DIR" && cd "$DATA_DIR"
    if [ -d "qubicbob" ]; then
        cd qubicbob && git pull
    else
        git clone "$REPO_URL"
        cd qubicbob
    fi
    mkdir -p build && cd build
    cmake ../
    make -j"$(nproc)"

    # Generate config
    generate_config "$DATA_DIR/qubicbob/build/config.json"

    # Create systemd service
    log_info "Creating systemd service..."
    cat > /etc/systemd/system/qubic-bob.service << SERVICEEOF
[Unit]
Description=Qubic Bob Node
After=network.target keydb-server.service kvrocks.service
Wants=keydb-server.service kvrocks.service

[Service]
Type=simple
WorkingDirectory=${DATA_DIR}/qubicbob/build
ExecStart=${DATA_DIR}/qubicbob/build/bob ${DATA_DIR}/qubicbob/build/config.json
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

    systemctl daemon-reload
    systemctl enable qubic-bob
    systemctl start qubic-bob

    log_info "Bob Node is running as systemd service!"
    log_info "P2P Port: ${SERVER_PORT}"
    log_info "RPC Port: ${RPC_PORT}"
    log_info "Binary: ${DATA_DIR}/qubicbob/build/bob"
    log_info "Config: ${DATA_DIR}/qubicbob/build/config.json"
    echo ""
    log_info "Useful commands:"
    echo "  systemctl status qubic-bob"
    echo "  journalctl -u qubic-bob -f"
    echo "  systemctl restart qubic-bob"
}

# ─── Main ────────────────────────────────────────────────────────────────────

print_banner
check_root
parse_args "$@"

case "$MODE" in
    docker-standalone)
        install_docker_standalone
        ;;
    docker-compose)
        install_docker_compose
        ;;
    manual)
        install_manual
        ;;
    *)
        log_error "Unknown mode: $MODE"
        show_usage
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Installation completed!                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
