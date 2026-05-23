# Feature Specification: Authentik OIDC App Integration (Tier 1a)

**Feature Branch**: `064-authentik-oidc-apps`
**Created**: 2026-05-11
**Status**: Deployed — 2026-05-23
**Input**: User description: "Wire Tier 1a apps (Grafana, Gitea, ArgoCD) as OIDC clients of Authentik. OIDC is added alongside existing native auth, not replacing it — the native admin login stays valid as Tier 0 break-glass."

---

> ⚠️ **STATUS: NEEDS REVALIDATION BEFORE PLANNING**
>
> This spec was seeded from a grill-me session on 2026-05-11. It is **not** a ready-to-plan spec. Before invoking `/speckit.plan` or `/speckit.tasks`, run `/speckit.clarify` and confirm:
> - Is Authentik (spec 063) actually deployed and stable?
> - Are Grafana, Gitea, and ArgoCD still the right Tier 1a set? Have any of them moved to a different auth strategy in the meantime?
> - Are the group → role mappings still appropriate?
> - Has anything changed about the `admins`/`users` group model from spec 063?

---

## Clarifications

### Session 2026-05-22

- Q: Auto-create on first OIDC login or require manual pre-provisioning? → A: Auto-create for all three apps (Grafana, Gitea, ArgoCD)
- Q: ArgoCD OIDC via Dex federation or direct to Authentik? → A: Direct — remove Dex, configure ArgoCD to use Authentik as OIDC provider
- Q: Authentik hostname for OIDC discovery URLs — `auth.fleet1.lan` or `authentik.fleet1.lan`? → A: `authentik.fleet1.lan` (spec 063 deployed hostname; `auth.` was a stub typo)
- Q: One PR per app or bundled? → A: One PR per app — Grafana first, then Gitea, then ArgoCD
- Q: OIDC client secret — Authentik-generated (manual copy) or locally generated (sealed)? → A: Generate locally with `openssl rand -hex 32`, store in `group_vars/all.yml`, seal via `seal-secrets.yml`

---

## Captured Design Summary

**Purpose**: Add Authentik OIDC login as an *additional* sign-in option for Grafana, Gitea, and ArgoCD. Native admin login stays valid on all three as the Tier 0 break-glass path.

**Apps in scope**:

| App | OIDC role | Group mapping |
|---|---|---|
| Grafana | OIDC login + role from `groups` claim | `groups contains "admins"` → Admin; default → Viewer |
| Gitea | OIDC login for web UI | `groups contains "admins"` → site admin; default → regular user |
| ArgoCD | OIDC login + RBAC policy | `groups contains "admins"` → admin policy; default → readonly policy |

**Dependencies**:
- **Hard**: Spec 063 (Authentik IdP) must be deployed, MFA-enrolled, and stable.
- **Hard**: `admins` + `users` groups exist in Authentik with a custom scope mapping that emits the `groups` claim in OIDC tokens.

**Per-app gotchas to carry into planning**:

- **Gitea**: OIDC affects the **web UI only**. `git push`/`git pull` over HTTPS continues to use HTTP basic auth with personal access tokens; over SSH continues to use SSH keys. No change to git CLI workflow. Existing PATs remain valid. The site admin native account stays untouched.
- **ArgoCD**: Dex removed; ArgoCD configured to use Authentik directly as OIDC provider. OIDC login works for the web UI *and* the `argocd login` CLI flow (`argocd login --sso`). The bootstrap `admin` user remains valid — important for break-glass. ArgoCD RBAC policy (`argocd-rbac-cm`) needs an entry mapping the `admins` group to admin actions.
- **Grafana**: Map `role_attribute_path` JMESPath against the `groups` claim. Verify Grafana version supports the JMESPath syntax planned (older versions used different mechanisms).

**Per-app OIDC client config in Authentik**:
- Each app gets its own OIDC provider/client in Authentik (managed in blueprints, committed to Git).
- Redirect URIs: `https://<app>.fleet1.lan/<oidc-callback-path>`.
- Scopes: `openid profile email groups`.
- Client secret: stored in Sealed Secret on the app side.

**Out of scope (in this spec)**:
- Forward-auth apps (spec 065).
- Removing native auth on any Tier 1a app — native admin stays valid by design.
- SCIM provisioning / auto-create users on first OIDC login (Authentik default behavior may suffice; revalidate).

## Open Questions to Revalidate

1. **Auto-create on first login**: ✅ Auto-create local account on first OIDC login for all three apps (Grafana, Gitea, ArgoCD).
2. **Username conflicts**: If the OIDC `preferred_username` collides with an existing native account, what wins? (Usually the OIDC mapping wins on subsequent logins, but verify per app.)
3. **Token lifetime alignment**: Does the 7-day Authentik session (spec 063) need to match each app's session timeout, or are they independent?
4. **CLI auth for ArgoCD in scripts/CI**: If you run ArgoCD CLI in any automation, those flows usually use a service account token, not user OIDC. Confirm none of your automation breaks.
5. **Grafana role mapping syntax**: Test JMESPath against actual Authentik tokens — `role_attribute_path` rules are easy to get wrong silently (everyone ends up Viewer).
6. **ArgoCD OIDC strategy**: ✅ Remove Dex, configure ArgoCD to use Authentik directly as the OIDC provider. Dex adds no value when Authentik is a full OIDC provider.

## Known Gotchas to Carry into Planning

- OIDC `groups` claim is **opt-in** per OIDC client — Authentik only emits it if the configured scope includes the mapping. Forgetting this means everyone ends up in the "default" role.
- ArgoCD's `argocd-cm` and `argocd-rbac-cm` are two separate ConfigMaps; OIDC config goes in one, role mapping in the other. Common mistake.
- For Gitea OIDC, the discovery URL is `https://authentik.fleet1.lan/application/o/<slug>/.well-known/openid-configuration` — slug is set when the application is created in Authentik and is easy to mistype.

## Assumptions (revalidate)

- Spec 063 (Authentik IdP) has shipped and is stable.
- `admins` and `users` groups exist; current user is a member of `admins`.
- Custom OIDC scope mapping emits the `groups` claim.
- Each app stays on its existing `*.fleet1.lan` hostname; no domain changes.
- Native admin accounts on Grafana, Gitea, ArgoCD are retained per the Tier 0 break-glass model.
- Each app's OIDC client secret is generated locally (`openssl rand -hex 32`), stored in `group_vars/all.yml`, and sealed via the existing `seal-secrets.yml` playbook — same pattern as Vaultwarden and Authentik.
- One PR per app — Grafana, Gitea, ArgoCD each merged and validated independently. OIDC failures are easier to isolate app-at-a-time.
- Auto-create local account on first OIDC login is enabled for all three apps; no manual pre-provisioning required.
