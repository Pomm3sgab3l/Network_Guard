#!/bin/bash
# lite-install.sh - Qubic Lite Node installer
#
# Usage: ./lite-install.sh <mode> [options]
#
# Modes:
#   docker     build + run via docker
#   manual     build from source + systemd
#
# Options:
#   --peers <ip1,ip2,...>   peer IPs
#   --testnet               testnet mode (default: mainnet)
#   --port <port>           P2P port (default: 21841)
#   --http-port <port>      HTTP/RPC port (default: 41841)
#   --data-dir <path>       install dir (default: /opt/qubic-lite)
#   --avx512                enable AVX-512
#   --operator-seed <seed>  operator identity seed (required)
#   --operator-alias <alias> operator alias name (required)
#   --security-tick <n>     quorum bypass interval, testnet (default: 32)
#   --ticking-delay <n>     tick delay ms, testnet (default: 1000)
#   --no-epoch              skip automatic epoch data download (mainnet)

set -e

# defaults
MODE=""
PEERS=""
TESTNET=false
NODE_PORT=21841
HTTP_PORT=41841
DATA_DIR="/opt/qubic-lite"
REPO_URL="https://github.com/hackerby888/qubic-core-lite.git"
ENABLE_AVX512=false
OPERATOR_SEED=""
OPERATOR_ALIAS=""
SECURITY_TICK=32
TICKING_DELAY=1000
SKIP_EPOCH=false
DETECTED_EPOCH=""
CLANG_C="clang"
CLANG_CXX="clang++"
APT_WAIT="-o DPkg::Lock::Timeout=60"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }

print_usage() {
    echo "Usage: $0 <mode> [options]"
    echo ""
    echo "Modes:"
    echo "  docker     build + run via docker"
    echo "  manual     build from source + systemd"
    echo ""
    echo "Options:"
    echo "  --peers <ip1,ip2,...>   peer IPs"
    echo "  --testnet               testnet mode (default: mainnet)"
    echo "  --port <port>           P2P port (default: 21841)"
    echo "  --http-port <port>      HTTP/RPC port (default: 41841)"
    echo "  --data-dir <path>       install dir (default: /opt/qubic-lite)"
    echo "  --operator-seed <seed>  operator identity seed (REQUIRED)"
    echo "  --operator-alias <alias> operator alias name (REQUIRED)"
    echo "  --avx512                enable AVX-512"
    echo "  --security-tick <n>     quorum bypass, testnet only (default: 32)"
    echo "  --ticking-delay <n>     tick delay ms, testnet only (default: 1000)"
    echo "  --no-epoch              skip automatic epoch data download (mainnet)"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "run as root"
        exit 1
    fi
}

check_system() {
    log_info "checking system..."

    if [ ! -f /etc/os-release ]; then
        log_error "needs Ubuntu/Debian"
        exit 1
    fi

    local ram_kb ram_gb cores avail_gb min_ram
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    ram_gb=$((ram_kb / 1024 / 1024))
    cores=$(nproc)
    avail_gb=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')

    [ "$TESTNET" = true ] && min_ram=14 || min_ram=60

    [ "$ram_gb" -lt "$min_ram" ] && log_warn "RAM: ${ram_gb}GB (need $((min_ram + 2))GB)" || log_ok "RAM: ${ram_gb}GB"
    log_ok "CPU: ${cores} cores"
    grep -q avx2 /proc/cpuinfo && log_ok "AVX2: yes" || log_warn "AVX2: not detected (required for mainnet)"

    if [ "$ENABLE_AVX512" = true ]; then
        grep -q avx512 /proc/cpuinfo && log_ok "AVX-512: yes" || log_warn "AVX-512: not detected but requested"
    fi

    if [ "$TESTNET" = false ] && [ "$avail_gb" -lt 500 ]; then
        log_warn "Disk: ${avail_gb}GB (need 500GB for mainnet)"
    else
        log_ok "Disk: ${avail_gb}GB"
    fi
}

# --- build node args ---

build_node_args() {
    local args=""
    args="--operator-seed ${OPERATOR_SEED} --operator-alias ${OPERATOR_ALIAS}"
    [ "$TESTNET" = true ] && args="${args} --security-tick ${SECURITY_TICK} --ticking-delay ${TICKING_DELAY}"
    [ -n "$PEERS" ] && args="${args} --peers ${PEERS}"
    echo "$args"
}

# --- docker install ---

install_docker() {
    log_info "setting up lite node (docker)..."

    install_docker_engine
    mkdir -p "${DATA_DIR}" && cd "${DATA_DIR}"

    # clone source locally so we can patch it before building
    log_info "cloning qubic-core-lite..."
    if [ -d "${DATA_DIR}/qubic-core-lite" ]; then
        log_info "source exists, pulling..."
        cd "${DATA_DIR}/qubic-core-lite" && git pull
    else
        git clone "${REPO_URL}" "${DATA_DIR}/qubic-core-lite"
    fi
    cd "${DATA_DIR}"

    # download epoch data first to detect available epoch
    mkdir -p "${DATA_DIR}/data"
    download_epoch_data "${DATA_DIR}/data"

    # patch source to match downloaded epoch data before building
    sync_source_epoch "${DATA_DIR}/qubic-core-lite"

    local avx_flag="OFF"
    [ "$ENABLE_AVX512" = true ] && avx_flag="ON"

    # exclude large dirs from Docker build context
    printf "data/\nqubic-core-lite/.git/\n" > "${DATA_DIR}/.dockerignore"

    log_info "creating Dockerfile..."
    cat > "${DATA_DIR}/Dockerfile" <<DOCKEREOF
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \\
    build-essential clang cmake nasm git g++ \\
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \\
    libstdc++-12-dev libfmt-dev \\
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY qubic-core-lite/ .
WORKDIR /app/build
RUN cmake .. \\
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \\
    -DBUILD_TESTS=OFF -DBUILD_BINARY=ON \\
    -DCMAKE_BUILD_TYPE=Release -DENABLE_AVX512=${avx_flag} \\
    && cmake --build . -- -j\$(nproc)

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \\
    libc++1 libc++abi1 libjsoncpp25 libfmt9 \\
    && rm -rf /var/lib/apt/lists/*
WORKDIR /qubic
COPY --from=builder /app/build/src/Qubic .
EXPOSE ${NODE_PORT} ${HTTP_PORT}
ENTRYPOINT ["./Qubic"]
DOCKEREOF

    log_info "building docker image (this takes a while)..."
    docker build -t qubic-lite-node "${DATA_DIR}"

    local node_args
    node_args=$(build_node_args)

    cat > "${DATA_DIR}/docker-compose.yml" <<COMPOSEEOF
services:
  qubic-lite:
    image: qubic-lite-node
    container_name: qubic-lite
    restart: unless-stopped
    ports:
      - "${NODE_PORT}:${NODE_PORT}"
      - "${HTTP_PORT}:${HTTP_PORT}"
    volumes:
      - ${DATA_DIR}/data:/qubic/data
    command: ${node_args}
COMPOSEEOF

    log_info "starting container..."
    docker compose up -d

    log_ok "done!"
    print_status_docker
}

# --- manual install (source) ---

install_manual() {
    log_info "building lite node from source..."

    log_info "installing deps..."
    apt-get update -qq
    NEEDRESTART_MODE=a apt-get install -y -qq build-essential clang cmake nasm git g++ \
        libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \
        libstdc++-12-dev libfmt-dev \
        wget curl tmux

    ensure_build_tools

    log_info "cloning qubic-core-lite..."
    mkdir -p "${DATA_DIR}"

    if [ -d "${DATA_DIR}/qubic-core-lite" ]; then
        log_info "source exists, pulling..."
        cd "${DATA_DIR}/qubic-core-lite" && git pull
    else
        git clone "${REPO_URL}" "${DATA_DIR}/qubic-core-lite"
    fi

    cd "${DATA_DIR}/qubic-core-lite"

    # download epoch data first so we can detect the available epoch
    mkdir -p "${DATA_DIR}/data"
    download_epoch_data "${DATA_DIR}/data"

    # patch source to match downloaded epoch data before building
    sync_source_epoch "${DATA_DIR}/qubic-core-lite"

    local avx_flag="OFF"
    [ "$ENABLE_AVX512" = true ] && avx_flag="ON"

    mkdir -p build

    # clear cmake cache if compiler changed (avoids stale cache losing build flags)
    if [ -f build/CMakeCache.txt ]; then
        local cached_cxx
        cached_cxx=$(grep -oP 'CMAKE_CXX_COMPILER:FILEPATH=\K.*' build/CMakeCache.txt 2>/dev/null || true)
        local target_cxx
        target_cxx=$(command -v "${CLANG_CXX}" 2>/dev/null || echo "${CLANG_CXX}")
        if [ -n "$cached_cxx" ] && [ "$cached_cxx" != "$target_cxx" ]; then
            log_warn "compiler changed (${cached_cxx} -> ${target_cxx}), clearing cmake cache..."
            rm -rf build/*
        fi
    fi

    cd build
    cmake .. \
        -DCMAKE_C_COMPILER="${CLANG_C}" \
        -DCMAKE_CXX_COMPILER="${CLANG_CXX}" \
        -DBUILD_TESTS=OFF \
        -DBUILD_BINARY=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_AVX512="${avx_flag}"
    cmake --build . -- -j"$(nproc)"
    log_ok "build complete"

    create_lite_service

    log_ok "done!"
    print_status_manual
}

# --- component installers ---

ensure_build_tools() {
    log_info "checking build tools..."

    # check clang version, install 18 if missing or too old
    # prefer clang-18 binary first (avoids false warning when system default is older)
    local need_clang=false
    if command -v clang-18 &> /dev/null; then
        local clang_ver
        clang_ver=$(clang-18 --version | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)
        log_ok "clang-18: ${clang_ver}"
        CLANG_C="clang-18"
        CLANG_CXX="clang++-18"
    elif command -v clang &> /dev/null; then
        local clang_ver clang_major
        clang_ver=$(clang --version | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)
        clang_major=$(echo "$clang_ver" | cut -d. -f1)
        if [ "$clang_major" -ge 18 ] 2>/dev/null; then
            log_ok "clang: ${clang_ver}"
        else
            log_warn "clang: ${clang_ver} (need >= 18) -- installing clang-18..."
            need_clang=true
        fi
    else
        log_warn "clang: not found -- installing clang-18..."
        need_clang=true
    fi

    if [ "$need_clang" = true ]; then
        # try default repos first (Ubuntu 24.04+ ships clang-18)
        apt-get update -qq
        if NEEDRESTART_MODE=a apt-get install -y -qq clang-18 libc++-18-dev libc++abi-18-dev 2>/dev/null; then
            log_ok "clang-18 installed (default repos)"
        else
            # fallback: add LLVM upstream repo
            log_info "clang-18 not in default repos, adding LLVM repo..."

            # get codename from os-release (no lsb_release needed)
            local codename=""
            if [ -f /etc/os-release ]; then
                codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
            fi
            if [ -z "$codename" ]; then
                codename=$(. /etc/os-release && echo "$UBUNTU_CODENAME")
            fi
            if [ -z "$codename" ]; then
                log_error "cannot determine distro codename for LLVM repo"
                exit 1
            fi

            rm -f /usr/share/keyrings/llvm-archive-keyring.gpg
            if ! wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key \
                | gpg --dearmor -o /usr/share/keyrings/llvm-archive-keyring.gpg; then
                log_error "failed to import LLVM GPG key"
                exit 1
            fi

            echo "deb [signed-by=/usr/share/keyrings/llvm-archive-keyring.gpg] http://apt.llvm.org/${codename}/ llvm-toolchain-${codename}-18 main" \
                > /etc/apt/sources.list.d/llvm-18.list
            apt-get update -qq

            if ! NEEDRESTART_MODE=a apt-get install -y -qq clang-18 libc++-18-dev libc++abi-18-dev; then
                log_error "failed to install clang-18"
                exit 1
            fi
            log_ok "clang-18 installed (LLVM repo)"
        fi

        # verify clang-18 is actually usable
        if ! command -v clang-18 &> /dev/null; then
            log_error "clang-18 binary not found after install"
            exit 1
        fi

        CLANG_C="clang-18"
        CLANG_CXX="clang++-18"
    fi

    # cmake
    if command -v cmake &> /dev/null; then
        local cmake_ver
        cmake_ver=$(cmake --version | head -1 | grep -oP '\d+\.\d+(\.\d+)?' | head -1)
        log_ok "cmake: ${cmake_ver}"
    else
        log_error "cmake not found"; exit 1
    fi

    # nasm
    if command -v nasm &> /dev/null; then
        local nasm_ver
        nasm_ver=$(nasm --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        log_ok "nasm: ${nasm_ver}"
    else
        log_error "nasm not found"; exit 1
    fi
}

install_docker_engine() {
    if command -v docker &> /dev/null; then
        log_ok "docker: $(docker --version)"
        return
    fi
    log_info "installing docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker && systemctl start docker
    log_ok "docker installed"
}

create_lite_service() {
    log_info "creating systemd service..."

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
    systemctl enable qubic-lite && systemctl start qubic-lite
    log_ok "service started"
}

# --- epoch data download (mainnet) ---

download_epoch_data() {
    local target_dir="$1"

    if [ "$TESTNET" = true ]; then
        return
    fi

    if [ "$SKIP_EPOCH" = true ]; then
        log_warn "epoch download skipped (--no-epoch)"
        log_warn "download manually from: https://storage.qubic.li/network/"
        return
    fi

    # ensure unzip is available
    if ! command -v unzip &> /dev/null; then
        log_info "installing unzip..."
        apt-get update -qq
        NEEDRESTART_MODE=a apt-get install -y -qq unzip
    fi

    local storage_url="https://storage.qubic.li/network"

    log_info "detecting latest epoch from storage.qubic.li..."
    local latest_epoch
    latest_epoch=$(curl -sf "${storage_url}/" | grep -o 'ep[0-9]*-full\.zip' | grep -o '[0-9]*' | sort -n | tail -1)

    if [ -z "$latest_epoch" ]; then
        log_warn "could not detect latest epoch"
        log_warn "download manually from: ${storage_url}/"
        return
    fi

    local zip_file="ep${latest_epoch}-full.zip"
    local zip_url="${storage_url}/${latest_epoch}/${zip_file}"

    log_info "latest epoch: ${latest_epoch}"
    log_info "downloading ${zip_file} ..."

    mkdir -p "${target_dir}"

    if ! wget --tries=3 --timeout=120 --waitretry=5 --show-progress -O "${target_dir}/${zip_file}" "${zip_url}"; then
        log_warn "download failed: ${zip_url}"
        log_warn "download manually from: ${storage_url}/"
        rm -f "${target_dir}/${zip_file}"
        return
    fi

    log_info "extracting epoch data..."
    if ! unzip -o -q "${target_dir}/${zip_file}" -d "${target_dir}"; then
        log_warn "extraction failed"
        return
    fi

    rm -f "${target_dir}/${zip_file}"
    DETECTED_EPOCH="${latest_epoch}"
    log_ok "epoch ${latest_epoch} data ready in ${target_dir}"
}

# --- epoch / source sync ---

sync_source_epoch() {
    local src_dir="$1"
    local settings_file="${src_dir}/src/public_settings.h"

    if [ -z "$DETECTED_EPOCH" ]; then
        log_warn "no epoch detected, skipping source sync"
        return
    fi

    if [ ! -f "$settings_file" ]; then
        log_warn "public_settings.h not found, skipping source sync"
        return
    fi

    local current_epoch current_tick
    current_epoch=$(grep -oP '#define\s+EPOCH\s+\K[0-9]+' "$settings_file" || true)
    current_tick=$(grep -oP '#define\s+TICK\s+\K[0-9]+' "$settings_file" || true)

    if [ -z "$current_epoch" ]; then
        log_warn "could not read EPOCH from public_settings.h"
        return
    fi

    if [ "$current_epoch" = "$DETECTED_EPOCH" ]; then
        log_ok "source EPOCH ${current_epoch} matches epoch data (TICK ${current_tick})"
        return
    fi

    # find the matching TICK from git history (EPOCH + TICK are always committed together)
    log_info "source EPOCH ${current_epoch} != epoch data ${DETECTED_EPOCH}, searching git history for matching TICK..."
    local target_tick=""
    local commits
    commits=$(cd "$src_dir" && git log --format="%H" -50 -- src/public_settings.h 2>/dev/null || true)
    for c in $commits; do
        local ep
        ep=$(cd "$src_dir" && git show "${c}:src/public_settings.h" 2>/dev/null | grep -oP '#define\s+EPOCH\s+\K[0-9]+' || true)
        if [ "$ep" = "$DETECTED_EPOCH" ]; then
            target_tick=$(cd "$src_dir" && git show "${c}:src/public_settings.h" | grep -oP '#define\s+TICK\s+\K[0-9]+' || true)
            log_info "found TICK ${target_tick} for EPOCH ${DETECTED_EPOCH} in commit ${c:0:8}"
            break
        fi
    done

    if [ -z "$target_tick" ]; then
        log_warn "could not find TICK for EPOCH ${DETECTED_EPOCH} in git history, keeping TICK ${current_tick}"
        target_tick="$current_tick"
    fi

    log_info "patching source: EPOCH ${current_epoch} -> ${DETECTED_EPOCH}, TICK ${current_tick} -> ${target_tick}"
    sed -i "s/#define EPOCH ${current_epoch}/#define EPOCH ${DETECTED_EPOCH}/" "$settings_file"
    sed -i "s/#define TICK ${current_tick}/#define TICK ${target_tick}/" "$settings_file"
    log_ok "public_settings.h patched (EPOCH=${DETECTED_EPOCH}, TICK=${target_tick})"
}

# --- status output ---

print_status_docker() {
    local mode_label="mainnet"
    [ "$TESTNET" = true ] && mode_label="testnet"

    echo ""
    echo -e "${GREEN}--- lite node ready (${mode_label}) ---${NC}"
    echo "  dir:      ${DATA_DIR}"
    echo "  P2P:      ${NODE_PORT}"
    echo "  HTTP/RPC: http://localhost:${HTTP_PORT}"
    [ -n "$PEERS" ] && echo "  peers:    ${PEERS}"
    echo ""
    echo "  docker compose ps       # status"
    echo "  docker compose logs -f  # logs"
    echo ""
    echo "  http://localhost:${HTTP_PORT}/live/v1   # live status"
    echo "  http://localhost:${HTTP_PORT}/query/v1  # query API"
    echo ""
    if [ "$TESTNET" = false ]; then
        echo "  epoch data: ${DATA_DIR}/data"
        echo "  update epochs: https://storage.qubic.li/network/"
        echo ""
    fi
}

print_status_manual() {
    local mode_label="mainnet"
    [ "$TESTNET" = true ] && mode_label="testnet"

    echo ""
    echo -e "${GREEN}--- lite node ready (${mode_label}) ---${NC}"
    echo "  binary:   ${DATA_DIR}/qubic-core-lite/build/src/Qubic"
    echo "  workdir:  ${DATA_DIR}/data"
    echo "  service:  qubic-lite"
    echo "  P2P:      ${NODE_PORT}"
    echo "  HTTP/RPC: http://localhost:${HTTP_PORT}"
    [ -n "$PEERS" ] && echo "  peers:    ${PEERS}"
    echo ""
    echo "  systemctl status qubic-lite    # status"
    echo "  journalctl -u qubic-lite -f    # logs"
    echo ""
    echo "  http://localhost:${HTTP_PORT}/live/v1   # live status"
    echo "  http://localhost:${HTTP_PORT}/query/v1  # query API"
    echo ""
    if [ "$TESTNET" = false ]; then
        echo "  epoch data: ${DATA_DIR}/data"
        echo "  update epochs: https://storage.qubic.li/network/"
        echo ""
    fi
}

# --- arg parsing ---

parse_args() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
    fi

    MODE="$1"; shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --peers)         PEERS="$2";         shift 2 ;;
            --testnet)       TESTNET=true;       shift   ;;
            --port)          NODE_PORT="$2";      shift 2 ;;
            --http-port)     HTTP_PORT="$2";      shift 2 ;;
            --data-dir)      DATA_DIR="$2";       shift 2 ;;
            --operator-seed) OPERATOR_SEED="$2";  shift 2 ;;
            --operator-alias) OPERATOR_ALIAS="$2"; shift 2 ;;
            --avx512)        ENABLE_AVX512=true;  shift   ;;
            --security-tick) SECURITY_TICK="$2";  shift 2 ;;
            --ticking-delay) TICKING_DELAY="$2";  shift 2 ;;
            --no-epoch)      SKIP_EPOCH=true;     shift   ;;
            --help|-h)       print_usage;         exit 0  ;;
            *) log_error "unknown option: $1"; print_usage; exit 1 ;;
        esac
    done
}

# --- main ---

main() {
    echo -e "${CYAN}=== qubic lite node installer ===${NC}"
    parse_args "$@"
    check_root

    if [ -z "$OPERATOR_SEED" ]; then
        log_error "--operator-seed is required."
        print_usage
        exit 1
    fi

    if [ -z "$OPERATOR_ALIAS" ]; then
        log_error "--operator-alias is required."
        print_usage
        exit 1
    fi

    check_system

    case "$MODE" in
        docker) install_docker ;;
        manual) install_manual ;;
        *) log_error "unknown mode: ${MODE}"; print_usage; exit 1 ;;
    esac

    # cleanup: remove installer script
    local script_path
    script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    rm -f "$script_path"
    log_ok "installer removed: ${script_path}"
}

main "$@"
