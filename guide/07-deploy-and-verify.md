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

1. Go to your GitHub repository
2. Click **Actions** tab
3. Watch the **Build and Deploy Clawdbot** workflow

The workflow has two jobs:
- **build**: Creates the Docker image and pushes to GHCR
- **deploy**: SSHs to server and starts the container

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

The gateway binds to localhost. Access via SSH tunnel.

From your **local machine**:

```bash
ssh -L 18789:127.0.0.1:18789 <your-username>@<tailscale-ip>
```

Open in browser: http://127.0.0.1:18789

Enter your gateway token when prompted.

---

## 7.6 Configure Channels

SSH to server and run CLI commands inside the container:

```bash
# Interactive channel login
docker exec -it clawdbot clawdbot channels login
```

Or add specific channels:

```bash
# Telegram
docker exec -it clawdbot clawdbot channels add --channel telegram --token "<bot-token>"

# Discord
docker exec -it clawdbot clawdbot channels add --channel discord --token "<bot-token>"

# WhatsApp (scan QR)
docker exec -it clawdbot clawdbot channels add --channel whatsapp
```

---

## 7.7 Manual Trigger (Optional)

To redeploy without pushing code:

1. Go to **Actions** → **Build and Deploy Clawdbot**
2. Click **Run workflow**
3. Optionally specify a Clawdbot version
4. Click **Run workflow**

---

## Troubleshooting

### Container not starting

Check logs:

```bash
docker compose -f /opt/clawdbot/docker-compose.yml logs
```

Common issues:
- Missing environment variables → Check `.env` file
- Permission errors → Verify `chown -R 1000:1000 /opt/clawdbot/data`

### Health check failing

```bash
# Check if container exists
docker ps -a

# Check detailed status
docker inspect clawdbot | grep -A 10 Health

# View recent logs
docker logs clawdbot --tail=100
```

### Can't pull image

Verify GHCR login works:

```bash
echo "<GHCR_DEPLOY_TOKEN>" | docker login ghcr.io -u <username> --password-stdin
docker pull ghcr.io/<user>/<repo>:latest
```

### Gateway unreachable via tunnel

Verify container is binding correctly:

```bash
docker exec clawdbot netstat -tlnp
```

Should show port 18789 listening.

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

- Set up monitoring/alerts for container health
- Configure Tailscale Serve for easier gateway access
- Add additional channels as needed
- Set up regular backups

---

[← Back to README](../README.md) | [Previous: Server Preparation](06-server-preparation.md)
