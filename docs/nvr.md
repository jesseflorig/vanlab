# NVR — Frigate + Hailo-8

Dedicated NVR host at `10.1.10.11` running Frigate with Hailo-8 PCIe object detection. Event clips are stored on a Longhorn RWX volume (50Gi, NFS-mounted). Detection events are published to the MQTT broker for Home Assistant consumption.

See `specs/041-nvr-frigate-hailo/quickstart.md` for the full operator runbook.

## Integration Wiring

| From | To | Protocol | Auth |
|------|----|----------|------|
| Frigate | Mosquitto | MQTTS (30883) | Password auth + mTLS transport (`frigate-nvr` user) |
| Traefik | Frigate | HTTP (5000) | n/a — Traefik terminates TLS externally |
| Home Assistant | Frigate | HTTPS (frigate.fleet1.lan) | Frigate integration |

## First-time Provisioning (Two-Phase)

**Phase A** — provision host, install Hailo driver, render Frigate config:

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml \
  --tags host-setup,hailo,frigate-config
```

Then push the branch, merge via PR, and wait for ArgoCD to sync `manifests/frigate/`. Once the Longhorn share-manager pod is Running, obtain the NFS endpoint:

```bash
kubectl get svc -n longhorn-system -l longhorn.io/pvc-name=frigate-clips \
  -o jsonpath='{.items[0].spec.clusterIP}'
```

Set `nvr_longhorn_nfs_ip` and `nvr_longhorn_nfs_path` in `group_vars/all.yml`.

**Phase B** — configure NFS mount and start Frigate:

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml \
  --tags nfs-mount,frigate-service
```

## Re-provisioning

Safe to run without tags at any time:

```bash
ansible-playbook -i hosts.ini playbooks/nvr/nvr-provision.yml
```

## Cameras

Camera RTSP URLs are defined in `group_vars/all.yml` under `nvr_cameras`. Each camera has a main stream (record) and sub stream (detect). Object detection runs on the sub stream at 640×480 @ 5fps via the Hailo-8 accelerator.

Tracked objects: `person`, `car`, `truck`, `bicycle`, `dog`, `cat`.

## Storage

| Location | Purpose | Retention |
|----------|---------|-----------|
| `/var/lib/frigate/media` (local NVMe) | Continuous recordings | 7 days (motion mode) |
| Longhorn RWX PVC `frigate-clips` (50Gi) | Event clips + snapshots | 30 days (active objects) |

## Frigate Config

Managed by Ansible at `roles/nvr/templates/frigate-config.yml.j2`. Do not edit the config directly on the host — changes are overwritten on re-provision.

Key variables in `group_vars/all.yml`:

| Variable | Purpose |
|----------|---------|
| `nvr_mqtt_broker_host` | MQTT broker hostname |
| `nvr_mqtt_username` | Frigate MQTT username |
| `nvr_mqtt_password` | Frigate MQTT password |
| `nvr_recording_retain_days` | Continuous recording retention |
| `nvr_clips_retain_days` | Event clip retention |
| `nvr_longhorn_nfs_ip` | Longhorn NFS share IP |
| `nvr_longhorn_nfs_path` | Longhorn NFS share path |
