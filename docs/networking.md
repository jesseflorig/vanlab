# Networking

Remote access, OPNsense management, and Cloudflare tunnel configuration.

## Remote Access

Remote access uses a two-layer approach:

- **Tailscale** — only `edge` and the management laptop are enrolled. Provides a persistent, authenticated tunnel into the lab from anywhere.
- **SSH ProxyJump** — cluster nodes and NVR are accessed by jumping through edge. No Tailscale on cluster nodes avoids boot-time network conflicts.

**Off-LAN:**
```bash
ssh edge-ts          # hop onto edge via Tailscale
ssh node1            # laptop → edge (Tailscale) → node1 (SSH config handles hops)
```

**Tailscale IPs**: Run `tailscale status` on any enrolled device to get current IPs.

**Re-deploying Tailscale on edge:**
```bash
ansible-playbook -i hosts.ini playbooks/edge/tailscale-deploy.yml --vault-password-file=<(cat ~/.vault_pass)
```
Generate a new auth key at `https://login.tailscale.com/admin/settings/keys` if re-enrolling.

## OPNsense

OPNsense (10.1.1.1) is managed via the `oxlorg.opnsense` REST API collection. Always run with `--check` first:

```bash
# Dry run
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check

# Apply
ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml
```

Firewall rules, DNAT, unbound DNS, and VLAN configuration are all declared in `playbooks/network/network-deploy.yml`.

## Exposing a New Service via Cloudflare Tunnel

Every new Traefik ingress needs a matching public hostname rule in Cloudflare Zero Trust before it's reachable externally.

1. **Traefik IngressRoute** — use the `websecure` entrypoint with the appropriate TLS secret.

2. **Cloudflare Zero Trust → Tunnels → Public Hostnames** — add a rule:
   - **Subdomain**: the new subdomain (e.g. `grafana`)
   - **Domain**: `fleet1.cloud`
   - **Service**: `https://10.1.20.11:30443`
   - **TLS → Origin Server Name**: the full hostname (e.g. `grafana.fleet1.cloud`)

   > Creating the public hostname rule auto-creates the Cloudflare DNS CNAME. Do **not** create the CNAME manually first — rule creation will fail if the DNS record already exists.
   >
   > The origin server name lets cloudflared send the correct SNI during the TLS handshake with Traefik, allowing the wildcard cert (`*.fleet1.cloud`) to verify cleanly. Do **not** use "No TLS Verify".

## Adding a fleet1.lan Hostname

Internal `.lan` services are served by Traefik using the `fleet1-lan-wildcard-tls` TLS store (SNI-selected). To add a new internal hostname:

1. Add a Traefik `IngressRoute` in the service's manifests directory with `tls: {}` and `Host(`<name>.fleet1.lan`)`.
2. Add an unbound DNS host override in `network-deploy.yml` pointing `<name>.fleet1.lan` to the Traefik NodePort IP (`10.1.20.11`).
3. Add a DNAT rule in `network-deploy.yml` if the service needs to be reachable from outside the cluster VLAN.

## VLAN Layout

| VLAN | Subnet | Purpose |
|------|--------|---------|
| LAN | 10.1.1.0/24 | Management / router |
| VLAN10 | 10.1.10.0/24 | Edge + NVR hosts |
| VLAN20 | 10.1.20.0/24 | K3s cluster nodes |
| VLAN40 | 10.1.40.0/24 | IoT cameras |
