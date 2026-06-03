# Feature Specification: WAX610 WiFi with Trusted and Guest VLANs

**Feature Branch**: `067-wifi-vlans`
**Created**: 2026-05-26
**Status**: Draft
**Input**: User description: "Add WiFi to the lab via a Netgear WAX610 AP. Two SSIDs: fleet1 on VLAN50 and fleet1-guest on VLAN60."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Trusted WiFi Access to Lab Services (Priority: P1)

As the lab administrator, I connect my personal devices (phone, laptop) to the "fleet1" WiFi network and have full access to lab services — dashboards, home automation, ArgoCD, Gitea — exactly as if I were plugged into the wired LAN, without needing a VPN or separate tunnel.

**Why this priority**: This is the primary motivation for adding WiFi — removing the need to be physically wired to access lab services from within the building.

**Independent Test**: Connect a device to "fleet1" SSID, verify it receives an IP in the 10.1.50.100–200 range, and confirm that `https://grafana.fleet1.lan`, `https://argocd.fleet1.lan`, and `https://hass.fleet1.lan` all load correctly. Verify the device cannot directly SSH to cluster nodes (10.1.20.x).

**Acceptance Scenarios**:

1. **Given** a device connects to "fleet1" SSID, **When** it requests an address, **Then** it receives an IP in `10.1.50.100–10.1.50.200` with OPNsense as the gateway and DNS resolver
2. **Given** a device on VLAN50, **When** it navigates to any `*.fleet1.lan` hostname, **Then** DNS resolves correctly and the service loads over HTTPS
3. **Given** a device on VLAN50, **When** it attempts to reach a cluster node IP directly (e.g., `10.1.20.11`), **Then** the connection is blocked
4. **Given** a device on VLAN50, **When** it accesses any public internet site, **Then** traffic routes out through OPNsense normally

---

### User Story 2 - Guest WiFi Internet Access (Priority: P2)

As a guest in the lab, I connect to the "fleet1-guest" WiFi network and get working internet access without any exposure to or visibility into the lab's internal infrastructure.

**Why this priority**: Guest WiFi is a standard hospitality feature, but isolation from the lab is a hard security requirement — guest devices must not be able to probe or reach any internal resources.

**Independent Test**: Connect a device to "fleet1-guest" SSID, verify it receives an IP in the 10.1.60.100–200 range, confirm internet access works, and confirm that no internal address (10.1.x.x) is reachable from the guest device.

**Acceptance Scenarios**:

1. **Given** a guest device connects to "fleet1-guest" SSID, **When** it requests an address, **Then** it receives an IP in `10.1.60.100–10.1.60.200` with OPNsense as the gateway
2. **Given** a guest device on VLAN60, **When** it attempts to reach any internal address (`10.1.0.0/8`), **Then** the connection is blocked by firewall
3. **Given** a guest device on VLAN60, **When** it resolves a public hostname (e.g., `google.com`), **Then** DNS resolution succeeds and the site loads
4. **Given** two guest devices on VLAN60, **When** one attempts to reach the other directly, **Then** the connection is blocked (client isolation)

---

### User Story 3 - AP Management from Wired LAN (Priority: P3)

As the lab administrator, I can reach the WAX610's management interface from any wired LAN device without being connected to the WiFi network itself, and the AP management interface is not reachable from WiFi clients.

**Why this priority**: Keeping AP management on the wired LAN prevents WiFi clients from accessing or disrupting the AP configuration.

**Independent Test**: From a wired LAN device, browse to `10.1.1.50` and confirm the WAX610 admin UI loads. From a device on "fleet1" SSID, confirm `10.1.1.50` is not reachable.

**Acceptance Scenarios**:

1. **Given** a wired device on the LAN (`10.1.1.0/24`), **When** it browses to `10.1.1.50`, **Then** the WAX610 management interface loads
2. **Given** a device connected to "fleet1" or "fleet1-guest" SSID, **When** it attempts to reach `10.1.1.50`, **Then** the connection is blocked

---

### Edge Cases

- What if the GS308EPP loses power — do VLAN trunk configurations survive a reboot? (Yes, Netgear switch config is persistent across power cycles.)
- What if a device on VLAN50 tries to reach MQTT (`10.1.20.11:30883`)? It is allowed via the Traefik NodePort, same as HTTPS.
- What if OPNsense DHCP is momentarily unreachable — do WiFi clients fail to associate? Standard DHCP retry behavior applies; no special handling needed.
- What if a device roams between "fleet1" and "fleet1-guest"? It receives a new DHCP lease on whichever VLAN it associates with — no session persistence across SSIDs.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The lab network MUST provide a wireless network named "fleet1" that places connected devices on subnet `10.1.50.0/24` with DHCP-assigned addresses in the `10.1.50.100–10.1.50.200` range
- **FR-002**: Devices on "fleet1" MUST be able to reach all `fleet1.lan` services (via Traefik entry point at `10.1.20.11:30443` and `:30883`) and public internet; all other internal subnets MUST be blocked
- **FR-003**: DNS resolution of `*.fleet1.lan` hostnames MUST work for devices on the "fleet1" network
- **FR-004**: The lab network MUST provide a wireless network named "fleet1-guest" that places connected devices on subnet `10.1.60.0/24` with DHCP-assigned addresses in the `10.1.60.100–10.1.60.200` range
- **FR-005**: Devices on "fleet1-guest" MUST have internet access only; all `10.1.0.0/8` address space MUST be blocked by firewall
- **FR-006**: "fleet1-guest" MUST enforce wireless client isolation — guest devices MUST NOT be able to communicate directly with each other
- **FR-007**: The WAX610 access point management interface MUST be reachable only from the wired LAN at address `10.1.1.50`; WiFi clients on either SSID MUST NOT be able to reach `10.1.1.50`
- **FR-008**: The physical switch trunk path (WAX610 → GS308EPP → GS308T → OPNsense) MUST carry VLAN50 and VLAN60 as tagged traffic with LAN as the native/untagged management VLAN
- **FR-009**: All OPNsense firewall rules and DNS configuration for VLAN50 and VLAN60 MUST be declared in the version-controlled network management playbook and be re-applicable idempotently

### Key Entities

- **VLAN50 (Trusted WiFi)**: Subnet `10.1.50.0/24`, SSID "fleet1", DHCP pool `.100–.200`, gateway and DNS via OPNsense, `fleet1.lan` hostnames resolve correctly
- **VLAN60 (Guest WiFi)**: Subnet `10.1.60.0/24`, SSID "fleet1-guest", DHCP pool `.100–.200`, internet-only, no internal hostname overrides
- **WAX610 AP**: Management IP `10.1.1.50` on LAN; hosts both SSIDs with VLAN tagging; connected to GS308EPP port 7 via PoE
- **GS308EPP**: PoE switch at `10.1.1.11`; port 7 trunk (untagged LAN + tagged VLAN50/60); uplink to GS308T carries VLAN50/60 tagged
- **GS308T**: Upstream switch; uplink to OPNsense carries VLAN50/60 tagged
- **OPNsense**: Router at `10.1.1.1`; VLAN50 and VLAN60 interfaces with DHCP servers, firewall rules, and DNS configuration

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A device connecting to "fleet1" receives a valid IP and can load any `fleet1.lan` service within 30 seconds of associating with the SSID
- **SC-002**: A device on "fleet1" cannot reach any internal IP outside the Traefik NodePort — 100% of direct connection attempts to cluster node IPs are blocked
- **SC-003**: A device connecting to "fleet1-guest" receives a valid IP and has working internet access within 30 seconds of associating
- **SC-004**: A device on "fleet1-guest" cannot reach any `10.1.x.x` address — 100% of attempted connections to internal IPs are blocked
- **SC-005**: The WAX610 management UI is reachable at `10.1.1.50` from a wired LAN device and unreachable from devices on either WiFi SSID
- **SC-006**: All firewall rules and DNS configuration are captured in the version-controlled network playbook and pass an idempotent re-run without errors or changes

## Assumptions

- OPNsense VLAN interface creation (VLAN50 and VLAN60 sub-interfaces with DHCP servers) is performed manually via the OPNsense web UI before running the Ansible network-deploy playbook
- Switch trunk port configuration (GS308EPP port 7 + uplink ports on both GS308EPP and GS308T) is performed manually via each switch's web UI
- WAX610 SSID configuration (SSID names, VLAN tagging per SSID, client isolation for guest SSID, management IP reassignment) is performed manually via the WAX610 web UI or InsightApp
- VLAN50 (`10.1.50.0/24`) is already advertised via the existing Tailscale subnet router — no Tailscale changes are required
- VLAN60 is intentionally excluded from Tailscale subnet routes; guest devices have no services worth reaching remotely
- The existing Unbound DNS host overrides for `fleet1.lan` services are extended to respond on the VLAN50 interface — no new hostnames need to be added
- WiFi passphrase selection for each SSID is out of scope for this spec and handled at AP configuration time
- WiFi channel selection and radio band (2.4GHz / 5GHz) configuration are handled automatically by the WAX610 and are out of scope
- The GS308EPP PoE switch at `10.1.1.11` is already powered on and reachable from the LAN management network
