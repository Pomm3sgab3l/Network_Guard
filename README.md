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

### Option 1: Install Script (recommended)

```bash
wget -O bob.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob.sh
chmod +x bob.sh && ./bob.sh
```

The script provides an interactive menu and stores data in `/opt/qubic-bob`.

### Option 2: Docker (manual)

The container requires a `bob.json` config file (environment variables are not supported).

**Install & Start:**
```bash
# Create config
mkdir -p /opt/qubic-bob
cat > /opt/qubic-bob/bob.json << 'EOF'
{
  "node-seed": "your55characterlowercaseseed",
  "p2p-node": [],
  "arbitrator-identity": "AFZPUAIYVPNUYGJRQVLUKOPPVLHAZQTGLYAAUUNBXFTVTAMSBKQBLEIEPCVJ",
  "keydb-url": "tcp://127.0.0.1:6379",
  "kvrocks-url": "tcp://127.0.0.1:6666",
  "tick-storage-mode": "kvrocks",
  "log-level": "info"
}
EOF

# Start container
docker run -d --name qubic-bob \
  -p 21842:21842 -p 40420:40420 \
  -v /opt/qubic-bob/bob.json:/app/bob.json:ro \
  -v /opt/qubic-bob/data:/data \
  --restart unless-stopped \
  qubiccore/bob
```

**Management:**
| Action | Command |
|--------|---------|
| View logs | `docker logs -f qubic-bob` |
| Stop | `docker stop qubic-bob` |
| Start | `docker start qubic-bob` |
| Restart | `docker restart qubic-bob` |
| Status | `docker ps -a --filter name=qubic-bob` |

**Update:**
```bash
docker pull qubiccore/bob
docker rm -f qubic-bob
docker run -d --name qubic-bob \
  -p 21842:21842 -p 40420:40420 \
  -v /opt/qubic-bob/bob.json:/app/bob.json:ro \
  -v /opt/qubic-bob/data:/data \
  --restart unless-stopped \
  qubiccore/bob
```

**Uninstall:**
```bash
docker rm -f qubic-bob      # Remove container
rm -rf /opt/qubic-bob       # Remove data (optional)
docker rmi qubiccore/bob    # Remove image (optional)
```

**Data location:** `/opt/qubic-bob/data`

## Security

Your seed is stored in `/opt/qubic-bob/bob.json`. To prevent it from being saved in shell history when using manual setup:

```bash
# Add space before command to prevent history save
 cat > /opt/qubic-bob/bob.json << 'EOF'
...
EOF

# Or use the interactive script
./bob.sh
```

## Management (Script)

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
wget -O lite.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/lite-install.sh
chmod +x lite.sh && ./lite.sh
```

## Management

```bash
./lite.sh status    # show status
./lite.sh logs      # view logs
./lite.sh stop      # stop node
./lite.sh start     # start node
./lite.sh restart   # restart node
./lite.sh update    # rebuild + restart
```

---

## Links

- Bob Node: [qubic/core-bob](https://github.com/qubic/core-bob) | [Docker Hub](https://hub.docker.com/r/qubiccore/bob)
- Lite Node: [hackerby888/qubic-core-lite](https://github.com/hackerby888/qubic-core-lite)
- Qubic: [Website](https://qubic.org) | [Network Dashboard](https://app.qubic.li/network/live)
