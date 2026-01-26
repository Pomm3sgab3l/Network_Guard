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
9. [Troubleshooting](#9-troubleshooting)

**Lite Node**
10. [Requirements](#10-requirements)
11. [Quick Start](#11-quick-start)
12. [Docker: Manual Setup](#12-docker-manual-setup)
13. [Build from Source](#13-build-from-source)
14. [CLI Arguments & Config](#14-cli-arguments--config)
15. [RPC Endpoints](#15-rpc-endpoints)
16. [Maintenance](#16-maintenance)
17. [Troubleshooting](#17-troubleshooting)

**General**
18. [Links](#18-links)

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

## 2. Quick Start

```bash
wget -O bob-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob-install.sh
chmod +x bob-install.sh

# pick one:
./bob-install.sh docker-standalone                              # all-in-one container
./bob-install.sh docker-compose --peers 1.2.3.4:21841           # separate containers
./bob-install.sh manual --peers 1.2.3.4:21841 --threads 8      # build from source + systemd
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--peers <ip:port,...>` | none | Peers to sync from |
| `--threads <n>` | 0 (auto) | Max threads |
| `--rpc-port <port>` | 40420 | REST API port |
| `--server-port <port>` | 21842 | P2P port |
| `--data-dir <path>` | /opt/qubic-bob | Install directory |
| `--firewall <mode>` | none | Firewall profile: `closed` or `open` |

## 3. Docker: Manual Setup

If you don't want to use the script, grab the files from the upstream repo directly:

```bash
mkdir -p ~/qubic-bob && cd ~/qubic-bob

# standalone (bob + redis + kvrocks in one container)
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.standalone.yml
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/bob.json.standalone
mv bob.json.standalone bob.json
nano bob.json                           # add your peers
docker compose -f docker-compose.standalone.yml up -d

# --- OR modular (separate containers) ---
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.yml
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/bob.json
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/keydb.conf
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/kvrocks.conf
nano bob.json
docker compose up -d
```

Ports: `21842` (P2P), `40420` (REST API)

## 4. Build from Source

```bash
sudo apt update && sudo apt install -y build-essential cmake git \
    libjsoncpp-dev uuid-dev libhiredis-dev zlib1g-dev

git clone https://github.com/krypdkat/qubicbob.git && cd qubicbob
mkdir build && cd build
cmake ../ && make -j$(nproc)

cp ../default_config_bob.json ./config.json
nano config.json        # set trusted-node, keydb-url, kvrocks-url etc.

# run in tmux so it survives disconnect
tmux new -s bob "./bob ./config.json"
```

You also need KeyDB and KVRocks running - see [KeyDB install](https://github.com/krypdkat/qubicbob/blob/master/KEYDB_INSTALL.md) / [KVRocks install](https://github.com/krypdkat/qubicbob/blob/master/KVROCKS_INSTALL.MD). The install script (`bob-install.sh manual`) handles this automatically.

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
  "spam-qu-threshold": 100
}
```

When running with Docker Compose, use container hostnames (`keydb`, `kvrocks`) instead of `127.0.0.1`.

| Setting | Description |
|---------|-------------|
| `trusted-node` | Peers to sync from, format `IP:PORT` or `IP:PORT:PASSCODE` |
| `request-cycle-ms` | Polling interval, don't go too low |
| `tick-storage-mode` / `tx-storage-mode` | Use `kvrocks` for persistence |
| `max-thread` | 0 = auto |

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

```bash
# docker
docker compose ps                                       # status
docker compose logs -f                                  # logs
docker compose pull && docker compose up -d             # update
docker compose down                                     # stop
docker compose down && docker volume rm qubic-bob-redis qubic-bob-kvrocks qubic-bob-data  # reset

# systemd (manual install)
systemctl status qubic-bob
journalctl -u qubic-bob -f
systemctl restart qubic-bob

# update from source
cd /opt/qubic-bob/qubicbob && git pull
cd build && cmake ../ && make -j$(nproc)
sudo systemctl restart qubic-bob
```

## 8. Uninstall

### a. Docker (standalone / compose)

```bash
cd /opt/qubic-bob
docker compose down -v              # stop containers + delete volumes
cd / && rm -rf /opt/qubic-bob       # remove install directory
```

### b. Manual (systemd)

```bash
sudo systemctl stop qubic-bob
sudo systemctl disable qubic-bob
sudo rm /etc/systemd/system/qubic-bob.service
sudo systemctl daemon-reload

# optional: remove keydb + kvrocks
sudo systemctl stop keydb-server kvrocks
sudo systemctl disable keydb-server kvrocks
sudo rm -f /etc/systemd/system/kvrocks.service
sudo systemctl daemon-reload

rm -rf /opt/qubic-bob               # remove install directory
```

### c. Firewall reset

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

## 12. Docker: Manual Setup

Dockerfile for building from source:

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

```bash
docker build -t qubic-lite-node .

# testnet
docker run -d --name qubic-lite --restart unless-stopped \
    -p 21841:21841 -p 41841:41841 \
    qubic-lite-node --security-tick 32 --ticking-delay 1000

# mainnet (mount data dir for epoch files)
docker run -d --name qubic-lite --restart unless-stopped \
    -p 21841:21841 -p 41841:41841 \
    -v ~/qubic-data:/qubic/data \
    qubic-lite-node --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
```

Ports: `21841` (P2P), `41841` (HTTP/RPC)

Mainnet needs epoch files (`spectrum.XXX`, `universe.XXX`, `contract0000.XXX` ...) in the data volume.

## 13. Build from Source

```bash
sudo apt update && sudo apt install -y build-essential clang cmake nasm git g++ \
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \
    libstdc++-12-dev libfmt-dev

git clone https://github.com/hackerby888/qubic-core-lite.git && cd qubic-core-lite
mkdir -p build && cd build
cmake .. -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_TESTS=OFF -DBUILD_BINARY=ON \
    -DCMAKE_BUILD_TYPE=Release -DENABLE_AVX512=OFF
cmake --build . -- -j$(nproc)

# testnet
./src/Qubic --security-tick 32 --ticking-delay 1000

# mainnet
./src/Qubic --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
```

The install script (`lite-install.sh manual`) sets up systemd so the node starts on boot.

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

```bash
# docker
docker compose ps / logs -f / restart / down
docker build -t qubic-lite-node . && docker compose up -d   # rebuild

# systemd (manual install)
systemctl status qubic-lite
journalctl -u qubic-lite -f
systemctl restart qubic-lite

# update from source
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
