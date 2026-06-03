# Data Model: WAX610 WiFi with Trusted and Guest VLANs

This feature is purely network infrastructure — no database schema or Kubernetes resources. The "data model" describes the network object configuration that must exist across OPNsense, switches, and the AP after implementation.

## Network Interfaces (OPNsense)

### VLAN50 — Trusted WiFi

| Attribute | Value |
|-----------|-------|
| Interface name | `opt5` (next available after opt4/VLAN40) |
| VLAN tag | 50 |
| Parent interface | OPNsense LAN trunk interface |
| IPv4 address | `10.1.50.1/24` (gateway) |
| DHCP pool start | `10.1.50.100` |
| DHCP pool end | `10.1.50.200` |
| DNS server (DHCP) | `10.1.50.1` (OPNsense Unbound) |
| Default gateway (DHCP) | `10.1.50.1` |

### VLAN60 — Guest WiFi

| Attribute | Value |
|-----------|-------|
| Interface name | `opt6` (next available after opt5/VLAN50) |
| VLAN tag | 60 |
| Parent interface | OPNsense LAN trunk interface |
| IPv4 address | `10.1.60.1/24` (gateway) |
| DHCP pool start | `10.1.60.100` |
| DHCP pool end | `10.1.60.200` |
| DNS server (DHCP) | `10.1.60.1` (OPNsense Unbound, public names only) |
| Default gateway (DHCP) | `10.1.60.1` |

---

## Firewall Rules

Rules are applied in sequence. OPNsense evaluates top-to-bottom and stops at first match.

### VLAN50 Rules

| Seq | Source | Destination | Port | Protocol | Action | Description |
|-----|--------|-------------|------|----------|--------|-------------|
| 300 | VLAN50 net | 10.1.50.1 | 53 | UDP+TCP | Allow | vlan50-dns |
| 301 | VLAN50 net | 10.1.20.11 | 30443 | TCP | Allow | vlan50-traefik-https |
| 302 | VLAN50 net | 10.1.20.11 | 30883 | TCP | Allow | vlan50-traefik-mqtts |
| 303 | VLAN50 net | 10.1.0.0/8 | any | any | Block | vlan50-block-internal |
| 304 | VLAN50 net | any | any | any | Allow | vlan50-internet |

### VLAN60 Rules

| Seq | Source | Destination | Port | Protocol | Action | Description |
|-----|--------|-------------|------|----------|--------|-------------|
| 310 | VLAN60 net | 10.1.60.1 | 53 | UDP+TCP | Allow | vlan60-dns |
| 311 | VLAN60 net | 10.1.0.0/8 | any | any | Block | vlan60-block-internal |
| 312 | VLAN60 net | any | any | any | Allow | vlan60-internet |

---

## Access Point Configuration (WAX610)

| Attribute | Value |
|-----------|-------|
| Management IP | `10.1.1.50` (static, LAN) |
| Management VLAN | Untagged (native LAN) |
| Connected to | GS308EPP port 7 |

### SSID: fleet1

| Attribute | Value |
|-----------|-------|
| SSID name | `fleet1` |
| VLAN | 50 (tagged) |
| Security | WPA2/WPA3 (passphrase set at config time) |
| Client isolation | Disabled (trusted clients may reach each other) |

### SSID: fleet1-guest

| Attribute | Value |
|-----------|-------|
| SSID name | `fleet1-guest` |
| VLAN | 60 (tagged) |
| Security | WPA2 (passphrase set at config time) |
| Client isolation | Enabled (guests cannot reach each other) |

---

## Switch Trunk Ports

### GS308EPP — Port 7 (WAX610 connection)

| Attribute | Value |
|-----------|-------|
| Port mode | Trunk |
| Native (untagged) VLAN | LAN (VLAN1) |
| Tagged VLANs | VLAN50, VLAN60 |

### GS308EPP — Uplink to GS308T

| Attribute | Value |
|-----------|-------|
| Port mode | Trunk (existing) |
| Additional tagged VLANs | Add VLAN50, VLAN60 to existing tagged set |
| Existing tagged VLANs | VLAN10, VLAN20, VLAN40 (must not be disturbed) |

### GS308T — Downlink from GS308EPP

| Attribute | Value |
|-----------|-------|
| Port mode | Trunk (existing) |
| Additional tagged VLANs | Add VLAN50, VLAN60 to existing tagged set |
| Existing tagged VLANs | VLAN10, VLAN20, VLAN40 (must not be disturbed) |

---

## Tailscale Subnet Routes (no change)

| Subnet | Status |
|--------|--------|
| `10.1.50.0/24` | Already advertised — no change |
| `10.1.60.0/24` | Intentionally excluded — no change |
