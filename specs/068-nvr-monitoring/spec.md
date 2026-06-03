# Feature Specification: NVR Host Monitoring and Alerting

**Feature Branch**: `068-nvr-monitoring`
**Created**: 2026-06-03
**Status**: Draft
**Input**: User description: "Add monitoring for the NVR host (10.1.10.11, Intel NUC 11 running Frigate + Hailo-8 standalone). The host runs in a van on a LiFePO4 battery bank via a DC-DC buck converter and occasionally powers off unexpectedly. We need node_exporter, Prometheus scrape target, Alertmanager webhook to Home Assistant, and Alloy journald forwarding to Loki."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Know When the NVR Goes Offline (Priority: P1)

An operator receives a push notification on their phone within minutes of the NVR host losing power or becoming unreachable — without having to check Frigate manually. The notification arrives via Home Assistant.

**Why this priority**: The NVR currently powers off unexpectedly and the operator only finds out by chance. Proactive alerting is the core deliverable and delivers standalone value even without dashboards or log analysis.

**Independent Test**: Power off the NVR host manually and confirm a Home Assistant mobile push notification arrives within 5 minutes.

**Acceptance Scenarios**:

1. **Given** the NVR host is running normally, **When** it loses power or becomes unreachable, **Then** a push notification arrives on the operator's phone via Home Assistant within 5 minutes.
2. **Given** the NVR host has been offline and then recovers, **When** it becomes reachable again, **Then** a recovery notification is sent to Home Assistant.
3. **Given** the NVR host is intentionally shut down for maintenance, **When** it goes offline, **Then** the alert fires identically to an unexpected shutdown.

---

### User Story 2 - View NVR Host Health in Grafana (Priority: P2)

An operator can open Grafana and see current and historical metrics for the NVR host — CPU, memory, disk usage, uptime, and system load — alongside existing cluster node dashboards.

**Why this priority**: Metrics provide context for correlating shutdowns with load spikes (e.g., Hailo-8 inference bursts, NVMe writes) and confirm the host is healthy between incidents.

**Independent Test**: Open Grafana after provisioning and confirm the NVR host appears as a scrape target with CPU, memory, and uptime panels visible.

**Acceptance Scenarios**:

1. **Given** the NVR host is running, **When** an operator opens Grafana, **Then** NVR host metrics (CPU, memory, disk, uptime) are visible and updating in real time.
2. **Given** a past shutdown event occurred, **When** an operator reviews historical data, **Then** a gap in uptime is visible at the time of the incident.
3. **Given** the NVR host is under inference load, **When** an operator views the dashboard, **Then** CPU and memory usage reflect the actual load on the host.

---

### User Story 3 - Investigate Shutdown Root Cause via Logs (Priority: P3)

After an unexpected shutdown, an operator can query the log system in Grafana to see kernel and systemd log entries from the minutes before the host went offline — identifying whether the shutdown was triggered by a power event, kernel panic, OOM kill, or service crash.

**Why this priority**: Alerting tells you it happened; logs tell you why. This is the post-mortem capability that distinguishes a transient power issue from a recurring software fault.

**Independent Test**: After the NVR host has been running for 10+ minutes, query the log system filtered to the NVR host and confirm systemd and kernel logs are present with timestamps.

**Acceptance Scenarios**:

1. **Given** the NVR host is running, **When** an operator queries the log system filtered to the NVR host, **Then** kernel and systemd journal entries are present and queryable.
2. **Given** the NVR host experienced an unexpected shutdown, **When** an operator queries logs for the period before the shutdown, **Then** entries up to the moment of power loss are available.
3. **Given** a software service crashed before shutdown, **When** an operator queries logs, **Then** the crash error or service failure message is visible in the log stream.

---

### Edge Cases

- What happens when the NVR host is unreachable due to network issues rather than power loss? Alert fires the same — operator must distinguish via context (e.g., other VLAN10 devices still reachable).
- What happens if the Home Assistant webhook is unavailable when the alert fires? The alert is recorded in the alerting system; notification delivery depends on Home Assistant availability at that moment.
- What happens to buffered logs if the NVR loses power before they are shipped? Logs not yet forwarded are lost — this is acceptable; the priority is capturing entries up to the last possible moment before shutdown.
- What if the NVR host is offline when monitoring is first deployed? It appears as a down target immediately with no grace period required.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The NVR host MUST expose system metrics (CPU, memory, disk, network, uptime) for collection by the existing monitoring stack.
- **FR-002**: The existing metrics collector MUST scrape the NVR host on an interval of 60 seconds or less.
- **FR-003**: An alert MUST fire when the NVR host has been unreachable for 2 consecutive minutes.
- **FR-004**: The alert MUST deliver a push notification to the operator's phone via Home Assistant.
- **FR-005**: A recovery notification MUST be sent when the NVR host becomes reachable again after an outage.
- **FR-006**: NVR host kernel and systemd journal logs MUST be forwarded to the existing log aggregation system in near-real-time.
- **FR-007**: Logs MUST be queryable filtered by host (NVR) and by time range.
- **FR-008**: NVR host metrics MUST be visible in Grafana alongside existing cluster node dashboards.
- **FR-009**: All monitoring components on the NVR host MUST be provisioned by the existing NVR playbook — idempotent and version-controlled.
- **FR-010**: Monitoring components MUST start automatically on host boot and restart automatically on failure.

### Key Entities

- **NVR Host**: The standalone host at 10.1.10.11; the monitored target.
- **Host Metrics**: CPU usage, memory usage, disk usage (local NVMe + NFS mount), network I/O, system uptime, load average.
- **Shutdown Event**: Any period where the NVR host transitions from reachable to unreachable, regardless of cause.
- **Journal Log Entry**: A timestamped kernel or systemd log line forwarded from the NVR host to the central log store.
- **Offline Alert**: A notification fired when the NVR host has been unreachable beyond the configured threshold, delivered via Home Assistant.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operator receives a Home Assistant push notification within 5 minutes of the NVR host going offline.
- **SC-002**: NVR host metrics are visible in Grafana and update within 60 seconds of a change on the host.
- **SC-003**: Journal logs from the NVR host are queryable in Grafana within 60 seconds of being written on the host.
- **SC-004**: After an unexpected shutdown, an operator can identify the last log entry before power loss within 2 minutes of investigation.
- **SC-005**: Monitoring provisioning is fully automated — zero manual steps on the NVR host after running the playbook.

## Assumptions

- The existing Prometheus, Alertmanager, Loki, Alloy, and Grafana stack (specs 009, 014) is operational and reachable from the NVR host over VLAN10.
- The NVR host runs Ubuntu/Debian and has access to package repositories for installing monitoring agents.
- Home Assistant is running and the operator has the HA Companion app installed with push notifications enabled.
- The Home Assistant long-lived API token already used in the lab is available for Alertmanager webhook configuration.
- Existing firewall rules (spec 041) already permit traffic between the NVR host and the cluster — no new firewall changes needed.
- Log retention in the existing log store is sufficient — no new retention policy required.
- No Grafana dashboard JSON is committed to the repo — the operator creates panels manually or imports a community host metrics dashboard after provisioning.
