# Network Guard

Setup scripts for running [Bob Node](https://github.com/qubic/core-bob) and [Lite Node](https://github.com/hackerby888/qubic-core-lite) on the Qubic network.

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

All examples: Install Docker, then run the install script.

### Hetzner Cloud

```bash
# Create server (CPX31 = 8 vCPU, 16GB RAM)
hcloud server create --name bob-node --type cpx31 --image ubuntu-24.04

# SSH and install
ssh root@<IP>
curl -fsSL https://get.docker.com | sh
wget -O bob.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob.sh
chmod +x bob.sh && ./bob.sh
```

### OVH / Bare Metal

```bash
apt update && apt install -y docker.io
wget -O bob.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob.sh
chmod +x bob.sh && ./bob.sh
```

### AWS EC2

```bash
# Launch t3.xlarge (4 vCPU, 16GB) with Ubuntu 24.04 AMI
# Security Group: allow TCP 21842, 40420, 22

ssh -i key.pem ubuntu@<IP>
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker ubuntu && newgrp docker
wget -O bob.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob.sh
chmod +x bob.sh && ./bob.sh
```

### Google Cloud

```bash
# Create VM (e2-standard-4 = 4 vCPU, 16GB)
gcloud compute instances create bob-node \
  --machine-type=e2-standard-4 \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud

gcloud compute ssh bob-node
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker
wget -O bob.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob.sh
chmod +x bob.sh && ./bob.sh
```

### DigitalOcean

```bash
# Create Droplet: 4 vCPU, 16GB RAM, Ubuntu 24.04

ssh root@<IP>
curl -fsSL https://get.docker.com | sh
wget -O bob.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob.sh
chmod +x bob.sh && ./bob.sh
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

## Cloud Provider Examples

All examples: Install dependencies, then run the install script.

### Hetzner Cloud

```bash
# Create server (CCX33 = 8 vCPU, 64GB RAM for mainnet)
hcloud server create --name lite-node --type ccx33 --image ubuntu-24.04

ssh root@<IP>
wget -O lite.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite.sh
chmod +x lite.sh && ./lite.sh
```

### OVH / Bare Metal

```bash
apt update
wget -O lite.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite.sh
chmod +x lite.sh && ./lite.sh
```

### AWS EC2

```bash
# Launch c5.2xlarge (8 vCPU, 64GB) with Ubuntu 24.04 AMI
# Security Group: allow TCP 21841, 22

ssh -i key.pem ubuntu@<IP>
wget -O lite.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite.sh
chmod +x lite.sh && ./lite.sh
```

## Firewall

```bash
# UFW (Ubuntu)
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 21841/tcp   # P2P
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
- Lite Node: [hackerby888/qubic-core-lite](https://github.com/hackerby888/qubic-core-lite)
- Qubic: [Website](https://qubic.org) | [Network Dashboard](https://app.qubic.li/network/live)
