#!/bin/bash
#
# Bob Node Installer - Simple Docker-based setup
# https://github.com/qubic/core-bob
#
# Usage:
#   Interactive:  ./bob.sh
#   CLI:          ./bob.sh install --seed <seed> --alias <alias>
#
# Commands:
#   install       Install and start Bob node
#   uninstall     Remove Bob node
#   status        Show container status
#   logs          Show live logs
#   stop          Stop container
#   start         Start container
#   restart       Restart container
#   update        Pull latest image and restart
#

set -e

# --- Config ---
DOCKER_IMAGE="qubiccore/bob"
CONTAINER_NAME="qubic-bob"
DATA_DIR="/opt/qubic-bob"
PEERS_API="https://api.qubic.global/random-peers?service=bobNode&litePeers=6"

# Default ports
P2P_PORT=21842
API_PORT=40420

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[-]${NC} $1"; }

# --- Functions ---

print_usage() {
    echo "Bob Node Installer"
    echo ""
    echo "Usage:"
    echo "  Interactive:  $0"
    echo "  CLI:          $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  install       Install and start Bob node"
    echo "  uninstall     Remove Bob node and data"
    echo "  status        Show container status"
    echo "  logs          Show live logs (Ctrl+C to exit)"
    echo "  stop          Stop container"
    echo "  start         Start container"
    echo "  restart       Restart container"
    echo "  update        Pull latest image and restart"
    echo ""
    echo "Install options:"
    echo "  --seed <seed>       Node seed (55 lowercase letters) [REQUIRED]"
    echo "  --alias <alias>     Node alias name [REQUIRED]"
    echo "  --p2p-port <port>   P2P port (default: 21842)"
    echo "  --api-port <port>   API port (default: 40420)"
    echo "  --data-dir <path>   Data directory (default: /opt/qubic-bob)"
    echo ""
    echo "Examples:"
    echo "  $0 install --seed abcde...xyz --alias mynode"
    echo "  $0 logs"
    echo "  $0 update"
}

print_security_warning() {
    echo ""
    log_warn "SECURITY TIP: To prevent your seed from being saved in shell history:"
    echo "      - Add a SPACE before the command:  ' ./bob.sh install ...'"
    echo "      - Or use interactive mode:  ./bob.sh"
    echo "      - Or set: export HISTCONTROL=ignorespace"
    echo ""
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first:"
        echo ""
        echo "  curl -fsSL https://get.docker.com | sh"
        echo ""
        exit 1
    fi
    log_ok "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
}

container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

# Fetch peers from qubic.global with retry logic
fetch_peers() {
    local max_retries=5
    local retry_delay=10
    local attempt=1

    PEER_LIST=""

    while [ $attempt -le $max_retries ]; do
        log_info "Fetching peers from qubic.global (attempt ${attempt}/${max_retries})..."

        # Try to fetch peers
        local response
        response=$(curl -s --max-time 15 "$PEERS_API" 2>/dev/null)

        if [ -n "$response" ]; then
            # Extract IPs from JSON response
            local peers
            peers=$(echo "$response" | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | head -6)

            if [ -n "$peers" ]; then
                # Format as JSON array with port
                PEER_LIST=""
                while IFS= read -r ip; do
                    [ -n "$PEER_LIST" ] && PEER_LIST="${PEER_LIST},"
                    PEER_LIST="${PEER_LIST}\"${ip}:21841\""
                done <<< "$peers"

                local peer_count
                peer_count=$(echo "$peers" | wc -l)
                log_ok "Got ${peer_count} peers"
                return 0
            fi
        fi

        if [ $attempt -lt $max_retries ]; then
            log_warn "Failed to fetch peers, retrying in ${retry_delay}s..."
            sleep $retry_delay
        fi

        attempt=$((attempt + 1))
    done

    log_warn "Could not fetch peers - node will try to discover them automatically"
    return 1
}

generate_config() {
    local config_file="${DATA_DIR}/bob.json"
    log_info "Generating config..."

    # Use fetched peers or empty array
    local peer_json="[]"
    if [ -n "$PEER_LIST" ]; then
        peer_json="[${PEER_LIST}]"
    fi

    cat > "$config_file" <<EOF
{
  "p2p-node": ${peer_json},
  "request-cycle-ms": 100,
  "request-logging-cycle-ms": 30,
  "future-offset": 3,
  "log-level": "info",
  "keydb-url": "tcp://127.0.0.1:6379",
  "run-server": true,
  "server-port": 21842,
  "rpc-port": 40420,
  "arbitrator-identity": "AFZPUAIYVPNUYGJRQVLUKOPPVLHAZQTGLYAAUUNBXFTVTAMSBKQBLEIEPCVJ",
  "tick-storage-mode": "kvrocks",
  "kvrocks-url": "tcp://127.0.0.1:6666",
  "tx-storage-mode": "kvrocks",
  "tx_tick_to_live": 10000,
  "max-thread": 0,
  "spam-qu-threshold": 100,
  "node-seed": "${NODE_SEED}",
  "node-alias": "${NODE_ALIAS}"
}
EOF
    log_ok "Config: ${config_file}"
}

# Update peers in existing config file
update_peers_in_config() {
    local config_file="${DATA_DIR}/bob.json"

    if [ -z "$PEER_LIST" ]; then
        return
    fi

    if [ ! -f "$config_file" ]; then
        return
    fi

    # Update p2p-node in config using sed
    local peer_json="[${PEER_LIST}]"
    sed -i "s|\"p2p-node\": \[.*\]|\"p2p-node\": ${peer_json}|" "$config_file"
    log_ok "Updated peers in config"
}

do_install() {
    log_info "Installing Bob node..."

    check_docker

    # Validate inputs
    if [ -z "$NODE_SEED" ]; then
        log_error "--seed is required"
        exit 1
    fi

    if [ ${#NODE_SEED} -ne 55 ]; then
        log_warn "Seed should be 55 characters (got ${#NODE_SEED})"
    fi

    if [ -z "$NODE_ALIAS" ]; then
        log_error "--alias is required"
        exit 1
    fi

    # Stop existing container if running
    if container_exists; then
        log_info "Removing existing container..."
        docker rm -f "$CONTAINER_NAME" &>/dev/null || true
    fi

    # Create data directory and copy script
    mkdir -p "${DATA_DIR}/data"

    # Copy this script to DATA_DIR for easy access
    SCRIPT_PATH="${DATA_DIR}/bob.sh"
    cp "$0" "$SCRIPT_PATH" 2>/dev/null || true
    chmod +x "$SCRIPT_PATH" 2>/dev/null || true

    # Fetch peers from qubic.global (with retry)
    fetch_peers

    # Generate config file with seed, alias, and peers
    generate_config

    # Start container
    log_info "Starting container..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "${P2P_PORT}:21842" \
        -p "${API_PORT}:40420" \
        -v "${DATA_DIR}/bob.json:/app/bob.json:ro" \
        -v "${DATA_DIR}/data:/data" \
        "$DOCKER_IMAGE":latest

    log_ok "Bob node started!"
    echo ""
    echo "  Container:  $CONTAINER_NAME"
    echo "  Data:       ${DATA_DIR}/data"
    echo "  P2P:        port ${P2P_PORT}"
    echo "  API:        http://localhost:${API_PORT}"
    echo ""
    echo "  View logs:  ${SCRIPT_PATH} logs"
    echo "  Status:     ${SCRIPT_PATH} status"
    echo "  Update:     ${SCRIPT_PATH} update"
}

do_uninstall() {
    log_info "Uninstalling Bob node..."

    if container_exists; then
        docker rm -f "$CONTAINER_NAME" &>/dev/null
        log_ok "Container removed"
    else
        log_info "Container not found"
    fi

    # Ask before removing data
    if [ -d "$DATA_DIR" ]; then
        echo ""
        read -rp "Remove data directory ${DATA_DIR}? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$DATA_DIR"
            log_ok "Data removed"
        else
            log_info "Data kept at ${DATA_DIR}"
        fi
    fi

    # Remove docker volume if exists
    docker volume rm qubic-bob-data &>/dev/null || true

    log_ok "Uninstall complete"
}

do_status() {
    if container_running; then
        log_ok "Bob node is running"
        echo ""
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    elif container_exists; then
        log_warn "Bob node is stopped"
        docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}"
    else
        log_info "Bob node is not installed"
    fi
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

    # Check config file exists
    if [ ! -f "${DATA_DIR}/bob.json" ]; then
        log_error "Config file not found. Run: $0 install"
        exit 1
    fi

    # Fetch fresh peers and update config
    fetch_peers
    update_peers_in_config

    # Remove old container if exists
    docker rm -f "$CONTAINER_NAME" &>/dev/null || true

    # Start fresh container
    log_info "Starting container..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "${P2P_PORT}:21842" \
        -p "${API_PORT}:40420" \
        -v "${DATA_DIR}/bob.json:/app/bob.json:ro" \
        -v "${DATA_DIR}/data:/data" \
        "$DOCKER_IMAGE":latest

    log_ok "Started"
}

do_restart() {
    if ! container_exists && [ ! -f "${DATA_DIR}/bob.json" ]; then
        log_error "Container not found. Run: $0 install"
        exit 1
    fi

    # Fetch fresh peers and update config
    fetch_peers
    update_peers_in_config

    log_info "Restarting..."
    docker rm -f "$CONTAINER_NAME" &>/dev/null || true

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "${P2P_PORT}:21842" \
        -p "${API_PORT}:40420" \
        -v "${DATA_DIR}/bob.json:/app/bob.json:ro" \
        -v "${DATA_DIR}/data:/data" \
        "$DOCKER_IMAGE":latest

    log_ok "Restarted"
}

do_update() {
    log_info "Updating Bob node..."

    if ! container_exists; then
        log_error "Container not found"
        exit 1
    fi

    # Check config file exists
    if [ ! -f "${DATA_DIR}/bob.json" ]; then
        log_error "Config file not found at ${DATA_DIR}/bob.json. Please reinstall."
        exit 1
    fi

    # Pull latest image
    log_info "Pulling latest image..."
    docker pull "$DOCKER_IMAGE":latest

    # Fetch fresh peers and update config
    fetch_peers
    update_peers_in_config

    # Recreate container
    docker rm -f "$CONTAINER_NAME"

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "${P2P_PORT}:21842" \
        -p "${API_PORT}:40420" \
        -v "${DATA_DIR}/bob.json:/app/bob.json:ro" \
        -v "${DATA_DIR}/data:/data" \
        "$DOCKER_IMAGE":latest

    log_ok "Updated to latest version"
}

interactive_install() {
    echo ""
    echo "=== Bob Node Installer ==="
    echo ""

    print_security_warning

    # Get seed
    while [ -z "$NODE_SEED" ]; do
        read -rp "Node seed (55 characters): " NODE_SEED
        if [ -z "$NODE_SEED" ]; then
            echo "  Seed is required."
        elif [ ${#NODE_SEED} -ne 55 ]; then
            log_warn "Seed should be 55 characters (got ${#NODE_SEED})"
            read -rp "  Continue anyway? [y/N] " confirm
            [[ ! "$confirm" =~ ^[Yy]$ ]] && NODE_SEED=""
        fi
    done

    # Get alias
    while [ -z "$NODE_ALIAS" ]; do
        read -rp "Node alias: " NODE_ALIAS
        [ -z "$NODE_ALIAS" ] && echo "  Alias is required."
    done

    echo ""
    do_install
}

interactive_menu() {
    echo ""
    echo "=== Bob Node ==="
    echo ""
    echo "  1) install     Install Bob node"
    echo "  2) uninstall   Remove Bob node"
    echo "  3) status      Show status"
    echo "  4) logs        Show logs"
    echo "  5) stop        Stop node"
    echo "  6) start       Start node"
    echo "  7) restart     Restart node"
    echo "  8) update      Update to latest"
    echo ""
    read -rp "Choice [1-8]: " choice

    case "$choice" in
        1) interactive_install ;;
        2) do_uninstall ;;
        3) do_status ;;
        4) do_logs ;;
        5) do_stop ;;
        6) do_start ;;
        7) do_restart ;;
        8) do_update ;;
        *) log_error "Invalid choice"; exit 1 ;;
    esac
}

# --- Main ---

NODE_SEED=""
NODE_ALIAS=""

# Parse arguments
if [ $# -eq 0 ]; then
    interactive_menu
    exit 0
fi

COMMAND="$1"
shift

while [ $# -gt 0 ]; do
    case "$1" in
        --seed)      NODE_SEED="$2"; shift 2 ;;
        --alias)     NODE_ALIAS="$2"; shift 2 ;;
        --p2p-port)  P2P_PORT="$2"; shift 2 ;;
        --api-port)  API_PORT="$2"; shift 2 ;;
        --data-dir)  DATA_DIR="$2"; shift 2 ;;
        --help|-h)   print_usage; exit 0 ;;
        *)           log_error "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

case "$COMMAND" in
    install)    do_install ;;
    uninstall)  do_uninstall ;;
    status)     do_status ;;
    logs)       do_logs ;;
    stop)       do_stop ;;
    start)      do_start ;;
    restart)    do_restart ;;
    update)     do_update ;;
    help|--help|-h) print_usage ;;
    *)          log_error "Unknown command: $COMMAND"; print_usage; exit 1 ;;
esac
