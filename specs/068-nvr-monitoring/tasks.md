---
description: "Task list for NVR Host Monitoring and Alerting"
---

# Tasks: NVR Host Monitoring and Alerting

**Input**: Design documents from `/specs/068-nvr-monitoring/`
**Branch**: `068-nvr-monitoring`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, quickstart.md ✓

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths are included in all descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directory structure and scaffolding that all subsequent tasks depend on.

- [X] T001 Create directory `manifests/monitoring/nvr-exporter/` for cluster-side resources
- [X] T002 [P] Add `ha_alertmanager_token` placeholder to `group_vars/example.all.yml` with comment referencing the HA long-lived token
- [X] T003 [P] Add `nvr_loki_push_url` and `nvr_node_exporter_port` defaults to `roles/nvr/defaults/main.yml`

**Checkpoint**: Directory scaffold ready; all subsequent tasks can proceed

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Firewall rules that allow metrics scraping and log shipping to work. Both user story implementations depend on this.

- [X] T004 Add OPNsense firewall rule seq 206 (VLAN20→VLAN10 port 9100) to `playbooks/network/network-deploy.yml` — permits Prometheus → NVR node_exporter (seq 203+204 were already taken)
- [X] T005 [P] Add OPNsense firewall rule seq 207 (VLAN10→VLAN20 port 30100) to `playbooks/network/network-deploy.yml` — permits NVR Alloy → Loki NodePort
- [ ] T006 Run `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml` to apply firewall rules

**Checkpoint**: Firewall rules applied — traffic between NVR host and cluster is permitted on required ports

---

## Phase 3: User Story 1 — Know When the NVR Goes Offline (Priority: P1) 🎯 MVP

**Goal**: Operator receives a Home Assistant push notification within 5 minutes of the NVR host going offline or recovering.

**Independent Test**: Stop `prometheus-node-exporter` on the NVR host; confirm HA mobile push notification arrives within 5 minutes. Re-start service; confirm recovery notification arrives.

### Implementation for User Story 1

- [X] T007 [P] [US1] Create `manifests/monitoring/nvr-exporter/scrapeconfig.yaml` — `ScrapeConfig` (monitoring.coreos.com/v1alpha1) with static target `10.1.10.11:9100`, job `nvr-node-exporter`, scrapeInterval `60s`, label `release: kube-prometheus-stack`
- [X] T008 [P] [US1] Create `manifests/monitoring/nvr-exporter/prometheusrule.yaml` — `PrometheusRule` (monitoring.coreos.com/v1) with alert `NvrHostDown`: expr `up{job="nvr-node-exporter"} == 0`, for `2m`, severity `critical`, label `release: kube-prometheus-stack`
- [X] T009 [US1] Create `manifests/monitoring/nvr-exporter/alertmanagerconfig.yaml` — `AlertmanagerConfig` (monitoring.coreos.com/v1alpha1) with receiver `ha-nvr-notify` (HA webhook URL `http://home-assistant.home-automation.svc.cluster.local:8080/api/services/notify/notify`, bearer auth from secret `ha-alertmanager-token`), route matching `alertname: NvrHostDown`, repeatInterval `1h`, groupWait `30s`
- [X] T010 [US1] Create `manifests/monitoring/nvr-exporter/sealed-secrets.yaml` — placeholder with generation instructions; add `ha_alertmanager_token: ""` to `group_vars/all.yml`; add `nvr-monitoring` play to `playbooks/utilities/seal-secrets.yml`
- [X] T011 [US1] Add `monitoring-nvr` ArgoCD application entry to `argocd_apps` list in `group_vars/all.yml` — source `gitadmin/vanlab.git`, path `manifests/monitoring/nvr-exporter`, namespace `monitoring`, revision `main`
- [X] T012 [US1] Create `roles/nvr/tasks/monitoring.yml` — Grafana APT repo, install `prometheus-node-exporter` + `alloy` via apt, deploy Alloy config template, enable+start both services
- [X] T013 [US1] Add monitoring task import to `roles/nvr/tasks/main.yml` — `ansible.builtin.import_tasks: monitoring.yml` with `tags: monitoring`
- [ ] T014 [US1] Run `ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags monitoring --check` then apply to install node_exporter on NVR host (depends on T012, T013)

**Checkpoint**: node_exporter running on NVR host; ScrapeConfig, PrometheusRule, AlertmanagerConfig manifests written; ArgoCD app entry added. After sealing the secret and syncing ArgoCD, the offline alert pipeline is complete.

---

## Phase 4: User Story 2 — View NVR Host Health in Grafana (Priority: P2)

**Goal**: Operator can open Grafana and see NVR host CPU, memory, disk, uptime, and load metrics updating in real time.

**Independent Test**: Open Grafana → Explore → Prometheus; query `up{job="nvr-node-exporter"}` — should return 1. Import community dashboard 1860, filter by instance `10.1.10.11:9100`, confirm CPU/memory/disk/uptime panels are populated.

**Note**: US2 reuses the ScrapeConfig from US1 (T007). No new Kubernetes resources are needed — Grafana reads from the existing Prometheus store once scraping is working. This phase validates end-to-end metric visibility.

### Implementation for User Story 2

- [ ] T015 [US2] Verify Prometheus is scraping NVR host: `kubectl port-forward svc/prometheus-operated 9090 -n monitoring`, query `up{job="nvr-node-exporter"}` in Prometheus UI — depends on T007 being synced to cluster
- [ ] T016 [US2] Document Grafana dashboard import step in `specs/068-nvr-monitoring/quickstart.md` Step 4e (community dashboard 1860, filter instance `10.1.10.11:9100`) — no dashboard JSON committed to repo per project convention

**Checkpoint**: NVR metrics visible in Grafana; US1 + US2 are independently testable

---

## Phase 5: User Story 3 — Investigate Shutdown Root Cause via Logs (Priority: P3)

**Goal**: Operator can query Grafana/Loki for NVR host kernel and systemd journal entries filtered by `job="nvr-host"` and time range.

**Independent Test**: After NVR has been running 10+ minutes, query Loki in Grafana with `{job="nvr-host"}` — confirm kernel and systemd entries are present with timestamps.

### Implementation for User Story 3

- [X] T017 [P] [US3] Create `manifests/monitoring/nvr-exporter/loki-nodeport-service.yaml` — Kubernetes Service (type: NodePort) named `loki-nvr-push` in namespace `monitoring`, selector targeting existing Loki pod, port 3100 → nodePort 30100
- [X] T018 [US3] Create `roles/nvr/templates/alloy-nvr.config.j2` — Alloy config with `loki.source.journal` reading systemd journal, labels `job="nvr-host"` and `host="nvr-host"`, forwarding to `loki.write` component pointing to `{{ nvr_loki_push_url }}`
- [X] T019 [US3] Alloy install included in `roles/nvr/tasks/monitoring.yml` alongside node_exporter — Grafana APT repo, install alloy, template config, enable+start service, handler for restart on config change
- [ ] T020 [US3] Run `ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml --tags monitoring --check` then apply to install Alloy on NVR host (combined with T014)

**Checkpoint**: Alloy shipping journald to Loki NodePort; logs queryable in Grafana with `{job="nvr-host"}`; all three user stories are complete

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Wire everything together, validate the full pipeline, and confirm the checklist.

- [ ] T021 [P] Verify `manifests/monitoring/nvr-exporter/` contains all 5 required files: `loki-nodeport-service.yaml`, `scrapeconfig.yaml`, `prometheusrule.yaml`, `alertmanagerconfig.yaml`, `sealed-secrets.yaml`
- [ ] T022 Run `ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml` to generate populated `sealed-secrets.yaml` for `ha-alertmanager-token` (requires `ha_alertmanager_token` set in `group_vars/all.yml`)
- [ ] T023 Push branch, merge to main, confirm ArgoCD syncs `monitoring-nvr` application: `kubectl get application monitoring-nvr -n argocd` and `kubectl get scrapeconfig,prometheusrule,alertmanagerconfig,svc -n monitoring | grep nvr`
- [ ] T024 Run full quickstart.md verification sequence (Steps 4a–4e): node_exporter reachable, Prometheus scraping, logs in Loki, offline alert fires, Grafana dashboard visible
- [ ] T025 Mark spec tasks complete in `specs/068-nvr-monitoring/checklists/requirements.md`

**Checkpoint**: All three user stories verified end-to-end; feature complete

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately; T002 and T003 are parallel
- **Phase 2 (Foundational)**: Depends on Phase 1; T004 and T005 are parallel; T006 depends on both
- **Phase 3 (US1)**: Depends on Phase 2 (firewall seq 203 required for scraping); T007, T008 are parallel
- **Phase 4 (US2)**: Depends on T007 (ScrapeConfig) being synced to cluster — no new files, just validation
- **Phase 5 (US3)**: Depends on Phase 2 (firewall seq 204 required for Loki push); T017, T018 are parallel
- **Phase 6 (Polish)**: Depends on all user story phases complete

### User Story Dependencies

- **US1**: Depends on Phase 2 only — independently deliverable
- **US2**: Reuses US1 ScrapeConfig — cannot be validated before T007 is synced, but no new files to write
- **US3**: Depends on Phase 2 only — independently deliverable in parallel with US1

### Within Each User Story

- T007 (ScrapeConfig), T008 (PrometheusRule): independent, parallel
- T009 (AlertmanagerConfig): depends on understanding the secret name from T010 — write after T010
- T012 (monitoring.yml tasks): independent of cluster manifests; can write in parallel with T007–T011
- T018 (Alloy template), T017 (NodePort service): independent, parallel

### Parallel Opportunities

- T002 + T003 (Phase 1 parallel setup) can run together
- T004 + T005 (Phase 2 firewall rules) can run together
- T007 + T008 (ScrapeConfig + PrometheusRule) can run together
- T017 + T018 (Loki NodePort service + Alloy template) can run together
- T012 (node_exporter tasks) can be written in parallel with cluster manifests T007–T011

---

## Parallel Example: User Story 1

```bash
# These cluster manifest files can be written simultaneously (no shared state):
Task T007: manifests/monitoring/nvr-exporter/scrapeconfig.yaml
Task T008: manifests/monitoring/nvr-exporter/prometheusrule.yaml

# Then sequentially:
Task T009: manifests/monitoring/nvr-exporter/alertmanagerconfig.yaml
Task T010: manifests/monitoring/nvr-exporter/sealed-secrets.yaml + group_vars/all.yml ha_alertmanager_token

# In parallel with cluster manifests:
Task T012: roles/nvr/tasks/monitoring.yml (node_exporter install)
```

## Parallel Example: User Story 3

```bash
# These can run simultaneously:
Task T017: manifests/monitoring/nvr-exporter/loki-nodeport-service.yaml
Task T018: roles/nvr/templates/alloy-nvr.config.j2

# Then:
Task T019: add Alloy install tasks to roles/nvr/tasks/monitoring.yml
Task T020: apply playbook
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup — 3 tasks)
2. Complete Phase 2 (Foundational — 3 tasks including playbook run)
3. Complete Phase 3 (US1 — 8 tasks)
4. **STOP and VALIDATE**: Stop node_exporter on NVR host, confirm HA notification fires
5. US2 (dashboard validation) and US3 (log shipping) can wait if alerting is the core need

### Incremental Delivery

1. Setup + Foundational → firewall rules applied
2. US1 complete → alert pipeline ready; test offline notification (MVP!)
3. US2 complete → validate Grafana dashboard visibility
4. US3 complete → log shipping active; full observability stack

### One-Developer Sequential Order

T001 → T003 → T002 → T004 → T005 → T006 → T007 → T008 → T012 → T009 → T010 → T011 → T013 → T014 → T017 → T018 → T019 → T015 → T016 → T020 → T021 → T022 → T023 → T024 → T025

---

## Notes

- [P] tasks = different files, no shared state, safe to parallelize
- No test tasks generated — spec does not request TDD; verification is manual per quickstart.md
- `sealed-secrets.yaml` committed as a placeholder; real sealed content generated by `seal-secrets.yml` playbook (never commits plaintext token)
- Alloy journald config is a stripped-down version of the cluster DaemonSet config — no Kubernetes pod discovery, journald only
- `monitoring` tag on nvr role allows `--tags monitoring` re-runs on already-provisioned hosts without repeating full provisioning
