#!/bin/bash
###############################################################################
# Qubic Lite Node Installation Script
# Installs the Qubic Core Lite Node (runs on OS without UEFI)
#
# Usage:
#   ./lite-install.sh [MODE] [OPTIONS]
#
# Modes:
#   docker     Build and run via Docker container
#   manual     Build from source with systemd service
#
# Options:
#   --peers <ip1,ip2,...>   Peer node IPs to connect to
#   --testnet               Enable testnet mode (default: mainnet)
#   --port <port>           Node port (default: 21841)
#   --data-dir <path>       Data directory (default: /opt/qubic-lite)
#   --avx512                Enable AVX-512 support (default: AVX2 only)
#   --security-tick <n>     Security tick interval for testnet (default: 32)
#   --ticking-delay <n>     Ticking delay in ms for testnet (default: 1000)
#
# Examples:
#   ./lite-install.sh docker --testnet
#   ./lite-install.sh manual --peers 1.2.3.4,5.6.7.8
#   ./lite-install.sh manual --testnet --security-tick 32
###############################################################################

set -e

# =============================================================================
# Default Configuration
# =============================================================================
MODE=""
PEERS=""
TESTNET=false
NODE_PORT=21841
DATA_DIR="/opt/qubic-lite"
REPO_URL="https://github.com/hackerby888/qubic-core-lite.git"
ENABLE_AVX512=false
SECURITY_TICK=32
TICKING_DELAY=1000

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
    echo "     Qubic Lite Node Installer"
    echo "============================================="
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 [MODE] [OPTIONS]"
    echo ""
    echo "Modes:"
    echo "  docker     Build and run via Docker container"
    echo "  manual     Build from source with systemd service"
    echo ""
    echo "Options:"
    echo "  --peers <ip1,ip2,...>   Peer node IPs to connect to"
    echo "  --testnet               Enable testnet mode (default: mainnet)"
    echo "  --port <port>           Node port (default: 21841)"
    echo "  --data-dir <path>       Data directory (default: /opt/qubic-lite)"
    echo "  --avx512                Enable AVX-512 instruction support"
    echo "  --security-tick <n>     Security tick interval, testnet only (default: 32)"
    echo "  --ticking-delay <n>     Ticking delay in ms, testnet only (default: 1000)"
    echo ""
    echo "Examples:"
    echo "  $0 docker --testnet"
    echo "  $0 manual --peers 1.2.3.4,5.6.7.8"
    echo "  $0 manual --testnet --security-tick 32 --ticking-delay 1000"
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

    if [ "$TESTNET" = true ]; then
        local min_ram=14
    else
        local min_ram=60
    fi

    if [ "$TOTAL_RAM_GB" -lt "$min_ram" ]; then
        if [ "$TESTNET" = true ]; then
            log_warn "System has ${TOTAL_RAM_GB}GB RAM. Minimum for testnet: 16GB"
        else
            log_warn "System has ${TOTAL_RAM_GB}GB RAM. Minimum for mainnet: 64GB"
        fi
    else
        log_ok "RAM: ${TOTAL_RAM_GB}GB"
    fi

    # Check CPU
    CPU_CORES=$(nproc)
    log_ok "CPU cores: ${CPU_CORES}"

    # Check AVX2
    if grep -q avx2 /proc/cpuinfo; then
        log_ok "AVX2 support: yes"
    else
        log_warn "AVX2 support: not detected (required for mainnet!)"
    fi

    # Check AVX512
    if [ "$ENABLE_AVX512" = true ]; then
        if grep -q avx512 /proc/cpuinfo; then
            log_ok "AVX-512 support: yes"
        else
            log_warn "AVX-512 support: not detected but requested"
        fi
    fi

    # Check disk space
    AVAILABLE_GB=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ "$TESTNET" = false ] && [ "$AVAILABLE_GB" -lt 500 ]; then
        log_warn "Available disk: ${AVAILABLE_GB}GB. Minimum for mainnet: 500GB"
    else
        log_ok "Available disk: ${AVAILABLE_GB}GB"
    fi
}

# =============================================================================
# Build Qubic binary arguments
# =============================================================================
build_node_args() {
    local args=""

    if [ "$TESTNET" = true ]; then
        args="--security-tick ${SECURITY_TICK} --ticking-delay ${TICKING_DELAY}"
    fi

    if [ -n "$PEERS" ]; then
        args="${args} --peers ${PEERS}"
    fi

    echo "$args"
}

# =============================================================================
# Docker Installation
# =============================================================================
install_docker() {
    log_info "Installing Lite Node (Docker)..."

    # Install Docker if needed
    install_docker_engine

    # Create directories
    mkdir -p "${DATA_DIR}"
    cd "${DATA_DIR}"

    # Determine AVX512 flag
    local avx_flag="OFF"
    if [ "$ENABLE_AVX512" = true ]; then
        avx_flag="ON"
    fi

    # Create Dockerfile
    log_info "Creating Dockerfile..."
    cat > "${DATA_DIR}/Dockerfile" <<DOCKEREOF
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \\
    build-essential clang cmake nasm git \\
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \\
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone ${REPO_URL} .

WORKDIR /app/build
RUN cmake .. \\
    -DCMAKE_C_COMPILER=clang \\
    -DCMAKE_CXX_COMPILER=clang++ \\
    -DBUILD_TESTS=OFF \\
    -DBUILD_BINARY=ON \\
    -DCMAKE_BUILD_TYPE=Release \\
    -DENABLE_AVX512=${avx_flag} \\
    && cmake --build . -- -j\$(nproc)

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \\
    libc++1 libc++abi1 libjsoncpp25 \\
    && rm -rf /var/lib/apt/lists/*

WORKDIR /qubic
COPY --from=builder /app/build/src/Qubic .

EXPOSE ${NODE_PORT}

ENTRYPOINT ["./Qubic"]
DOCKEREOF

    # Build image
    log_info "Building Docker image (this may take several minutes)..."
    docker build -t qubic-lite-node "${DATA_DIR}"

    # Build node arguments
    local node_args
    node_args=$(build_node_args)

    # Create docker-compose file
    cat > "${DATA_DIR}/docker-compose.yml" <<COMPOSEEOF
services:
  qubic-lite:
    image: qubic-lite-node
    container_name: qubic-lite
    restart: unless-stopped
    ports:
      - "${NODE_PORT}:${NODE_PORT}"
    volumes:
      - qubic-lite-data:/qubic/data
    command: ${node_args}

volumes:
  qubic-lite-data:
    driver: local
COMPOSEEOF

    # Start container
    log_info "Starting container..."
    cd "${DATA_DIR}"
    docker compose up -d

    log_ok "Lite Node (Docker) installed successfully!"
    print_status_docker
}

# =============================================================================
# Manual Installation (Build from Source)
# =============================================================================
install_manual() {
    log_info "Installing Lite Node (Build from Source)..."

    # Install build dependencies
    log_info "Installing build dependencies..."
    apt-get update
    apt-get install -y build-essential clang cmake nasm git \
        libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \
        wget curl tmux

    # Clone and build
    log_info "Cloning and building Qubic Core Lite..."
    mkdir -p "${DATA_DIR}"

    if [ -d "${DATA_DIR}/qubic-core-lite" ]; then
        log_info "Existing source found, pulling updates..."
        cd "${DATA_DIR}/qubic-core-lite"
        git pull
    else
        git clone "${REPO_URL}" "${DATA_DIR}/qubic-core-lite"
    fi

    cd "${DATA_DIR}/qubic-core-lite"

    # Determine AVX512 flag
    local avx_flag="OFF"
    if [ "$ENABLE_AVX512" = true ]; then
        avx_flag="ON"
    fi

    mkdir -p build && cd build
    cmake .. \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DBUILD_TESTS=OFF \
        -DBUILD_BINARY=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_AVX512="${avx_flag}"
    cmake --build . -- -j"$(nproc)"

    log_ok "Qubic Core Lite built successfully"

    # Create data directory for runtime
    mkdir -p "${DATA_DIR}/data"

    # Create systemd service
    create_lite_service

    log_ok "Lite Node (Manual) installed successfully!"
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

create_lite_service() {
    log_info "Creating systemd service..."

    local node_args
    node_args=$(build_node_args)

    cat > /etc/systemd/system/qubic-lite.service <<EOF
[Unit]
Description=Qubic Lite Node
After=network.target

[Service]
Type=simple
WorkingDirectory=${DATA_DIR}/data
ExecStart=${DATA_DIR}/qubic-core-lite/build/src/Qubic ${node_args}
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable qubic-lite
    systemctl start qubic-lite

    log_ok "Systemd service created and started"
}

# =============================================================================
# Status Output
# =============================================================================
print_status_docker() {
    local mode_label="Mainnet"
    if [ "$TESTNET" = true ]; then
        mode_label="Testnet"
    fi

    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Lite Node Installation Complete${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo "  Mode:            ${mode_label}"
    echo "  Data directory:  ${DATA_DIR}"
    echo "  Node port:       ${NODE_PORT}"
    if [ -n "$PEERS" ]; then
        echo "  Peers:           ${PEERS}"
    fi
    echo ""
    echo "  Useful commands:"
    echo "    cd ${DATA_DIR}"
    echo "    docker compose ps              # check status"
    echo "    docker compose logs -f         # view logs"
    echo "    docker compose restart         # restart"
    echo "    docker compose down            # stop"
    echo ""
    if [ "$TESTNET" = false ]; then
        echo -e "  ${YELLOW}[NOTE]${NC} For mainnet, place epoch files in the data volume:"
        echo "    spectrum.XXX, universe.XXX, contract0000.XXX"
        echo "    Get peers from: https://app.qubic.li/network/live"
        echo ""
    fi
}

print_status_manual() {
    local mode_label="Mainnet"
    if [ "$TESTNET" = true ]; then
        mode_label="Testnet"
    fi

    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Lite Node Installation Complete${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo "  Mode:            ${mode_label}"
    echo "  Binary:          ${DATA_DIR}/qubic-core-lite/build/src/Qubic"
    echo "  Working dir:     ${DATA_DIR}/data"
    echo "  Service name:    qubic-lite"
    echo "  Node port:       ${NODE_PORT}"
    if [ -n "$PEERS" ]; then
        echo "  Peers:           ${PEERS}"
    fi
    echo ""
    echo "  Useful commands:"
    echo "    systemctl status qubic-lite     # check status"
    echo "    journalctl -u qubic-lite -f     # view logs"
    echo "    systemctl restart qubic-lite    # restart"
    echo "    systemctl stop qubic-lite       # stop"
    echo ""
    if [ "$TESTNET" = false ]; then
        echo -e "  ${YELLOW}[NOTE]${NC} For mainnet, place epoch files in: ${DATA_DIR}/data"
        echo "    spectrum.XXX, universe.XXX, contract0000.XXX"
        echo "    Get peers from: https://app.qubic.li/network/live"
        echo ""
    fi
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
            --testnet)
                TESTNET=true
                shift
                ;;
            --port)
                NODE_PORT="$2"
                shift 2
                ;;
            --data-dir)
                DATA_DIR="$2"
                shift 2
                ;;
            --avx512)
                ENABLE_AVX512=true
                shift
                ;;
            --security-tick)
                SECURITY_TICK="$2"
                shift 2
                ;;
            --ticking-delay)
                TICKING_DELAY="$2"
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
        docker)
            install_docker
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
