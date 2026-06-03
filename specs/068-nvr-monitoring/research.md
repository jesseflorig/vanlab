# Research: NVR Host Monitoring and Alerting

**Branch**: `068-nvr-monitoring` | **Date**: 2026-06-03

---

## Decision 1: node_exporter Installation Method

**Decision**: Install `prometheus-node-exporter` via apt (Ubuntu package).

**Rationale**: The apt package auto-configures a systemd unit (`prometheus-node-exporter.service`), handles the daemon user, and is idempotent via Ansible's `apt` module. The NVR host already uses apt for Docker, so no new package sources needed. Binary download alternatives (GitHub release) add SHA verification complexity and break on arm64 vs amd64 differences.

**Alternatives considered**:
- Downloading binary from GitHub releases: more control over version pinning but requires arch detection and SHA verification
- Running node_exporter as a Docker container: adds Docker networking complexity when the host already runs Frigate in Docker; port conflicts possible

**Scrape port**: Default `9100/tcp`. No configuration change needed — the apt package default is correct.

---

## Decision 2: Prometheus Scrape Target Pattern

**Decision**: Use the `ScrapeConfig` CRD (monitoring.coreos.com/v1alpha1) with a static config targeting `10.1.10.11:9100`.

**Rationale**: This is already the established pattern for the OPNsense exporter (`manifests/monitoring/exporter/scrapeconfig.yaml`). The `ScrapeConfig` CRD is discovered by the Prometheus Operator and managed by ArgoCD — no changes to the kube-prometheus-stack Helm values needed.

**Label requirement**: The ScrapeConfig must have `release: kube-prometheus-stack` label for the Prometheus Operator to discover it.

**New firewall rule needed**: Prometheus pods run on VLAN20 (10.1.20.0/24) and must reach the NVR host (10.1.10.11) on port 9100. Rule added to `network-deploy.yml` (seq 203).

---

## Decision 3: Alertmanager Alert + Home Assistant Webhook

**Decision**: Use `PrometheusRule` CRD for the alert definition (`up{job="nvr-node-exporter"} == 0` for 2m) and `AlertmanagerConfig` CRD for the receiver/route pointing to the HA REST API webhook.

**Rationale**: The `PrometheusRule` CRD pattern is already used for Longhorn backup alerts (`manifests/longhorn-backup/prometheus-rules.yaml`). The `AlertmanagerConfig` CRD routes specific alert labels to a specific receiver without modifying the global Alertmanager configuration — correct for adding a single targeted notification path.

**HA webhook endpoint**: `http://home-assistant.home-automation.svc.cluster.local:8080/api/services/notify/notify`
- Alertmanager sends a POST with `{"message": "...", "title": "..."}` payload
- The HA `notify.notify` service forwards to all configured notification platforms including the mobile app
- Operator must confirm their HA mobile app notify service name; `notify.notify` is the safe default

**HA token**: Stored as a SealedSecret in the `monitoring` namespace, referenced by the `AlertmanagerConfig` via `authorization.credentials`. The existing long-lived token (named "ansible", expires 2036) is used.

**Alternatives considered**:
- Modifying global Alertmanager config in kube-prometheus-stack Helm values: requires re-running the services-deploy playbook and risks overwriting existing config on future runs
- Email via Alertmanager: requires SMTP setup; HA push notification is more immediate and is already the operator's primary notification channel

---

## Decision 4: Log Shipping — Alloy Installation and Loki Endpoint

**Decision**: Install Alloy as a systemd service on the NVR host (not in K8s) via the Grafana APT repository. Ship journald to Loki using a dedicated NodePort Kubernetes Service on port 30100.

**Rationale**: Alloy has official apt packages for amd64/arm64 Ubuntu. The existing Alloy DaemonSet is K8s-native (ships pod+journal logs from cluster nodes) and cannot be reused for an external host. A standalone Alloy binary is the correct pattern for non-cluster hosts.

**Loki endpoint from NVR host**: The existing Loki service is ClusterIP only (`loki.monitoring.svc.cluster.local:3100`), unreachable from outside the cluster. A dedicated NodePort Service (`loki-nvr-push`) on port 30100 is added to `manifests/monitoring/nvr-exporter/`, exposing Loki's push API on every cluster node at `10.1.20.11:30100`. The NVR host connects to `http://10.1.20.11:30100/loki/api/v1/push`.

**Firewall rule needed**: NVR (10.1.10.11) → cluster (10.1.20.0/24) port 30100. Rule added to `network-deploy.yml` (seq 204).

**Principle VI exception**: This path crosses the VLAN10→VLAN20 boundary over HTTP (unencrypted). This is accepted for the same reason NFS (seq 202) is accepted: both VLANs are internal and trusted, the data (system logs) is not user-sensitive, and adding TLS would require either a Loki auth token infrastructure or an Authentik bypass that exceeds the scope of this feature.

**Alloy config for NVR**: Stripped-down version of the cluster Alloy config — journald only (no Kubernetes pod discovery). Labels: `job="nvr-host"`, `host="nvr-host"`.

**Alternatives considered**:
- Using `loki.fleet1.lan` HTTPS with a bearer token: Authentik forward auth blocks non-browser clients; adding a bypass path requires Traefik middleware changes that are out of scope
- Using syslog forwarding: Loki has a syslog source but requires additional configuration and lacks journald structured fields (unit name, priority)

---

## Decision 5: ArgoCD Application for NVR Monitoring Manifests

**Decision**: Add a new ArgoCD application `monitoring-nvr` pointing to `manifests/monitoring/nvr-exporter/`. Register in `group_vars/all.yml` `argocd_apps` list.

**Rationale**: The existing `monitoring-apps` application syncs only `manifests/monitoring/exporter/` (the OPNsense exporter). Adding NVR manifests there would mix unrelated concerns. A separate application provides independent sync status and rollback.

**Manifests in `manifests/monitoring/nvr-exporter/`**:
- `loki-nodeport-service.yaml` — NodePort Service for Loki push
- `scrapeconfig.yaml` — Prometheus scrape target for NVR node_exporter
- `prometheusrule.yaml` — alert rule: NVR host down for 2+ minutes
- `alertmanagerconfig.yaml` — receiver routing to HA webhook
- `sealed-secrets.yaml` — SealedSecret containing HA long-lived token

---

## Decision 6: NVR Role Structure

**Decision**: Add a new task file `roles/nvr/tasks/monitoring.yml` with tag `monitoring`, imported from `main.yml`. Add corresponding templates and defaults.

**Rationale**: Follows the existing nvr role tag-based routing pattern (host-setup, hailo, frigate-config, etc.). The `--tags monitoring` flag allows running just the monitoring tasks on an already-provisioned NVR host without re-running the full provisioning playbook.

**New files in nvr role**:
- `roles/nvr/tasks/monitoring.yml`
- `roles/nvr/templates/alloy-nvr.config.j2`
- `roles/nvr/defaults/main.yml` additions: `nvr_loki_push_url`, `nvr_node_exporter_port: 9100`
