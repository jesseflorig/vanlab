# Data Model: NVR Host Monitoring and Alerting

**Branch**: `068-nvr-monitoring` | **Date**: 2026-06-03

This feature introduces no new persistent data stores. The data entities below describe the monitoring objects that flow through the existing Prometheus / Loki / Alertmanager pipeline.

---

## Metrics (Prometheus)

### Scrape Target: nvr-node-exporter

| Field | Value |
|-------|-------|
| Job label | `nvr-node-exporter` |
| Instance | `10.1.10.11:9100` |
| Scrape interval | `60s` |
| Key metrics | `up`, `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_filesystem_avail_bytes`, `node_load1`, `node_network_receive_bytes_total` |

---

## Alerts (Alertmanager)

### NvrHostDown

| Field | Value |
|-------|-------|
| Expression | `up{job="nvr-node-exporter"} == 0` |
| Duration | `2m` |
| Severity | `critical` |
| Summary | `NVR host is unreachable` |
| Description | `The NVR host at 10.1.10.11 has been unreachable for more than 2 minutes.` |

### AlertmanagerConfig Routing

| Field | Value |
|-------|-------|
| Match label | `alertname="NvrHostDown"` |
| Receiver | `ha-nvr-notify` |
| Repeat interval | `1h` |
| Group wait | `30s` |

### Home Assistant Webhook Receiver

| Field | Value |
|-------|-------|
| Name | `ha-nvr-notify` |
| URL | `http://home-assistant.home-automation.svc.cluster.local:8080/api/services/notify/notify` |
| Auth | Bearer token (SealedSecret: `ha-alertmanager-token` in `monitoring` namespace) |
| Payload | `{"message": "{{ .CommonAnnotations.description }}", "title": "{{ .CommonAnnotations.summary }}"}` |

---

## Logs (Loki)

### NVR Journal Log Stream

| Label | Value |
|-------|-------|
| `job` | `nvr-host` |
| `host` | `nvr-host` |
| `unit` | `<systemd unit name>` (e.g., `frigate.service`, `kernel`) |
| `level` | `<syslog priority keyword>` (e.g., `err`, `warning`, `info`) |

**Source**: systemd journal on `nvr-host` via Alloy `loki.source.journal`

**Push endpoint**: `http://10.1.20.11:30100/loki/api/v1/push` (NodePort Service `loki-nvr-push`)

---

## Kubernetes Resources

### New Resources (manifests/monitoring/nvr-exporter/)

| Kind | Name | Namespace | Purpose |
|------|------|-----------|---------|
| Service | `loki-nvr-push` | `monitoring` | NodePort 30100 → Loki:3100 for NVR host log shipping |
| ScrapeConfig | `nvr-node-exporter` | `monitoring` | Static scrape of 10.1.10.11:9100 |
| PrometheusRule | `nvr-host-alerts` | `monitoring` | NvrHostDown alert rule |
| AlertmanagerConfig | `nvr-ha-notify` | `monitoring` | Route NvrHostDown → HA webhook |
| SealedSecret | `ha-alertmanager-token` | `monitoring` | HA long-lived token for webhook auth |

### New ArgoCD Application

| Field | Value |
|-------|-------|
| Name | `monitoring-nvr` |
| Source path | `manifests/monitoring/nvr-exporter` |
| Destination namespace | `monitoring` |
| Sync policy | automated, prune, selfHeal |

---

## Host-Side Resources (NVR host at 10.1.10.11)

| Component | Install method | Config path | Port |
|-----------|---------------|------------|------|
| `prometheus-node-exporter` | apt | `/etc/default/prometheus-node-exporter` | 9100 |
| Alloy | apt (Grafana repo) | `/etc/alloy/config.alloy` | — (push only) |

---

## New Firewall Rules (network-deploy.yml)

| Seq | Direction | Source | Destination | Port | Description |
|-----|-----------|--------|-------------|------|-------------|
| 203 | VLAN20→VLAN10 | 10.1.20.0/24 | 10.1.10.11 | 9100/TCP | Prometheus → NVR node_exporter |
| 204 | VLAN10→VLAN20 | 10.1.10.11 | 10.1.20.0/24 | 30100/TCP | NVR Alloy → Loki NodePort |
