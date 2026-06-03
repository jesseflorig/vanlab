# Research: WAX610 WiFi with Trusted and Guest VLANs

## Decision 1: OPNsense VLAN Interface Creation — Manual or Automated?

**Decision**: Manual via OPNsense web UI. Not automated via Ansible.

**Rationale**: The existing `network-deploy.yml` playbook does not create OPNsense VLAN interfaces — it assumes interfaces `opt1`–`opt5` already exist (this is documented in the playbook header comments). Adding VLAN interface creation via the `oxlorg.opnsense` REST API would require the `interfaces.vlan_settings` and `interfaces.assign` endpoints, which are complex and risk disrupting existing network connectivity if misapplied. The constitution already documents Netgear switches as "web UI only; not Ansible-manageable" — OPNsense VLAN interface creation falls in the same category: a one-time manual step that runs once and is then stable.

**Alternatives considered**:
- Automate via `oxlorg.opnsense` VLAN API: High implementation cost, high risk of connectivity disruption during development, marginal value for a one-time operation.
- Automate via OPNsense config XML import: Even higher complexity, not idempotent.

---

## Decision 2: Unbound DNS for VLAN50 — Configuration Required?

**Decision**: No Unbound DNS configuration changes needed. VLAN50 firewall rules must explicitly allow DNS queries (port 53 UDP/TCP) to the OPNsense VLAN50 gateway address.

**Rationale**: OPNsense Unbound by default listens on all configured interfaces (unless explicitly restricted). The existing `fleet1.lan` host overrides are global — they respond to any client that can reach the Unbound listener. The key requirement is that VLAN50 clients can reach OPNsense's DNS port on the VLAN50 interface gateway. This is a firewall rule, not a DNS configuration change. No new host overrides are needed; VLAN50 clients automatically receive the same `fleet1.lan` resolutions as wired LAN clients.

**Alternatives considered**:
- Configure Unbound to bind only to specific interfaces: Unnecessary complexity; the default "listen all" behavior is correct for this use case.
- Add a DNS-specific DNAT rule: Not needed since OPNsense itself is the DNS resolver for VLAN50.

---

## Decision 3: VLAN50 Firewall Rule Structure

**Decision**: Four rules in sequence for VLAN50 (`10.1.50.0/24`):
1. **Allow** VLAN50 → OPNsense VLAN50 gateway (10.1.50.1) port 53 UDP/TCP — DNS
2. **Allow** VLAN50 → 10.1.20.11 port 30443 TCP — Traefik HTTPS (post-DNAT)
3. **Allow** VLAN50 → 10.1.20.11 port 30883 TCP — Traefik MQTTS (post-DNAT)
4. **Block** VLAN50 → 10.1.0.0/8 — all other internal traffic
5. **Allow** VLAN50 → any — internet

**Rationale**: The existing DNAT rules in `network-deploy.yml` redirect traffic addressed to `10.1.20.11:443` → `:30443` and `:8883` → `:30883`. These DNAT rules apply at the OPNsense border regardless of source interface, so VLAN50 clients navigating to `https://grafana.fleet1.lan` (which resolves to `10.1.20.11`) will be correctly redirected. The firewall must allow the post-NAT destination ports (30443, 30883). The `10.1.1.50` (AP management) is on the LAN (`10.1.1.0/24`) which is covered by the "block all internal" rule — VLAN50 clients cannot reach it.

**Alternatives considered**:
- Allow VLAN50 → entire `10.1.20.0/24`: Too permissive; would expose cluster node IPs directly.
- Allow VLAN50 → `10.1.20.11:443` (pre-DNAT): May or may not work depending on OPNsense DNAT rule evaluation order; using post-NAT ports is more explicit and consistent with how other VLANs are handled.

---

## Decision 4: VLAN60 Firewall Rule Structure

**Decision**: Three rules for VLAN60 (`10.1.60.0/24`):
1. **Allow** VLAN60 → OPNsense VLAN60 gateway (10.1.60.1) port 53 UDP/TCP — DNS (public names only)
2. **Block** VLAN60 → 10.1.0.0/8 — all internal traffic
3. **Allow** VLAN60 → any — internet

**Rationale**: Placing the DNS allow rule before the RFC1918 block ensures guest clients can resolve public hostnames. Since Unbound will serve only public DNS for VLAN60 (no `fleet1.lan` overrides exposed to them), guest clients correctly resolve external names while being unable to reach any internal resource. DHCP traffic (UDP 67/68) is handled by OPNsense's DHCP server directly and does not require an explicit firewall rule.

**Alternatives considered**:
- Forward VLAN60 DNS to a public resolver (8.8.8.8) instead of OPNsense Unbound: Adds complexity without benefit; Unbound already handles recursive resolution for public names.
- Block VLAN60 → OPNsense gateway entirely (use separate DNS server): Unnecessary complexity.

---

## Decision 5: Switch Trunk Configuration Scope

**Decision**: Manual configuration on both GS308EPP and GS308T. Documented in quickstart.md, not automated.

**Rationale**: The constitution explicitly states Netgear switches are "web UI only; not Ansible-manageable." The trunk configuration is a one-time operation: add VLAN50 and VLAN60 as tagged VLANs on (a) the GS308EPP uplink port to GS308T, (b) the GS308T uplink port to/from GS308EPP, and (c) GS308EPP port 7 (WAX610 connection). These ports must also carry the existing tagged VLANs (VLAN10, VLAN20, VLAN40) on the uplink, which must not be disturbed.

**Alternatives considered**:
- SNMP-based switch configuration: GS308EPP supports SNMP read; write capability is limited and unreliable. Not a viable automation path.

---

## Decision 6: WAX610 Management IP Reassignment Timing

**Decision**: Reassign WAX610 management IP to `10.1.1.50` first (before SSID configuration), via the WAX610 web UI while connected to its current IP (`10.1.50.10`). After saving, reconnect at `10.1.1.50`.

**Rationale**: If SSID configuration is done first, the AP might serve DHCP-assigned IPs on VLAN50 before its management interface moves. Reconfiguring management IP first ensures all subsequent configuration is done from the stable LAN address. Requires the operator's laptop to be on the LAN or able to reach `10.1.50.10` at the time of configuration.

**Alternatives considered**:
- Configure SSIDs first, then move management IP: Risk of losing access to AP mid-configuration if the WAX610 reboots after SSID changes.
