# Vanlab

Ansible automation for a homelab running a 6-node K3s cluster with edge compute, NVR, and full network management.

**Hardware**: 6× CM5 64GB w/ PoE HAT + M.2 2TB NVMe (cluster) · 1× Waveshare CM5-PoE-BASE-A (edge) · Dedicated NVR host (Hailo-8 PCIe)

## Architecture

```
Internet
  │
  └── Cloudflare Tunnel ──────────────────────────────────────────┐
                                                                   │
Management Laptop                                                  │
  ├── SSH → edge (10.1.10.10) ←── Tailscale ───────────────────── │
  │     └── SSH ProxyJump → node{1-6} (10.1.20.{11-16})          │
  │                       → nvr (10.1.10.11)                      │
  │                                                                │
  └── Browser → fleet1.cloud / fleet1.lan                         │
                                                                   ▼
OPNsense (10.1.1.1) ── VLANs ──── edge ──── Traefik (K3s) ── Services
                                   │              │
                              Cloudflared    Longhorn (PVCs)
                                             ArgoCD ← Gitea
                                             Grafana / Prometheus
                                             Home Assistant / Node-RED
                                             Frigate (NVR @ 10.1.10.11)
```

## Prerequisites

```bash
# Install Ansible collections
ansible-galaxy collection install -r requirements.yml

# Copy and fill in secrets
cp group_vars/example.all.yml group_vars/all.yml
```

## Quick Reference

| What | Command |
|------|---------|
| Deploy K3s cluster | `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml` |
| Deploy all services | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml` |
| Deploy one service | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags <tag>` |
| Seal secrets | `ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml` |
| OPNsense (dry run) | `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check` |
| Disk health | `ansible-playbook -i hosts.ini playbooks/utilities/disk-health.yml` |
| Drain & shut down node | `ansible-playbook -i hosts.ini playbooks/utilities/drain-shutdown.yml -e target=<node>` |
| Push branch + open PRs | `make pr` |
| Merge PRs + sync main | `make merge` |

## Docs

- [Cluster — K3s, etcd, SSH, inventory, rebuild](docs/cluster.md)
- [GitOps — ArgoCD, Gitea, deploy workflow, rollback](docs/gitops.md)
- [Sealed Secrets — encryption, rotation, backup](docs/sealed-secrets.md)
- [Home Automation — HA, Node-RED, InfluxDB, Mosquitto](docs/home-automation.md)
- [NVR — Frigate + Hailo-8 provisioning](docs/nvr.md)
- [Networking — remote access, OPNsense, Cloudflare tunnel](docs/networking.md)
