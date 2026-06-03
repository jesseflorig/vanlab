# Quickstart: WAX610 WiFi with Trusted and Guest VLANs

This runbook covers all steps to bring up VLAN50 (trusted "fleet1") and VLAN60 (guest "fleet1-guest") WiFi. Steps 1–4 are manual web UI operations; Step 5 is the Ansible playbook run.

**Prerequisites**:
- Management laptop on wired LAN (`10.1.1.0/24`) or reachable via Tailscale
- WAX610 currently accessible at `10.1.50.10` (its current address before migration)
- OPNsense admin UI accessible at `https://10.1.1.1`
- GS308EPP admin UI accessible at `https://10.1.1.11`
- GS308T admin UI accessible (check current address in OPNsense ARP table if unknown)

---

## Step 1: OPNsense — Create VLAN Interfaces

**Access**: `https://10.1.1.1` → Interfaces → Other Types → VLANs

### Create VLAN50

1. Click **+ Add**
2. Parent interface: select the OPNsense interface that trunks to GS308T (likely `igb0` or the LAN trunk — check existing VLAN10/20/40 to confirm which parent they use)
3. VLAN tag: `50`
4. Description: `Trusted WiFi`
5. Save

### Create VLAN60

1. Click **+ Add**
2. Parent interface: same as above
3. VLAN tag: `60`
4. Description: `Guest WiFi`
5. Save

### Assign VLAN50 Interface

1. Interfaces → Assignments
2. Add the new VLAN50 interface → assign as `opt5` (or next available)
3. Save, then click the newly assigned interface name
4. Enable: checked
5. Description: `VLAN50`
6. IPv4 Configuration Type: Static IPv4
7. IPv4 address: `10.1.50.1 / 24`
8. Save → Apply Changes

### Assign VLAN60 Interface

1. Same as above but `opt6`, `10.1.60.1 / 24`, Description `VLAN60`

---

## Step 2: OPNsense — Configure DHCP

**Access**: `https://10.1.1.1` → Services → DHCPv4

### VLAN50 DHCP

1. Select the VLAN50 interface tab
2. Enable: checked
3. Range: From `10.1.50.100` To `10.1.50.200`
4. DNS servers: `10.1.50.1` (OPNsense itself — serves fleet1.lan overrides)
5. Gateway: `10.1.50.1`
6. Save

### VLAN60 DHCP

1. Select the VLAN60 interface tab
2. Enable: checked
3. Range: From `10.1.60.100` To `10.1.60.200`
4. DNS servers: `10.1.60.1`
5. Gateway: `10.1.60.1`
6. Save

---

## Step 3: Switch Trunk Configuration

**Important**: Add VLAN50 and VLAN60 to existing trunk ports. Do NOT remove existing tagged VLANs (VLAN10, VLAN20, VLAN40) from any port.

### GS308T — Uplink port to/from GS308EPP

1. Log into GS308T admin UI
2. Navigate to VLAN → 802.1Q → VLAN Configuration
3. For VLAN50: add the GS308EPP uplink port as **Tagged**
4. For VLAN60: add the GS308EPP uplink port as **Tagged**
5. Apply

### GS308EPP — Uplink port to GS308T

1. Log into GS308EPP admin UI at `https://10.1.1.11`
2. Navigate to VLAN → 802.1Q → VLAN Configuration
3. For VLAN50: add the GS308T uplink port as **Tagged**
4. For VLAN60: add the GS308T uplink port as **Tagged**
5. Apply

### GS308EPP — Port 7 (WAX610 connection)

1. For VLAN50: add port 7 as **Tagged**
2. For VLAN60: add port 7 as **Tagged**
3. For LAN (VLAN1): ensure port 7 is **Untagged** (native/management VLAN)
4. Apply

---

## Step 4: WAX610 Configuration

**Access**: While still at `10.1.50.10` from a device that can reach VLAN50, or plug a laptop directly into the WAX610's LAN port.

### 4a. Move Management IP to LAN

1. Log into WAX610 web UI at `http://10.1.50.10` (or current address)
2. Navigate to Management → IP Configuration (or Advanced → IP Settings)
3. Change IP from `10.1.50.10` to `10.1.1.50`
4. Subnet mask: `255.255.255.0`
5. Gateway: `10.1.1.1`
6. Save — the WAX610 will reboot or re-IP; reconnect at `http://10.1.1.50`

### 4b. Configure "fleet1" SSID (VLAN50)

1. Log into WAX610 at `http://10.1.1.50`
2. Navigate to Wireless → Basic → Add SSID (or edit existing)
3. SSID: `fleet1`
4. VLAN ID: `50`
5. Security: WPA2/WPA3-Personal, set passphrase
6. Client isolation: Disabled
7. Save

### 4c. Configure "fleet1-guest" SSID (VLAN60)

1. Add another SSID
2. SSID: `fleet1-guest`
3. VLAN ID: `60`
4. Security: WPA2-Personal, set passphrase
5. Client isolation: Enabled
6. Save → Apply

---

## Step 5: Ansible — Apply Firewall Rules and DNS

After Steps 1–4 are complete and OPNsense VLAN interfaces are up:

```bash
# Dry run first
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check

# Apply
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml
```

This adds the VLAN50 and VLAN60 firewall rules to OPNsense idempotently. No DNS changes are required (Unbound already serves fleet1.lan to all interfaces).

---

## Step 6: Verification

### Trusted WiFi (fleet1 / VLAN50)

```bash
# From a device connected to "fleet1" SSID:
# 1. Confirm IP in 10.1.50.100-200
ip addr show   # or check Settings → WiFi → IP address

# 2. Confirm fleet1.lan resolves
nslookup grafana.fleet1.lan

# 3. Confirm service access
curl -sk https://grafana.fleet1.lan | head -5

# 4. Confirm internal block (should time out / connection refused)
ping -c 3 10.1.20.11       # direct cluster node — should be blocked
ping -c 3 10.1.1.50        # AP management — should be blocked
```

### Guest WiFi (fleet1-guest / VLAN60)

```bash
# From a device connected to "fleet1-guest" SSID:
# 1. Confirm IP in 10.1.60.100-200
ip addr show

# 2. Confirm internet works
curl -s https://example.com | head -5

# 3. Confirm all internal blocked (should time out)
ping -c 3 10.1.1.1         # OPNsense — blocked
ping -c 3 10.1.20.11       # cluster node — blocked
ping -c 3 10.1.50.x        # VLAN50 device — blocked

# 4. Confirm fleet1.lan not reachable
curl -sk https://grafana.fleet1.lan  # should fail/time out
```

### AP Management Access

```bash
# From a wired LAN device:
curl -s http://10.1.1.50   # WAX610 admin — should respond

# From a device on "fleet1" SSID:
curl -s http://10.1.1.50   # should time out (blocked by firewall)
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| WiFi clients get no IP | DHCP not enabled on OPNsense VLAN interface, or trunk port not passing VLAN tags | Check OPNsense DHCP logs; verify switch trunk config |
| fleet1.lan not resolving from VLAN50 | DNS rule not allowing port 53 to OPNsense, or Ansible playbook not yet run | Run playbook; check OPNsense firewall logs |
| fleet1.lan services not loading | Traefik NodePort rule not in place | Run Ansible playbook; check rule seq 301 |
| Guest can reach internal IPs | Block rule (seq 311) not applied | Run Ansible playbook; verify rule order |
| Can't reach WAX610 at 10.1.1.50 | Management IP not yet moved, or switch port 7 native VLAN not set to LAN | Verify Step 4a; verify GS308EPP port 7 native VLAN |
