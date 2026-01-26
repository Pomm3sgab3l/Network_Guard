# Network Guard - Qubic Node Setup Guide

Installation guides for **Bob Node** and **Lite Node** on the Qubic network.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Bob Node](#2-bob-node)
  - [2.1 System Requirements](#21-system-requirements)
  - [2.2 Quick Install (Script)](#22-quick-install-script)
  - [2.3 Docker Setup (Manual)](#23-docker-setup-manual)
  - [2.4 Build from Source (Manual)](#24-build-from-source-manual)
  - [2.5 Configuration Reference](#25-configuration-reference)
  - [2.6 Maintenance & Troubleshooting](#26-maintenance--troubleshooting)
- [3. Lite Node](#3-lite-node)
  - [3.1 System Requirements](#31-system-requirements)
  - [3.2 Quick Install (Script)](#32-quick-install-script)
  - [3.3 Docker Setup (Manual)](#33-docker-setup-manual)
  - [3.4 Build from Source (Manual)](#34-build-from-source-manual)
  - [3.5 Configuration Reference](#35-configuration-reference)
  - [3.6 Maintenance & Troubleshooting](#36-maintenance--troubleshooting)
- [4. References](#4-references)

---

## 1. Overview

| Node Type | Description | Repository |
|-----------|-------------|------------|
| **Bob Node** | Ultra-lightweight indexer with REST API & JSON-RPC 2.0 for the Qubic network. Archives blockchain data and processes logging events. | [krypdkat/qubicbob](https://github.com/krypdkat/qubicbob) |
| **Lite Node** | Lite version of Qubic Core. Runs directly on the OS without a UEFI environment. Supports mainnet (beta) and local testnet. | [hackerby888/qubic-core-lite](https://github.com/hackerby888/qubic-core-lite) |

---

## 2. Bob Node

> Bob is a **BETA** indexer and logging node for the Qubic blockchain. It archives blockchain data, processes logging events, and provides a REST API / JSON-RPC 2.0 interface.

### 2.1 System Requirements

| Resource | Minimum |
|----------|---------|
| RAM | 16 GB |
| CPU | 4+ cores with AVX2 support |
| Storage | 100 GB fast SSD / NVMe |
| OS | Linux (Ubuntu 24.04 recommended) |
| Software | Docker **or** CMake, Clang/GCC, KeyDB, KVRocks |

### 2.2 Quick Install (Script)

The fastest way to get a Bob Node running. Download the script and choose a mode:

**Option A: Docker Standalone (recommended)**

All-in-one container with Bob + Redis + KVRocks bundled together.

```bash
# update sources
apt update

# download the installation script
wget -O bob-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob-install.sh

# make it executable
chmod u+x bob-install.sh

# install as Docker standalone
./bob-install.sh docker-standalone
```

**Option B: Docker Compose (modular)**

Separate containers for Bob, KeyDB, and KVRocks. More control and scalability.

```bash
wget -O bob-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob-install.sh
chmod u+x bob-install.sh

# install with custom peers
./bob-install.sh docker-compose --peers 1.2.3.4:21841,5.6.7.8:21841
```

**Option C: Build from source with systemd service**

```bash
wget -O bob-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob-install.sh
chmod u+x bob-install.sh

# install from source
./bob-install.sh manual --peers 1.2.3.4:21841 --threads 8
```

**Script Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--peers <ip:port,...>` | Trusted peers to sync from | *(none)* |
| `--threads <n>` | Max threads (0 = auto) | `0` |
| `--rpc-port <port>` | REST API / JSON-RPC port | `40420` |
| `--server-port <port>` | P2P server port | `21842` |
| `--data-dir <path>` | Data directory | `/opt/qubic-bob` |

### 2.3 Docker Setup (Manual)

If you prefer to set up Docker manually without the script:

**Prerequisites:**
```bash
# install Docker if not present
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# log out and back in, or run: newgrp docker
```

#### Standalone (All-in-One)

```bash
mkdir -p ~/qubic-bob && cd ~/qubic-bob

# download example files
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.standalone.yml
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/bob.json.standalone
mv bob.json.standalone bob.json

# edit configuration (add your peers etc.)
nano bob.json

# start
docker compose -f docker-compose.standalone.yml up -d
```

#### Docker Compose (Modular)

```bash
mkdir -p ~/qubic-bob && cd ~/qubic-bob

# download all required files
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.yml
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/bob.json
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/keydb.conf
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/kvrocks.conf

# edit configuration
nano bob.json

# start
docker compose up -d
```

**Exposed Ports:**

| Port | Service |
|------|---------|
| `21842` | P2P / Server |
| `40420` | REST API / JSON-RPC |

### 2.4 Build from Source (Manual)

Step-by-step guide for building Bob Node without Docker:

```bash
# 1. install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential cmake git libjsoncpp-dev \
    uuid-dev libhiredis-dev zlib1g-dev unzip wget net-tools tmux

# 2. clone the repository
git clone https://github.com/krypdkat/qubicbob.git
cd qubicbob

# 3. build
mkdir build && cd build
cmake ../
make -j$(nproc)

# 4. create config from template
cp ../default_config_bob.json ./config.json
nano config.json

# 5. start with tmux (keeps running after disconnect)
tmux new -s bob
./bob ./config.json
# detach: Ctrl+B, then D
# reattach: tmux attach -t bob
```

> **Note:** You also need KeyDB and KVRocks running locally. The installation script (`bob-install.sh manual`) handles this automatically.

### 2.5 Configuration Reference

Example `bob.json`:

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

> **Note:** When using Docker Compose, use container hostnames (`keydb`, `kvrocks`) instead of `127.0.0.1`.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `trusted-node` | Qubic peers to sync from (`IP:PORT` or `IP:PORT:PASSCODE`) | `[]` |
| `p2p-node` | P2P node addresses | `[]` |
| `request-cycle-ms` | Request polling interval in ms (do not set too low!) | `100` |
| `request-logging-cycle-ms` | Logging poll interval in ms | `30` |
| `log-level` | Log verbosity (`info`, `debug`, etc.) | `info` |
| `keydb-url` | KeyDB connection string | `tcp://127.0.0.1:6379` |
| `kvrocks-url` | KVRocks connection (persistent storage) | `tcp://127.0.0.1:6666` |
| `run-server` | Enable listener port | `false` |
| `server-port` | P2P server port | `21842` |
| `rpc-port` | REST API / JSON-RPC port | `40420` |
| `tick-storage-mode` | Storage backend (`kvrocks`, `lastNTick`, `free`) | `lastNTick` |
| `tx-storage-mode` | TX storage backend | `kvrocks` |
| `tx_tick_to_live` | Data retention in ticks | `3000` |
| `max-thread` | Max threads (0 = auto) | `8` |
| `spam-qu-threshold` | Spam filter threshold | `100` |

### 2.6 Maintenance & Troubleshooting

**Docker commands:**
```bash
docker compose ps                              # check status
docker compose logs -f                         # view logs
docker compose restart                         # restart
docker compose down                            # stop
docker compose pull && docker compose up -d    # update to latest image
```

**Systemd commands (manual install):**
```bash
systemctl status qubic-bob                     # check status
journalctl -u qubic-bob -f                     # view logs
systemctl restart qubic-bob                    # restart
systemctl stop qubic-bob                       # stop
```

**Reset databases (Docker):**
```bash
docker compose down
docker volume rm qubic-bob-redis qubic-bob-kvrocks qubic-bob-data
docker compose up -d
```

**Update from source (manual install):**
```bash
cd /opt/qubic-bob/qubicbob
git pull
cd build && cmake ../ && make -j$(nproc)
sudo systemctl restart qubic-bob
```

---

## 3. Lite Node

> The Lite version of Qubic Core runs directly on the operating system without a UEFI environment. Supports mainnet (beta) and local testnet.

### 3.1 System Requirements

**Local Testnet:**

| Resource | Minimum |
|----------|---------|
| RAM | 16 GB |
| CPU | Modern x86_64 processor |
| Storage | Minimal |

**Mainnet (Beta):**

| Resource | Minimum |
|----------|---------|
| RAM | 64 GB |
| CPU | High-frequency with AVX2/AVX512 (e.g., AMD 7950x) |
| Storage | 500 GB fast SSD |
| Network | 1 Gbit/s synchronous |
| Epoch Files | spectrum, universe, contract files (see below) |

### 3.2 Quick Install (Script)

**Option A: Docker**

```bash
# update sources
apt update

# download the installation script
wget -O lite-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite-install.sh

# make it executable
chmod u+x lite-install.sh

# install as Docker container (testnet)
./lite-install.sh docker --testnet

# install as Docker container (mainnet)
./lite-install.sh docker --peers 1.2.3.4,5.6.7.8
```

**Option B: Build from source with systemd service**

```bash
wget -O lite-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite-install.sh
chmod u+x lite-install.sh

# install from source (testnet)
./lite-install.sh manual --testnet

# install from source (mainnet)
./lite-install.sh manual --peers 1.2.3.4,5.6.7.8
```

**Script Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--peers <ip1,ip2,...>` | Peer node IPs to connect to | *(none)* |
| `--testnet` | Enable testnet mode | mainnet |
| `--port <port>` | Node port | `21841` |
| `--data-dir <path>` | Data directory | `/opt/qubic-lite` |
| `--avx512` | Enable AVX-512 support | off |
| `--security-tick <n>` | Quorum bypass interval (testnet only) | `32` |
| `--ticking-delay <n>` | Ticking delay in ms (testnet only) | `1000` |

### 3.3 Docker Setup (Manual)

> **Note:** The official repo does not include Docker files. Below is a custom Dockerfile for building from source.

**Dockerfile:**

```dockerfile
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential clang cmake nasm git \
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \
    g++ libstdc++-12-dev libfmt-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone https://github.com/hackerby888/qubic-core-lite.git .

WORKDIR /app/build
RUN cmake .. \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_TESTS=OFF \
    -DBUILD_BINARY=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_AVX512=OFF \
    && cmake --build . -- -j$(nproc)

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    libc++1 libc++abi1 libjsoncpp25 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /qubic
COPY --from=builder /app/build/src/Qubic .

EXPOSE 21841

ENTRYPOINT ["./Qubic"]
```

**Build and run:**

```bash
mkdir -p ~/qubic-lite && cd ~/qubic-lite

# save the Dockerfile above, then:
docker build -t qubic-lite-node .

# run (testnet)
docker run -d --name qubic-lite --restart unless-stopped \
    -p 21841:21841 \
    qubic-lite-node \
    --security-tick 32 --ticking-delay 1000

# run (mainnet - mount epoch files directory)
docker run -d --name qubic-lite --restart unless-stopped \
    -p 21841:21841 \
    -v ~/qubic-data:/qubic/data \
    qubic-lite-node \
    --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
```

> **Important:** For mainnet, epoch files (`spectrum.XXX`, `universe.XXX`, `contract0000.XXX`, etc.) must be placed in the mounted data volume.

### 3.4 Build from Source (Manual)

Step-by-step guide for building Lite Node without Docker:

```bash
# 1. install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential clang cmake nasm git \
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \
    g++ libstdc++-12-dev libfmt-dev

# 2. clone the repository
git clone https://github.com/hackerby888/qubic-core-lite.git
cd qubic-core-lite

# 3. build
mkdir -p build && cd build
cmake .. \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_TESTS=OFF \
    -DBUILD_BINARY=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_AVX512=OFF
cmake --build . -- -j$(nproc)

# 4a. start (testnet)
./src/Qubic --security-tick 32 --ticking-delay 1000

# 4b. start (mainnet - epoch files required!)
./src/Qubic --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
```

> **Note:** The installation script (`lite-install.sh manual`) sets up a systemd service automatically so the node starts on boot.

### 3.5 Configuration Reference

The Lite Node is configured via **command-line arguments** and **source code settings**.

**Command-Line Arguments:**

| Argument | Description | Example |
|----------|-------------|---------|
| `--security-tick <n>` | Bypass quorum verification every n ticks (testnet) | `--security-tick 32` |
| `--ticking-delay <n>` | Slow down testnet processing by n ms | `--ticking-delay 1000` |
| `--peers <ip1,ip2>` | Specify peer nodes directly | `--peers 1.2.3.4,5.6.7.8` |

**Source Code Settings (before building):**

| Setting | File | Description |
|---------|------|-------------|
| `#define TESTNET` | `qubic.cpp` | Enable testnet mode (comment out for mainnet) |
| `USE_SWAP` | `qubic.cpp` | Use disk as RAM fallback when memory is limited |
| `knownPublicPeers` | `private_settings.h` | Set peer IPs for mainnet |
| `TICK_STORAGE_AUTOSAVE_MODE` | `private_settings.h` | Set to `1` for snapshot persistence |

**Mainnet Preparation Checklist:**

1. Comment out `#define TESTNET` in `qubic.cpp`
2. Add active peer IPs to `knownPublicPeers` in `private_settings.h`
3. Rebuild the project
4. Place epoch files in the working directory:
   - `spectrum.XXX`, `universe.XXX`
   - `contract0000.XXX` through `contractNNNN.XXX`
5. Get current peers from [qubic.li Network Dashboard](https://app.qubic.li/network/live)

### 3.6 Maintenance & Troubleshooting

**Docker commands:**
```bash
docker logs -f qubic-lite                      # view logs
docker restart qubic-lite                      # restart
docker stop qubic-lite                         # stop
docker build -t qubic-lite-node . && \
  docker rm -f qubic-lite && \
  docker run -d --name qubic-lite ...          # rebuild & restart
```

**Systemd commands (manual install):**
```bash
systemctl status qubic-lite                    # check status
journalctl -u qubic-lite -f                    # view logs
systemctl restart qubic-lite                   # restart
systemctl stop qubic-lite                      # stop
```

**Update from source (manual install):**
```bash
cd /opt/qubic-lite/qubic-core-lite
git pull
cd build
cmake .. \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_TESTS=OFF \
    -DBUILD_BINARY=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_AVX512=OFF
cmake --build . -- -j$(nproc)
sudo systemctl restart qubic-lite
```

**Common Issues:**

| Problem | Solution |
|---------|----------|
| Node stops ticking after restart | Delete the `system` file in the working directory |
| Build fails | Verify: Clang >= 18.1.0, CMake >= 3.14, NASM >= 2.16.03 |
| Mainnet won't sync | Check epoch files, update peer IPs |
| Not enough RAM | Enable `USE_SWAP` in source code before building |
| Docker build fails on AVX | Make sure host CPU supports AVX2; disable AVX-512 if unsupported |

---

## 4. References

| Resource | Link |
|----------|------|
| Bob Node Repository | [github.com/krypdkat/qubicbob](https://github.com/krypdkat/qubicbob) |
| Bob Node Docker Hub | [j0et0m/qubic-bob](https://hub.docker.com/r/j0et0m/qubic-bob) |
| Bob Node Config Docs | [CONFIG_FILE.MD](https://github.com/krypdkat/qubicbob/blob/master/CONFIG_FILE.MD) |
| Bob Node REST API Docs | [RESTAPI/](https://github.com/krypdkat/qubicbob/tree/master/RESTAPI) |
| Bob Node Docker Docs | [docker/](https://github.com/krypdkat/qubicbob/tree/master/docker) |
| Lite Node Repository | [github.com/hackerby888/qubic-core-lite](https://github.com/hackerby888/qubic-core-lite) |
| Lite Node Linux Build Guide | [README_CLANG.md](https://github.com/hackerby888/qubic-core-lite/blob/main/README_CLANG.md) |
| Qubic Core (Full Node) | [github.com/qubic/core](https://github.com/qubic/core) |
| Qubic Node Types | [docs.qubic.org/learn/nodes](https://docs.qubic.org/learn/nodes/) |
| Qubic Network Dashboard | [app.qubic.li/network/live](https://app.qubic.li/network/live) |
| Example Docs (qubic-li/client) | [github.com/qubic-li/client](https://github.com/qubic-li/client) |
