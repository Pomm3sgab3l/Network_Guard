# Network Guard

Setup scripts for running [Bob Node](https://github.com/krypdkat/qubicbob) and [Lite Node](https://github.com/hackerby888/qubic-core-lite) on the Qubic network.

Bob is a blockchain indexer with REST API / JSON-RPC 2.0. Lite Node is a lightweight Qubic Core that runs natively on Linux (no UEFI needed).

---

## Bob Node

> BETA - Indexes blockchain data, processes logs, exposes REST + JSON-RPC API.

**Requirements:** 16 GB RAM, 4+ cores (AVX2), 100 GB SSD, Ubuntu 24.04

### Quick start (script)

```bash
wget -O bob-install.sh https://raw.githubusercontent.com/pomm3s/Network_Guard/main/scripts/bob-install.sh
chmod +x bob-install.sh

# pick one:
./bob-install.sh docker-standalone                              # all-in-one container
./bob-install.sh docker-compose --peers 1.2.3.4:21841           # separate containers
./bob-install.sh manual --peers 1.2.3.4:21841 --threads 8      # build from source + systemd
```

Options: `--peers`, `--threads` (0=auto), `--rpc-port` (40420), `--server-port` (21842), `--data-dir` (/opt/qubic-bob)

### Docker (manual setup)

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

### Build from source

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

### Config (`bob.json`)

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

Key settings:
- `trusted-node` - peers to sync from, format `IP:PORT` or `IP:PORT:PASSCODE`
- `request-cycle-ms` - polling interval, don't go too low
- `tick-storage-mode` / `tx-storage-mode` - use `kvrocks` for persistence
- `max-thread` - 0 = auto

### Maintenance

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

---

## Lite Node

> Lightweight Qubic Core - runs on Linux without UEFI. Mainnet (beta) + testnet.

**Testnet:** 16 GB RAM, any modern x86_64 CPU

**Mainnet:** 64 GB RAM, high-freq CPU with AVX2/AVX512 (AMD 7950x recommended), 500 GB SSD, 1 Gbit/s

**Build tools (source install):** Clang >= 18.1.0, CMake >= 3.14, NASM >= 2.16.03

### Quick start (script)

```bash
wget -O lite-install.sh https://raw.githubusercontent.com/pomm3s/Network_Guard/main/scripts/lite-install.sh
chmod +x lite-install.sh

# docker
./lite-install.sh docker --testnet
./lite-install.sh docker --peers 1.2.3.4,5.6.7.8

# source + systemd
./lite-install.sh manual --testnet
./lite-install.sh manual --peers 1.2.3.4,5.6.7.8 --avx512
```

Options: `--peers`, `--testnet`, `--port` (21841), `--http-port` (41841), `--data-dir` (/opt/qubic-lite), `--avx512`, `--security-tick` (32), `--ticking-delay` (1000)

### Docker (manual setup)

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

### Build from source

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

### CLI arguments

- `--peers <ip1,ip2>` - connect to specific peers
- `--security-tick <n>` - quorum bypass interval (testnet only)
- `--ticking-delay <n>` - processing delay in ms (testnet only)

### Source-level config (before building)

These are set in the source code and require a rebuild:

- `#define TESTNET` in `qubic.cpp` - comment out for mainnet
- `USE_SWAP` in `qubic.cpp` - disk-as-RAM fallback
- `knownPublicPeers` in `private_settings.h` - hardcoded peer list
- `TICK_STORAGE_AUTOSAVE_MODE` in `private_settings.h` - set `1` for crash recovery

For mainnet: get active peers from [app.qubic.li/network/live](https://app.qubic.li/network/live), place epoch files in the working directory.

### RPC endpoints

Once the node is running:

```
http://localhost:41841/live/v1    # live status
http://localhost:41841/           # stats
http://localhost:41841/query/v1   # query API
```

### Maintenance

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

### Troubleshooting

- **Node stops ticking after restart** - delete the `system` file in the working dir
- **Build fails** - check versions: Clang >= 18.1.0, CMake >= 3.14, NASM >= 2.16.03
- **Mainnet won't sync** - verify epoch files + peer IPs
- **Not enough RAM** - enable `USE_SWAP` before building
- **Docker build fails on AVX** - host CPU needs AVX2, disable AVX-512 if not supported

---

## Links

- Bob Node: [krypdkat/qubicbob](https://github.com/krypdkat/qubicbob) | [Docker Hub](https://hub.docker.com/r/j0et0m/qubic-bob) | [REST API docs](https://github.com/krypdkat/qubicbob/tree/master/RESTAPI) | [Config docs](https://github.com/krypdkat/qubicbob/blob/master/CONFIG_FILE.MD)
- Lite Node: [hackerby888/qubic-core-lite](https://github.com/hackerby888/qubic-core-lite) | [Linux build guide](https://github.com/hackerby888/qubic-core-lite/blob/main/README_CLANG.md)
- Qubic: [Core repo](https://github.com/qubic/core) | [Node docs](https://docs.qubic.org/learn/nodes/) | [Network dashboard](https://app.qubic.li/network/live)
