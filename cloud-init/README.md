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

### DigitalOcean

```bash
# Bob Node
doctl compute droplet create qubic-bob --size s-4vcpu-16gb --image ubuntu-24-04-x64 --user-data-file bob-cloud-init.yml

# Lite Node
doctl compute droplet create qubic-lite --size m-8vcpu-64gb --image ubuntu-24-04-x64 --user-data-file lite-cloud-init.yml
```

### Netcup / Hostkey

Upload the cloud-init file in the server configuration panel during VM creation.

### AWS EC2

```bash
# Bob Node
aws ec2 run-instances --image-id ami-ubuntu-24.04 --instance-type t3.xlarge --user-data file://bob-cloud-init.yml

# Lite Node
aws ec2 run-instances --image-id ami-ubuntu-24.04 --instance-type r5.2xlarge --user-data file://lite-cloud-init.yml
```

---

## After Deployment

SSH into your server and check the node status:

```bash
# Bob Node
cd /opt/qubic-bob && docker compose logs -f

# Lite Node
cd /opt/qubic-lite && docker compose logs -f
```
