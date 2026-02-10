# 7. Deploy and Verify

[← Back to README](../README.md)

Trigger the deployment and verify everything is working.

---

## 7.1 Commit and Push

From your local repository:

```bash
git add .
git commit -m "Add Clawdbot deployment configuration"
git push origin main
```

---

## 7.2 Monitor Deployment

The CI/CD pipeline uses two chained workflows:

1. **Build Image** — builds the Docker image and pushes to GHCR
2. **Deploy to Server** — triggers automatically when Build Image succeeds; connects via Tailscale VPN, copies `docker-compose.yml`, pulls the new image, and starts the container

### Via GitHub UI

1. Go to your GitHub repository
2. Click **Actions** tab
3. Watch **Build Image** first, then **Deploy to Server**

### Via CLI

```bash
# List recent runs
gh run list --repo <owner>/<repo> --limit 5

# Watch a specific run
gh run watch <run-id> --repo <owner>/<repo>

# View logs of a failed run
gh run view <run-id> --repo <owner>/<repo> --log-failed
```

---

## 7.3 Verify Container Status

SSH to your server:

```bash
ssh <your-username>@<tailscale-ip>
```

Check container is running:

```bash
docker ps
```

Expected output:

```
CONTAINER ID   IMAGE                              STATUS                   NAMES
abc123...      ghcr.io/<user>/<repo>:latest       Up X minutes (healthy)   clawdbot
```

---

## 7.4 Check Logs

```bash
docker logs clawdbot -f
```

Look for:

```
[gateway] listening on ws://0.0.0.0:18789
```

Press `Ctrl+C` to exit.

---

## 7.5 Access the Gateway

The gateway binds to localhost on the host. Access via SSH tunnel.

From your **local machine**:

```bash
ssh -L 18789:127.0.0.1:18789 -i ~/.ssh/clawdbot-deploy deploy@<tailscale-ip> -N
```

Generate a dashboard URL with embedded token:

```bash
ssh -i ~/.ssh/clawdbot-deploy deploy@<tailscale-ip> \
  'docker exec clawdbot node dist/index.js dashboard --no-open'
```

Open the URL (with `?token=...`) in your browser. See [OpenClaw Configuration](08-openclaw-configuration.md#85-access-the-web-dashboard) for device pairing approval.

---

## 7.6 Configure Channels

See [OpenClaw Configuration — Channels](08-openclaw-configuration.md#86-configure-messaging-channels) for detailed channel setup.

Quick reference — SSH to server and run CLI commands inside the container:

```bash
# Interactive channel login
docker exec -it clawdbot node dist/index.js channels login

# Telegram
docker exec -it clawdbot node dist/index.js channels add --channel telegram --token "<bot-token>"

# Discord
docker exec -it clawdbot node dist/index.js channels add --channel discord --token "<bot-token>"

# WhatsApp (scan QR)
docker exec -it clawdbot node dist/index.js channels add --channel whatsapp
```

**Note**: In our custom Docker image, the `openclaw` CLI binary is not in `$PATH`. Use `node dist/index.js <command>` for all container commands.

---

## 7.7 Manual Trigger (Optional)

To redeploy without pushing code:

### Via GitHub UI

1. Go to **Actions** → **Deploy to Server**
2. Click **Run workflow**
3. Click **Run workflow**

### Via CLI

```bash
# Trigger deploy only (uses latest image already on GHCR)
gh workflow run "Deploy to Server" --repo <owner>/<repo>

# Trigger full rebuild + deploy
gh workflow run "Build Image" --repo <owner>/<repo>
```

---

## Troubleshooting

### "Missing config" / "State dir migration"

```
Missing config. Run `openclaw setup` or set gateway.mode=local (or pass --allow-unconfigured).
State dir migration skipped: target already exists (/home/node/.openclaw).
```

**Cause**: The Dockerfile or docker-compose.yml uses old `CLAWDBOT_*` names from before the project was renamed to OpenClaw.

**Fix**: Update Dockerfile directory names to `.openclaw` / `openclaw-workspace`, add `--allow-unconfigured` to CMD, and update docker-compose.yml environment variables to `OPENCLAW_*`. See [section 8.1](08-openclaw-configuration.md#81-fix-the-naming-mismatch).

### Permission denied: EACCES

```
EACCES: permission denied, mkdir '/home/node/.openclaw/canvas'
```

**Cause**: The data volume is owned by the `deploy` user (uid 1001) on the host, but the container runs as `node` (uid 1000).

**Fix**:

```bash
docker run --rm -v /opt/clawdbot/data:/data alpine chown -R 1000:1000 /data
```

### Gateway binds to loopback instead of LAN

The logs show `listening on ws://127.0.0.1:18789` instead of `ws://0.0.0.0:18789`, even though `OPENCLAW_GATEWAY_BIND=lan` is set.

**Cause**: The gateway refuses to bind to non-loopback addresses without authentication. The `openclaw.json` config must include `"gateway": { "auth": { "mode": "token" } }`.

**Fix**: Create or update `openclaw.json` with the auth section. See [section 8.2](08-openclaw-configuration.md#82-create-the-configuration-file).

### "Legacy config keys detected"

```
Config invalid — agent.model string was replaced by agents.defaults.model.primary
```

**Cause**: The OpenClaw config schema evolves between versions. The `agent.model` key was replaced.

**Fix**: Update `openclaw.json` to use `agents.defaults.model.primary` instead of `agent.model`. The gateway auto-migrates on load but warns until the file is fixed.

### Container not starting

Check logs:

```bash
docker compose -f /opt/clawdbot/docker-compose.yml logs
```

Common issues:
- Missing environment variables → Check `.env` file
- Permission errors → Verify `chown -R 1000:1000 /opt/clawdbot/data`

### Health check failing in deploy workflow

The deploy workflow runs a health check loop (12 retries, 5 seconds apart = 60 seconds total). The gateway can take 40–50 seconds to start inside the container.

```bash
# Check if container exists
docker ps -a

# Check detailed status
docker inspect clawdbot | grep -A 10 Health

# View recent logs
docker logs clawdbot --tail=100

# Run health check manually
docker exec clawdbot node dist/index.js health
```

If the container is running and healthy but the deploy workflow's health check fails, the issue is likely startup timing. The `start_period: 40s` in docker-compose.yml gives the container grace time for Docker's own health check, but the deploy workflow's check starts immediately.

### SSH connection timeout during deploy

**Cause**: The server's Tailscale `tag:server` is not applied, or the CI runner's `tag:ci` cannot reach `tag:server` via the Tailscale ACL.

**Fix**: Verify tags:

```bash
# On the server
tailscale status

# Apply tag if missing
sudo tailscale up --advertise-tags=tag:server
```

Check [Tailscale ACLs](https://login.tailscale.com/admin/acls) to ensure `tag:ci` can reach `tag:server`.

### SSH permission denied (publickey)

**Cause**: The `DEPLOY_SSH_KEY` GitHub secret contains the wrong private key, or the corresponding public key is not in the deploy user's `~/.ssh/authorized_keys`.

**Fix**:

```bash
# Update the secret
gh secret set DEPLOY_SSH_KEY < ~/.ssh/clawdbot-deploy

# Verify the public key on the server
ssh -i ~/.ssh/clawdbot-deploy deploy@<tailscale-ip> "cat ~/.ssh/authorized_keys"
```

### Can't pull image

Verify GHCR login works:

```bash
echo "<GHCR_DEPLOY_TOKEN>" | docker login ghcr.io -u <username> --password-stdin
docker pull ghcr.io/<user>/<repo>:latest
```

### Gateway unreachable via tunnel

Verify the container is binding correctly:

```bash
docker logs clawdbot 2>&1 | grep "listening on"
```

Should show `listening on ws://0.0.0.0:18789` (not `127.0.0.1`).

### "disconnected (1008): pairing required" in dashboard

**Cause**: The Control UI is treated as a new device that needs approval.

**Fix**:

```bash
docker exec clawdbot node dist/index.js devices list
docker exec clawdbot node dist/index.js devices approve <request-id>
```

### Channel won't connect

Check channel-specific logs:

```bash
docker logs clawdbot 2>&1 | grep -i telegram
docker logs clawdbot 2>&1 | grep -i discord
```

---

## Maintenance Commands

```bash
# View live logs
docker compose -f /opt/clawdbot/docker-compose.yml logs -f

# Restart container
docker compose -f /opt/clawdbot/docker-compose.yml restart

# Stop container
docker compose -f /opt/clawdbot/docker-compose.yml down

# Start container
docker compose -f /opt/clawdbot/docker-compose.yml up -d

# Manual image update
cd /opt/clawdbot
docker compose pull
docker compose up -d
docker image prune -f
```

---

## Backup and Restore

### Backup

```bash
cd /opt/clawdbot
tar -czf clawdbot-backup-$(date +%Y%m%d).tar.gz data/
```

### Restore

```bash
cd /opt/clawdbot
docker compose down
tar -xzf clawdbot-backup-YYYYMMDD.tar.gz
sudo chown -R 1000:1000 data/
docker compose up -d
```

---

## Complete Checklist

| Item | Status |
|------|--------|
| Code pushed to main | ☐ |
| Build job succeeded | ☐ |
| Deploy job succeeded | ☐ |
| Container running | ☐ |
| Health check passing | ☐ |
| Gateway accessible via tunnel | ☐ |
| Gateway token accepted | ☐ |
| Channels configured | ☐ |

---

## Next Steps

- [OpenClaw Configuration](08-openclaw-configuration.md) — configure the gateway, add an AI provider, connect channels
- Set up monitoring/alerts for container health
- Configure Tailscale Serve for easier gateway access
- Set up regular backups

---

[← Back to README](../README.md) | [Previous: Server Preparation](06-server-preparation.md) | [Next: OpenClaw Configuration](08-openclaw-configuration.md)
