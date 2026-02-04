# Cloud-Init Deployment

Deploy Qubic nodes on any cloud provider with a single command using [cloud-init](https://cloud-init.io/).

## Files

| Node | File | Requirements |
|------|------|--------------|
| Bob | [bob-cloud-init.yml](bob-cloud-init.yml) | 16GB RAM, 4+ cores, 100GB SSD |
| Lite | [lite-cloud-init.yml](lite-cloud-init.yml) | 64GB RAM, AVX2 CPU, 500GB SSD |

> **Important:** Replace `YOUR_SEED` and `YOUR_ALIAS` in the file before deploying!

---

## Provider Commands

### Hetzner Cloud

```bash
# Bob Node (cx22 - 16GB RAM)
hcloud server create --name qubic-bob --type cx22 --image ubuntu-24.04 --user-data-from-file bob-cloud-init.yml

# Lite Node (cx52 - 64GB RAM)
hcloud server create --name qubic-lite --type cx52 --image ubuntu-24.04 --user-data-from-file lite-cloud-init.yml
```

### Netcup / Hostkey

Upload the cloud-init file in the server configuration panel during VM creation.

### DigitalOcean

```bash
# Bob Node
doctl compute droplet create qubic-bob --size s-4vcpu-16gb --image ubuntu-24-04-x64 --user-data "$(cat bob-cloud-init.yml)"

# Lite Node
doctl compute droplet create qubic-lite --size m-8vcpu-64gb --image ubuntu-24-04-x64 --user-data "$(cat lite-cloud-init.yml)"
```

### AWS EC2

```bash
# Bob Node
aws ec2 run-instances --image-id ami-0abcdef1234567890 --instance-type t3.xlarge --user-data file://bob-cloud-init.yml --key-name my-key

# Lite Node
aws ec2 run-instances --image-id ami-0abcdef1234567890 --instance-type m5.8xlarge --user-data file://lite-cloud-init.yml --key-name my-key
```

### Azure

```bash
# Bob Node
az vm create --name qubic-bob --image Ubuntu2404 --size Standard_D4s_v5 --custom-data bob-cloud-init.yml

# Lite Node
az vm create --name qubic-lite --image Ubuntu2404 --size Standard_D16s_v5 --custom-data lite-cloud-init.yml
```

### Google Cloud (GCP)

```bash
# Bob Node
gcloud compute instances create qubic-bob --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud --machine-type=e2-standard-4 --metadata-from-file user-data=bob-cloud-init.yml

# Lite Node
gcloud compute instances create qubic-lite --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud --machine-type=n2-standard-16 --metadata-from-file user-data=lite-cloud-init.yml
```

---

## Post-Deployment

SSH into your server and verify the deployment:

### Check Container Status

```bash
docker ps
```

### View Logs

```bash
# Bob Node
docker logs -f qubic-bob

# Lite Node
docker logs -f qubic-lite
```

### Node Health Check (Lite only)

```bash
docker exec qubic-lite orchestrator-ctl status
```

### Modify Configuration

```bash
# Edit config
nano /opt/qubic-lite/docker-compose.yml

# Apply changes
cd /opt/qubic-lite && docker compose up -d
```
