# Network Guard - Qubic Node Installation Guide

Setup-Anleitungen fuer **Bob Node** und **Lite Node** im Qubic-Netzwerk.

---

## Inhaltsverzeichnis

- [1. Uebersicht](#1-uebersicht)
- [2. Bob Node](#2-bob-node)
  - [2.1 Systemanforderungen](#21-systemanforderungen)
  - [2.2 Installation mit Docker (Empfohlen)](#22-installation-mit-docker-empfohlen)
    - [2.2.1 Standalone (All-in-One)](#221-standalone-all-in-one)
    - [2.2.2 Docker Compose (Modular)](#222-docker-compose-modular)
  - [2.3 Manuelle Installation (Build from Source)](#23-manuelle-installation-build-from-source)
  - [2.4 Konfiguration](#24-konfiguration)
  - [2.5 Wartung und Troubleshooting](#25-wartung-und-troubleshooting)
- [3. Lite Node](#3-lite-node)
  - [3.1 Systemanforderungen](#31-systemanforderungen)
  - [3.2 Installation mit Docker](#32-installation-mit-docker)
  - [3.3 Manuelle Installation (Build from Source)](#33-manuelle-installation-build-from-source)
  - [3.4 Konfiguration](#34-konfiguration)
  - [3.5 Betrieb](#35-betrieb)
- [4. Referenzen](#4-referenzen)

---

## 1. Uebersicht

| Node-Typ | Beschreibung | Repo |
|-----------|-------------|------|
| **Bob Node** | Ultra-lightweight Indexer mit REST API fuer das Qubic-Netzwerk. Archiviert Blockchain-Daten und stellt sie ueber JSON-RPC 2.0 bereit. | [krypdkat/qubicbob](https://github.com/krypdkat/qubicbob) |
| **Lite Node** | Lite-Version des Qubic Core. Laeuft direkt auf dem OS ohne UEFI-Umgebung. Unterstuetzt Mainnet (Beta) und lokales Testnet. | [vitwit/qubic-core-lite](https://github.com/vitwit/qubic-core-lite) |

---

## 2. Bob Node

> Bob ist ein BETA Indexer und Logging-Node fuer das Qubic-Netzwerk. Er archiviert Blockchain-Daten, verarbeitet Logging-Events und bietet eine REST API / JSON-RPC 2.0 API.

### 2.1 Systemanforderungen

| Ressource | Minimum |
|-----------|---------|
| RAM | 16 GB |
| CPU | 4+ Kerne mit AVX2-Support |
| Speicher | 100 GB schnelle SSD / NVMe |
| OS | Linux (Ubuntu 24.04 empfohlen) |
| Software | Docker **oder** CMake, Clang/GCC, KeyDB, KVRocks |

### 2.2 Installation mit Docker (Empfohlen)

> **Voraussetzung:** Docker und Docker Compose muessen installiert sein.
>
> ```bash
> # Docker installieren (falls nicht vorhanden)
> curl -fsSL https://get.docker.com | sh
> sudo usermod -aG docker $USER
> # Danach neu einloggen oder: newgrp docker
> ```

#### 2.2.1 Standalone (All-in-One)

Die Standalone-Variante buendelt **Bob + Redis + KVRocks** in einem einzigen Container. Ideal fuer schnelles Setup.

```bash
# 1. Beispiel-Dateien herunterladen
mkdir -p ~/qubic-bob && cd ~/qubic-bob

curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.standalone.yml
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/bob.json.standalone

# 2. Konfiguration anpassen (optional)
mv bob.json.standalone bob.json
# Datei bearbeiten falls noetig:
# nano bob.json

# 3. Container starten
docker compose -f docker-compose.standalone.yml up -d
```

**Ports:**
- `21842` - P2P / Server Port
- `40420` - REST API / JSON-RPC

**Logs pruefen:**
```bash
docker compose -f docker-compose.standalone.yml logs -f
```

#### 2.2.2 Docker Compose (Modular)

Die modulare Variante betreibt Bob, KeyDB und KVRocks als separate Container. Bietet mehr Kontrolle und Skalierbarkeit.

```bash
# 1. Beispiel-Dateien herunterladen
mkdir -p ~/qubic-bob && cd ~/qubic-bob

curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/docker-compose.yml
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/bob.json
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/keydb.conf
curl -O https://raw.githubusercontent.com/krypdkat/qubicbob/master/docker/examples/kvrocks.conf

# 2. Konfiguration anpassen (optional)
# nano bob.json

# 3. Container starten
docker compose up -d
```

**Status pruefen:**
```bash
docker compose ps
docker compose logs -f qubic-bob
```

**Container stoppen:**
```bash
docker compose down
```

### 2.3 Manuelle Installation (Build from Source)

Einrichtungs-Skript fuer Ubuntu/Debian:

```bash
#!/bin/bash
# bob-install.sh - Bob Node Installation Script

set -e

echo "=== Bob Node Installation ==="

# 1. System-Updates und Abhaengigkeiten
sudo apt update && sudo apt upgrade -y
sudo apt install -y vim net-tools tmux cmake git libjsoncpp-dev \
    build-essential uuid-dev libhiredis-dev zlib1g-dev unzip

# 2. KeyDB installieren
echo "=== KeyDB installieren ==="
echo "deb https://download.keydb.dev/open-source-dist $(lsb_release -sc) main" | \
    sudo tee /etc/apt/sources.list.d/keydb.list
sudo wget -O /etc/apt/trusted.gpg.d/keydb.gpg https://download.keydb.dev/open-source-dist/keyring.gpg
sudo apt update
sudo apt install -y keydb

# KeyDB starten
sudo systemctl enable keydb-server
sudo systemctl start keydb-server

# 3. KVRocks installieren (fuer persistente Speicherung)
echo "=== KVRocks installieren ==="
cd /tmp
git clone --branch v2.9.0 https://github.com/apache/kvrocks.git
cd kvrocks
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo cp src/kvrocks /usr/local/bin/
cd ~

# 4. Bob Node klonen und bauen
echo "=== Bob Node bauen ==="
git clone https://github.com/krypdkat/qubicbob.git
cd qubicbob
mkdir build && cd build
cmake ../
make -j$(nproc)

echo "=== Installation abgeschlossen ==="
echo "Binary liegt unter: $(pwd)/bob"
echo ""
echo "Starten mit: ./bob /pfad/zur/config.json"
```

**Schritt-fuer-Schritt (manuell):**

```bash
# 1. Abhaengigkeiten installieren
sudo apt update && sudo apt upgrade -y
sudo apt install -y vim net-tools tmux cmake git libjsoncpp-dev \
    build-essential uuid-dev libhiredis-dev zlib1g-dev unzip

# 2. Repository klonen
git clone https://github.com/krypdkat/qubicbob.git
cd qubicbob

# 3. Bauen
mkdir build && cd build
cmake ../
make -j$(nproc)

# 4. Konfigurationsdatei erstellen
cp ../default_config_bob.json ./config.json
# Konfiguration anpassen:
nano config.json

# 5. Starten (mit tmux fuer Persistenz)
tmux new -s bob
./bob ./config.json
# Tmux verlassen: Ctrl+B, dann D
# Wieder verbinden: tmux attach -t bob
```

### 2.4 Konfiguration

Beispiel `bob.json`:

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

> **Hinweis:** Bei Docker Compose die Hostnames `keydb` und `kvrocks` statt `127.0.0.1` verwenden.

**Wichtige Konfigurationsparameter:**

| Parameter | Beschreibung | Standard |
|-----------|-------------|----------|
| `trusted-node` | Qubic-Peers zum Synchronisieren (`IP:PORT` oder `IP:PORT:PASSCODE`) | `[]` |
| `p2p-node` | P2P-Node-Adressen | `[]` |
| `request-cycle-ms` | Abfrage-Intervall in ms (nicht zu niedrig setzen!) | `100` |
| `request-logging-cycle-ms` | Logging-Abfrage-Intervall in ms | `30` |
| `log-level` | Log-Detailgrad (`info`, `debug`, etc.) | `info` |
| `keydb-url` | KeyDB-Verbindung | `tcp://127.0.0.1:6379` |
| `kvrocks-url` | KVRocks-Verbindung (persistente Speicherung) | `tcp://127.0.0.1:6666` |
| `run-server` | Listener-Port aktivieren | `false` |
| `server-port` | P2P-Server Port | `21842` |
| `rpc-port` | REST API / JSON-RPC Port | `40420` |
| `tick-storage-mode` | Speicher-Backend (`kvrocks`, `lastNTick`, `free`) | `lastNTick` |
| `tx-storage-mode` | TX-Speicher-Backend | `kvrocks` |
| `tx_tick_to_live` | Datenaufbewahrung (Ticks) | `3000` |
| `max-thread` | Max. Threads (0 = automatisch) | `8` |
| `spam-qu-threshold` | Spam-Filter Schwellenwert | `100` |

### 2.5 Wartung und Troubleshooting

**Logs anzeigen (Docker):**
```bash
docker compose logs -f qubic-bob
```

**In den Container verbinden:**
```bash
docker exec -it qubic-bob /bin/bash
```

**Datenbank zuruecksetzen:**
```bash
# Docker Compose
docker compose down
docker volume rm qubic-bob-redis qubic-bob-kvrocks qubic-bob-data
docker compose up -d
```

**Updates einspielen (Docker):**
```bash
docker compose pull
docker compose up -d
```

**Updates einspielen (Manuell):**
```bash
cd ~/qubicbob
git pull
cd build
cmake ../
make -j$(nproc)
# Neustart des Bob-Prozesses
```

---

## 3. Lite Node

> Die Lite-Version des Qubic Core laeuft direkt auf dem Betriebssystem ohne UEFI-Umgebung. Unterstuetzt Mainnet (Beta) und lokales Testnet.

### 3.1 Systemanforderungen

**Lokales Testnet:**

| Ressource | Minimum |
|-----------|---------|
| RAM | 16 GB |
| CPU | Moderner x86_64-Prozessor |
| Speicher | Minimal |

**Mainnet (Beta):**

| Ressource | Minimum |
|-----------|---------|
| RAM | 64 GB |
| CPU | High-Frequency mit AVX2/AVX512 (z.B. AMD 7950x) |
| Speicher | 500 GB schnelle SSD |
| Netzwerk | 1 Gbit/s synchron |
| Epoch-Dateien | spectrum, universe, contract files (siehe unten) |

### 3.2 Installation mit Docker

> **Hinweis:** Das offizielle Repo hat keine Docker-Dateien. Hier ein Dockerfile zum Selberbauen.

**Dockerfile erstellen:**

```dockerfile
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential clang cmake nasm git \
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone https://github.com/vitwit/qubic-core-lite.git .

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

**Docker Image bauen und starten:**

```bash
# 1. Projektordner erstellen
mkdir -p ~/qubic-lite && cd ~/qubic-lite

# 2. Dockerfile erstellen (Inhalt von oben einfuegen)
nano Dockerfile

# 3. Image bauen
docker build -t qubic-lite-node .

# 4. Fuer Testnet starten
docker run -d \
    --name qubic-lite \
    --restart unless-stopped \
    -p 21841:21841 \
    qubic-lite-node \
    --security-tick 32 --ticking-delay 1000

# 5. Fuer Mainnet starten (Epoch-Dateien benoetigt)
docker run -d \
    --name qubic-lite \
    --restart unless-stopped \
    -p 21841:21841 \
    -v ~/qubic-data:/qubic/data \
    qubic-lite-node \
    --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
```

> **Wichtig:** Fuer Mainnet muessen die Epoch-Dateien (`spectrum.XXX`, `universe.XXX`, `contract0000.XXX` etc.) im gemounteten Verzeichnis liegen.

### 3.3 Manuelle Installation (Build from Source)

Einrichtungs-Skript fuer Ubuntu/Debian:

```bash
#!/bin/bash
# lite-node-install.sh - Qubic Lite Node Installation Script

set -e

echo "=== Qubic Lite Node Installation ==="

# 1. System-Updates und Abhaengigkeiten
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential clang cmake nasm git \
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev

# 2. Repository klonen
git clone https://github.com/vitwit/qubic-core-lite.git
cd qubic-core-lite

# 3. Build-Verzeichnis erstellen
mkdir -p build && cd build

# 4. CMake konfigurieren
cmake .. \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_TESTS=OFF \
    -DBUILD_BINARY=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_AVX512=OFF

# 5. Bauen
cmake --build . -- -j$(nproc)

echo "=== Installation abgeschlossen ==="
echo "Binary liegt unter: $(pwd)/src/Qubic"
echo ""
echo "Testnet starten: ./src/Qubic --security-tick 32 --ticking-delay 1000"
echo "Mainnet starten: ./src/Qubic --peers PEER_IP_1,PEER_IP_2"
```

**Schritt-fuer-Schritt (manuell):**

```bash
# 1. Abhaengigkeiten installieren
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential clang cmake nasm git \
    libc++-dev libc++abi-dev libjsoncpp-dev uuid-dev zlib1g-dev

# 2. Repository klonen
git clone https://github.com/vitwit/qubic-core-lite.git
cd qubic-core-lite

# 3. Bauen
mkdir -p build && cd build
cmake .. \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_TESTS=OFF \
    -DBUILD_BINARY=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_AVX512=OFF
cmake --build . -- -j$(nproc)

# 4. Starten (Testnet)
./src/Qubic --security-tick 32 --ticking-delay 1000

# 5. Starten (Mainnet) - Epoch-Dateien vorher bereitstellen!
./src/Qubic --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
```

### 3.4 Konfiguration

Die Lite Node wird ueber **Kommandozeilen-Parameter** und **Quellcode-Einstellungen** konfiguriert.

**Kommandozeilen-Parameter:**

| Parameter | Beschreibung | Beispiel |
|-----------|-------------|---------|
| `--security-tick N` | Umgeht Quorum-Verifikation alle N Ticks (Testnet) | `--security-tick 32` |
| `--ticking-delay N` | Verlangsamt Testnet-Verarbeitung um N ms | `--ticking-delay 1000` |
| `--peers IP1,IP2` | Peer-Nodes direkt angeben | `--peers 1.2.3.4,5.6.7.8` |

**Quellcode-Konfiguration (vor dem Build):**

| Einstellung in `qubic.cpp` | Beschreibung |
|---------------------------|-------------|
| `#define TESTNET` | Aktiviert Testnet-Modus (auskommentieren fuer Mainnet) |
| `USE_SWAP` | Nutzt Disk als RAM-Fallback |

**Fuer Mainnet:**

1. In `qubic.cpp` die Zeile `#define TESTNET` auskommentieren
2. In `private_settings.h` die `knownPublicPeers` mit aktiven Peer-IPs fuellen
3. Epoch-Dateien im Startverzeichnis ablegen:
   - `spectrum.XXX`
   - `universe.XXX`
   - `contract0000.XXX` bis `contractNNNN.XXX`
4. Peers von [qubic.li Network Dashboard](https://app.qubic.li/network/live) holen

### 3.5 Betrieb

**Testnet starten:**
```bash
# Mit tmux fuer Persistenz
tmux new -s qubic
./Qubic --security-tick 32 --ticking-delay 1000
# Tmux verlassen: Ctrl+B, dann D
```

**Mainnet starten:**
```bash
tmux new -s qubic
./Qubic --peers PEER_IP_1,PEER_IP_2,PEER_IP_3
# F12 druecken um in den MAIN-Modus zu wechseln
```

**Als systemd Service einrichten:**
```bash
sudo tee /etc/systemd/system/qubic-lite.service > /dev/null <<EOF
[Unit]
Description=Qubic Lite Node
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER/qubic-core-lite/build/src
ExecStart=/home/$USER/qubic-core-lite/build/src/Qubic --peers PEER_IP_1,PEER_IP_2
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable qubic-lite
sudo systemctl start qubic-lite
```

**Service-Status pruefen:**
```bash
sudo systemctl status qubic-lite
sudo journalctl -u qubic-lite -f
```

**Troubleshooting:**

| Problem | Loesung |
|---------|---------|
| Node tickt nicht mehr nach Neustart | `system`-Datei im Arbeitsverzeichnis loeschen |
| Build schlaegt fehl | Clang >= 18.1.0, CMake >= 3.14, NASM >= 2.16.03 pruefen |
| Mainnet synchronisiert nicht | Epoch-Dateien pruefen, Peers aktualisieren |
| Nicht genug RAM | `USE_SWAP` in Quellcode aktivieren |

---

## 4. Referenzen

| Ressource | Link |
|-----------|------|
| Bob Node Repository | [github.com/krypdkat/qubicbob](https://github.com/krypdkat/qubicbob) |
| Bob Node Docker Hub | [j0et0m/qubic-bob](https://hub.docker.com/r/j0et0m/qubic-bob) |
| Bob Node Config Docs | [CONFIG_FILE.MD](https://github.com/krypdkat/qubicbob/blob/master/CONFIG_FILE.MD) |
| Bob Node REST API | [RESTAPI/](https://github.com/krypdkat/qubicbob/tree/master/RESTAPI) |
| Lite Node Repository | [github.com/vitwit/qubic-core-lite](https://github.com/vitwit/qubic-core-lite) |
| Lite Node Linux Build | [README_CLANG.md](https://github.com/vitwit/qubic-core-lite/blob/main/README_CLANG.md) |
| Qubic Core (Full Node) | [github.com/qubic/core](https://github.com/qubic/core) |
| Qubic Node Types Docs | [docs.qubic.org/learn/nodes](https://docs.qubic.org/learn/nodes/) |
| Qubic Network Dashboard | [app.qubic.li/network/live](https://app.qubic.li/network/live) |
| Beispiel-Doku (qubic-li/client) | [github.com/qubic-li/client](https://github.com/qubic-li/client) |
