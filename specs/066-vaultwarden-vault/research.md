# Research: Vaultwarden Password Vault (066)

## R1 — Helm Chart Source and Version

**Decision**: Use the `guerzon/vaultwarden` community chart from `https://guerzon.github.io/vaultwarden`.

**Rationale**: Most widely maintained community chart for Vaultwarden; supports arm64; has `adminToken.existingSecret` support (required for SealedSecrets pattern). The official Vaultwarden project does not publish its own Helm chart.

**Pinned versions (verified 2026-05-22)**:
- Chart: `0.36.4` from `https://guerzon.github.io/vaultwarden`
- Image: `vaultwarden/server:1.36.0` (Docker Hub, multi-arch including arm64)

**Verified values key names** (from chart source `v0.36.4/charts/vaultwarden/values.yaml`):
- `signupsAllowed` — boolean, disables new registrations
- `storage.data.name` / `storage.data.size` / `storage.data.class` — PVC config (key is `class`, NOT `storageClass`)
- `adminToken.existingSecret` / `adminToken.existingSecretKey` — SealedSecret reference
- `ingress.enabled: false` — we use Traefik IngressRoute directly
- `image.tag` — image version tag
- Service port defaults to 80 (ClusterIP)

**Alternatives considered**: Helm chart from `keyporttech/vaultwarden` (less maintained, fewer stars). Rejected.

---

## R2 — arm64 Compatibility

**Decision**: `ghcr.io/dani-garcia/vaultwarden` is a multi-arch image with arm64 support.

**Rationale**: The Vaultwarden project explicitly builds for `linux/arm/v7`, `linux/arm64`, and `linux/amd64` on every release. No special configuration needed on CM5 nodes.

**Version pinning**: Pin to a specific semver tag (e.g., `1.32.7`) — not `latest`. Determine current stable at implementation time:
```bash
# Check current release on GitHub: https://github.com/dani-garcia/vaultwarden/releases
```

---

## R3 — TLS Strategy: No device-mTLS

**Decision**: Use standard Traefik `websecure` entrypoint with TLS via the fleet1-lan TLSStore (SNI-selected wildcard cert). Do NOT apply the `device-mtls` TLS option used by other fleet1.lan services.

**Rationale**: Vaultwarden is the recovery toolchain for device certificates and MFA seeds. If device-mTLS is required to reach the vault, losing the device cert also locks the admin out of the vault — a circular dependency. The vault must remain accessible from any Tailscale-connected device using the master password alone.

**Alternatives considered**: Apply device-mTLS for consistency with other fleet1.lan services. Rejected — circular recovery dependency outweighs consistency benefit.

**IngressRoute pattern** (no TLS options block):
```yaml
spec:
  entryPoints:
    - websecure
  tls: {}   # TLSStore provides wildcard cert via SNI; no options block = no device-mTLS
  routes:
    - match: Host(`vault.fleet1.lan`)
      kind: Rule
      services:
        - name: vaultwarden
          port: 80
```

---

## R4 — Admin Token Generation

**Decision**: Generate a random 64-character hex string as the admin token. Store in `group_vars/all.yml` as `vaultwarden_admin_token`. Seal via `seal-secrets.yml`.

**How to generate**:
```bash
openssl rand -hex 32   # produces 64-char hex string
```

**SealedSecret key name**: `admin-token` (matches `adminToken.existingSecretKey` in Helm values).

**Secret name**: `vaultwarden-admin-token` (matches `adminToken.existingSecret` in Helm values).

---

## R5 — DNS Entry Pattern

**Decision**: Add `- hostname: vault` to `fleet1_lan_traefik_dns_records` in `playbooks/network/network-deploy.yml`. Re-run the network playbook to register the unbound entry in OPNsense.

**Rationale**: This is the established pattern for all fleet1.lan Traefik-fronted services (argocd, minio, grafana, etc.). All hostnames in that list resolve to the Traefik node IP via OPNsense unbound.

---

## R6 — Disabling Registrations

**Decision**: Set `signupsAllowed: false` in `vaultwarden-values.yaml` from the start. Do NOT rely on disabling it after first login — the Helm values approach prevents any registration window.

**Rationale**: If the admin forgets to disable signups post-bootstrap, the vault is open to any user who can reach `vault.fleet1.lan`. Setting it in values means ArgoCD enforces it continuously.

**Post-bootstrap note**: The admin account is created via the web UI on first boot (before signups are locked). Because `signupsAllowed: false` is set in values from the start, the admin must create their account in the brief window before ArgoCD applies the Helm values — OR temporarily set `signupsAllowed: true` in values, deploy, register, then set back to `false`.

**Recommended flow**: Initial deploy with `signupsAllowed: true` → register account → set `signupsAllowed: false` → push update → ArgoCD re-syncs.

---

## R7 — Seal-Secrets Playbook Extension

**Decision**: Add a new task block to `playbooks/utilities/seal-secrets.yml` for the `vaultwarden-admin-token` secret, following the identical pattern used for `opnsense-exporter-credentials`.

**New group_vars/all.yml key**: `vaultwarden_admin_token`
**Namespace**: `vaultwarden`
**Secret name**: `vaultwarden-admin-token`
**Secret key**: `admin-token`
**Output file**: `manifests/vaultwarden/prereqs/sealed-secrets.yaml`
