#!/bin/bash
#
# Lite Node Installer - Docker-based setup
# https://github.com/hackerby888/qubic-core-lite
#
# Usage:
#   Interactive:  ./lite.sh
#   CLI:          ./lite.sh install --seed <seed> --alias <alias>
#
# Commands:
#   install       Install and start Lite node
#   uninstall     Remove Lite node
#   status        Show container status
#   logs          Show live logs
#   stop          Stop container
#   start         Start container
#   restart       Restart container
#   update        Rebuild and restart
#

set -e

# --- Config ---
CONTAINER_NAME="qubic-lite"
IMAGE_NAME="qubic-lite-node"
DOCKERHUB_IMAGE="qubiccore/lite"
DATA_DIR="/opt/qubic-lite"
REPO_URL="https://github.com/hackerby888/qubic-core-lite.git"
PEERS_API="https://api.qubic.global/random-peers?service=bobNode&litePeers=8"

# Default ports
P2P_PORT=21841
HTTP_PORT=41841

# Build options
TESTNET=false
ENABLE_AVX512=false
MAX_PROCESSORS=""
TARGET_EPOCH=""
SKIP_EPOCH=false
USE_DOCKERHUB=false

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }

# --- Functions ---

print_usage() {
    echo "Lite Node Installer"
    echo ""
    echo "Usage:"
    echo "  Interactive:  $0"
    echo "  CLI:          $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  install       Install and start Lite node"
    echo "  uninstall     Remove Lite node and data"
    echo "  status        Show container status"
    echo "  info          Show node info (tick, epoch, operator)"
    echo "  logs          Show live logs (Ctrl+C to exit)"
    echo "  stop          Stop container"
    echo "  start         Start container"
    echo "  restart       Restart container"
    echo "  update        Rebuild image and restart"
    echo ""
    echo "Install options:"
    echo "  --seed <seed>         Operator seed [REQUIRED]"
    echo "  --alias <alias>       Operator alias [REQUIRED]"
    echo "  --dockerhub           Use pre-built Docker Hub image (beta)"
    echo "  --avx512              Enable AVX-512 support (build only)"
    echo "  --processors <N>      Max processors (build only)"
    echo "  --epoch <N>           Build for specific epoch (build only)"
    echo "  --no-epoch            Skip epoch data download"
    echo "  --peers <ip1,ip2>     Peer IPs (auto-fetched if omitted)"
    echo "  --p2p-port <port>     P2P port (default: 21841)"
    echo "  --http-port <port>    HTTP port (default: 41841)"
    echo "  --data-dir <path>     Data directory (default: /opt/qubic-lite)"
    echo ""
    echo "Examples:"
    echo "  $0 install --seed myseed --alias mynode"
    echo "  $0 install --seed myseed --alias mynode --dockerhub"
    echo "  $0 logs"
    echo "  $0 update"
}

print_security_warning() {
    echo ""
    log_warn "SECURITY TIP: To prevent your seed from being saved in shell history:"
    echo "      - Add a SPACE before the command:  ' ./lite.sh install ...'"
    echo "      - Or use interactive mode:  ./lite.sh"
    echo "      - Or set: export HISTCONTROL=ignorespace"
    echo ""
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found. Installing..."
        curl -fsSL https://get.docker.com | sh
        if ! command -v docker &> /dev/null; then
            log_error "Docker installation failed"
            exit 1
        fi
        log_ok "Docker installed"
    fi
    log_ok "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
}

check_system() {
    log_info "Checking system..."

    local ram_kb ram_gb min_ram
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    ram_gb=$((ram_kb / 1024 / 1024))

    [ "$TESTNET" = true ] && min_ram=14 || min_ram=60

    if [ "$ram_gb" -lt "$min_ram" ]; then
        log_warn "RAM: ${ram_gb}GB (recommended: ${min_ram}GB+)"
    else
        log_ok "RAM: ${ram_gb}GB"
    fi

    if grep -q avx2 /proc/cpuinfo; then
        log_ok "AVX2: supported"
    else
        log_warn "AVX2: not detected (required for mainnet)"
    fi

    if [ "$ENABLE_AVX512" = true ]; then
        if grep -q avx512 /proc/cpuinfo; then
            log_ok "AVX-512: supported"
        else
            log_warn "AVX-512: not detected but requested"
        fi
    fi
}

container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

# Fetch peers from API
fetch_peers() {
    local max_retries=3
    local attempt=1

    PEER_LIST=""

    while [ $attempt -le $max_retries ]; do
        log_info "Fetching peers (attempt ${attempt}/${max_retries})..."

        local response
        response=$(curl -sf --max-time 15 "$PEERS_API" 2>/dev/null || true)

        if [ -n "$response" ]; then
            # Extract litePeers from JSON
            local peers
            peers=$(echo "$response" | grep -oP '"litePeers"\s*:\s*\[[^\]]*\]' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)

            if [ -n "$peers" ]; then
                PEER_LIST=$(echo "$peers" | head -8 | tr '\n' ',' | sed 's/,$//')
                local peer_count
                peer_count=$(echo "$peers" | wc -l)
                log_ok "Got ${peer_count} peers"
                return 0
            fi
        fi

        attempt=$((attempt + 1))
        [ $attempt -le $max_retries ] && sleep 5
    done

    log_warn "Could not fetch peers automatically"
    return 1
}

# Detect latest epoch from storage
detect_epoch() {
    if [ "$TESTNET" = true ] || [ "$SKIP_EPOCH" = true ]; then
        return
    fi

    if [ -n "$TARGET_EPOCH" ]; then
        DETECTED_EPOCH="$TARGET_EPOCH"
        return
    fi

    log_info "Detecting latest epoch..."
    local storage_url="https://storage.qubic.li/network"
    DETECTED_EPOCH=$(curl -sf "${storage_url}/" | grep -o 'ep[0-9]*-full\.zip' | grep -o '[0-9]*' | sort -n | tail -1 || true)

    if [ -n "$DETECTED_EPOCH" ]; then
        log_ok "Detected epoch: ${DETECTED_EPOCH}"
    else
        log_warn "Could not detect epoch, using HEAD"
    fi
}

# Checkout source for specific epoch
checkout_epoch() {
    local src_dir="$1"
    local epoch="$2"

    if [ -z "$epoch" ]; then
        log_info "Building from latest source (HEAD)"
        return
    fi

    local settings_file="${src_dir}/src/public_settings.h"
    local head_epoch
    head_epoch=$(grep -oP '#define\s+EPOCH\s+\K[0-9]+' "$settings_file" 2>/dev/null || true)

    if [ "$head_epoch" = "$epoch" ]; then
        log_ok "Source already at epoch ${epoch}"
        return
    fi

    log_info "Searching for epoch ${epoch} in git history..."

    local commits target_commit=""
    commits=$(cd "$src_dir" && git log --all --format="%H" -100 -- src/public_settings.h 2>/dev/null || true)

    for c in $commits; do
        local ep
        ep=$(cd "$src_dir" && git show "${c}:src/public_settings.h" 2>/dev/null | grep -oP '#define\s+EPOCH\s+\K[0-9]+' || true)
        if [ "$ep" = "$epoch" ]; then
            target_commit="$c"
            break
        fi
    done

    if [ -z "$target_commit" ]; then
        log_warn "Could not find epoch ${epoch}, using HEAD"
        return
    fi

    log_info "Checking out ${target_commit:0:8} for epoch ${epoch}..."
    cd "$src_dir" && git checkout "$target_commit" --quiet
    log_ok "Checked out epoch ${epoch}"
}

# Patch max processors in source
patch_processors() {
    local src_dir="$1"
    local max_procs="$2"

    if [ -z "$max_procs" ]; then
        return
    fi

    local settings_file="${src_dir}/src/public_settings.h"
    if [ -f "$settings_file" ]; then
        sed -i "s/#define MAX_NUMBER_OF_PROCESSORS [0-9]*/#define MAX_NUMBER_OF_PROCESSORS ${max_procs}/g" "$settings_file"
        log_ok "Patched MAX_PROCESSORS to ${max_procs}"
    fi
}

# Download epoch data
download_epoch_data() {
    if [ "$TESTNET" = true ] || [ "$SKIP_EPOCH" = true ]; then
        return
    fi

    if [ -z "$DETECTED_EPOCH" ]; then
        return
    fi

    # Ensure unzip is available
    if ! command -v unzip &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq unzip
    fi

    local zip_file="ep${DETECTED_EPOCH}-full.zip"
    local zip_url="https://storage.qubic.li/network/${DETECTED_EPOCH}/${zip_file}"

    log_info "Downloading epoch ${DETECTED_EPOCH} data..."

    if wget -q --show-progress -O "${DATA_DIR}/data/${zip_file}" "${zip_url}"; then
        log_info "Extracting..."
        unzip -o -q "${DATA_DIR}/data/${zip_file}" -d "${DATA_DIR}/data"
        rm -f "${DATA_DIR}/data/${zip_file}"
        log_ok "Epoch data ready"
    else
        log_warn "Could not download epoch data"
        rm -f "${DATA_DIR}/data/${zip_file}"
    fi
}

# Build docker command for compose
build_docker_command() {
    local cmd="command: [\"--operator-seed\", \"${OPERATOR_SEED}\", \"--operator-alias\", \"${OPERATOR_ALIAS}\""

    if [ "$TESTNET" = true ]; then
        cmd="${cmd}, \"--security-tick\", \"32\", \"--ticking-delay\", \"1000\""
    fi

    if [ -n "$PEER_LIST" ]; then
        cmd="${cmd}, \"--peers\", \"${PEER_LIST}\""
    fi

    cmd="${cmd}]"
    echo "$cmd"
}

do_install() {
    log_info "Installing Lite node..."

    check_docker
    check_system

    # Validate inputs
    if [ -z "$OPERATOR_SEED" ]; then
        log_error "--seed is required"
        exit 1
    fi

    if [ -z "$OPERATOR_ALIAS" ]; then
        log_error "--alias is required"
        exit 1
    fi

    # Stop existing container
    if container_exists; then
        log_info "Removing existing container..."
        docker rm -f "$CONTAINER_NAME" &>/dev/null || true
    fi

    # Create directories
    mkdir -p "${DATA_DIR}/data"

    # Copy script for management
    cp "$0" "${DATA_DIR}/lite.sh" 2>/dev/null || true
    chmod +x "${DATA_DIR}/lite.sh" 2>/dev/null || true

    # Fetch peers
    if [ -z "$PEER_LIST" ]; then
        fetch_peers || true
        if [ -z "$PEER_LIST" ]; then
            log_error "No peers available. Use --peers <ip1,ip2,...>"
            log_error "Find peers at: https://app.qubic.li/network/live"
            exit 1
        fi
    fi

    # Build or pull image
    local final_image
    if [ "$USE_DOCKERHUB" = true ]; then
        # Quick install: pull from Docker Hub
        log_info "Pulling image from Docker Hub..."
        docker pull "${DOCKERHUB_IMAGE}"
        final_image="${DOCKERHUB_IMAGE}"
        log_ok "Image ready"
    else
        # Build from source
        detect_epoch
        download_epoch_data

        log_info "Cloning qubic-core-lite..."
        if [ -d "${DATA_DIR}/qubic-core-lite" ]; then
            cd "${DATA_DIR}/qubic-core-lite"
            git checkout main --quiet 2>/dev/null || true
            git pull --quiet
        else
            git clone --quiet "${REPO_URL}" "${DATA_DIR}/qubic-core-lite"
        fi

        checkout_epoch "${DATA_DIR}/qubic-core-lite" "$DETECTED_EPOCH"
        patch_processors "${DATA_DIR}/qubic-core-lite" "$MAX_PROCESSORS"

        log_info "Building Docker image (this takes a while)..."

        local avx_flag="OFF"
        local avx_cmake=""
        if [ "$ENABLE_AVX512" = true ]; then
            avx_flag="ON"
            avx_cmake='RUN echo "add_compile_options(-mavx512vbmi2)" > /app/avx512.cmake'
        fi

        local avx_include=""
        [ "$ENABLE_AVX512" = true ] && avx_include="-DCMAKE_PROJECT_INCLUDE=/app/avx512.cmake"

        printf "data/\nqubic-core-lite/.git/\n" > "${DATA_DIR}/.dockerignore"

        cat > "${DATA_DIR}/Dockerfile" <<EOF
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \\
    build-essential clang cmake nasm git g++ \\
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \\
    libstdc++-12-dev libfmt-dev \\
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY qubic-core-lite/ .
${avx_cmake}
WORKDIR /app/build
RUN cmake .. \\
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \\
    -DBUILD_TESTS=OFF -DBUILD_BINARY=ON \\
    -DCMAKE_BUILD_TYPE=Release -DENABLE_AVX512=${avx_flag} \\
    ${avx_include} \\
    && cmake --build . -- -j\$(nproc)

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \\
    libc++1 libc++abi1 libjsoncpp25 libfmt9 \\
    && rm -rf /var/lib/apt/lists/*
WORKDIR /qubic
COPY --from=builder /app/build/src/Qubic .
EXPOSE ${P2P_PORT} ${HTTP_PORT}
ENTRYPOINT ["/qubic/Qubic"]
EOF

        docker build -t "$IMAGE_NAME" "${DATA_DIR}"
        final_image="${IMAGE_NAME}"
    fi

    # Create docker-compose.yml
    if [ "$USE_DOCKERHUB" = true ]; then
        # Docker Hub image uses environment variables
        cat > "${DATA_DIR}/docker-compose.yml" <<EOF
services:
  qubic-lite:
    image: ${final_image}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "${P2P_PORT}:21841"
      - "${HTTP_PORT}:41841"
    volumes:
      - ${DATA_DIR}/data:/app/data
    environment:
      - QUBIC_OPERATOR_SEED=${OPERATOR_SEED}
      - QUBIC_OPERATOR_ALIAS=${OPERATOR_ALIAS}
      - QUBIC_PEERS=${PEER_LIST}
EOF
    else
        # Build from source uses command arguments
        local docker_cmd
        docker_cmd=$(build_docker_command)

        cat > "${DATA_DIR}/docker-compose.yml" <<EOF
services:
  qubic-lite:
    image: ${final_image}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    working_dir: /qubic/data
    ports:
      - "${P2P_PORT}:${P2P_PORT}"
      - "${HTTP_PORT}:${HTTP_PORT}"
    volumes:
      - ${DATA_DIR}/data:/qubic/data
    ${docker_cmd}
EOF
    fi

    # Start container
    log_info "Starting container..."
    cd "${DATA_DIR}" && docker compose up -d

    local mode_label="build"
    [ "$USE_DOCKERHUB" = true ] && mode_label="dockerhub"

    log_ok "Lite node started! (${mode_label})"
    echo ""
    echo "  Container:  $CONTAINER_NAME"
    echo "  Data:       ${DATA_DIR}/data"
    echo "  P2P:        port ${P2P_PORT}"
    echo "  HTTP:       http://localhost:${HTTP_PORT}"
    echo ""
    echo "  View logs:  ./lite.sh logs"
    echo "  Status:     ./lite.sh status"
    echo "  Update:     ./lite.sh update"
    echo ""

    # Remove original script if not in DATA_DIR
    local script_path
    script_path=$(realpath "$0" 2>/dev/null || echo "$0")
    if [ "$script_path" != "${DATA_DIR}/lite.sh" ] && [ -f "$script_path" ]; then
        rm -f "$script_path"
        log_ok "Removed installer from download location"
    fi

    log_info "Entering ${DATA_DIR}..."
    cd "${DATA_DIR}" && exec bash
}

do_uninstall() {
    log_info "Uninstalling Lite node..."

    # Stop container
    if [ -f "${DATA_DIR}/docker-compose.yml" ]; then
        docker compose -f "${DATA_DIR}/docker-compose.yml" down -v 2>/dev/null || true
        log_ok "Container stopped"
    elif container_exists; then
        docker rm -f "$CONTAINER_NAME" &>/dev/null || true
        log_ok "Container removed"
    fi

    # Remove image
    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        docker rmi "$IMAGE_NAME" 2>/dev/null || true
        log_ok "Image removed"
    fi

    # Ask before removing data
    local data_removed=false
    if [ -d "$DATA_DIR" ]; then
        echo ""
        read -rp "Remove data directory ${DATA_DIR}? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$DATA_DIR"
            log_ok "Data removed"
            data_removed=true
        else
            log_info "Data kept at ${DATA_DIR}"
        fi
    fi

    log_ok "Uninstall complete"

    # Return to home if data dir was removed
    if [ "$data_removed" = true ]; then
        cd ~ && exec bash
    fi
}

do_status() {
    if container_running; then
        log_ok "Lite node is running"
        echo ""
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        log_info "Checking HTTP endpoint..."
        local response
        response=$(curl -sf --max-time 5 "http://localhost:${HTTP_PORT}/live/v1" 2>/dev/null || true)
        if [ -n "$response" ]; then
            echo "$response" | head -c 500
            echo ""
        else
            log_warn "HTTP not responding on port ${HTTP_PORT}"
        fi
    elif container_exists; then
        log_warn "Lite node is stopped"
        docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}"
    else
        log_info "Lite node is not installed"
    fi
}

do_info() {
    if ! container_running; then
        log_error "Lite node is not running"
        exit 1
    fi

    log_info "Fetching node info..."
    local response
    response=$(curl -sf --max-time 10 "http://localhost:${HTTP_PORT}/tick-info" 2>/dev/null || true)

    if [ -z "$response" ]; then
        log_error "Could not fetch tick-info from port ${HTTP_PORT}"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}=== Lite Node Info ===${NC}"
    echo ""

    # Parse and display key info
    local epoch tick alias operator version uptime
    epoch=$(echo "$response" | grep -oP '"epoch":\K[0-9]+' | head -1)
    tick=$(echo "$response" | grep -oP '"tick":\K[0-9]+')
    alias=$(echo "$response" | grep -oP '"alias":"[^"]*"' | head -1 | cut -d'"' -f4)
    operator=$(echo "$response" | grep -oP '"operator":"[^"]*"' | head -1 | cut -d'"' -f4)
    version=$(echo "$response" | grep -oP '"version":"[^"]*"' | cut -d'"' -f4)
    uptime=$(echo "$response" | grep -oP '"uptime":\K[0-9]+')

    [ -n "$alias" ] && echo -e "  Alias:     ${CYAN}${alias}${NC}"
    [ -n "$operator" ] && echo -e "  Operator:  ${CYAN}${operator}${NC}"
    [ -n "$epoch" ] && echo -e "  Epoch:     ${epoch}"
    [ -n "$tick" ] && echo -e "  Tick:      ${tick}"
    [ -n "$version" ] && echo -e "  Version:   ${version}"
    [ -n "$uptime" ] && echo -e "  Uptime:    ${uptime}s"
    echo ""

    log_info "Raw response:"
    echo "$response" | head -c 1000
    echo ""
}

do_logs() {
    if ! container_exists; then
        log_error "Container not found"
        exit 1
    fi
    log_info "Showing logs (Ctrl+C to exit)..."
    docker logs -f "$CONTAINER_NAME"
}

do_stop() {
    if container_running; then
        docker stop "$CONTAINER_NAME"
        log_ok "Stopped"
    else
        log_info "Already stopped"
    fi
}

do_start() {
    if container_running; then
        log_info "Already running"
        return
    fi

    if [ -f "${DATA_DIR}/docker-compose.yml" ]; then
        cd "${DATA_DIR}" && docker compose start
        log_ok "Started"
    elif container_exists; then
        docker start "$CONTAINER_NAME"
        log_ok "Started"
    else
        log_error "Container not found. Run: $0 install"
        exit 1
    fi
}

do_restart() {
    if [ -f "${DATA_DIR}/docker-compose.yml" ]; then
        cd "${DATA_DIR}" && docker compose restart
        log_ok "Restarted"
    elif container_exists; then
        docker restart "$CONTAINER_NAME"
        log_ok "Restarted"
    else
        log_error "Container not found. Run: $0 install"
        exit 1
    fi
}

do_update() {
    log_info "Updating Lite node..."

    if [ ! -d "${DATA_DIR}/qubic-core-lite" ]; then
        log_error "Source not found. Run: $0 install"
        exit 1
    fi

    # Update source
    log_info "Pulling latest source..."
    cd "${DATA_DIR}/qubic-core-lite"
    git checkout main --quiet 2>/dev/null || true
    git pull --quiet

    # Rebuild image
    log_info "Rebuilding Docker image..."
    docker build -t "$IMAGE_NAME" "${DATA_DIR}"

    # Restart container
    if [ -f "${DATA_DIR}/docker-compose.yml" ]; then
        cd "${DATA_DIR}" && docker compose up -d
    fi

    log_ok "Update complete"
}

interactive_install() {
    echo ""
    echo "=== Lite Node Installer ==="
    echo ""

    print_security_warning

    # Get seed
    while [ -z "$OPERATOR_SEED" ]; do
        read -rp "Operator seed: " OPERATOR_SEED
        [ -z "$OPERATOR_SEED" ] && echo "  Seed is required."
    done

    # Get alias
    while [ -z "$OPERATOR_ALIAS" ]; do
        read -rp "Operator alias: " OPERATOR_ALIAS
        [ -z "$OPERATOR_ALIAS" ] && echo "  Alias is required."
    done

    # Max processors
    echo ""
    read -rp "Max processors (Enter for default=8): " input_procs
    [ -n "$input_procs" ] && MAX_PROCESSORS="$input_procs"

    echo ""
    do_install
}

print_logo() {
    echo -e "${CYAN}"
    cat << 'EOF'
            ██████  ██    ██ ██████  ██  ██████
            ██    ██ ██    ██ ██   ██ ██ ██
            ██    ██ ██    ██ ██████  ██ ██
            ██ ▄▄ ██ ██    ██ ██   ██ ██ ██
             ██████   ██████  ██████  ██  ██████
                ▀▀
EOF
    echo -e "${NC}"
    echo ""
    echo -e "                  ${GREEN}Qubic Lite Node Installer${NC}"
    echo -e "                  ${CYAN}─────────────────────────${NC}"
    echo ""
}

interactive_menu() {
    echo ""
    print_logo

    echo -e "         ${CYAN}┌────────────────────────────────────────┐${NC}"
    echo -e "         ${CYAN}│${NC} ${GREEN}INSTALL${NC}                                ${CYAN}│${NC}"
    echo -e "         ${CYAN}│${NC}   1) docker        build from source   ${CYAN}│${NC}"
    echo -e "         ${CYAN}│${NC}   2) beta          quick install (v1)  ${CYAN}│${NC}"
    echo -e "         ${CYAN}│${NC}   3) uninstall     remove lite node    ${CYAN}│${NC}"
    echo -e "         ${CYAN}│${NC}                                        ${CYAN}│${NC}"
    echo -e "         ${CYAN}│${NC} ${GREEN}MANAGE${NC}                                 ${CYAN}│${NC}"
    echo -e "         ${CYAN}│${NC}   4) status    5) info      6) logs    ${CYAN}│${NC}"
    echo -e "         ${CYAN}│${NC}   7) stop      8) start     9) restart ${CYAN}│${NC}"
    echo -e "         ${CYAN}│${NC}  10) update                            ${CYAN}│${NC}"
    echo -e "         ${CYAN}└────────────────────────────────────────┘${NC}"
    echo ""
    read -rp "         Select [1-10]: " choice

    case "$choice" in
        1) interactive_install ;;
        2) USE_DOCKERHUB=true; interactive_install ;;
        3) do_uninstall ;;
        4) do_status ;;
        5) do_info ;;
        6) do_logs ;;
        7) do_stop ;;
        8) do_start ;;
        9) do_restart ;;
        10) do_update ;;
        *) log_error "Invalid choice"; exit 1 ;;
    esac
}

# --- Main ---

OPERATOR_SEED=""
OPERATOR_ALIAS=""
PEER_LIST=""
DETECTED_EPOCH=""

# Parse arguments
if [ $# -eq 0 ]; then
    interactive_menu
    exit 0
fi

COMMAND="$1"
shift

while [ $# -gt 0 ]; do
    case "$1" in
        --seed)        OPERATOR_SEED="$2"; shift 2 ;;
        --alias)       OPERATOR_ALIAS="$2"; shift 2 ;;
        --peers)       PEER_LIST="$2"; shift 2 ;;
        --dockerhub)   USE_DOCKERHUB=true; shift ;;
        --avx512)      ENABLE_AVX512=true; shift ;;
        --processors)  MAX_PROCESSORS="$2"; shift 2 ;;
        --epoch)       TARGET_EPOCH="$2"; shift 2 ;;
        --no-epoch)    SKIP_EPOCH=true; shift ;;
        --p2p-port)    P2P_PORT="$2"; shift 2 ;;
        --http-port)   HTTP_PORT="$2"; shift 2 ;;
        --data-dir)    DATA_DIR="$2"; shift 2 ;;
        --help|-h)     print_usage; exit 0 ;;
        *)             log_error "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

case "$COMMAND" in
    install)    do_install ;;
    uninstall)  do_uninstall ;;
    status)     do_status ;;
    info)       do_info ;;
    logs)       do_logs ;;
    stop)       do_stop ;;
    start)      do_start ;;
    restart)    do_restart ;;
    update)     do_update ;;
    help|--help|-h) print_usage ;;
    *)          log_error "Unknown command: $COMMAND"; print_usage; exit 1 ;;
esac
