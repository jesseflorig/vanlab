# Feature Specification: Vaultwarden Password Vault

**Feature Branch**: `066-vaultwarden-vault`
**Created**: 2026-05-22
**Status**: Deployed
**Input**: User description: "Deploy Vaultwarden as the cluster's out-of-band password manager and secrets vault. Vaultwarden must NOT be behind Authentik — it's the recovery toolchain for MFA seeds, recovery codes, and break-glass credentials. It needs to be accessible even if Authentik is down. Single-user (admin only). Exposed on fleet1.lan via Traefik + the existing wildcard cert. Persistent storage via Longhorn. ArgoCD-managed. Sealed Secret for admin token. This is spec 066."

---

## User Scenarios & Testing

### User Story 1 - Access Vault During Authentik Outage (Priority: P1)

The admin needs to retrieve an MFA recovery code, TOTP seed, or break-glass credential when Authentik is unavailable (e.g., misconfigured flow, outpost down, DR scenario). Vaultwarden must be reachable independently of Authentik's health.

**Why this priority**: This is the core safety property. If Vaultwarden is ever gated by Authentik, a single-point failure locks the admin out of every recovery path simultaneously.

**Independent Test**: With Authentik pods scaled to zero, the admin can still reach `https://vault.fleet1.lan`, log in with the Vaultwarden master password, and read a stored credential.

**Acceptance Scenarios**:

1. **Given** Authentik is down (pods not running), **When** the admin navigates to `https://vault.fleet1.lan`, **Then** the Vaultwarden login page loads and credentials are accessible.
2. **Given** a valid master password, **When** the admin logs into Vaultwarden, **Then** stored items (TOTP seeds, recovery codes) are readable.

---

### User Story 2 - Initial Vault Setup and Admin Account Bootstrap (Priority: P2)

The admin bootstraps a fresh Vaultwarden instance: creates the single admin account, disables new registrations, and verifies the vault is ready to receive secrets.

**Why this priority**: Must be completed before spec 063 (Authentik) can proceed — the vault needs to exist before MFA enrollment.

**Independent Test**: After deployment, the admin registers one account, stores a test item, and confirms registrations are then disabled (a second registration attempt is rejected).

**Acceptance Scenarios**:

1. **Given** a fresh Vaultwarden deployment, **When** the admin visits the web UI and registers, **Then** an account is created successfully.
2. **Given** one account exists and signups are disabled, **When** a second registration is attempted, **Then** it is rejected.
3. **Given** the admin is logged in, **When** a credential item is saved, **Then** it persists across pod restarts (Longhorn PVC).

---

### User Story 3 - Vault Survives Pod Restart (Priority: P3)

Stored credentials are durable across Vaultwarden pod restarts, node reboots, and Longhorn failovers.

**Why this priority**: Loss of recovery codes from a pod restart would be catastrophic; durability is non-negotiable.

**Independent Test**: Store an item, delete the pod, wait for it to reschedule, confirm the item is still present.

**Acceptance Scenarios**:

1. **Given** items stored in the vault, **When** the Vaultwarden pod is deleted and rescheduled, **Then** all items are intact.
2. **Given** a Longhorn volume snapshot exists, **When** the PVC is restored to that snapshot, **Then** items from before the snapshot are accessible.

---

### Edge Cases

- What if the Longhorn PVC becomes unavailable? Vaultwarden pod fails to start; data is not lost (Longhorn replication). Resolve by recovering the volume.
- What if the admin forgets the master password? No recovery path exists — this is by design. The master password must be stored out-of-band on paper (it is the bottom of the trust chain).
- What if the Sealed Secret is rotated without redeploying? The admin token endpoint stops working; resolved by redeploying with the new Sealed Secret.
- What if `vault.fleet1.lan` DNS is not resolvable? The IngressRoute exists but the OPNsense unbound entry is missing — must be added the same way as other fleet1.lan services.

---

## Requirements

### Functional Requirements

- **FR-001**: Vaultwarden MUST be deployed as an ArgoCD-managed Application in a dedicated `vaultwarden` namespace.
- **FR-002**: Vaultwarden MUST NOT be protected by Authentik forward-auth or any Authentik middleware — it must remain reachable with only a master password, independent of Authentik's health.
- **FR-003**: Vaultwarden MUST be exposed at `https://vault.fleet1.lan` via a Traefik IngressRoute using the existing fleet1.lan wildcard TLS certificate.
- **FR-004**: Persistent data MUST be stored on a Longhorn PVC (`storageClassName: longhorn`, 1Gi) so vault contents survive pod restarts and node failures.
- **FR-005**: The Vaultwarden admin token MUST be stored as a Sealed Secret and injected as an environment variable — never committed to Git in plaintext.
- **FR-006**: New user registrations MUST be disabled after the single admin account is created (`SIGNUPS_ALLOWED=false`).
- **FR-007**: Vaultwarden MUST run as a single replica.
- **FR-008**: The Vaultwarden container image MUST be pinned to a specific version tag (not `latest`).
- **FR-009**: A DNS entry for `vault.fleet1.lan` MUST be added to OPNsense unbound as part of this spec.

### Key Entities

- **Vault**: The Vaultwarden instance — single Deployment, single PVC, single namespace.
- **Admin Account**: The one registered Bitwarden-compatible user account. Created manually post-deploy; registrations disabled immediately after.
- **Admin Token**: A secret token enabling access to the Vaultwarden `/admin` panel. Stored in a Sealed Secret; never in Git.
- **PVC**: Longhorn-backed persistent volume holding the SQLite database and attachments.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Vaultwarden web UI is reachable at `https://vault.fleet1.lan` within 60 seconds of ArgoCD sync completing.
- **SC-002**: Vaultwarden login page loads and credentials are accessible when Authentik pods are scaled to zero.
- **SC-003**: A credential stored in the vault is retrievable after the Vaultwarden pod is deleted and rescheduled (zero data loss across pod restarts).
- **SC-004**: ArgoCD reports the Vaultwarden Application as `Synced` and `Healthy` with no manual intervention after initial deploy.
- **SC-005**: A second account registration is rejected after the admin account is created and signups are disabled.

---

## Assumptions

- ArgoCD, Sealed Secrets controller, Longhorn, Traefik, and cert-manager with the fleet1.lan wildcard cert are all deployed and healthy (specs 005, 006, 054).
- No SMTP is configured — Vaultwarden email flows are out of scope. The vault is accessed via master password only.
- No Vaultwarden-native 2FA is configured — the vault is the bottom of the trust chain; adding MFA to it creates a circular dependency with its own recovery codes.
- The community Vaultwarden image (`ghcr.io/dani-garcia/vaultwarden`) is used.
- 1Gi PVC is sufficient for a single-user vault with text credentials and no large attachments.
- Longhorn backup of the Vaultwarden PVC is out of scope — the vault is the recovery toolchain, not a primary data store. The master password on paper is the DR path.
- Spec 063 (Authentik) is the downstream consumer and is blocked on this spec completing.

---

## Out of Scope

- HA / multi-replica Vaultwarden.
- SMTP / email notifications or 2FA-via-email.
- Vaultwarden-native TOTP or hardware key login (circular dependency with the recovery toolchain).
- Longhorn recurring backup of the Vaultwarden PVC.
- Putting Vaultwarden behind Authentik (explicitly prohibited — it must remain independently accessible).
