# Network Guard

Setup scripts for running [Bob Node](https://github.com/krypdkat/qubicbob) and [Lite Node](https://github.com/hackerby888/qubic-core-lite) on the Qubic network.

Bob is a blockchain indexer with REST API / JSON-RPC 2.0. Lite Node is a lightweight Qubic Core that runs natively on Linux (no UEFI needed).

## Table of Contents

**Bob Node**

1. [Requirements](#1-requirements)
2. [Quick Start](#2-quick-start)
3. [Docker: Manual Setup](#3-docker-manual-setup)
4. [Configuration](#4-configuration)
5. [Firewall](#5-firewall)
6. [Maintenance](#6-maintenance)
7. [Uninstall](#7-uninstall)
   a. [Docker via install script](#a-docker-via-install-script-section-2)
   b. [Docker via manual setup](#b-docker-via-manual-setup-section-3)
   c. [Firewall reset](#c-firewall-reset)
8. [Troubleshooting](#8-troubleshooting)

**Lite Node**

<ol start="9">
<li><a href="#9-requirements">Requirements</a></li>
<li><a href="#10-quick-start">Quick Start</a></li>
<li><a href="#11-docker-manual-setup">Docker: Manual Setup</a></li>
<li><a href="#12-cli-arguments--config">CLI Arguments & Config</a></li>
<li><a href="#13-rpc-endpoints">RPC Endpoints</a></li>
<li><a href="#14-maintenance">Maintenance</a></li>
<li><a href="#15-uninstall">Uninstall</a></li>
<li><a href="#16-troubleshooting">Troubleshooting</a></li>
</ol>

**General**

<ol start="17">
<li><a href="#17-links">Links</a></li>
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

**Which method should I use?**

| Method | Best for | Difficulty |
|--------|----------|------------|
| **Quick Start** (section 2) | Most users. Script handles everything. | Easy |
| **Docker: Manual Setup** (section 3) | Users who want full control over docker-compose. | Medium |

## 2. Quick Start

Download the installer:

```bash
wget -O bob-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob-install.sh
chmod +x bob-install.sh
```

Pick one of the two modes:

**All-in-one container** (recommended):

```bash
./bob-install.sh docker-standalone --node-seed YOUR_SEED --node-alias YOUR_ALIAS
```

**Separate containers** (bob, keydb, kvrocks each in own container):

```bash
./bob-install.sh docker-compose --node-seed YOUR_SEED --node-alias YOUR_ALIAS --peers 1.2.3.4:21841
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--node-seed <seed>` | **required** | Node identity seed -- Bob will not start without it |
| `--node-alias <alias>` | **required** | Node alias name -- Bob will not start without it |
| `--peers <ip:port,...>` | none | Peers to sync from |
| `--threads <n>` | 0 (auto) | Max threads |
| `--rpc-port <port>` | 40420 | REST API port |
| `--server-port <port>` | 21842 | P2P port |
| `--data-dir <path>` | /opt/qubic-bob | Install directory |
| `--firewall <mode>` | none | Firewall profile: `closed` or `open` |

**Verify:**

```bash
docker compose -f /opt/qubic-bob/docker-compose.yml ps       # container status
docker compose -f /opt/qubic-bob/docker-compose.yml logs -f  # live log output
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

**Step 2** -- Edit `bob.json`. You **must** set `node-seed`, `node-alias`, and `trusted-node` (see section 4 for all options):

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

**Step 2** -- Edit `bob.json`. You **must** set `node-seed`, `node-alias`, and `trusted-node` (see section 4 for all options):

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

## 4. Configuration

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
  "node-seed": "YOUR_SEED_HERE",
  "node-alias": "YOUR_ALIAS_HERE"
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
| `node-alias` | **Required.** Alias name for the node -- Bob will not start without it |

## 5. Firewall

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

## 6. Maintenance

Pick the section that matches how you installed.

**Docker via install script** (section 2):

Update to latest image:

```bash
docker compose -f /opt/qubic-bob/docker-compose.yml pull
docker compose -f /opt/qubic-bob/docker-compose.yml up -d
```

Stop all containers:

```bash
docker compose -f /opt/qubic-bob/docker-compose.yml down
```

Full reset (deletes all data):

```bash
docker compose -f /opt/qubic-bob/docker-compose.yml down
docker volume rm qubic-bob-redis qubic-bob-kvrocks qubic-bob-data
```

**Docker via manual setup** (section 3):

Run the same commands from your install directory (`~/qubic-bob`), or replace the `-f` path accordingly.

## 7. Uninstall

Pick the section that matches how you installed.

### a. Docker via install script (section 2)

```bash
docker compose -f /opt/qubic-bob/docker-compose.yml down -v   # stop containers + delete volumes
rm -rf /opt/qubic-bob                                          # remove install directory
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

### c. Firewall reset

```bash
sudo ufw disable
sudo ufw --force reset
```

## 8. Troubleshooting

| Problem | Solution |
|---------|----------|
| API returns 404 on all endpoints | Endpoints have no `/v1/` prefix - use `/status`, `/tick/1`, `/balance/{id}` |
| API not reachable from outside | Check firewall: `sudo ufw status`. If `closed`, API is blocked by design |
| Container starts but exits immediately | Check logs: `docker compose -f /opt/qubic-bob/docker-compose.yml logs`. Often missing/invalid `bob.json` |
| Node not syncing | Verify `trusted-node` peers in `bob.json`. Peers must be reachable on P2P port |
| KeyDB/KVRocks connection refused | For Docker standalone: uses `127.0.0.1`. For compose: use hostnames `keydb`/`kvrocks` |
| Bob won't start / crashes immediately | Check that `node-seed` is set in `bob.json` -- it is required |
| High CPU usage | Set `max-thread` in `bob.json` to limit worker threads |
| `ufw` blocks SSH after enable | Always allow SSH **before** enabling: `sudo ufw allow 22/tcp` |

---

# Lite Node

> Lightweight Qubic Core - runs on Linux without UEFI. Mainnet (beta) + testnet.

## 9. Requirements

| Component | Testnet | Mainnet |
|-----------|---------|---------|
| RAM | 16 GB | 64 GB |
| CPU | any modern x86_64 | High-freq AVX2/AVX512 (AMD 7950x recommended) |
| Disk | - | 500 GB SSD |
| Network | - | 1 Gbit/s |

## 10. Quick Start

Download the installer:

```bash
wget -O lite-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite-install.sh
chmod +x lite-install.sh
```

Pick a mode:

**Docker -- testnet:**

```bash
./lite-install.sh docker --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --testnet
```

**Docker -- mainnet:**

```bash
./lite-install.sh docker --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --peers 1.2.3.4,5.6.7.8
```

**Manual (systemd) -- testnet:**

```bash
./lite-install.sh manual --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --testnet
```

**Manual (systemd) -- mainnet:**

```bash
./lite-install.sh manual --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --peers 1.2.3.4,5.6.7.8
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--operator-seed <seed>` | **required** | Operator identity seed |
| `--operator-alias <alias>` | **required** | Operator alias name |
| `--peers <ip1,ip2,...>` | none | Peer IPs to connect to |
| `--testnet` | mainnet | Enable testnet mode |
| `--port <port>` | 21841 | P2P port |
| `--http-port <port>` | 41841 | HTTP/RPC port |
| `--data-dir <path>` | /opt/qubic-lite | Install directory |
| `--avx512` | off | Enable AVX-512 support |
| `--security-tick <n>` | 32 | Quorum bypass interval (testnet) |
| `--ticking-delay <n>` | 1000 | Tick processing delay in ms |
| `--no-epoch` | off | Skip automatic epoch data download (mainnet) |

> **Mainnet:** The script automatically downloads the latest epoch data from [storage.qubic.li/network](https://storage.qubic.li/network/). Use `--no-epoch` to skip this step and download manually.

**Verify (Docker):**

```bash
docker compose ps                       # container status
docker logs -f qubic-lite               # live log output
```

**Verify (Manual):**

```bash
systemctl status qubic-lite             # service status
journalctl -u qubic-lite -f             # live log output
```

## 11. Docker: Manual Setup

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
    qubic-lite-node --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --security-tick 32 --ticking-delay 1000
```

Mainnet (mount data dir for epoch files):

```bash
docker run -d --name qubic-lite --restart unless-stopped \
    -p 21841:21841 -p 41841:41841 \
    -v ~/qubic-data:/qubic/data \
    qubic-lite-node --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
```

> Mainnet needs epoch files in the data volume. Download from [storage.qubic.li/network](https://storage.qubic.li/network/) (the Quick Start script does this automatically).

**Step 4** -- Verify:

```bash
docker ps                                # container running?
docker logs -f qubic-lite                # live log output
```

Ports: `21841` (P2P), `41841` (HTTP/RPC)

## 12. CLI Arguments & Config

**Runtime arguments:**

- `--operator-seed <seed>` - operator identity seed (**required**)
- `--operator-alias <alias>` - operator alias name (**required**)
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

## 13. RPC Endpoints

```
http://localhost:41841/live/v1    # live status
http://localhost:41841/           # stats
http://localhost:41841/query/v1   # query API
```

## 14. Maintenance

Pick the section that matches how you installed.

**Docker** (section 10 or 11):

Rebuild and restart:

```bash
docker build -t qubic-lite-node . && docker compose up -d
```

Stop and remove container:

```bash
docker stop qubic-lite && docker rm qubic-lite
```

**Manual / systemd** (section 10, manual mode):

Restart:

```bash
systemctl restart qubic-lite
```

Stop:

```bash
systemctl stop qubic-lite
```

## 15. Uninstall

Pick the section that matches how you installed.

### a. Docker via install script (section 10)

```bash
docker compose -f /opt/qubic-lite/docker-compose.yml down    # stop container
docker rmi qubic-lite-node                                     # remove image
rm -rf /opt/qubic-lite                                         # remove install directory + data
```

### b. Docker via manual setup (section 11)

```bash
docker stop qubic-lite && docker rm qubic-lite                # stop + remove container
docker rmi qubic-lite-node                                     # remove image
rm -rf ~/qubic-data                                            # remove data directory (if used)
```

### c. Manual / systemd (section 10, manual mode)

```bash
systemctl stop qubic-lite                                      # stop service
systemctl disable qubic-lite                                   # disable autostart
rm /etc/systemd/system/qubic-lite.service                      # remove service file
systemctl daemon-reload                                        # reload systemd
rm -rf /opt/qubic-lite                                         # remove install directory + data
```

## 16. Troubleshooting

| Problem | Solution |
|---------|----------|
| Node stops ticking after restart | Delete the `system` file in the working dir |
| Build fails | Check versions: Clang >= 18.1.0, CMake >= 3.14, NASM >= 2.16.03 |
| Mainnet won't sync | Verify epoch files + peer IPs |
| Not enough RAM | Enable `USE_SWAP` before building |
| Docker build fails on AVX | Host CPU needs AVX2, disable AVX-512 if not supported |

---

## 17. Links

- Bob Node: [krypdkat/qubicbob](https://github.com/krypdkat/qubicbob) | [Docker Hub](https://hub.docker.com/r/j0et0m/qubic-bob) | [REST API docs](https://github.com/krypdkat/qubicbob/tree/master/RESTAPI) | [Config docs](https://github.com/krypdkat/qubicbob/blob/master/CONFIG_FILE.MD)
- Lite Node: [hackerby888/qubic-core-lite](https://github.com/hackerby888/qubic-core-lite) | [Linux build guide](https://github.com/hackerby888/qubic-core-lite/blob/main/README_CLANG.md)
- Qubic: [Core repo](https://github.com/qubic/core) | [Node docs](https://docs.qubic.org/learn/nodes/) | [Network dashboard](https://app.qubic.li/network/live)
