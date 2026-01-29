# Network Guard

Setup scripts for running [Bob Node](https://github.com/krypdkat/qubicbob) and [Lite Node](https://github.com/hackerby888/qubic-core-lite) on the Qubic network.

Bob is a blockchain indexer with REST API / JSON-RPC 2.0. Lite Node is a lightweight Qubic Core that runs natively on Linux (no UEFI needed).

## Table of Contents

**Bob Node**

1. [Requirements](#1-requirements)
2. [Quick Start](#2-quick-start)
3. [Configuration](#3-configuration)
4. [Firewall](#4-firewall)
5. [Maintenance](#5-maintenance)
6. [Uninstall](#6-uninstall)
   a. [Docker via install script](#a-docker-via-install-script-section-2)
   b. [Firewall reset](#b-firewall-reset)
7. [Troubleshooting](#7-troubleshooting)

**Lite Node**

<ol start="8">
<li><a href="#8-requirements">Requirements</a></li>
<li><a href="#9-quick-start">Quick Start</a></li>
<li><a href="#10-cli-arguments--config">CLI Arguments & Config</a></li>
<li><a href="#11-rpc-endpoints">RPC Endpoints</a></li>
<li><a href="#12-maintenance">Maintenance</a></li>
<li><a href="#13-uninstall">Uninstall</a></li>
<li><a href="#14-troubleshooting">Troubleshooting</a></li>
</ol>

**General**

<ol start="15">
<li><a href="#15-links">Links</a></li>
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

## 2. Quick Start

Download and run the installer:

```bash
wget -O bob-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob-install.sh
chmod +x bob-install.sh && ./bob-install.sh
```

The script will prompt you for:
- Mode (docker-standalone, docker-compose, or uninstall)
- Node seed (for install)
- Node alias (for install)
- Peers (optional, for install)

**Alternative: CLI mode**

You can also pass all options directly:

```bash
# All-in-one container (recommended)
./bob-install.sh docker-standalone --node-seed YOUR_SEED --node-alias YOUR_ALIAS

# Separate containers
./bob-install.sh docker-compose --node-seed YOUR_SEED --node-alias YOUR_ALIAS --peers 1.2.3.4:21841

# Uninstall
./bob-install.sh uninstall
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
/opt/qubic-bob/bob-install.sh status   # container status
/opt/qubic-bob/bob-install.sh logs     # live log output
```

## 3. Configuration

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

## 4. Firewall

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

## 5. Maintenance

After installation, use the script in `/opt/qubic-bob/` for management:

```bash
/opt/qubic-bob/bob-install.sh status    # show container status
/opt/qubic-bob/bob-install.sh logs      # show live logs (Ctrl+C to exit)
/opt/qubic-bob/bob-install.sh stop      # stop containers
/opt/qubic-bob/bob-install.sh start     # start containers
/opt/qubic-bob/bob-install.sh restart   # restart containers
/opt/qubic-bob/bob-install.sh update    # pull latest image + restart
```

**Full reset (deletes all data):**

```bash
/opt/qubic-bob/bob-install.sh stop
docker volume rm qubic-bob-redis qubic-bob-kvrocks qubic-bob-data
/opt/qubic-bob/bob-install.sh start
```

## 6. Uninstall

Pick the section that matches how you installed.

### a. Docker via install script (section 2)

```bash
docker compose -f /opt/qubic-bob/docker-compose.yml down -v   # stop containers + delete volumes
rm -rf /opt/qubic-bob                                          # remove install directory
```

### b. Firewall reset

```bash
sudo ufw disable
sudo ufw --force reset
```

## 7. Troubleshooting

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

## 8. Requirements

| Component | Testnet | Mainnet |
|-----------|---------|---------|
| RAM | 16 GB | 64 GB |
| CPU | any modern x86_64 | High-freq AVX2/AVX512 (AMD 7950x recommended) |
| Disk | - | 500 GB SSD |
| Network | - | 1 Gbit/s |

## 9. Quick Start

Download and run the installer:

```bash
wget -O lite-install.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite-install.sh
chmod +x lite-install.sh && ./lite-install.sh
```

The script will prompt you for:
- Mode (docker, manual, or uninstall)
- Network (mainnet or testnet)
- Operator seed (for install)
- Operator alias (for install)
- Peers (optional, for install)

**Alternative: CLI mode**

You can also pass all options directly:

```bash
# Docker -- testnet
./lite-install.sh docker --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --testnet

# Docker -- mainnet
./lite-install.sh docker --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --peers 1.2.3.4,5.6.7.8

# Manual (systemd) -- testnet
./lite-install.sh manual --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --testnet

# Manual (systemd) -- mainnet
./lite-install.sh manual --operator-seed YOUR_SEED --operator-alias YOUR_ALIAS --peers 1.2.3.4,5.6.7.8

# Uninstall
./lite-install.sh uninstall
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
| `--epoch <N>` | auto-detect | Build for specific epoch (checks out matching source + downloads data) |
| `--no-epoch` | off | Skip automatic epoch data download (mainnet) |

> **Mainnet:** The script auto-detects the current epoch from [storage.qubic.li/network](https://storage.qubic.li/network/), checks out the matching source version, and downloads the epoch data. Use `--epoch <N>` to target a specific epoch, or `--no-epoch` to skip the data download (if you already have the files).

**Verify:**

```bash
/opt/qubic-lite/lite-install.sh status   # container/service status
/opt/qubic-lite/lite-install.sh logs     # live log output
```

## 10. CLI Arguments & Config

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

## 11. RPC Endpoints

```
http://localhost:41841/live/v1    # live status
http://localhost:41841/           # stats
http://localhost:41841/query/v1   # query API
```

## 12. Maintenance

After installation, use the script in `/opt/qubic-lite/` for management:

```bash
/opt/qubic-lite/lite-install.sh status    # show status
/opt/qubic-lite/lite-install.sh logs      # show live logs (Ctrl+C to exit)
/opt/qubic-lite/lite-install.sh stop      # stop node
/opt/qubic-lite/lite-install.sh start     # start node
/opt/qubic-lite/lite-install.sh restart   # restart node
/opt/qubic-lite/lite-install.sh update    # rebuild + restart (docker only)
```

These commands work for both Docker and manual (systemd) installations.

## 13. Uninstall

Pick the section that matches how you installed.

### a. Docker via install script (section 9)

```bash
docker compose -f /opt/qubic-lite/docker-compose.yml down    # stop container
docker rmi qubic-lite-node                                     # remove image
rm -rf /opt/qubic-lite                                         # remove install directory + data
```

### b. Manual / systemd (section 9, manual mode)

```bash
systemctl stop qubic-lite                                      # stop service
systemctl disable qubic-lite                                   # disable autostart
rm /etc/systemd/system/qubic-lite.service                      # remove service file
systemctl daemon-reload                                        # reload systemd
rm -rf /opt/qubic-lite                                         # remove install directory + data
```

## 14. Troubleshooting

| Problem | Solution |
|---------|----------|
| Node stops ticking after restart | Delete the `system` file in the working dir |
| Build fails | Check versions: Clang >= 18.1.0, CMake >= 3.14, NASM >= 2.16.03 |
| Mainnet won't sync | Verify epoch files + peer IPs |
| Not enough RAM | Enable `USE_SWAP` before building |
| Docker build fails on AVX | Host CPU needs AVX2, disable AVX-512 if not supported |

---

## 15. Links

- Bob Node: [krypdkat/qubicbob](https://github.com/krypdkat/qubicbob) | [Docker Hub](https://hub.docker.com/r/j0et0m/qubic-bob) | [REST API docs](https://github.com/krypdkat/qubicbob/tree/master/RESTAPI) | [Config docs](https://github.com/krypdkat/qubicbob/blob/master/CONFIG_FILE.MD)
- Lite Node: [hackerby888/qubic-core-lite](https://github.com/hackerby888/qubic-core-lite) | [Linux build guide](https://github.com/hackerby888/qubic-core-lite/blob/main/README_CLANG.md)
- Qubic: [Core repo](https://github.com/qubic/core) | [Node docs](https://docs.qubic.org/learn/nodes/) | [Network dashboard](https://app.qubic.li/network/live)
