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

Deploy Bob Node with a single command using [cloud-init](https://cloud-init.io/). Replace `YOUR_SEED` and `YOUR_ALIAS` before deploying.

<details>
<summary><b>bob-cloud-init.yml</b> (click to expand)</summary>

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - ca-certificates
  - curl
  - ufw

runcmd:
  # Install Docker
  - curl -fsSL https://get.docker.com | sh

  # Configure firewall
  - ufw allow 22/tcp
  - ufw allow 21842/tcp
  - ufw allow 40420/tcp
  - ufw --force enable

  # Create directory
  - mkdir -p /opt/qubic-bob

  # Fetch peers and create config
  - |
    PEERS=$(curl -sf "https://api.qubic.global/random-peers?service=bobNode&litePeers=6" | grep -oE '"bobPeers":\[[^]]*\]' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -6 | while read ip; do echo -n "\"BM:${ip}:21841:0-0-0-0\","; done | sed 's/,$//')
    cat > /opt/qubic-bob/bob.json << EOF
    {
      "p2p-node": ["BM:0.0.0.0:21841:0-0-0-0",${PEERS}],
      "request-cycle-ms": 100,
      "log-level": "info",
      "run-server": true,
      "server-port": 21842,
      "rpc-port": 40420,
      "arbitrator-identity": "AFZPUAIYVPNUYGJRQVLUKOPPVLHAZQTGLYAAUUNBXFTVTAMSBKQBLEIEPCVJ",
      "tick-storage-mode": "kvrocks",
      "kvrocks-url": "tcp://127.0.0.1:6666",
      "tx-storage-mode": "kvrocks",
      "node-seed": "YOUR_SEED",
      "node-alias": "YOUR_ALIAS"
    }
    EOF

  # Create docker-compose.yml
  - |
    cat > /opt/qubic-bob/docker-compose.yml << 'EOF'
    services:
      qubic-bob:
        image: qubiccore/bob:latest
        container_name: qubic-bob
        restart: unless-stopped
        ports:
          - "21842:21842"
          - "40420:40420"
        volumes:
          - /opt/qubic-bob/bob.json:/app/bob.json:ro
          - /opt/qubic-bob/data:/data

      watchtower:
        image: containrrr/watchtower
        container_name: watchtower
        restart: unless-stopped
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock
        command: --interval 300 qubic-bob
    EOF

  # Start containers
  - cd /opt/qubic-bob && docker compose up -d
```

</details>

**Provider Commands:**

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

Deploy Lite Node with a single command using [cloud-init](https://cloud-init.io/). Replace `YOUR_SEED` and `YOUR_ALIAS` before deploying.

<details>
<summary><b>lite-cloud-init.yml</b> (click to expand)</summary>

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - ca-certificates
  - curl
  - ufw

runcmd:
  # Install Docker
  - curl -fsSL https://get.docker.com | sh

  # Configure firewall
  - ufw allow 22/tcp
  - ufw allow 21841/tcp
  - ufw allow 41841/tcp
  - ufw --force enable

  # Create directory
  - mkdir -p /opt/qubic-lite

  # Create docker-compose.yml
  - |
    cat > /opt/qubic-lite/docker-compose.yml << 'EOF'
    services:
      qubic-lite:
        image: qubiccore/lite:latest
        container_name: qubic-lite
        restart: unless-stopped
        ports:
          - "21841:21841"
          - "41841:41841"
        volumes:
          - /opt/qubic-lite/data:/qubic
        environment:
          - QUBIC_MODE=normal
          - QUBIC_OPERATOR_SEED=YOUR_SEED
          - QUBIC_OPERATOR_ALIAS=YOUR_ALIAS
          - QUBIC_LOG_LEVEL=INFO

      watchtower:
        image: containrrr/watchtower
        container_name: watchtower
        restart: unless-stopped
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock
        command: --interval 300 qubic-lite
    EOF

  # Start containers
  - cd /opt/qubic-lite && docker compose up -d
```

</details>

**Provider Commands:**

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
