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
#   --peers <ip:port,ip:port>   Trusted peers to sync from
#   --threads <n>               Max threads (0 = auto, default: 0)
#   --rpc-port <port>           REST API / JSON-RPC port (default: 40420)
#   --server-port <port>        P2P server port (default: 21842)
#   --data-dir <path>           Data directory (default: /opt/qubic-bob)
#
# Examples:
#   ./bob-install.sh docker-standalone
#   ./bob-install.sh docker-compose --peers 1.2.3.4:21841
#   ./bob-install.sh manual --peers 1.2.3.4:21841 --threads 8
###############################################################################

set -e

# =============================================================================
# Default Configuration
# =============================================================================
MODE=""
PEERS=""
MAX_THREADS=0
RPC_PORT=40420
SERVER_PORT=21842
DATA_DIR="/opt/qubic-bob"
REPO_URL="https://github.com/krypdkat/qubicbob.git"
DOCKER_IMAGE="j0et0m/qubic-bob"
DOCKER_IMAGE_STANDALONE="j0et0m/qubic-bob-standalone"
ARBITRATOR_ID="AFZPUAIYVPNUYGJRQVLUKOPPVLHAZQTGLYAAUUNBXFTVTAMSBKQBLEIEPCVJ"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================
log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "============================================="
    echo "       Qubic Bob Node Installer"
    echo "============================================="
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 [MODE] [OPTIONS]"
    echo ""
    echo "Modes:"
    echo "  docker-standalone   All-in-one Docker container (recommended)"
    echo "  docker-compose      Modular Docker setup (separate containers)"
    echo "  manual              Build from source with systemd service"
    echo ""
    echo "Options:"
    echo "  --peers <ip:port,...>   Trusted peers to sync from"
    echo "  --threads <n>          Max threads (0 = auto, default: 0)"
    echo "  --rpc-port <port>      REST API port (default: 40420)"
    echo "  --server-port <port>   P2P server port (default: 21842)"
    echo "  --data-dir <path>      Data directory (default: /opt/qubic-bob)"
    echo ""
    echo "Examples:"
    echo "  $0 docker-standalone"
    echo "  $0 docker-compose --peers 1.2.3.4:21841"
    echo "  $0 manual --peers 1.2.3.4:21841 --threads 8"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_system() {
    log_info "Checking system requirements..."

    # Check OS
    if [ ! -f /etc/os-release ]; then
        log_error "Unsupported OS. This script requires Ubuntu/Debian."
        exit 1
    fi

    # Check RAM
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
    if [ "$TOTAL_RAM_GB" -lt 14 ]; then
        log_warn "System has ${TOTAL_RAM_GB}GB RAM. Minimum recommended: 16GB"
    else
        log_ok "RAM: ${TOTAL_RAM_GB}GB"
    fi

    # Check CPU cores
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 4 ]; then
        log_warn "System has ${CPU_CORES} CPU cores. Minimum recommended: 4"
    else
        log_ok "CPU cores: ${CPU_CORES}"
    fi

    # Check AVX2
    if grep -q avx2 /proc/cpuinfo; then
        log_ok "AVX2 support: yes"
    else
        log_warn "AVX2 support: not detected (may cause issues)"
    fi

    # Check disk space
    AVAILABLE_GB=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ "$AVAILABLE_GB" -lt 100 ]; then
        log_warn "Available disk: ${AVAILABLE_GB}GB. Minimum recommended: 100GB"
    else
        log_ok "Available disk: ${AVAILABLE_GB}GB"
    fi
}

# =============================================================================
# Configuration Generator
# =============================================================================
generate_config() {
    local keydb_host="$1"
    local kvrocks_host="$2"
    local config_path="$3"

    # Build peers array
    local peers_json="[]"
    if [ -n "$PEERS" ]; then
        peers_json=$(echo "$PEERS" | tr ',' '\n' | awk '{printf "\"%s\",", $0}' | sed 's/,$//' | awk '{print "["$0"]"}')
    fi

    cat > "$config_path" <<CONFIGEOF
{
  "p2p-node": ${peers_json},
  "trusted-node": ${peers_json},
  "request-cycle-ms": 100,
  "request-logging-cycle-ms": 30,
  "future-offset": 3,
  "log-level": "info",
  "keydb-url": "tcp://${keydb_host}:6379",
  "run-server": true,
  "server-port": ${SERVER_PORT},
  "rpc-port": ${RPC_PORT},
  "arbitrator-identity": "${ARBITRATOR_ID}",
  "tick-storage-mode": "kvrocks",
  "kvrocks-url": "tcp://${kvrocks_host}:6666",
  "tx-storage-mode": "kvrocks",
  "tx_tick_to_live": 10000,
  "max-thread": ${MAX_THREADS},
  "spam-qu-threshold": 100
}
CONFIGEOF

    log_ok "Configuration written to ${config_path}"
}

# =============================================================================
# Docker Standalone Installation
# =============================================================================
install_docker_standalone() {
    log_info "Installing Bob Node (Docker Standalone)..."

    # Install Docker if needed
    install_docker_engine

    # Create directories
    mkdir -p "${DATA_DIR}"
    cd "${DATA_DIR}"

    # Generate config
    generate_config "127.0.0.1" "127.0.0.1" "${DATA_DIR}/bob.json"

    # Create docker-compose file
    cat > "${DATA_DIR}/docker-compose.yml" <<'COMPOSEEOF'
services:
  qubic-bob:
    image: j0et0m/qubic-bob-standalone:prod
    restart: unless-stopped
    ports:
      - "21842:21842"
      - "40420:40420"
    volumes:
      - ./bob.json:/bob/bob.json:ro
      - qubic-bob-redis:/data/redis
      - qubic-bob-kvrocks:/data/kvrocks
      - qubic-bob-data:/data/bob

volumes:
  qubic-bob-redis:
    driver: local
  qubic-bob-kvrocks:
    driver: local
  qubic-bob-data:
    driver: local
COMPOSEEOF

    # Update ports in compose file
    sed -i "s/\"21842:21842\"/\"${SERVER_PORT}:21842\"/" "${DATA_DIR}/docker-compose.yml"
    sed -i "s/\"40420:40420\"/\"${RPC_PORT}:40420\"/" "${DATA_DIR}/docker-compose.yml"

    # Start containers
    log_info "Starting containers..."
    cd "${DATA_DIR}"
    docker compose up -d

    log_ok "Bob Node (Docker Standalone) installed successfully!"
    print_status_docker
}

# =============================================================================
# Docker Compose Installation (Modular)
# =============================================================================
install_docker_compose() {
    log_info "Installing Bob Node (Docker Compose)..."

    # Install Docker if needed
    install_docker_engine

    # Create directories
    mkdir -p "${DATA_DIR}"
    cd "${DATA_DIR}"

    # Generate config (using container hostnames)
    generate_config "keydb" "kvrocks" "${DATA_DIR}/bob.json"

    # Download config files from repo
    log_info "Downloading configuration files..."
    curl -sSfL -o "${DATA_DIR}/keydb.conf" \
        "https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/keydb.conf"
    curl -sSfL -o "${DATA_DIR}/kvrocks.conf" \
        "https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/kvrocks.conf"

    # Create docker-compose file
    cat > "${DATA_DIR}/docker-compose.yml" <<'COMPOSEEOF'
services:
  qubic-bob:
    image: j0et0m/qubic-bob:prod
    restart: unless-stopped
    ports:
      - "21842:21842"
      - "40420:40420"
    volumes:
      - ./bob.json:/bob/bob.json:ro
      - qubic-bob-data:/data/bob
    depends_on:
      keydb:
        condition: service_healthy
      kvrocks:
        condition: service_healthy
    networks:
      - qubic-bob-network

  keydb:
    image: eqalpha/keydb:latest
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - ./keydb.conf:/etc/keydb/keydb.conf:ro
      - qubic-bob-keydb:/data
    command: keydb-server /etc/keydb/keydb.conf
    healthcheck:
      test: ["CMD", "keydb-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - qubic-bob-network

  kvrocks:
    image: apache/kvrocks:latest
    restart: unless-stopped
    ports:
      - "6666:6666"
    volumes:
      - ./kvrocks.conf:/var/lib/kvrocks/kvrocks.conf:ro
      - qubic-bob-kvrocks:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "6666", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - qubic-bob-network

networks:
  qubic-bob-network:
    driver: bridge

volumes:
  qubic-bob-data:
    driver: local
  qubic-bob-keydb:
    driver: local
  qubic-bob-kvrocks:
    driver: local
COMPOSEEOF

    # Update ports in compose file
    sed -i "0,/\"21842:21842\"/{s/\"21842:21842\"/\"${SERVER_PORT}:21842\"/}" "${DATA_DIR}/docker-compose.yml"
    sed -i "0,/\"40420:40420\"/{s/\"40420:40420\"/\"${RPC_PORT}:40420\"/}" "${DATA_DIR}/docker-compose.yml"

    # Start containers
    log_info "Starting containers..."
    cd "${DATA_DIR}"
    docker compose up -d

    log_ok "Bob Node (Docker Compose) installed successfully!"
    print_status_docker
}

# =============================================================================
# Manual Installation (Build from Source)
# =============================================================================
install_manual() {
    log_info "Installing Bob Node (Build from Source)..."

    # Install build dependencies
    log_info "Installing build dependencies..."
    apt-get update
    apt-get install -y build-essential cmake git libjsoncpp-dev \
        uuid-dev libhiredis-dev zlib1g-dev unzip wget curl \
        net-tools tmux lsb-release gnupg

    # Install KeyDB
    install_keydb

    # Install KVRocks
    install_kvrocks

    # Clone and build Bob
    log_info "Cloning and building Bob Node..."
    mkdir -p "${DATA_DIR}"
    cd "${DATA_DIR}"

    if [ -d "${DATA_DIR}/qubicbob" ]; then
        log_info "Existing source found, pulling updates..."
        cd "${DATA_DIR}/qubicbob"
        git pull
    else
        git clone "${REPO_URL}" "${DATA_DIR}/qubicbob"
        cd "${DATA_DIR}/qubicbob"
    fi

    mkdir -p build && cd build
    cmake ../
    make -j"$(nproc)"

    log_ok "Bob Node built successfully"

    # Generate config
    generate_config "127.0.0.1" "127.0.0.1" "${DATA_DIR}/qubicbob/build/config.json"

    # Create systemd service
    create_bob_service

    log_ok "Bob Node (Manual) installed successfully!"
    print_status_manual
}

# =============================================================================
# Component Installers
# =============================================================================
install_docker_engine() {
    if command -v docker &> /dev/null; then
        log_ok "Docker already installed: $(docker --version)"
        return
    fi

    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log_ok "Docker installed"
}

install_keydb() {
    if systemctl is-active --quiet keydb-server 2>/dev/null; then
        log_ok "KeyDB already running"
        return
    fi

    log_info "Installing KeyDB..."
    echo "deb https://download.keydb.dev/open-source-dist $(lsb_release -sc) main" | \
        tee /etc/apt/sources.list.d/keydb.list
    wget -qO /etc/apt/trusted.gpg.d/keydb.gpg \
        https://download.keydb.dev/open-source-dist/keyring.gpg
    apt-get update
    apt-get install -y keydb

    systemctl enable keydb-server
    systemctl start keydb-server
    log_ok "KeyDB installed and running"
}

install_kvrocks() {
    if command -v kvrocks &> /dev/null || [ -f /usr/local/bin/kvrocks ]; then
        log_ok "KVRocks already installed"
        return
    fi

    log_info "Building and installing KVRocks (this may take a while)..."
    local build_dir="/tmp/kvrocks-build"
    rm -rf "${build_dir}"
    git clone --branch v2.9.0 --depth 1 https://github.com/apache/kvrocks.git "${build_dir}"
    cd "${build_dir}"
    mkdir build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j"$(nproc)"
    cp src/kvrocks /usr/local/bin/

    # Create KVRocks systemd service
    cat > /etc/systemd/system/kvrocks.service <<EOF
[Unit]
Description=KVRocks Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kvrocks
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable kvrocks
    systemctl start kvrocks

    rm -rf "${build_dir}"
    log_ok "KVRocks installed and running"
}

create_bob_service() {
    log_info "Creating systemd service..."

    cat > /etc/systemd/system/qubic-bob.service <<EOF
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
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable qubic-bob
    systemctl start qubic-bob

    log_ok "Systemd service created and started"
}

# =============================================================================
# Status Output
# =============================================================================
print_status_docker() {
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Bob Node Installation Complete${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo "  Data directory:  ${DATA_DIR}"
    echo "  Config file:     ${DATA_DIR}/bob.json"
    echo "  P2P port:        ${SERVER_PORT}"
    echo "  RPC/API port:    ${RPC_PORT}"
    echo ""
    echo "  Useful commands:"
    echo "    cd ${DATA_DIR}"
    echo "    docker compose ps              # check status"
    echo "    docker compose logs -f         # view logs"
    echo "    docker compose restart         # restart"
    echo "    docker compose down            # stop"
    echo "    docker compose pull && docker compose up -d  # update"
    echo ""
    echo "  API endpoint:    http://localhost:${RPC_PORT}"
    echo ""
}

print_status_manual() {
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Bob Node Installation Complete${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo "  Binary:          ${DATA_DIR}/qubicbob/build/bob"
    echo "  Config file:     ${DATA_DIR}/qubicbob/build/config.json"
    echo "  Service name:    qubic-bob"
    echo "  P2P port:        ${SERVER_PORT}"
    echo "  RPC/API port:    ${RPC_PORT}"
    echo ""
    echo "  Useful commands:"
    echo "    systemctl status qubic-bob     # check status"
    echo "    journalctl -u qubic-bob -f     # view logs"
    echo "    systemctl restart qubic-bob    # restart"
    echo "    systemctl stop qubic-bob       # stop"
    echo ""
    echo "  API endpoint:    http://localhost:${RPC_PORT}"
    echo ""
}

# =============================================================================
# Parse Arguments
# =============================================================================
parse_args() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
    fi

    MODE="$1"
    shift

    while [ $# -gt 0 ]; do
        case "$1" in
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
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Main
# =============================================================================
main() {
    print_banner
    parse_args "$@"
    check_root
    check_system

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
            log_error "Unknown mode: ${MODE}"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
