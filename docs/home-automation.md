# Home Automation

The `home-automation` namespace runs four integrated services managed by ArgoCD. Configuration lives in `manifests/home-automation/` — Git is the source of truth.

## Services

| Service | URL | Access |
|---------|-----|--------|
| Home Assistant | `https://hass.fleet1.cloud` | Public via Cloudflare Tunnel |
| Node-RED | `https://node-red.fleet1.cloud` | Public via Cloudflare Tunnel |
| InfluxDB | `https://influxdb.fleet1.cloud` | Public via Cloudflare Tunnel |
| Mosquitto | `mqtts://10.1.20.11:8883` | LAN only |

## Architecture

```
manifests/home-automation/
├── prereqs/                    ← ArgoCD app: home-automation-prereqs
│   ├── namespace.yaml          (sync wave 0)
│   ├── ca-issuer.yaml          (sync wave 1-3) cert-manager CA chain for mTLS
│   ├── certificates.yaml       (sync wave 4)  TLS + mTLS certs
│   ├── config-extra.yaml       (sync wave 4)  Home Assistant packages ConfigMap
│   └── sealed-secrets.yaml     (sync wave 5)  encrypted secrets
│
├── apps/                       ← ArgoCD app: home-automation-apps
│   ├── mosquitto-app.yaml      ArgoCD Application → helmforgedev/mosquitto
│   ├── influxdb-app.yaml       ArgoCD Application → influxdata/influxdb2
│   ├── home-assistant-app.yaml ArgoCD Application → pajikos/home-assistant
│   └── node-red-app.yaml       ArgoCD Application → schwarzit/node-red
│
├── mosquitto-values.yaml
├── influxdb-values.yaml
├── home-assistant-values.yaml
└── node-red-values.yaml
```

Each `*-app.yaml` is a multi-source ArgoCD Application: one source is the upstream Helm chart repo, the second is this Gitea repo providing the values file.

## Integration Wiring

| From | To | Protocol | Auth |
|------|----|----------|------|
| Home Assistant | Mosquitto | MQTTS (8883) | mTLS client cert (`home-assistant-mqtt-client`) |
| Node-RED | Mosquitto | MQTTS (8883) | mTLS client cert (`node-red-mqtt-client`) |
| Home Assistant | InfluxDB | HTTP (8086) | Bearer token (`INFLUXDB_TOKEN` env var) |
| IoT devices | Mosquitto | MQTTS (8883) | mTLS client cert + password file |

Mosquitto is LAN-only (K3s ServiceLB at `10.1.20.11:8883`). Not routed through Traefik or Cloudflare.

The InfluxDB token and org ID are stored in the `home-assistant-influxdb` SealedSecret and injected as environment variables (`INFLUXDB_TOKEN`, `INFLUXDB_ORG_ID`). The `influxdb2.yaml` package reads them via `!env_var`.

## First-time Bootstrap

```bash
# 1. Fill in all home-automation secrets in group_vars/all.yml (see example.all.yml)

# 2. Deploy the full stack
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml

# 3. Get InfluxDB org ID — log in at https://influxdb.fleet1.cloud,
#    copy the hex UUID from the URL (/orgs/<hex-id>), set influxdb_org_id in group_vars/all.yml

# 4. Seal secrets
ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml

# 5. Commit sealed secrets
git add manifests/home-automation/prereqs/sealed-secrets.yaml
git commit -m "feat: add sealed secrets for home-automation stack"
git push gitea main

# 6. Register ArgoCD apps
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap
```

## Upgrading a Helm Chart

```bash
# Example: upgrade Mosquitto from 1.0.7 to 1.1.0
vim manifests/home-automation/apps/mosquitto-app.yaml   # change targetRevision
vim manifests/home-automation/mosquitto-values.yaml     # adjust values if needed
git commit -am "chore(mosquitto): upgrade chart to 1.1.0"
git push gitea main
# ArgoCD auto-syncs within 3 minutes
```

## Changing Helm Values

```bash
vim manifests/home-automation/home-assistant-values.yaml
git commit -am "feat(hass): bump image tag to 2025.4"
git push gitea main
```

## Mosquitto Client Certificates (mTLS)

Mosquitto enforces mTLS — every client must present a certificate signed by the `home-automation-ca` ClusterIssuer. Home Assistant and Node-RED receive their certs automatically via cert-manager Certificate objects in `prereqs/certificates.yaml`.

To issue a cert for an IoT device, add a Certificate object to `manifests/home-automation/prereqs/certificates.yaml` and let ArgoCD apply it. See `specs/016-home-automation-stack/quickstart.md` for VLAN-segmented IoT device setup.
