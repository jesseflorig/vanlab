# Cluster

K3s cluster management — inventory, SSH access, etcd, node operations, and rebuild procedures.

## Inventory Groups

| Group | Members | IPs |
|-------|---------|-----|
| `servers` | node1, node3, node5 | 10.1.20.11, .13, .15 |
| `agents` | node2, node4, node6 | 10.1.20.12, .14, .16 |
| `cluster` | servers + agents | Full 6-node K3s cluster |
| `edge_hosts` | edge | 10.1.10.10 — Tailscale + Cloudflared |
| `nvr` | nvr-host | 10.1.10.11 — Frigate + Hailo-8 |

OPNsense (10.1.1.1) is documented as a topology comment in `hosts.ini` — managed via `network-deploy.yml`.

## SSH Access

All hosts use ed25519 key auth. Cluster nodes and NVR are reached via ProxyJump through edge — the SSH config and Ansible group_vars handle this automatically.

```
Management laptop
  ├── ssh edge          → direct (10.1.10.10)
  ├── ssh edge-ts       → direct via Tailscale (off-LAN)
  ├── ssh node{1-6}     → ProxyJump via edge → 10.1.20.{11-16}
  └── ssh nvr           → ProxyJump via edge → 10.1.10.11
```

## etcd Topology

K3s uses embedded etcd. Server count must be odd for quorum:

| Servers | Fault tolerance |
|---------|----------------|
| 1 | None |
| **3** | **1 node — active** |
| 5 | 2 nodes |

The first entry in `[servers]` initializes the cluster (`--cluster-init`). Additional servers join automatically on the next `k3s-deploy.yml` run.

## Promoting an Agent to Server

1. Move the node from `[agents]` to `[servers]` in `hosts.ini`
2. Uninstall the agent: `ansible <node> -i hosts.ini -m shell -a "k3s-agent-uninstall.sh" --become`
3. Re-run: `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml`
4. Verify: `kubectl get nodes` — promoted node shows `control-plane,etcd` role

## Full Command Reference

| Category | Playbook | Command |
|----------|----------|---------|
| Cluster | Deploy K3s | `ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml` |
| Cluster | Deploy Services | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml` |
| Cluster | Deploy Loki only | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags loki` |
| Cluster | Deploy Alloy only | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags alloy` |
| Cluster | Sealed Secrets only | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags sealed-secrets` |
| Cluster | ArgoCD bootstrap | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap` |
| Cluster | Fix static IPs | `ansible-playbook -i hosts.ini playbooks/compute/netplan-deploy.yml` |
| Edge | Deploy Cloudflared | `ansible-playbook -i hosts.ini playbooks/compute/edge-deploy.yml` |
| Edge | Deploy Tailscale | `ansible-playbook -i hosts.ini playbooks/edge/tailscale-deploy.yml --vault-password-file=<(cat ~/.vault_pass)` |
| Edge | Fix static IP | `ansible-playbook -i hosts.ini playbooks/edge/nm-static-deploy.yml` |
| Edge | Deploy SSH config | `ansible-playbook -i hosts.ini playbooks/edge/ssh-config-deploy.yml` |
| Network | OPNsense (check) | `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check` |
| Utilities | Disk Health | `ansible-playbook -i hosts.ini playbooks/utilities/disk-health.yml` |
| Utilities | Drain & Shutdown | `ansible-playbook -i hosts.ini playbooks/utilities/drain-shutdown.yml -e target=<node>` |
| Utilities | Full rack shutdown | `ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml` |
| Utilities | Seal secrets | `ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml` |
| Utilities | Gen Mosquitto passwd | `ansible-playbook -i hosts.ini playbooks/utilities/gen-mosquitto-passwd.yml -e "mqtt_user=<user> mqtt_pass=<pass>"` |

## Playbook Structure

```
playbooks/
├── cluster/
│   ├── k3s-deploy.yml            — provision K3s server and agent nodes
│   └── services-deploy.yml       — deploy Helm, Traefik, Longhorn, ArgoCD, etc.
├── compute/
│   ├── edge-deploy.yml           — install Cloudflared on edge
│   ├── netplan-deploy.yml        — deploy static netplan config to cluster nodes
│   └── tailscale-remove.yml      — remove Tailscale from cluster nodes
├── edge/
│   ├── nm-static-deploy.yml      — manage NetworkManager static IP on edge
│   ├── ssh-config-deploy.yml     — deploy SSH client config to edge
│   └── tailscale-deploy.yml      — install and enroll edge in Tailscale
├── network/
│   └── network-deploy.yml        — manage OPNsense via REST API
└── utilities/
    ├── disk-health.yml           — enumerate NVMe drives per node
    ├── drain-shutdown.yml        — drain a node and shut it down
    ├── gen-mosquitto-passwd.yml  — generate mosquitto_passwd hash
    ├── rack-shutdown.yml         — graceful full-rack shutdown sequence
    ├── read-k3s-token.yml        — read K3s join token from server node
    ├── seal-secrets.yml          — (re)generate sealed-secrets.yaml
    └── test-join-cmd.yml         — print K3s agent join command
```

## Cluster Rebuild

A full rebuild is required when migrating datastores or recovering from total cluster loss. All Longhorn PVC data is lost — ensure the Gitea repo is up to date first (ArgoCD restores apps automatically).

> **Note**: After a rebuild, the Sealed Secrets controller generates a new key — all existing SealedSecrets must be re-sealed before ArgoCD can deploy the home-automation stack. See [Sealed Secrets](sealed-secrets.md).

```bash
# 1. Uninstall agents
ansible agents -i hosts.ini -m shell -a "k3s-agent-uninstall.sh" --become

# 2. Uninstall servers
ansible servers -i hosts.ini -m shell -a "k3s-uninstall.sh" --become

# 3. Deploy etcd-backed cluster (~3 min)
ansible-playbook -i hosts.ini playbooks/cluster/k3s-deploy.yml

# 4. Deploy all services including Sealed Secrets controller (~12 min)
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml

# 5. Re-seal secrets and commit
ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml
git add manifests/home-automation/prereqs/sealed-secrets.yaml
git commit -m "chore: re-seal secrets after cluster rebuild"
git push gitea main

# 6. Bootstrap GitOps (after creating a new Gitea PAT in group_vars/all.yml)
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap
```

Total rebuild time: ~15–20 minutes. ArgoCD syncs apps from Gitea automatically within 3 minutes of coming online.
