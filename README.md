# Network Guard

Setup scripts for running [Bob Node](https://github.com/krypdkat/qubicbob) and [Lite Node](https://github.com/hackerby888/qubic-core-lite) on the Qubic network.

Bob is a blockchain indexer with REST API / JSON-RPC 2.0. Lite Node is a lightweight Qubic Core that runs natively on Linux (no UEFI needed).

## Table of Contents

**Bob Node**

1. [Requirements](#1-requirements)
2. [Quick Start](#2-quick-start)
3. [Docker: Manual Setup](#3-docker-manual-setup)
4. [Build from Source](#4-build-from-source)
5. [Configuration](#5-configuration)
6. [Firewall](#6-firewall)
7. [Maintenance](#7-maintenance)
8. [Uninstall](#8-uninstall)
   a. [Docker via install script](#a-docker-via-install-script-section-2)
   b. [Docker via manual setup](#b-docker-via-manual-setup-section-3)
   c. [Build from source / systemd](#c-build-from-source--systemd-section-4)
   d. [Firewall reset](#d-firewall-reset)
9. [Troubleshooting](#9-troubleshooting)

**Lite Node**

<ol start="10">
<li><a href="#10-requirements">Requirements</a></li>
<li><a href="#11-quick-start">Quick Start</a></li>
<li><a href="#12-docker-manual-setup">Docker: Manual Setup</a></li>
<li><a href="#13-build-from-source">Build from Source</a></li>
<li><a href="#14-cli-arguments--config">CLI Arguments & Config</a></li>
<li><a href="#15-rpc-endpoints">RPC Endpoints</a></li>
<li><a href="#16-maintenance">Maintenance</a></li>
<li><a href="#17-troubleshooting">Troubleshooting</a></li>
</ol>

**General**

<ol start="18">
<li><a href="#18-links">Links</a></li>
</ol>

---

# Bob Node

> BETA - Indexes blockchain data, processes logs, exposes REST + JSON-RPC API.

## 1. Requirements

| Component | Minimum |
|-----------|---------|
| RAM | 16 GB |
| CPU | 4+ cores (AVX2) |
| Disk | 100 GB SSD |
| OS | Ubuntu 24.04 |

**Prerequisites:**

| Method | You need |
|--------|----------|
| Quick Start (section 2) | `wget`, `bash` -- the script installs Docker if missing |
| Docker: Manual Setup (section 3) | [Docker](https://docs.docker.com/engine/install/) + [Docker Compose](https://docs.docker.com/compose/install/) already installed |
| Build from Source (section 4) | `build-essential`, `cmake`, `git` + KeyDB + KVRocks |

**Which method should I use?**

| Method | Best for | Difficulty |
|--------|----------|------------|
| **Quick Start** (section 2) | Most users. Script handles everything. | Easy |
| **Docker: Manual Setup** (section 3) | Users who want full control over docker-compose. | Medium |
| **Build from Source** (section 4) | Advanced users / development. | Advanced |

## 2. Quick Start

```bash
wget -O bob-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob-install.sh
chmod +x bob-install.sh

# pick one:
./bob-install.sh docker-standalone --node-seed YOUR_SEED                              # all-in-one container
./bob-install.sh docker-compose --node-seed YOUR_SEED --peers 1.2.3.4:21841           # separate containers
./bob-install.sh manual --node-seed YOUR_SEED --peers 1.2.3.4:21841 --threads 8      # build from source + systemd
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--node-seed <seed>` | **required** | Node identity seed -- Bob will not start without it |
| `--peers <ip:port,...>` | none | Peers to sync from |
| `--threads <n>` | 0 (auto) | Max threads |
| `--rpc-port <port>` | 40420 | REST API port |
| `--server-port <port>` | 21842 | P2P port |
| `--data-dir <path>` | /opt/qubic-bob | Install directory |
| `--firewall <mode>` | none | Firewall profile: `closed` or `open` |

**Verify:**

If you used `docker-standalone` or `docker-compose`:

```bash
docker compose ps                        # container status
docker compose logs -f                   # live log output
```

If you used `manual`:

```bash
systemctl status qubic-bob
journalctl -u qubic-bob -f              # live log output
```

## 3. Docker: Manual Setup

If you don't want to use the script, pick one of the options below. Copy, paste, done.

**Option A: Standalone** (bob + redis + kvrocks in one container)

**Step 1** -- Create directory and download files:

```bash
mkdir -p ~/qubic-bob && cd ~/qubic-bob
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.standalone.yml
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/bob.json.standalone
mv bob.json.standalone bob.json
```

**Step 2** -- Edit `bob.json`. You **must** set `node-seed` and `trusted-node` (see section 5 for all options):

```bash
nano bob.json
```

**Step 3** -- Mount your config into the container. Open `docker-compose.standalone.yml` and add (or uncomment) this line under `volumes:`:

```bash
nano docker-compose.standalone.yml
```

Add this:

```yaml
    volumes:
      - ./bob.json:/data/bob/bob.json:ro
```

> Without this step, the container ignores your edited `bob.json` and uses its built-in defaults.

**Step 4** -- Start:

```bash
docker compose -f docker-compose.standalone.yml up -d
```

**Step 5** -- Verify:

```bash
docker ps                                # container running?
docker logs -f qubic-bob-standalone      # live log output
```

**Option B: Modular** (separate containers for bob, keydb, kvrocks)

**Step 1** -- Create directory and download files:

```bash
mkdir -p ~/qubic-bob && cd ~/qubic-bob
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.yml
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/bob.json
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/keydb.conf
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/kvrocks.conf
```

**Step 2** -- Edit `bob.json`. You **must** set `node-seed` and `trusted-node` (see section 5 for all options):

```bash
nano bob.json
```

> For Compose use the hostnames `keydb` / `kvrocks` instead of `127.0.0.1` in `keydb-url` and `kvrocks-url`.

**Step 3** -- Start:

```bash
docker compose up -d
```

**Step 4** -- Verify:

```bash
docker compose ps                        # all containers running?
docker compose logs -f                   # live log output
```

Ports: `21842` (P2P), `40420` (REST API)

## 4. Build from Source

**Step 1** -- Install build dependencies:

```bash
sudo apt update && sudo apt install -y build-essential cmake git \
    libjsoncpp-dev uuid-dev libhiredis-dev zlib1g-dev
```

**Step 2** -- Install and start KeyDB (Redis-compatible database):

```bash
echo "deb https://download.keydb.dev/open-source-dist $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/keydb.list
sudo wget -qO - https://download.keydb.dev/open-source-dist/keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/keydb-archive-keyring.gpg
sudo sed -i 's|^deb |deb [signed-by=/usr/share/keyrings/keydb-archive-keyring.gpg] |' /etc/apt/sources.list.d/keydb.list
sudo apt update && sudo apt install -y keydb
sudo systemctl enable --now keydb-server
```

Verify KeyDB is running:

```bash
keydb-cli ping
```

> Expected output: `PONG`

**Step 3** -- Install and start KVRocks (persistent key-value store):

```bash
sudo apt install -y gcc g++ make libsnappy-dev autoconf
git clone --branch v2.9.0 https://github.com/apache/kvrocks.git /tmp/kvrocks
cd /tmp/kvrocks
./x.py build
sudo cp build/kvrocks /usr/local/bin/
```

Create systemd service:

```bash
sudo tee /etc/systemd/system/kvrocks.service > /dev/null <<'EOF'
[Unit]
Description=KVRocks
After=network.target

[Service]
ExecStart=/usr/local/bin/kvrocks -c /etc/kvrocks/kvrocks.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir -p /etc/kvrocks /var/lib/kvrocks
sudo kvrocks --config-dump > /etc/kvrocks/kvrocks.conf 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl enable --now kvrocks
```

Verify KVRocks is running:

```bash
redis-cli -p 6666 ping
```

> Expected output: `PONG`

**Step 4** -- Clone and build Bob:

```bash
git clone https://github.com/krypdkat/qubicbob.git && cd qubicbob
mkdir build && cd build
cmake ../ && make -j$(nproc)
```

**Step 5** -- Create and edit config (you **must** set `node-seed` and `trusted-node`):

```bash
cp ../default_config_bob.json ./config.json
nano config.json
```

**Step 6** -- Download blockchain data (spectrum + universe files):

Bob needs the current blockchain data to start. Download it from [storage.qubic.li/network](https://storage.qubic.li/network/) and place the files in Bob's data directory.

**Step 7** -- Run (in tmux so it survives disconnect):

```bash
tmux new -s bob "./bob ./config.json"
```

> To detach from tmux (leave it running in background): press `Ctrl+B`, then `D`.

**Step 8** -- Verify:

```bash
tmux attach -t bob                       # re-attach to see output

# or if installed via script (systemd):
systemctl status qubic-bob
journalctl -u qubic-bob -f              # live log output
```

## 5. Configuration

`bob.json`:

```json
{
  "p2p-node": [],
  "trusted-node": ["PEER_IP:PORT"],
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
  "node-seed": "YOUR_SEED_HERE"
}
```

When running with Docker Compose, use container hostnames (`keydb`, `kvrocks`) instead of `127.0.0.1`.

| Setting | Description |
|---------|-------------|
| `trusted-node` | Peers to sync from, format `IP:PORT` or `IP:PORT:PASSCODE` |
| `request-cycle-ms` | Polling interval, don't go too low |
| `tick-storage-mode` / `tx-storage-mode` | Use `kvrocks` for persistence |
| `max-thread` | 0 = auto |
| `node-seed` | **Required.** Seed for the node identity -- Bob will not start without it |

## 6. Firewall

The install script can configure `ufw` to lock down the server. Use `--firewall` with a profile:

| Profile | Ports allowed | Use case |
|---------|---------------|----------|
| `closed` | SSH (22) + P2P (21842) | Node syncs with the network, API only reachable locally |
| `open` | SSH (22) + P2P (21842) + API (40420) | API accessible from outside |

```bash
# recommended: closed firewall (API not exposed)
./bob-install.sh docker-standalone --firewall closed

# open: API accessible from outside
./bob-install.sh docker-standalone --firewall open
```

Without `--firewall` no firewall rules are changed.

**Manual ufw setup** (if you didn't use `--firewall`):

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp                # SSH
sudo ufw allow 21842/tcp             # P2P
# sudo ufw allow 40420/tcp           # API (uncomment if needed)
sudo ufw enable
sudo ufw status
```

## 7. Maintenance

Pick the section that matches how you installed.

**Docker** (section 2 or 3):

Update to latest image:

```bash
docker compose pull && docker compose up -d
```

Stop all containers:

```bash
docker compose down
```

Full reset (deletes all data):

```bash
docker compose down && docker volume rm qubic-bob-redis qubic-bob-kvrocks qubic-bob-data
```

**Build from source / systemd** (section 4):

Restart:

```bash
sudo systemctl restart qubic-bob
```

Update source and rebuild:

```bash
cd /opt/qubic-bob/qubicbob && git pull
cd build && cmake ../ && make -j$(nproc)
sudo systemctl restart qubic-bob
```

## 8. Uninstall

Pick the section that matches how you installed.

### a. Docker via install script (section 2)

```bash
cd /opt/qubic-bob
docker compose down -v              # stop containers + delete volumes
```

```bash
rm -rf /opt/qubic-bob               # remove install directory
```

### b. Docker via manual setup (section 3)

If you used **Option A (Standalone)**:

```bash
cd ~/qubic-bob
docker compose -f docker-compose.standalone.yml down -v
```

If you used **Option B (Modular)**:

```bash
cd ~/qubic-bob
docker compose down -v
```

Remove install directory:

```bash
rm -rf ~/qubic-bob
```

### c. Build from source / systemd (section 4)

**Remove Bob service:**

```bash
sudo systemctl stop qubic-bob
sudo systemctl disable qubic-bob
sudo rm /etc/systemd/system/qubic-bob.service
sudo systemctl daemon-reload
```

**Remove KeyDB + KVRocks** (optional):

```bash
sudo systemctl stop keydb-server kvrocks
sudo systemctl disable keydb-server kvrocks
sudo rm -f /etc/systemd/system/kvrocks.service
sudo systemctl daemon-reload
```

**Remove install directory:**

```bash
rm -rf /opt/qubic-bob
```

### d. Firewall reset

```bash
sudo ufw disable
sudo ufw --force reset
```

## 9. Troubleshooting

| Problem | Solution |
|---------|----------|
| API returns 404 on all endpoints | Endpoints have no `/v1/` prefix - use `/status`, `/tick/1`, `/balance/{id}` |
| API not reachable from outside | Check firewall: `sudo ufw status`. If `closed`, API is blocked by design |
| Container starts but exits immediately | Check logs: `docker compose logs`. Often missing/invalid `bob.json` |
| Node not syncing | Verify `trusted-node` peers in `bob.json`. Peers must be reachable on P2P port |
| KeyDB/KVRocks connection refused | For Docker standalone: uses `127.0.0.1`. For compose: use hostnames `keydb`/`kvrocks` |
| Bob won't start / crashes immediately | Check that `node-seed` is set in `bob.json` -- it is required |
| High CPU usage | Set `max-thread` in `bob.json` to limit worker threads |
| `ufw` blocks SSH after enable | Always allow SSH **before** enabling: `sudo ufw allow 22/tcp` |

---

# Lite Node

> Lightweight Qubic Core - runs on Linux without UEFI. Mainnet (beta) + testnet.

## 10. Requirements

| Component | Testnet | Mainnet |
|-----------|---------|---------|
| RAM | 16 GB | 64 GB |
| CPU | any modern x86_64 | High-freq AVX2/AVX512 (AMD 7950x recommended) |
| Disk | - | 500 GB SSD |
| Network | - | 1 Gbit/s |
| Build tools | Clang >= 18.1.0, CMake >= 3.14, NASM >= 2.16.03 | same |

## 11. Quick Start

```bash
wget -O lite-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite-install.sh
chmod +x lite-install.sh

# docker
./lite-install.sh docker --testnet
./lite-install.sh docker --peers 1.2.3.4,5.6.7.8

# source + systemd
./lite-install.sh manual --testnet
./lite-install.sh manual --peers 1.2.3.4,5.6.7.8 --avx512
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--peers <ip1,ip2,...>` | none | Peer IPs to connect to |
| `--testnet` | mainnet | Enable testnet mode |
| `--port <port>` | 21841 | P2P port |
| `--http-port <port>` | 41841 | HTTP/RPC port |
| `--data-dir <path>` | /opt/qubic-lite | Install directory |
| `--avx512` | off | Enable AVX-512 support |
| `--security-tick <n>` | 32 | Quorum bypass interval (testnet) |
| `--ticking-delay <n>` | 1000 | Tick processing delay in ms |

**Verify:**

If you used `docker`:

```bash
docker logs -f qubic-lite               # live log output
```

If you used `manual`:

```bash
systemctl status qubic-lite
journalctl -u qubic-lite -f             # live log output
```

## 12. Docker: Manual Setup

**Step 1** -- Save this Dockerfile (builds from source inside the container):

```dockerfile
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential clang cmake nasm git g++ \
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \
    libstdc++-12-dev libfmt-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN git clone https://github.com/hackerby888/qubic-core-lite.git .
WORKDIR /app/build
RUN cmake .. \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_TESTS=OFF -DBUILD_BINARY=ON \
    -DCMAKE_BUILD_TYPE=Release -DENABLE_AVX512=OFF \
    && cmake --build . -- -j$(nproc)

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \
    libc++1 libc++abi1 libjsoncpp25 libfmt9 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /qubic
COPY --from=builder /app/build/src/Qubic .
EXPOSE 21841 41841
ENTRYPOINT ["./Qubic"]
```

**Step 2** -- Build the image:

```bash
docker build -t qubic-lite-node .
```

**Step 3** -- Run (pick testnet or mainnet):

Testnet:

```bash
docker run -d --name qubic-lite --restart unless-stopped \
    -p 21841:21841 -p 41841:41841 \
    qubic-lite-node --security-tick 32 --ticking-delay 1000
```

Mainnet (mount data dir for epoch files):

```bash
docker run -d --name qubic-lite --restart unless-stopped \
    -p 21841:21841 -p 41841:41841 \
    -v ~/qubic-data:/qubic/data \
    qubic-lite-node --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
```

> Mainnet needs epoch files (`spectrum.XXX`, `universe.XXX`, `contract0000.XXX` ...) in the data volume.

**Step 4** -- Verify:

```bash
docker ps                                # container running?
docker logs -f qubic-lite                # live log output
```

Ports: `21841` (P2P), `41841` (HTTP/RPC)

## 13. Build from Source

**Step 1** -- Install build dependencies:

```bash
sudo apt update && sudo apt install -y build-essential clang cmake nasm git g++ \
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \
    libstdc++-12-dev libfmt-dev
```

**Step 2** -- Clone and build:

```bash
git clone https://github.com/hackerby888/qubic-core-lite.git && cd qubic-core-lite
mkdir -p build && cd build
cmake .. -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_TESTS=OFF -DBUILD_BINARY=ON \
    -DCMAKE_BUILD_TYPE=Release -DENABLE_AVX512=OFF
cmake --build . -- -j$(nproc)
```

**Step 3** -- Run (pick testnet or mainnet):

Testnet:

```bash
./src/Qubic --security-tick 32 --ticking-delay 1000
```

Mainnet:

```bash
./src/Qubic --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
```

**Step 4** -- Verify:

```bash
# systemd (if installed via script):
systemctl status qubic-lite
journalctl -u qubic-lite -f             # live log output
```

> The install script (`lite-install.sh manual`) sets up systemd so the node starts on boot.

## 14. CLI Arguments & Config

**Runtime arguments:**

- `--peers <ip1,ip2>` - connect to specific peers
- `--security-tick <n>` - quorum bypass interval (testnet only)
- `--ticking-delay <n>` - processing delay in ms (testnet only)

**Source-level config** (requires rebuild):

| Setting | File | Description |
|---------|------|-------------|
| `#define TESTNET` | `qubic.cpp` | Comment out for mainnet |
| `USE_SWAP` | `qubic.cpp` | Disk-as-RAM fallback |
| `knownPublicPeers` | `private_settings.h` | Hardcoded peer list |
| `TICK_STORAGE_AUTOSAVE_MODE` | `private_settings.h` | Set `1` for crash recovery |

For mainnet: get active peers from [app.qubic.li/network/live](https://app.qubic.li/network/live), place epoch files in the working directory.

## 15. RPC Endpoints

```
http://localhost:41841/live/v1    # live status
http://localhost:41841/           # stats
http://localhost:41841/query/v1   # query API
```

## 16. Maintenance

Pick the section that matches how you installed.

**Docker** (section 11 or 12):

Rebuild and restart:

```bash
docker build -t qubic-lite-node . && docker compose up -d
```

Stop and remove container:

```bash
docker stop qubic-lite && docker rm qubic-lite
```

**Build from source / systemd** (section 13):

Restart:

```bash
sudo systemctl restart qubic-lite
```

Update source and rebuild:

```bash
cd /opt/qubic-lite/qubic-core-lite && git pull
cd build && cmake .. -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_TESTS=OFF -DBUILD_BINARY=ON -DCMAKE_BUILD_TYPE=Release -DENABLE_AVX512=OFF
cmake --build . -- -j$(nproc)
sudo systemctl restart qubic-lite
```

## 17. Troubleshooting

| Problem | Solution |
|---------|----------|
| Node stops ticking after restart | Delete the `system` file in the working dir |
| Build fails | Check versions: Clang >= 18.1.0, CMake >= 3.14, NASM >= 2.16.03 |
| Mainnet won't sync | Verify epoch files + peer IPs |
| Not enough RAM | Enable `USE_SWAP` before building |
| Docker build fails on AVX | Host CPU needs AVX2, disable AVX-512 if not supported |

---

## 18. Links

- Bob Node: [krypdkat/qubicbob](https://github.com/krypdkat/qubicbob) | [Docker Hub](https://hub.docker.com/r/j0et0m/qubic-bob) | [REST API docs](https://github.com/krypdkat/qubicbob/tree/master/RESTAPI) | [Config docs](https://github.com/krypdkat/qubicbob/blob/master/CONFIG_FILE.MD)
- Lite Node: [hackerby888/qubic-core-lite](https://github.com/hackerby888/qubic-core-lite) | [Linux build guide](https://github.com/hackerby888/qubic-core-lite/blob/main/README_CLANG.md)
- Qubic: [Core repo](https://github.com/qubic/core) | [Node docs](https://docs.qubic.org/learn/nodes/) | [Network dashboard](https://app.qubic.li/network/live)
