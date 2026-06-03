# Tasks: WAX610 WiFi with Trusted and Guest VLANs

**Input**: Design documents from `/specs/067-wifi-vlans/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, quickstart.md ✓

**Tests**: Not applicable — this is network infrastructure with manual verification steps.

**Organization**: Tasks are grouped by user story. Manual prerequisite steps (OPNsense, switches, WAX610) must complete before Ansible tasks run.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different systems, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup — Manual Infrastructure Prerequisites

**Purpose**: One-time manual configuration that must complete before any Ansible work. These steps cannot be automated (OPNsense VLAN interface creation, Netgear switch web UI, WAX610 web UI).

**⚠️ CRITICAL**: All Phase 1 tasks must complete before Phase 3+ Ansible tasks can be verified against a live network.

- [ ] T001 Create VLAN50 interface (opt5, 10.1.50.1/24) and VLAN60 interface (opt6, 10.1.60.1/24) on OPNsense via web UI per specs/067-wifi-vlans/quickstart.md Step 1
- [ ] T002 Enable DHCP servers for VLAN50 (pool 10.1.50.100-200) and VLAN60 (pool 10.1.60.100-200) on OPNsense via web UI per specs/067-wifi-vlans/quickstart.md Step 2
- [ ] T003 [P] Add VLAN50 and VLAN60 as tagged VLANs on GS308T uplink port (to/from GS308EPP) per specs/067-wifi-vlans/quickstart.md Step 3
- [ ] T004 [P] Add VLAN50 and VLAN60 as tagged VLANs on GS308EPP uplink (to GS308T) and port 7 (WAX610); set port 7 native VLAN to LAN per specs/067-wifi-vlans/quickstart.md Step 3
- [ ] T005 Reassign WAX610 management IP to 10.1.1.50, then create "fleet1" SSID (VLAN50, client isolation off) and "fleet1-guest" SSID (VLAN60, client isolation on) per specs/067-wifi-vlans/quickstart.md Step 4

**Checkpoint**: OPNsense VLAN interfaces are up with DHCP, switches trunk VLAN50/60, WAX610 broadcasts both SSIDs from 10.1.1.50

---

## Phase 2: Foundational — Codebase Orientation

**Purpose**: Read the existing network-deploy.yml to identify the correct insertion point for new firewall rules. This is a read-only step that informs all Phase 3+ tasks.

- [ ] T006 Read playbooks/network/network-deploy.yml firewall rules section to confirm highest existing sequence number and identify the insertion point for VLAN50 (seq 300) and VLAN60 (seq 310) rules

**Checkpoint**: Insertion point confirmed — VLAN50/60 rules can now be added without conflicts

---

## Phase 3: User Story 1 — Trusted WiFi Firewall Rules (Priority: P1) 🎯 MVP

**Goal**: VLAN50 clients can reach fleet1.lan services and internet; all other internal traffic is blocked

**Independent Test**: Connect a device to "fleet1" SSID → confirm IP in 10.1.50.100-200 → confirm `https://grafana.fleet1.lan` loads → confirm `ping 10.1.20.11` is blocked

- [X] T007 [US1] Add VLAN50 DNS allow rule (seq 300: source=VLAN50 net, dest=10.1.50.1, port=53, proto=UDP+TCP, action=allow, desc=vlan50-dns) to playbooks/network/network-deploy.yml firewall rules section
- [X] T008 [US1] Add VLAN50 Traefik HTTPS allow rule (seq 301: source=VLAN50 net, dest=10.1.20.11, port=30443, proto=TCP, action=allow, desc=vlan50-traefik-https) to playbooks/network/network-deploy.yml
- [X] T009 [US1] Add VLAN50 Traefik MQTTS allow rule (seq 302: source=VLAN50 net, dest=10.1.20.11, port=30883, proto=TCP, action=allow, desc=vlan50-traefik-mqtts) to playbooks/network/network-deploy.yml
- [X] T010 [US1] Add VLAN50 internal block rule (seq 303: source=VLAN50 net, dest=10.1.0.0/8, action=block, desc=vlan50-block-internal) to playbooks/network/network-deploy.yml
- [X] T011 [US1] Add VLAN50 internet allow rule (seq 304: source=VLAN50 net, dest=any, action=allow, desc=vlan50-internet) to playbooks/network/network-deploy.yml
- [X] T012 [US1] Dry-run network-deploy.yml with `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check` to verify VLAN50 rules parse without errors

**Checkpoint**: VLAN50 rules added and syntax-verified. After applying (Phase 6), trusted WiFi should be fully functional.

---

## Phase 4: User Story 2 — Guest WiFi Firewall Rules (Priority: P2)

**Goal**: VLAN60 clients can reach internet only; all RFC1918 space is blocked

**Independent Test**: Connect a device to "fleet1-guest" SSID → confirm IP in 10.1.60.100-200 → confirm `curl https://example.com` works → confirm `ping 10.1.1.1` is blocked

- [X] T013 [US2] Add VLAN60 DNS allow rule (seq 310: source=VLAN60 net, dest=10.1.60.1, port=53, proto=UDP+TCP, action=allow, desc=vlan60-dns) to playbooks/network/network-deploy.yml
- [X] T014 [US2] Add VLAN60 internal block rule (seq 311: source=VLAN60 net, dest=10.1.0.0/8, action=block, desc=vlan60-block-internal) to playbooks/network/network-deploy.yml
- [X] T015 [US2] Add VLAN60 internet allow rule (seq 312: source=VLAN60 net, dest=any, action=allow, desc=vlan60-internet) to playbooks/network/network-deploy.yml
- [X] T016 [US2] Dry-run network-deploy.yml with `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml --check` to verify VLAN60 rules parse without errors

**Checkpoint**: VLAN60 rules added and syntax-verified. After applying (Phase 6), guest WiFi should be fully isolated.

---

## Phase 5: User Story 3 — AP Management Isolation (Priority: P3)

**Goal**: WAX610 management UI reachable from wired LAN only; unreachable from both WiFi SSIDs

**Independent Test**: From wired LAN device, `curl http://10.1.1.50` responds. From "fleet1" SSID, `curl http://10.1.1.50` times out.

*Note: No new Ansible code required for this story — the VLAN50 seq 303 "block internal" rule (T010) and VLAN60 seq 311 "block internal" rule (T014) already prevent WiFi clients from reaching 10.1.1.50 on the LAN. AP management IP migration is covered by T005. This phase captures only the verification tasks.*

- [ ] T017 [US3] Verify WAX610 management UI is accessible at http://10.1.1.50 from a wired LAN device (manual check after T005)
- [ ] T018 [US3] Verify WAX610 management UI is NOT accessible from a device on "fleet1" SSID (manual check after Phase 6 apply)

**Checkpoint**: All three user stories are now implemented and verified independently.

---

## Phase 6: Polish & Deployment

**Purpose**: Apply changes to live OPNsense, run full verification, update documentation

- [X] T019 Apply network-deploy.yml to live OPNsense with `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml` (run after T001-T016 are complete)
- [ ] T020 Run full WiFi verification suite per specs/067-wifi-vlans/quickstart.md Step 6 (trusted WiFi access, guest isolation, AP management check)
- [ ] T021 [P] Update docs/networking.md VLAN table to add VLAN50 (10.1.50.0/24, Trusted WiFi) and VLAN60 (10.1.60.0/24, Guest WiFi) rows

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately; T003 and T004 can run in parallel (different switches)
- **Foundational (Phase 2 / T006)**: No dependencies — can run in parallel with Phase 1 (read-only)
- **US1 (Phase 3)**: Depends on T006 (know insertion point); T007-T011 are sequential (same file, rule order matters); T012 verifies
- **US2 (Phase 4)**: Depends on T006; T013-T015 sequential (same file); T016 verifies. Can be worked in parallel with Phase 3 if careful about file conflicts
- **US3 (Phase 5)**: T017 depends on T005; T018 depends on T019 (live apply)
- **Polish (Phase 6)**: T019 depends on T001-T005 (manual prereqs) + T007-T016 (rules added); T020 depends on T019; T021 is independent

### User Story Dependencies

- **US1 (P1)**: Requires T006 complete; no dependencies on US2/US3
- **US2 (P2)**: Requires T006 complete; no dependencies on US1/US3 (different rules, different seq range)
- **US3 (P3)**: Requires T005 (WAX610 IP move) + T010/T014 (block-internal rules applied via T019)

### Within Each User Story

- Firewall rules within a story are sequential (seq numbers must be applied in order for correct OPNsense rule evaluation)
- Dry-run (T012, T016) should be done after all rules for that story are added
- Apply (T019) must come after all rules from all stories are added and dry-run verified

### Parallel Opportunities

- T003 and T004 (switch config) can run in parallel — different physical switches
- T006 (read playbook) can run in parallel with Phase 1 manual steps
- T007-T011 (VLAN50 rules) and T013-T015 (VLAN60 rules) could technically be done in parallel by two people on the same file — but sequential is safer to avoid merge conflicts
- T021 (docs update) is always independent and can be done at any time

---

## Parallel Example: Phase 1 (Manual Prerequisites)

```bash
# T003 and T004 can happen simultaneously on different switches:
# Person/session A:
GS308T web UI → Add VLAN50, VLAN60 tagged on GS308EPP downlink port

# Person/session B:
GS308EPP web UI → Add VLAN50, VLAN60 tagged on GS308T uplink + port 7 (native: LAN)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Manual prerequisites (T001-T005)
2. Complete Phase 2: Read playbook (T006)
3. Complete Phase 3: Add VLAN50 rules (T007-T012)
4. Apply with T019, verify SC-001/SC-002 from spec
5. **STOP and VALIDATE**: Trusted WiFi works; guest SSID exists but has no firewall rules yet

### Incremental Delivery

1. Phase 1 + Phase 2 → infrastructure ready
2. Phase 3 (US1) → apply → trusted WiFi functional (MVP!)
3. Phase 4 (US2) → apply → guest WiFi isolated
4. Phase 5 (US3) → verify → AP management confirmed isolated
5. Phase 6 → full deployment + docs

---

## Notes

- [P] tasks = different systems/files, no dependencies on each other
- [US1/US2/US3] label maps task to specific user story for traceability
- Rule sequence numbers (300-304 for VLAN50, 310-312 for VLAN60) must not conflict with existing rules — T006 confirms this
- The `oxlorg.opnsense` firewall rule module uses `description` as the idempotency key — rule descriptions (e.g., `vlan50-dns`) must be unique and stable
- VLAN50 "block internal" rule (T010) at seq 303 also covers blocking access to 10.1.1.50 (WAX610 management) — no separate rule needed for US3
- Commit after T012 (VLAN50 rules verified) and again after T016 (VLAN60 rules verified), before applying with T019
