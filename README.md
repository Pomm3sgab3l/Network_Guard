# Network Guard

Setup scripts for running [Bob Node](https://github.com/qubic/core-bob) and [Lite Node](https://github.com/qubic/core-lite) on the Qubic network.

---

# Bob Node

Blockchain indexer with REST API for the Qubic network.

## Requirements

| Component | Minimum |
|-----------|---------|
| RAM | 16 GB |
| CPU | 4+ cores |
| Disk | 100 GB SSD |
| Docker | Required |

## Quick Start

```bash
wget -O bob.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob.sh
chmod +x bob.sh && ./bob.sh
```

The script provides an interactive menu and stores data in `/opt/qubic-bob`.

## Management

```bash
cd /opt/qubic-bob
./bob.sh status     # show status
./bob.sh logs       # view logs
./bob.sh stop       # stop node
./bob.sh start      # start node
./bob.sh restart    # restart node
./bob.sh update     # update to latest
./bob.sh uninstall  # remove node
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 21842 | TCP | P2P (required) |
| 40420 | TCP | REST API |

## Cloud Provider Examples

The following providers have been tested with Bob Node:

- Hetzner Cloud
- Netcup / Hostkey
- OVH / Bare Metal
- AWS EC2
- Google Cloud
- DigitalOcean

> **Note:** These are examples only. We do not guarantee that any provider permits running blockchain nodes. Please check the provider's terms of service before deploying.

### Cloud-Init Deployment

Deploy Bob Node with a single command using [cloud-init](https://cloud-init.io/).

**[bob-cloud-init.yml](cloud-init/bob-cloud-init.yml)** - Replace `YOUR_SEED` and `YOUR_ALIAS` before deploying.

```bash
# Hetzner Cloud (cx22 - 16GB RAM)
hcloud server create --name qubic-bob --type cx22 --image ubuntu-24.04 --user-data-from-file bob-cloud-init.yml

# DigitalOcean
doctl compute droplet create qubic-bob --size s-4vcpu-16gb --image ubuntu-24-04-x64 --user-data-file bob-cloud-init.yml

# Netcup / Hostkey: Upload cloud-init.yml in server configuration panel
```

## Firewall

```bash
# UFW (Ubuntu)
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 21842/tcp   # P2P
sudo ufw allow 40420/tcp   # API (optional)
sudo ufw enable
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Container exits immediately | Check logs: `docker logs qubic-bob` |
| Not syncing | Wait a few minutes, check logs for peer connections |
| API not reachable | Check firewall, ensure port 40420 is open |

---

# Lite Node

Lightweight Qubic Core that runs on Linux without UEFI.

## Requirements

| Component | Testnet | Mainnet |
|-----------|---------|---------|
| RAM | 16 GB | 64 GB |
| CPU | x86_64 | High-freq AVX2 |
| Disk | - | 500 GB SSD |

## Quick Start

```bash
wget -O lite.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite.sh
chmod +x lite.sh && ./lite.sh
```

The script provides an interactive menu and stores data in `/opt/qubic-lite`.

## Management

```bash
cd /opt/qubic-lite
./lite.sh status    # show status
./lite.sh logs      # view logs
./lite.sh stop      # stop node
./lite.sh start     # start node
./lite.sh restart   # restart node
./lite.sh update    # rebuild + restart
./lite.sh uninstall # remove node
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 21841 | TCP | P2P (required) |
| 41841 | TCP | HTTP API |

## Cloud Provider Examples

The following providers have been tested with Lite Node:

- Hetzner Cloud
- Netcup / Hostkey
- OVH / Bare Metal
- AWS EC2
- Google Cloud
- DigitalOcean

> **Note:** These are examples only. We do not guarantee that any provider permits running blockchain nodes. Please check the provider's terms of service before deploying.

### Cloud-Init Deployment

Deploy Lite Node with a single command using [cloud-init](https://cloud-init.io/).

**[lite-cloud-init.yml](cloud-init/lite-cloud-init.yml)** - Replace `YOUR_SEED` and `YOUR_ALIAS` before deploying.

```bash
# Hetzner Cloud (cx52 - 64GB RAM)
hcloud server create --name qubic-lite --type cx52 --image ubuntu-24.04 --user-data-from-file lite-cloud-init.yml

# DigitalOcean
doctl compute droplet create qubic-lite --size m-8vcpu-64gb --image ubuntu-24-04-x64 --user-data-file lite-cloud-init.yml

# Netcup / Hostkey: Upload cloud-init.yml in server configuration panel
```

## Firewall

```bash
# UFW (Ubuntu)
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 21841/tcp   # P2P
sudo ufw allow 41841/tcp   # HTTP API
sudo ufw enable
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Build fails | Check if AVX2 is supported: `grep avx2 /proc/cpuinfo` |
| Not syncing | Check logs, verify peers are connecting |
| High CPU usage | Normal during sync |

---

## Links

- Bob Node: [qubic/core-bob](https://github.com/qubic/core-bob) | [Docker Hub](https://hub.docker.com/r/qubiccore/bob)
- Lite Node: [qubic/core-lite](https://github.com/qubic/core-lite) | [Docker Hub](https://hub.docker.com/r/qubiccore/lite)
- Qubic: [Website](https://qubic.org) | [Network Dashboard](https://app.qubic.li/network/live)
