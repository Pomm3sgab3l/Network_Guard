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

**One command:**

```bash
docker run -d --name qubic-bob \
  -e NODE_SEED=your55characterlowercaseseed \
  -e NODE_ALIAS=mynode \
  -p 21842:21842 -p 40420:40420 \
  -v qubic-bob-data:/data \
  qubiccore/bob
```

That's it. The container handles everything automatically.

**Or use the install script:**

```bash
wget -O bob.sh https://raw.githubusercontent.com/Pomm3sgab3l/Network_Guard/main/scripts/bob.sh
chmod +x bob.sh && ./bob.sh
```

## Security

Never put your seed directly in a command that gets saved to shell history:

```bash
# BAD - seed saved in history
docker run -e NODE_SEED=mysecret...

# GOOD - space before command prevents history save
 docker run -e NODE_SEED=mysecret...

# GOOD - use interactive mode
./bob.sh install
```

## Management

```bash
./bob.sh status     # show status
./bob.sh logs       # view logs
./bob.sh stop       # stop node
./bob.sh start      # start node
./bob.sh restart    # restart node
./bob.sh update     # update to latest
./bob.sh uninstall  # remove node
```

Or with plain Docker:

```bash
docker logs -f qubic-bob        # view logs
docker stop qubic-bob           # stop
docker start qubic-bob          # start
docker pull qubiccore/bob       # update image
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 21842 | TCP | P2P (required) |
| 40420 | TCP | REST API |

## Cloud Provider Examples

### Hetzner Cloud

```bash
# Create server (CPX31 = 8 vCPU, 16GB RAM)
hcloud server create --name bob-node --type cpx31 --image ubuntu-24.04

# SSH and run
ssh root@<IP>
curl -fsSL https://get.docker.com | sh
docker run -d --name qubic-bob \
  -e NODE_SEED=your55characterlowercaseseed \
  -e NODE_ALIAS=mynode \
  -p 21842:21842 -p 40420:40420 \
  -v qubic-bob-data:/data \
  --restart unless-stopped \
  qubiccore/bob
```

### OVH / Bare Metal

```bash
# After OS install, SSH and run
apt update && apt install -y docker.io
docker run -d --name qubic-bob \
  -e NODE_SEED=your55characterlowercaseseed \
  -e NODE_ALIAS=mynode \
  -p 21842:21842 -p 40420:40420 \
  -v qubic-bob-data:/data \
  --restart unless-stopped \
  qubiccore/bob
```

### AWS EC2

```bash
# Launch t3.xlarge (4 vCPU, 16GB) with Ubuntu 24.04 AMI
# Security Group: allow TCP 21842, 40420, 22

# SSH and run
ssh -i key.pem ubuntu@<IP>
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker ubuntu && newgrp docker
docker run -d --name qubic-bob \
  -e NODE_SEED=your55characterlowercaseseed \
  -e NODE_ALIAS=mynode \
  -p 21842:21842 -p 40420:40420 \
  -v qubic-bob-data:/data \
  --restart unless-stopped \
  qubiccore/bob
```

### Google Cloud

```bash
# Create VM (e2-standard-4 = 4 vCPU, 16GB)
gcloud compute instances create bob-node \
  --machine-type=e2-standard-4 \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud

# SSH and run
gcloud compute ssh bob-node
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker
docker run -d --name qubic-bob \
  -e NODE_SEED=your55characterlowercaseseed \
  -e NODE_ALIAS=mynode \
  -p 21842:21842 -p 40420:40420 \
  -v qubic-bob-data:/data \
  --restart unless-stopped \
  qubiccore/bob
```

### DigitalOcean

```bash
# Create Droplet: 4 vCPU, 16GB RAM, Ubuntu 24.04

ssh root@<IP>
curl -fsSL https://get.docker.com | sh
docker run -d --name qubic-bob \
  -e NODE_SEED=your55characterlowercaseseed \
  -e NODE_ALIAS=mynode \
  -p 21842:21842 -p 40420:40420 \
  -v qubic-bob-data:/data \
  --restart unless-stopped \
  qubiccore/bob
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
