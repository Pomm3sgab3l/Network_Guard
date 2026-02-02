#!/bin/bash
# bob-install.sh - Qubic Bob Node installer & manager
#
# Usage:
#   Interactive:  ./bob-install.sh
#   CLI:          ./bob-install.sh <mode> [options]
#
# Install modes:
#   docker-standalone   all-in-one container (recommended)
#   docker-compose      modular setup (separate containers)
#   uninstall           remove bob node completely
#
# Management modes:
#   status              show container status
#   logs                show live logs (Ctrl+C to exit)
#   stop                stop containers
#   start               start containers
#   restart             restart containers
#   update              pull latest image + restart
#
# Options:
#   --node-seed <seed>      node identity seed (required for install)
#   --node-alias <alias>    node alias name (required for install)
#   --peers <ip:port,...>   peers to sync from
#   --threads <n>           max threads (0=auto)
#   --rpc-port <port>       REST API port (default: 40420)
#   --server-port <port>    P2P port (default: 21842)
#   --data-dir <path>       install dir (default: /opt/qubic-bob)
#   --firewall <mode>       firewall profile: closed | open

set -e

# resolve own path before any cd changes the working directory
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# defaults
MODE=""
PEERS=""
BM_PEERS=""
MAX_THREADS=0
RPC_PORT=40420
SERVER_PORT=21842
DATA_DIR="/opt/qubic-bob"
REPO_URL="https://github.com/qubic/core-bob.git"
DOCKER_IMAGE="qubiccore/bob"
DOCKER_IMAGE_STANDALONE="qubiccore/bob"
ARBITRATOR_ID="AFZPUAIYVPNUYGJRQVLUKOPPVLHAZQTGLYAAUUNBXFTVTAMSBKQBLEIEPCVJ"
BOOTSTRAP_URL="https://storage.qubic.li/network"
FIREWALL_MODE=""
NODE_SEED=""
NODE_ALIAS=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }

print_usage() {
    echo "Usage:"
    echo "  Interactive:  $0"
    echo "  CLI:          $0 <mode> --node-seed <seed> --node-alias <alias> [options]"
    echo ""
    echo "Modes (install):"
    echo "  docker-standalone   all-in-one container (recommended)"
    echo "  docker-compose      modular (separate containers)"
    echo "  uninstall           remove bob node completely"
    echo ""
    echo "Modes (manage):"
    echo "  status              show container status"
    echo "  logs                show live logs (Ctrl+C to exit)"
    echo "  stop                stop containers"
    echo "  start               start containers"
    echo "  restart             restart containers"
    echo "  update              pull latest image + restart"
    echo ""
    echo "Options:"
    echo "  --node-seed <seed>     node identity seed (REQUIRED for install)"
    echo "  --node-alias <alias>   node alias name (REQUIRED for install)"
    echo "  --peers <ip:port,...>  peers to sync from"
    echo "  --threads <n>          max threads (0=auto)"
    echo "  --rpc-port <port>      REST API port (default: 40420)"
    echo "  --server-port <port>   P2P port (default: 21842)"
    echo "  --data-dir <path>      install dir (default: /opt/qubic-bob)"
    echo "  --firewall <mode>      firewall profile: closed | open"
    echo "                           closed = SSH + P2P only (recommended)"
    echo "                           open   = SSH + P2P + API"
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

    local ram_kb ram_gb cores avail_gb
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    ram_gb=$((ram_kb / 1024 / 1024))
    cores=$(nproc)
    avail_gb=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')

    [ "$ram_gb" -lt 14 ] && log_warn "RAM: ${ram_gb}GB (need 16GB)" || log_ok "RAM: ${ram_gb}GB"
    [ "$cores" -lt 4 ] && log_warn "CPU: ${cores} cores (need 4)" || log_ok "CPU: ${cores} cores"
    grep -q avx2 /proc/cpuinfo && log_ok "AVX2: yes" || log_warn "AVX2: not detected"
    [ "$avail_gb" -lt 100 ] && log_warn "Disk: ${avail_gb}GB (need 100GB)" || log_ok "Disk: ${avail_gb}GB"
}

# --- firewall ---

setup_firewall() {
    if [ -z "$FIREWALL_MODE" ]; then
        return
    fi

    log_info "configuring firewall (${FIREWALL_MODE})..."

    if ! command -v ufw &> /dev/null; then
        log_info "installing ufw..."
        apt-get update -qq && apt-get install -y -qq ufw > /dev/null
    fi

    # reset to clean state
    ufw --force reset > /dev/null 2>&1

    # default policy: block incoming, allow outgoing
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1

    # always allow SSH
    ufw allow 22/tcp > /dev/null 2>&1
    log_ok "fw: allow SSH (22/tcp)"

    # always allow P2P
    ufw allow "${SERVER_PORT}/tcp" > /dev/null 2>&1
    log_ok "fw: allow P2P (${SERVER_PORT}/tcp)"

    # API only in open mode
    if [ "$FIREWALL_MODE" = "open" ]; then
        ufw allow "${RPC_PORT}/tcp" > /dev/null 2>&1
        log_ok "fw: allow API (${RPC_PORT}/tcp)"
    else
        log_ok "fw: block API (${RPC_PORT}/tcp) -- closed mode"
    fi

    # enable firewall
    ufw --force enable > /dev/null 2>&1
    log_ok "fw: enabled ($(ufw status | head -1))"
}

# --- peer discovery ---

PEER_LIST_URL="https://app.qubic.li/network/live"

fetch_default_peers() {
    # fetch peers from qubic.global API when none provided
    if [ -n "$PEERS" ]; then
        # user provided manual peers - parse them into BM category
        parse_manual_peers
        return
    fi
    log_info "fetching peers from qubic.global API..."
    local resp
    resp=$(curl -sSf --max-time 10 "https://api.qubic.global/random-peers?service=bobNode&litePeers=6" 2>/dev/null) || {
        log_error "could not reach qubic.global API"
        log_warn "please provide peers manually with --peers or select from:"
        log_warn "  ${PEER_LIST_URL}"
        log_warn ""
        log_warn "example: --peers 1.2.3.4,5.6.7.8"
        exit 1
    }

    # Extract litePeers (these become BM/trusted-node peers)
    local api_lite_peers
    api_lite_peers=$(echo "$resp" | grep -oP '"litePeers"\s*:\s*\[([^\]]*)\]' | grep -oP '"[^"]+\.\d+"' | tr -d '"')

    # Extract bobPeers (these provide actual tick data)
    local api_bob_peers
    api_bob_peers=$(echo "$resp" | grep -oP '"bobPeers"\s*:\s*\[([^\]]*)\]' | grep -oP '"[^"]+\.\d+"' | tr -d '"')

    # Build peer lists
    BM_PEERS=""
    for ip in $api_lite_peers; do BM_PEERS="${BM_PEERS:+$BM_PEERS,}BM:${ip}:21841:0-0-0-0"; done

    BOB_PEERS=""
    for ip in $api_bob_peers; do BOB_PEERS="${BOB_PEERS:+$BOB_PEERS,}bob:${ip}:21842"; done

    if [ -z "$BM_PEERS" ] && [ -z "$BOB_PEERS" ]; then
        log_error "API returned no peers"
        log_warn "please provide peers manually with --peers or select from:"
        log_warn "  ${PEER_LIST_URL}"
        exit 1
    fi

    [ -n "$BM_PEERS" ] && log_ok "peers (BM): ${BM_PEERS}"
    [ -n "$BOB_PEERS" ] && log_ok "peers (bob): ${BOB_PEERS}"
}

parse_manual_peers() {
    # Parse user-provided PEERS string into BM and bob peers
    # Supports formats:
    #   BM:ip:port:pass        -> BM peer as-is
    #   BM:ip:port             -> BM peer, add :0-0-0-0 suffix
    #   bob:ip:port            -> bob peer as-is
    #   bob:ip                 -> bob peer, add :21842 port
    #   ip:port                -> BM peer, add BM: prefix and :0-0-0-0 suffix
    #   ip                     -> BM peer, add BM: prefix, :21841 port, and :0-0-0-0 suffix
    BM_PEERS=""
    BOB_PEERS=""
    local IFS=','
    for peer in $PEERS; do
        peer=$(echo "$peer" | xargs)  # trim whitespace
        if [[ "$peer" == BM:* ]]; then
            # BM peer
            if [[ "$peer" =~ ^BM:[0-9.]+:[0-9]+:[0-9-]+$ ]]; then
                BM_PEERS="${BM_PEERS:+$BM_PEERS,}$peer"
            elif [[ "$peer" =~ ^BM:[0-9.]+:[0-9]+$ ]]; then
                BM_PEERS="${BM_PEERS:+$BM_PEERS,}${peer}:0-0-0-0"
            else
                log_warn "skipping invalid BM peer format: $peer"
            fi
        elif [[ "$peer" == bob:* ]]; then
            # bob peer
            if [[ "$peer" =~ ^bob:[0-9.]+:[0-9]+$ ]]; then
                BOB_PEERS="${BOB_PEERS:+$BOB_PEERS,}$peer"
            elif [[ "$peer" =~ ^bob:[0-9.]+$ ]]; then
                local ip="${peer#bob:}"
                BOB_PEERS="${BOB_PEERS:+$BOB_PEERS,}bob:${ip}:21842"
            else
                log_warn "skipping invalid bob peer format: $peer"
            fi
        elif [[ "$peer" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
            # ip:port format -> add BM: prefix and passcode
            BM_PEERS="${BM_PEERS:+$BM_PEERS,}BM:${peer}:0-0-0-0"
        elif [[ "$peer" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # ip only -> add BM: prefix, default port, and passcode
            BM_PEERS="${BM_PEERS:+$BM_PEERS,}BM:${peer}:21841:0-0-0-0"
        else
            log_warn "skipping invalid peer format: $peer"
        fi
    done

    if [ -z "$BM_PEERS" ] && [ -z "$BOB_PEERS" ]; then
        log_error "no valid peers found in: $PEERS"
        log_warn "please provide valid peer IPs, e.g.: --peers 1.2.3.4,5.6.7.8"
        log_warn "find peers at: ${PEER_LIST_URL}"
        exit 1
    fi

    [ -n "$BM_PEERS" ] && log_ok "peers (BM): ${BM_PEERS}"
    [ -n "$BOB_PEERS" ] && log_ok "peers (bob): ${BOB_PEERS}"
}

# --- bootstrap download ---

download_bootstrap() {
    local data_dir="$1"

    log_info "checking for bootstrap files..."

    # Get current epoch from API
    local epoch
    epoch=$(curl -sSf --max-time 10 "https://rpc.qubic.org/v1/status" 2>/dev/null | grep -oP '"epoch":\s*\K[0-9]+' | head -1) || {
        log_warn "could not get current epoch from API, skipping bootstrap"
        return 0
    }

    if [ -z "$epoch" ]; then
        log_warn "could not parse epoch, skipping bootstrap"
        return 0
    fi

    log_ok "current epoch: ${epoch}"

    # Check if bootstrap files already exist
    if [ -f "${data_dir}/spectrum.${epoch}" ] && [ -f "${data_dir}/universe.${epoch}" ]; then
        log_ok "bootstrap files already exist"
        return 0
    fi

    # Download bootstrap ZIP
    local zip_url="${BOOTSTRAP_URL}/${epoch}/ep${epoch}-bob.zip"
    local zip_file="/tmp/ep${epoch}-bob.zip"

    log_info "downloading bootstrap files (~1.8GB)..."
    log_info "  ${zip_url}"

    if ! curl -sSfL --max-time 600 -o "$zip_file" "$zip_url" 2>/dev/null; then
        log_warn "bootstrap download failed, node will sync from scratch (slower)"
        return 0
    fi

    # Extract to data directory
    log_info "extracting bootstrap files..."
    mkdir -p "$data_dir"
    if ! unzip -o -q "$zip_file" -d "$data_dir" 2>/dev/null; then
        log_warn "bootstrap extraction failed"
        rm -f "$zip_file"
        return 0
    fi

    rm -f "$zip_file"
    log_ok "bootstrap files ready (epoch ${epoch})"
}

# --- config generation ---

generate_config() {
    local keydb_host="$1" kvrocks_host="$2" config_path="$3"

    # Combine BM and bob peers for trusted-node
    local all_peers=""
    [ -n "$BM_PEERS" ] && all_peers="$BM_PEERS"
    [ -n "$BOB_PEERS" ] && all_peers="${all_peers:+$all_peers,}$BOB_PEERS"

    # Build JSON array for trusted-node
    local trusted_json="[]"
    if [ -n "$all_peers" ]; then
        trusted_json=$(echo "$all_peers" | tr ',' '\n' | awk '{printf "\"%s\",", $0}' | sed 's/,$//' | awk '{print "["$0"]"}')
    fi

    cat > "$config_path" <<CONFIGEOF
{
  "p2p-node": [],
  "trusted-node": ${trusted_json},
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
  "spam-qu-threshold": 100,
  "node-seed": "${NODE_SEED}",
  "node-alias": "${NODE_ALIAS}"
}
CONFIGEOF

    log_ok "config -> ${config_path}"
}

# --- docker standalone ---

install_docker_standalone() {
    log_info "setting up bob (docker standalone)..."

    install_docker_engine
    mkdir -p "${DATA_DIR}/data" && cd "${DATA_DIR}"

    fetch_default_peers
    generate_config "127.0.0.1" "127.0.0.1" "${DATA_DIR}/bob.json"

    # Download bootstrap files before starting container
    download_bootstrap "${DATA_DIR}/data"

    cat > "${DATA_DIR}/docker-compose.yml" <<'COMPOSEEOF'
services:
  qubic-bob:
    image: j0et0m/qubic-bob-standalone:latest
    restart: unless-stopped
    ports:
      - "21842:21842"
      - "40420:40420"
    volumes:
      - ./bob.json:/app/config/bob.json:ro
      - qubic-bob-redis:/data/redis
      - qubic-bob-kvrocks:/data/kvrocks
      - ./data:/data/bob

volumes:
  qubic-bob-redis:
  qubic-bob-kvrocks:
COMPOSEEOF

    sed -i "s/\"21842:21842\"/\"${SERVER_PORT}:21842\"/" "${DATA_DIR}/docker-compose.yml"
    sed -i "s/\"40420:40420\"/\"${RPC_PORT}:40420\"/" "${DATA_DIR}/docker-compose.yml"

    log_info "starting containers..."
    docker compose up -d

    log_ok "done!"
    print_status_docker
}

# --- docker compose (modular) ---

install_docker_compose() {
    log_info "setting up bob (docker compose)..."

    install_docker_engine
    mkdir -p "${DATA_DIR}/data" && cd "${DATA_DIR}"

    fetch_default_peers
    generate_config "keydb" "kvrocks" "${DATA_DIR}/bob.json"

    log_info "downloading keydb/kvrocks configs..."
    curl -sSfL -o "${DATA_DIR}/keydb.conf" \
        "https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/keydb.conf"
    curl -sSfL -o "${DATA_DIR}/kvrocks.conf" \
        "https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/kvrocks.conf"

    # Download bootstrap files before starting container
    download_bootstrap "${DATA_DIR}/data"

    cat > "${DATA_DIR}/docker-compose.yml" <<'COMPOSEEOF'
services:
  qubic-bob:
    image: j0et0m/qubicbob:latest
    restart: unless-stopped
    entrypoint: ["/app/bob", "/app/bob.json"]
    working_dir: /data/bob
    ports:
      - "21842:21842"
      - "40420:40420"
    volumes:
      - ./bob.json:/app/bob.json:ro
      - ./data:/data/bob
    depends_on:
      keydb:
        condition: service_healthy
      kvrocks:
        condition: service_healthy
    networks:
      - bobnet

  keydb:
    image: eqalpha/keydb:latest
    restart: unless-stopped
    command: keydb-server /etc/keydb/keydb.conf
    ports:
      - "6379:6379"
    volumes:
      - ./keydb.conf:/etc/keydb/keydb.conf:ro
      - qubic-bob-keydb:/data
    healthcheck:
      test: ["CMD", "keydb-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - bobnet

  kvrocks:
    image: apache/kvrocks:latest
    restart: unless-stopped
    ports:
      - "6666:6666"
    volumes:
      - ./kvrocks.conf:/var/lib/kvrocks/kvrocks.conf:ro
      - qubic-bob-kvrocks:/var/lib/kvrocks
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "6666", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - bobnet

networks:
  bobnet:

volumes:
  qubic-bob-keydb:
  qubic-bob-kvrocks:
COMPOSEEOF

    sed -i "0,/\"21842:21842\"/{s/\"21842:21842\"/\"${SERVER_PORT}:21842\"/}" "${DATA_DIR}/docker-compose.yml"
    sed -i "0,/\"40420:40420\"/{s/\"40420:40420\"/\"${RPC_PORT}:40420\"/}" "${DATA_DIR}/docker-compose.yml"

    log_info "starting containers..."
    docker compose up -d

    log_ok "done!"
    print_status_docker
}

# --- manual (source build) ---

install_manual() {
    log_info "building bob from source..."

    log_info "installing deps..."
    apt-get update
    apt-get install -y build-essential cmake git libjsoncpp-dev \
        uuid-dev libhiredis-dev zlib1g-dev unzip wget curl \
        net-tools tmux lsb-release gnupg

    install_keydb
    install_kvrocks

    log_info "cloning qubicbob..."
    mkdir -p "${DATA_DIR}"

    if [ -d "${DATA_DIR}/qubicbob" ]; then
        log_info "source exists, pulling..."
        cd "${DATA_DIR}/qubicbob" && git pull
    else
        git clone "${REPO_URL}" "${DATA_DIR}/qubicbob"
        cd "${DATA_DIR}/qubicbob"
    fi

    mkdir -p build && cd build
    cmake ../
    make -j"$(nproc)"
    log_ok "build complete"

    generate_config "127.0.0.1" "127.0.0.1" "${DATA_DIR}/qubicbob/build/config.json"

    # Download bootstrap files
    download_bootstrap "${DATA_DIR}/qubicbob/build"

    create_bob_service

    log_ok "done!"
    print_status_manual
}

# --- component installers ---

install_docker_engine() {
    if command -v docker &> /dev/null; then
        log_ok "docker: $(docker --version)"
    else
        log_info "installing docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker && systemctl start docker
        log_ok "docker installed"
    fi

    # Ensure unzip is available for bootstrap extraction
    if ! command -v unzip &> /dev/null; then
        log_info "installing unzip..."
        apt-get update -qq && apt-get install -y -qq unzip > /dev/null
    fi
}

install_keydb() {
    if systemctl is-active --quiet keydb-server 2>/dev/null; then
        log_ok "keydb already running"
        return
    fi
    log_info "installing keydb..."
    echo "deb https://download.keydb.dev/open-source-dist $(lsb_release -sc) main" | \
        tee /etc/apt/sources.list.d/keydb.list
    wget -qO /etc/apt/trusted.gpg.d/keydb.gpg \
        https://download.keydb.dev/open-source-dist/keyring.gpg
    apt-get update && apt-get install -y keydb
    systemctl enable keydb-server && systemctl start keydb-server
    log_ok "keydb running"
}

install_kvrocks() {
    if command -v kvrocks &> /dev/null || [ -f /usr/local/bin/kvrocks ]; then
        log_ok "kvrocks already installed"
        return
    fi
    log_info "building kvrocks (takes a while)..."
    local bdir="/tmp/kvrocks-build"
    rm -rf "${bdir}"
    git clone --branch v2.9.0 --depth 1 https://github.com/apache/kvrocks.git "${bdir}"
    cd "${bdir}" && mkdir build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j"$(nproc)"
    cp src/kvrocks /usr/local/bin/

    cat > /etc/systemd/system/kvrocks.service <<EOF
[Unit]
Description=KVRocks
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
    systemctl enable kvrocks && systemctl start kvrocks
    rm -rf "${bdir}"
    log_ok "kvrocks running"
}

create_bob_service() {
    log_info "creating systemd service..."
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
    systemctl enable qubic-bob && systemctl start qubic-bob
    log_ok "service started"
}

# --- status output ---

print_status_docker() {
    echo ""
    echo -e "${GREEN}--- bob node ready ---${NC}"
    echo "  dir:     ${DATA_DIR}"
    echo "  config:  ${DATA_DIR}/bob.json"
    echo "  P2P:     ${SERVER_PORT}"
    echo "  API:     http://localhost:${RPC_PORT}"
    if [ -n "$FIREWALL_MODE" ]; then
        echo "  FW:      ${FIREWALL_MODE}"
    fi
    echo ""
    echo "  docker compose -f ${DATA_DIR}/docker-compose.yml ps       # status"
    echo "  docker compose -f ${DATA_DIR}/docker-compose.yml logs -f  # logs"
    echo "  docker compose -f ${DATA_DIR}/docker-compose.yml restart  # restart"
    echo ""
}

print_status_manual() {
    echo ""
    echo -e "${GREEN}--- bob node ready ---${NC}"
    echo "  binary:  ${DATA_DIR}/qubicbob/build/bob"
    echo "  config:  ${DATA_DIR}/qubicbob/build/config.json"
    echo "  service: qubic-bob"
    echo "  P2P:     ${SERVER_PORT}"
    echo "  API:     http://localhost:${RPC_PORT}"
    if [ -n "$FIREWALL_MODE" ]; then
        echo "  FW:      ${FIREWALL_MODE}"
    fi
    echo ""
    echo "  systemctl status qubic-bob    # status"
    echo "  journalctl -u qubic-bob -f    # logs"
    echo ""
}

# --- uninstall ---

do_uninstall() {
    log_info "uninstalling bob node..."

    # stop and remove docker containers
    if [ -f "${DATA_DIR}/docker-compose.yml" ]; then
        log_info "stopping docker containers..."
        docker compose -f "${DATA_DIR}/docker-compose.yml" down -v 2>/dev/null || true
        log_ok "containers stopped and volumes removed"
    fi

    # stop systemd service if exists
    if systemctl is-active --quiet qubic-bob 2>/dev/null; then
        log_info "stopping systemd service..."
        systemctl stop qubic-bob
        systemctl disable qubic-bob
        rm -f /etc/systemd/system/qubic-bob.service
        systemctl daemon-reload
        log_ok "service removed"
    fi

    # remove install directory
    if [ -d "${DATA_DIR}" ]; then
        log_info "removing ${DATA_DIR}..."
        rm -rf "${DATA_DIR}"
        log_ok "directory removed"
    fi

    # ask about firewall reset
    echo ""
    read -rp "Reset firewall rules? [y/N]: " reset_fw
    if [[ "$reset_fw" =~ ^[Yy]$ ]]; then
        if command -v ufw &> /dev/null; then
            ufw --force disable > /dev/null 2>&1
            ufw --force reset > /dev/null 2>&1
            log_ok "firewall reset"
        else
            log_warn "ufw not installed"
        fi
    fi

    echo ""
    log_ok "bob node uninstalled"
}

# --- management commands ---

check_installed() {
    if [ ! -f "${DATA_DIR}/docker-compose.yml" ]; then
        log_error "bob node not installed in ${DATA_DIR}"
        log_info "run '$0 docker-standalone' to install"
        exit 1
    fi
}

cmd_status() {
    check_installed
    echo ""
    log_info "container status:"
    docker compose -f "${DATA_DIR}/docker-compose.yml" ps
    echo ""
    log_info "checking API..."
    local api_response
    api_response=$(curl -sf --max-time 5 "http://localhost:${RPC_PORT}/status" 2>/dev/null) && {
        echo "$api_response" | head -c 500
        echo ""
    } || log_warn "API not responding on port ${RPC_PORT}"
}

cmd_logs() {
    check_installed
    log_info "showing live logs (Ctrl+C to exit)..."
    docker compose -f "${DATA_DIR}/docker-compose.yml" logs -f
}

cmd_stop() {
    check_installed
    log_info "stopping containers..."
    docker compose -f "${DATA_DIR}/docker-compose.yml" stop
    log_ok "containers stopped"
}

cmd_start() {
    check_installed
    log_info "starting containers..."
    docker compose -f "${DATA_DIR}/docker-compose.yml" start
    log_ok "containers started"
}

cmd_restart() {
    check_installed
    log_info "restarting containers..."
    docker compose -f "${DATA_DIR}/docker-compose.yml" restart
    log_ok "containers restarted"
}

cmd_update() {
    check_installed
    log_info "pulling latest images..."
    docker compose -f "${DATA_DIR}/docker-compose.yml" pull
    log_info "restarting containers..."
    docker compose -f "${DATA_DIR}/docker-compose.yml" up -d
    log_ok "update complete"
}

# --- interactive setup ---

interactive_setup() {
    echo ""
    echo -e "${CYAN}Select mode:${NC}"
    echo "  1) docker-standalone   (all-in-one container, recommended)"
    echo "  2) docker-compose      (separate containers)"
    echo "  3) uninstall           (remove bob node)"
    echo "  ─────────────────────────────────────────────"
    echo "  4) status              (show container status)"
    echo "  5) logs                (show live logs)"
    echo "  6) stop                (stop containers)"
    echo "  7) start               (start containers)"
    echo "  8) restart             (restart containers)"
    echo "  9) update              (pull latest + restart)"
    echo ""
    while true; do
        read -rp "Enter choice [1-9]: " choice
        case "$choice" in
            1) MODE="docker-standalone"; break ;;
            2) MODE="docker-compose";    break ;;
            3) MODE="uninstall";         break ;;
            4) MODE="status";            break ;;
            5) MODE="logs";              break ;;
            6) MODE="stop";              break ;;
            7) MODE="start";             break ;;
            8) MODE="restart";           break ;;
            9) MODE="update";            break ;;
            *) echo "  Please enter 1-9." ;;
        esac
    done

    # skip seed/alias prompts for uninstall and management commands
    if [ "$MODE" = "uninstall" ] || [ "$MODE" = "status" ] || [ "$MODE" = "logs" ] || \
       [ "$MODE" = "stop" ] || [ "$MODE" = "start" ] || [ "$MODE" = "restart" ] || [ "$MODE" = "update" ]; then
        return
    fi

    echo ""
    while [ -z "$NODE_SEED" ]; do
        read -rp "Node seed: " NODE_SEED
        [ -z "$NODE_SEED" ] && echo "  Node seed is required."
    done

    while [ -z "$NODE_ALIAS" ]; do
        read -rp "Node alias: " NODE_ALIAS
        [ -z "$NODE_ALIAS" ] && echo "  Node alias is required."
    done

    read -rp "Peers (ip:port, comma-separated, Enter to skip): " PEERS

    echo ""
    read -rp "Max threads (Enter for auto, 0=auto): " input_threads
    if [ -n "$input_threads" ]; then
        MAX_THREADS="$input_threads"
    fi
    echo ""
}

# --- arg parsing ---

parse_args() {
    if [ $# -eq 0 ]; then
        interactive_setup
        return
    fi

    MODE="$1"; shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --peers)       PEERS="$2";       shift 2 ;;
            --threads)     MAX_THREADS="$2"; shift 2 ;;
            --rpc-port)    RPC_PORT="$2";    shift 2 ;;
            --server-port) SERVER_PORT="$2"; shift 2 ;;
            --data-dir)    DATA_DIR="$2";    shift 2 ;;
            --node-seed)   NODE_SEED="$2";     shift 2 ;;
            --node-alias)  NODE_ALIAS="$2";    shift 2 ;;
            --firewall)    FIREWALL_MODE="$2"; shift 2 ;;
            --help|-h)     print_usage;      exit 0  ;;
            *) log_error "unknown option: $1"; print_usage; exit 1 ;;
        esac
    done
}

# --- main ---

main() {
    echo -e "${CYAN}=== qubic bob node installer ===${NC}"
    parse_args "$@"
    check_root

    # handle uninstall separately
    if [ "$MODE" = "uninstall" ]; then
        do_uninstall
        exit 0
    fi

    # handle management commands (no seed/system check needed)
    case "$MODE" in
        status)  cmd_status;  exit 0 ;;
        logs)    cmd_logs;    exit 0 ;;
        stop)    cmd_stop;    exit 0 ;;
        start)   cmd_start;   exit 0 ;;
        restart) cmd_restart; exit 0 ;;
        update)  cmd_update;  exit 0 ;;
    esac

    if [ -n "$FIREWALL_MODE" ] && [ "$FIREWALL_MODE" != "closed" ] && [ "$FIREWALL_MODE" != "open" ]; then
        log_error "unknown firewall mode: ${FIREWALL_MODE} (use: closed | open)"
        exit 1
    fi

    if [ -z "$NODE_SEED" ]; then
        log_error "--node-seed is required. Bob cannot start without a node seed."
        print_usage
        exit 1
    fi

    if [ -z "$NODE_ALIAS" ]; then
        log_error "--node-alias is required. Bob cannot start without a node alias."
        print_usage
        exit 1
    fi

    check_system

    case "$MODE" in
        docker-standalone) install_docker_standalone ;;
        docker-compose)    install_docker_compose ;;
        manual)            install_manual ;;
        *) log_error "unknown mode: ${MODE}"; print_usage; exit 1 ;;
    esac

    setup_firewall

    # copy script to install directory for future management
    if [ -f "$SELF" ] && [ "$SELF" != "${DATA_DIR}/bob-install.sh" ]; then
        cp "$SELF" "${DATA_DIR}/bob-install.sh"
        chmod +x "${DATA_DIR}/bob-install.sh"
        log_ok "script copied to ${DATA_DIR}/bob-install.sh"
        rm -f "$SELF"
    fi
}

main "$@"
