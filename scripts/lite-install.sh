#!/bin/bash
###############################################################################
# Qubic Lite Node Installation Script
# Installs the Qubic Core Lite Node (runs on OS without UEFI)
#
# Usage:
#   ./lite-install.sh [MODE] [OPTIONS]
#
# Modes:
#   docker    Build and run via Docker container
#   manual    Build from source with systemd service
#
# Options:
#   --peers <ip1,ip2,...>     Peer node IPs to connect to
#   --testnet                 Enable testnet mode
#   --port <port>             Node port (default: 21841)
#   --data-dir <path>         Data directory (default: /opt/qubic-lite)
#   --avx512                  Enable AVX-512 support
#   --security-tick <n>       Quorum bypass interval, testnet (default: 32)
#   --ticking-delay <n>       Ticking delay in ms, testnet (default: 1000)
#
# Examples:
#   ./lite-install.sh docker --testnet
#   ./lite-install.sh docker --peers 1.2.3.4,5.6.7.8
#   ./lite-install.sh manual --testnet
#   ./lite-install.sh manual --peers 1.2.3.4,5.6.7.8 --avx512
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
TESTNET=false
NODE_PORT=21841
DATA_DIR="/opt/qubic-lite"
REPO_URL="https://github.com/hackerby888/qubic-core-lite.git"
ENABLE_AVX512=false
SECURITY_TICK=32
TICKING_DELAY=1000

# ─── Functions ───────────────────────────────────────────────────────────────

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║        Qubic Lite Node Installation Script      ║"
    echo "║         Core Lite (no UEFI required)            ║"
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
    echo "  docker    Build and run via Docker"
    echo "  manual    Build from source"
    echo ""
    echo "Options:"
    echo "  --peers <ip1,ip2,...>     Peer node IPs"
    echo "  --testnet                 Enable testnet mode"
    echo "  --port <port>             Node port (default: 21841)"
    echo "  --data-dir <path>         Data dir (default: /opt/qubic-lite)"
    echo "  --avx512                  Enable AVX-512 support"
    echo "  --security-tick <n>       Quorum bypass interval (default: 32)"
    echo "  --ticking-delay <n>       Ticking delay ms (default: 1000)"
}

build_run_args() {
    local args=""

    if [ "$TESTNET" = true ]; then
        args="--security-tick ${SECURITY_TICK} --ticking-delay ${TICKING_DELAY}"
    fi

    if [ -n "$PEERS" ]; then
        args="${args} --peers ${PEERS}"
    fi

    echo "$args"
}

get_avx512_flag() {
    if [ "$ENABLE_AVX512" = true ]; then
        echo "ON"
    else
        echo "OFF"
    fi
}

# ─── Docker ──────────────────────────────────────────────────────────────────

install_docker() {
    log_info "Installing Qubic Lite Node (Docker)..."
    check_docker

    mkdir -p "$DATA_DIR" && cd "$DATA_DIR"

    local avx512_flag
    avx512_flag=$(get_avx512_flag)

    # Create Dockerfile
    cat > "$DATA_DIR/Dockerfile" << DOCKEREOF
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \\
    build-essential clang cmake nasm git \\
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \\
    g++ libstdc++-12-dev libfmt-dev \\
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
    -DENABLE_AVX512=${avx512_flag} \\
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
    log_info "Building Docker image (this may take a few minutes)..."
    docker build -t qubic-lite-node "$DATA_DIR"

    # Stop existing container if running
    docker rm -f qubic-lite 2>/dev/null || true

    # Build run arguments
    local run_args
    run_args=$(build_run_args)

    # Start container
    log_info "Starting Qubic Lite Node container..."
    docker run -d \
        --name qubic-lite \
        --restart unless-stopped \
        -p "${NODE_PORT}:${NODE_PORT}" \
        -v "${DATA_DIR}/data:/qubic/data" \
        qubic-lite-node \
        $run_args

    log_info "Qubic Lite Node (Docker) is running!"
    log_info "Port: ${NODE_PORT}"
    log_info "Mode: $([ "$TESTNET" = true ] && echo 'Testnet' || echo 'Mainnet')"
    log_info "Data Dir: ${DATA_DIR}/data"
    echo ""
    log_info "Useful commands:"
    echo "  docker logs -f qubic-lite"
    echo "  docker restart qubic-lite"
    echo "  docker stop qubic-lite"

    if [ "$TESTNET" = false ] && [ -z "$PEERS" ]; then
        echo ""
        log_warn "No peers specified for mainnet. The node may not sync."
        log_warn "Use --peers to specify peer IPs or add epoch files to ${DATA_DIR}/data"
    fi
}

# ─── Manual Build ────────────────────────────────────────────────────────────

install_manual() {
    log_info "Installing Qubic Lite Node (Build from Source)..."

    # Install dependencies
    log_info "Installing system dependencies..."
    apt update && apt upgrade -y
    apt install -y build-essential clang cmake nasm git \
        libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \
        g++ libstdc++-12-dev libfmt-dev tmux

    # Clone or update repo
    log_info "Cloning Qubic Core Lite repository..."
    mkdir -p "$DATA_DIR" && cd "$DATA_DIR"
    if [ -d "qubic-core-lite" ]; then
        cd qubic-core-lite && git pull
    else
        git clone "$REPO_URL"
        cd qubic-core-lite
    fi

    # Build
    local avx512_flag
    avx512_flag=$(get_avx512_flag)

    log_info "Building Qubic Lite Node..."
    mkdir -p build && cd build
    cmake .. \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DBUILD_TESTS=OFF \
        -DBUILD_BINARY=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_AVX512="${avx512_flag}"
    cmake --build . -- -j"$(nproc)"

    # Build run arguments
    local run_args
    run_args=$(build_run_args)

    # Create systemd service
    log_info "Creating systemd service..."
    cat > /etc/systemd/system/qubic-lite.service << SERVICEEOF
[Unit]
Description=Qubic Lite Node
After=network.target

[Service]
Type=simple
WorkingDirectory=${DATA_DIR}/qubic-core-lite/build/src
ExecStart=${DATA_DIR}/qubic-core-lite/build/src/Qubic ${run_args}
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICEEOF

    systemctl daemon-reload
    systemctl enable qubic-lite
    systemctl start qubic-lite

    log_info "Qubic Lite Node is running as systemd service!"
    log_info "Port: ${NODE_PORT}"
    log_info "Mode: $([ "$TESTNET" = true ] && echo 'Testnet' || echo 'Mainnet')"
    log_info "Binary: ${DATA_DIR}/qubic-core-lite/build/src/Qubic"
    echo ""
    log_info "Useful commands:"
    echo "  systemctl status qubic-lite"
    echo "  journalctl -u qubic-lite -f"
    echo "  systemctl restart qubic-lite"

    if [ "$TESTNET" = false ] && [ -z "$PEERS" ]; then
        echo ""
        log_warn "No peers specified for mainnet. The node may not sync."
        log_warn "Add peers: edit /etc/systemd/system/qubic-lite.service"
        log_warn "Then: systemctl daemon-reload && systemctl restart qubic-lite"
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

print_banner
check_root
parse_args "$@"

case "$MODE" in
    docker)
        install_docker
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
