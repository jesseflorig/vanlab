# Feature Specification: Authentik IdP Standup

**Feature Branch**: `063-authentik-idp`
**Created**: 2026-05-11
**Status**: Stub — captured from design session, not ready to plan
**Input**: User description: "Stand up Authentik as the cluster's SSO identity provider. No app integration yet — just a working IdP, MFA enrolled, observability wired, backups in place."

---

> ⚠️ **STATUS: NEEDS REVALIDATION BEFORE PLANNING**
>
> This spec was seeded from a grill-me session on 2026-05-11. It is **not** a ready-to-plan spec. By the time you return to this work, the Authentik Helm chart may have changed values structure, the design may have evolved, or a different SSO product (Pocket-ID, Zitadel, Kanidm) may now make more sense.
>
> Before invoking `/speckit.plan` or `/speckit.tasks`, run `/speckit.clarify` (or just re-read the assumptions below) and confirm:
> - Is Authentik still the chosen product?
> - Is the tier model (Tier 0 native-auth break-glass; Tier 1a OIDC; Tier 1b forward-auth) still desired?
> - Are the YubiKey hardware keys actually purchased and on hand?
> - Has the cookie domain decision (`*.fleet1.lan`) changed (e.g., consolidation onto `*.fleet1.cloud`)?
> - Has any in-flight or new spec changed the dependency graph?

---

## Captured Design Summary

**Purpose**: Deploy Authentik as the cluster's identity provider. This spec covers **the IdP only** — no app integration. Apps are onboarded in specs 064 (OIDC) and 065 (forward-auth).

**Goals**:
- Primary: (a) one login across services + (b) central MFA enforcement.
- Single user (admin) at standup; group model designed for future multi-user.

**Dependencies**:
- **Hard**: Spec 061 (Longhorn backup target via MinIO) must be in place before Authentik holds any meaningful state. **✅ Spec 061 is deployed as of 2026-05-16** — BackupTarget active, RecurringJobs live, SealedSecret decrypted, all 7 ArgoCD resources Synced+Healthy.
- **Soft**: Spec 059 (Tailscale) should be merged before Tier 1b forward-auth (spec 065) lands, so remote break-glass works.

**Tier A label for Authentik Postgres PVC**:
Once spec 063 is deployed, add the Authentik Postgres PVC to Tier A recurring backups by adding it to `playbooks/utilities/label-pvcs.yml` (named PVC or selector-discovered) and re-running the playbook. The PVC will be in the `authentik` namespace. Example entry to add to the `Label Tier A PVCs by name` loop:
```yaml
- { name: authentik-postgresql-0, namespace: authentik }
```
Or discover dynamically via selector `app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=authentik`. Re-run: `ansible-playbook playbooks/utilities/label-pvcs.yml`

**Topology**:
- Hostname: `auth.fleet1.lan` (LAN + Tailscale; not publicly exposed).
- TLS: existing fleet1.lan wildcard (spec 054).
- Cookie domain: `.fleet1.lan` — all protected apps must standardize on `*.fleet1.lan` hostnames.

**Deployment shape**:
- Official Authentik Helm chart, **pinned version** (not auto-sync on major bumps).
- ArgoCD-managed `Application`.
- Bundled Postgres + Redis subcharts (no external CNPG operator).
- Single replica everywhere (server, worker, Postgres, Redis).
- Embedded outpost (no separate Deployment).
- Bootstrap admin password via Sealed Secret.
- No SMTP configured.

**MFA**:
- 2× YubiKey enrolled as primary WebAuthn factors (single key = SPOF).
- TOTP secondary, seed stored in Vaultwarden.
- Recovery codes generated once → stored in Vaultwarden + a physical printed/written copy.
- MFA required on every login.
- **Important sequencing**: enroll YubiKeys on the bootstrap admin *before* enabling any MFA-required flow.

**Groups**:
- Two groups at standup: `admins` (you) and `users` (placeholder for future).
- Custom scope mapping configured so `groups` claim is emitted in OIDC tokens.

**Backup/DR**:
- Longhorn recurring backup on Authentik Postgres PVC (nightly snapshot, weekly backup to MinIO).
- `ak export_blueprint` weekly CronJob → PVC → periodically committed to vanlab repo.
- `pg_dump` skipped.
- Accepted DR posture: "Full DR = re-enroll YubiKeys via recovery code."

**Observability (all in this spec, not deferred)**:
- `ServiceMonitor` → kube-prometheus-stack.
- Loki log shipping via namespace labels.
- `PrometheusRule` alerts:
  - `AuthentikDown` (server pod unavailable >2min).
  - `AuthentikOutpostDown` (forward-auth outpost unavailable — critical, silently breaks Tier 1b apps).
  - `AuthentikLoginFailureSpike` (>10 failed logins in 5min from a single IP).
  - `AuthentikCertExpiring` (internal JWT signing cert <14 days to expiry).

**Session policy**:
- 7-day session.
- 7-day remember-me.
- MFA always required on re-auth.
- Immediate session revocation on user disable (verify default behavior).

**Out of scope (in this spec)**:
- Any app integration. No OIDC clients configured. No forward-auth providers. No proxy outposts pointing at apps.
- HA / multi-replica.
- SMTP / email flows.
- External Postgres (CNPG).
- Public exposure of `auth.fleet1.lan`.

## Open Questions to Revalidate

1. **Helm chart version**: Pin the current stable chart at planning time. Major version bumps need deliberate handling.
2. **Authentik feature evolution**: Has Authentik shipped any "managed flows" or default-policy changes that affect bootstrap?
3. **YubiKey ordering**: Has the 2× YubiKey purchase happened? If not, planning waits.
4. **Default flows**: Are the out-of-the-box flows (`default-authentication-flow`, etc.) still acceptable, or do they need customization for the MFA-always-required posture?
5. **Internal JWT cert**: Confirm Authentik's default token-signing cert lifetime and align the `AuthentikCertExpiring` alert threshold accordingly.
6. **Blueprint export workflow**: How are exported blueprints committed to Git? (Manual periodic commit? A bot? Just left on a PVC and committed at audit time?)

## Known Gotchas to Carry into Planning

- The bootstrap admin starts with no MFA. Enroll MFA *before* enabling any flow that requires it, or you lock yourself out on first config push.
- Authentik internal JWT signing cert lives in the DB. If you restore from a Longhorn backup older than the current outpost, the outpost may have a cached cert that doesn't match — symptom is silent 401s. Fix: restart the outpost. Document this in the DR runbook.
- Major Helm bumps require values-file review, not blind ArgoCD sync.

## Assumptions (revalidate)

- Specs 060 and 061 (MinIO + Longhorn backup target) have shipped.
- ArgoCD + Sealed Secrets remain the deployment pattern.
- Traefik + cert-manager + fleet1.lan wildcard provide ingress/TLS.
- Vaultwarden is available as the out-of-band secrets vault for TOTP seeds and recovery codes (Vaultwarden is **not** behind Authentik — it's part of the recovery toolchain).
- Tier 0 apps (ArgoCD, Gitea, Longhorn UI, K8s API) will *not* be put behind Authentik — they retain native auth as the break-glass path.
- No public/internet exposure of the Authentik endpoint.
