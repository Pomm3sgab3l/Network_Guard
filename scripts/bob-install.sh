#!/bin/bash
# bob-install.sh - Qubic Bob Node installer
#
# Usage: ./bob-install.sh <mode> [options]
#
# Modes:
#   docker-standalone   all-in-one container (bob + redis + kvrocks)
#   docker-compose      modular setup (separate containers)
#   manual              build from source + systemd
#
# Options:
#   --peers <ip:port,...>   peers to sync from
#   --threads <n>           max threads (0=auto)
#   --rpc-port <port>       REST API port (default: 40420)
#   --server-port <port>    P2P port (default: 21842)
#   --data-dir <path>       install dir (default: /opt/qubic-bob)
#   --node-seed <seed>      node identity seed (required)
#   --node-alias <alias>    node alias name (required)
#   --firewall <mode>       firewall profile: closed | open

set -e

# resolve own path before any cd changes the working directory
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# defaults
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
FIREWALL_MODE=""
NODE_SEED=""
NODE_ALIAS=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }

print_usage() {
    echo "Usage: $0 <mode> [options]"
    echo ""
    echo "Modes:"
    echo "  docker-standalone   all-in-one container (recommended)"
    echo "  docker-compose      modular (separate containers)"
    echo "  manual              build from source + systemd"
    echo ""
    echo "Options:"
    echo "  --peers <ip:port,...>   peers to sync from"
    echo "  --threads <n>          max threads (0=auto)"
    echo "  --rpc-port <port>      REST API port (default: 40420)"
    echo "  --server-port <port>   P2P port (default: 21842)"
    echo "  --data-dir <path>      install dir (default: /opt/qubic-bob)"
    echo "  --node-seed <seed>     node identity seed (REQUIRED)"
    echo "  --node-alias <alias>   node alias name (REQUIRED)"
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

# --- config generation ---

generate_config() {
    local keydb_host="$1" kvrocks_host="$2" config_path="$3"

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
    mkdir -p "${DATA_DIR}" && cd "${DATA_DIR}"

    generate_config "127.0.0.1" "127.0.0.1" "${DATA_DIR}/bob.json"

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
  qubic-bob-kvrocks:
  qubic-bob-data:
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
    mkdir -p "${DATA_DIR}" && cd "${DATA_DIR}"

    generate_config "keydb" "kvrocks" "${DATA_DIR}/bob.json"

    log_info "downloading keydb/kvrocks configs..."
    curl -sSfL -o "${DATA_DIR}/keydb.conf" \
        "https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/keydb.conf"
    curl -sSfL -o "${DATA_DIR}/kvrocks.conf" \
        "https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/kvrocks.conf"

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
      - bobnet

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
      - bobnet

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
      - bobnet

networks:
  bobnet:

volumes:
  qubic-bob-data:
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
    create_bob_service

    log_ok "done!"
    print_status_manual
}

# --- component installers ---

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
    echo "  docker compose ps       # status"
    echo "  docker compose logs -f  # logs"
    echo "  docker compose restart  # restart"
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

# --- arg parsing ---

parse_args() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
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

    # self-cleanup: remove installer script after successful run
    if [ -f "$SELF" ]; then
        rm -f "$SELF"
        log_ok "installer removed (${SELF})"
    fi
}

main "$@"
