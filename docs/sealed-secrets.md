# Sealed Secrets

[Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) stores encrypted secret values safely in Git. The controller runs in `kube-system` and holds a private key only it can decrypt; the public key encrypts secrets locally.

## How It Works

```
group_vars/all.yml          seal-secrets.yml playbook         Git (safe to commit)
(plaintext, gitignored)  →  kubeseal encryption            →  SealedSecret YAML
                                                               (AES-256 encrypted)
                                         ↓ ArgoCD applies
                                    cluster decrypts
                                         ↓
                                    Kubernetes Secret
```

SealedSecrets are namespace-scoped — a secret sealed for `home-automation` on this cluster cannot be decrypted by any other cluster or namespace.

## Secrets Managed as SealedSecrets

| Secret | Namespace | Contents |
|--------|-----------|----------|
| `mosquitto-passwords` | `home-automation` | Mosquitto password file |
| `influxdb-auth` | `home-automation` | InfluxDB admin password + operator token |
| `home-assistant-influxdb` | `home-automation` | InfluxDB token + org ID for HA |
| `node-red-admin` | `home-automation` | Node-RED admin bcrypt hash + credential secret |

## Rotating a Secret

1. Update the value in `group_vars/all.yml`
2. Re-seal:
   ```bash
   ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml
   ```
3. Commit and push:
   ```bash
   git add manifests/home-automation/prereqs/sealed-secrets.yaml
   git commit -m "chore: rotate <secret-name>"
   git push gitea main
   ```
4. ArgoCD applies the new SealedSecret within 3 minutes. The controller decrypts it and updates the underlying Kubernetes Secret automatically.

## After a Cluster Rebuild

The controller generates a new key pair on rebuild — all existing SealedSecrets in Git are undecryptable until re-sealed:

```bash
# After services-deploy.yml completes (controller is running):
ansible-playbook -i hosts.ini playbooks/utilities/seal-secrets.yml
git add manifests/home-automation/prereqs/sealed-secrets.yaml
git commit -m "chore: re-seal secrets after cluster rebuild"
git push gitea main
```

## Backing Up the Controller Key

Back up the controller's private key before decommissioning the cluster if you want to restore existing SealedSecrets without re-sealing:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key-backup.yaml
# Store this file securely — it contains the private key
```

To restore on a new cluster:

```bash
kubectl apply -f sealed-secrets-key-backup.yaml
kubectl rollout restart deployment/sealed-secrets-controller -n kube-system
```
