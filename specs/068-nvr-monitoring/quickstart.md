# Quickstart: NVR Host Monitoring and Alerting

This runbook covers deploying monitoring for the NVR host (`10.1.10.11`). Steps 1–2 are cluster-side (manifests + ArgoCD); Step 3 is host-side (Ansible); Step 4 is verification.

**Prerequisites**:
- NVR host provisioned and running (spec 041)
- Prometheus, Alertmanager, Loki, Grafana running in cluster (specs 009, 014)
- HA long-lived token added to `group_vars/all.yml` as `ha_alertmanager_token`
- `kubeseal` CLI available on a cluster node

---

## Step 1: Generate SealedSecret for HA Token

```bash
# Ensure group_vars/all.yml has:
# ha_alertmanager_token: "<the long-lived token>"

ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml
# Generates manifests/monitoring/nvr-exporter/sealed-secrets.yaml
```

---

## Step 2: Commit Manifests and Sync ArgoCD

```bash
git add manifests/monitoring/nvr-exporter/ group_vars/all.yml
git commit -m "feat(068): add NVR monitoring manifests"
git push gitea 068-nvr-monitoring

# After merge to main, ArgoCD auto-syncs monitoring-nvr application
# Verify sync:
kubectl get application monitoring-nvr -n argocd
kubectl get scrapeconfig,prometheusrule,alertmanagerconfig,svc -n monitoring | grep nvr
```

---

## Step 3: Provision NVR Host Monitoring Agents

```bash
# Dry run first
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags monitoring --check

# Apply
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags monitoring
```

Expected output:
- `prometheus-node-exporter` installed and running on port 9100
- Alloy installed and running, shipping journald to `http://10.1.20.11:30100/loki/api/v1/push`

---

## Step 4: Verification

### 4a. Confirm node_exporter is reachable

```bash
# From a cluster node (or via kubectl exec):
curl -s http://10.1.10.11:9100/metrics | grep "node_cpu"
# Should return CPU metric lines
```

### 4b. Confirm Prometheus is scraping NVR host

```bash
# In Grafana → Explore → Prometheus:
up{job="nvr-node-exporter"}
# Should return: 1
```

### 4c. Confirm logs are flowing to Loki

```bash
# In Grafana → Explore → Loki:
{job="nvr-host"}
# Should return recent journal entries from the NVR host
# Confirm: frigate.service entries visible, kernel entries visible
```

### 4d. Test the offline alert

```bash
# SSH to NVR host and stop node_exporter temporarily:
sudo systemctl stop prometheus-node-exporter
# Wait 3 minutes
# Check: HA notification received on mobile?
# Check Alertmanager: kubectl port-forward svc/alertmanager-operated 9093 -n monitoring
#   → http://localhost:9093 → NvrHostDown alert should be firing

# Re-enable:
sudo systemctl start prometheus-node-exporter
# Wait 2 minutes — recovery notification should arrive in HA
```

### 4e. Confirm Grafana dashboard visibility

```bash
# In Grafana → Dashboards → import community dashboard ID 1860 (Node Exporter Full)
# Add data source: Prometheus
# Filter by instance: 10.1.10.11:9100
# Confirm: CPU, memory, disk, uptime panels all populated
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `up{job="nvr-node-exporter"}` returns 0 or no data | Firewall seq 203 not applied or node_exporter not running | Run `network-deploy.yml`; check `systemctl status prometheus-node-exporter` on NVR |
| Loki shows no NVR logs | Alloy not running or firewall seq 204 not applied | Check `systemctl status alloy` on NVR; run `network-deploy.yml` |
| Alert fires but no HA notification | AlertmanagerConfig not synced or HA token wrong | Check ArgoCD sync; verify HA token in group_vars/all.yml; re-run seal-secrets.yml |
| Alloy fails to connect to Loki NodePort | NodePort Service not synced in ArgoCD | Check `kubectl get svc loki-nvr-push -n monitoring` |
| `NvrHostDown` alert never fires | Alert not routing through AlertmanagerConfig | Check `kubectl get alertmanagerconfig -n monitoring`; verify label `release: kube-prometheus-stack` |
