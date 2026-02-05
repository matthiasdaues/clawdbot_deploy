# 6. Server Deployment Preparation

[← Back to README](../README.md)

Prepare the server to receive deployments from GitHub Actions.

---

## 6.1 Create Deploy User

```bash
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG docker deploy
```

Create SSH directory:

```bash
sudo mkdir -p /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
sudo chown deploy:deploy /home/deploy/.ssh
```

---

## 6.2 Generate Deploy SSH Key

On your **local machine**:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/clawdbot-deploy -C "github-actions-deploy" -N ""
```

Display the public key:

```bash
cat ~/.ssh/clawdbot-deploy.pub
```

Add it to the server:

```bash
sudo tee /home/deploy/.ssh/authorized_keys << 'EOF'
<paste-your-public-key-here>
EOF

sudo chmod 600 /home/deploy/.ssh/authorized_keys
sudo chown deploy:deploy /home/deploy/.ssh/authorized_keys
```

Test from your local machine:

```bash
ssh -i ~/.ssh/clawdbot-deploy deploy@<tailscale-ip>
```

---

## 6.3 Create Clawdbot Directory Structure

```bash
sudo mkdir -p /opt/clawdbot/data/.clawdbot
sudo mkdir -p /opt/clawdbot/data/workspace
```

Set ownership:

```bash
sudo chown -R deploy:deploy /opt/clawdbot
sudo chown -R 1000:1000 /opt/clawdbot/data
```

---

## 6.4 Create Docker Compose File

```bash
sudo tee /opt/clawdbot/docker-compose.yml << 'EOF'
services:
  clawdbot-gateway:
    image: ghcr.io/${GITHUB_REPOSITORY}:latest
    container_name: clawdbot
    restart: unless-stopped
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - CLAWDBOT_GATEWAY_BIND=lan
      - CLAWDBOT_GATEWAY_PORT=18789
      - CLAWDBOT_GATEWAY_TOKEN=${CLAWDBOT_GATEWAY_TOKEN}
    volumes:
      - ./data/.clawdbot:/home/node/.clawdbot
      - ./data/workspace:/home/node/clawd
    ports:
      - "127.0.0.1:18789:18789"
    healthcheck:
      test: ["CMD", "node", "dist/index.js", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF

sudo chown deploy:deploy /opt/clawdbot/docker-compose.yml
```

---

## 6.5 Create Environment File

Generate a secure gateway token:

```bash
GATEWAY_TOKEN=$(openssl rand -hex 32)
echo "Generated token: $GATEWAY_TOKEN"
```

**Save this token securely**—you'll need it to access the gateway.

Create the .env file:

```bash
sudo tee /opt/clawdbot/.env << EOF
CLAWDBOT_GATEWAY_TOKEN=${GATEWAY_TOKEN}
GITHUB_REPOSITORY=<your-github-username>/<your-repo-name>
EOF

sudo chown deploy:deploy /opt/clawdbot/.env
sudo chmod 600 /opt/clawdbot/.env
```

Replace `<your-github-username>/<your-repo-name>` with your actual repository path.

---

## 6.6 Verify Directory Structure

```bash
ls -la /opt/clawdbot/
```

Expected:

```
drwxr-xr-x deploy deploy  .
drwxr-xr-x root   root    ..
drwxr-xr-x 1000   1000    data
-rw-r--r-- deploy deploy  docker-compose.yml
-rw------- deploy deploy  .env
```

```bash
ls -la /opt/clawdbot/data/
```

Expected:

```
drwxr-xr-x 1000 1000 .
drwxr-xr-x 1000 1000 .clawdbot
drwxr-xr-x 1000 1000 workspace
```

---

## Checklist

| Item | Status |
|------|--------|
| Deploy user created | ☐ |
| Deploy user in docker group | ☐ |
| Deploy SSH key generated | ☐ |
| Public key added to server | ☐ |
| SSH access tested | ☐ |
| /opt/clawdbot directories created | ☐ |
| docker-compose.yml created | ☐ |
| .env file created | ☐ |
| Gateway token saved securely | ☐ |
| GITHUB_REPOSITORY set in .env | ☐ |

---

[← Back to README](../README.md) | [Previous: GitHub Actions](05-github-actions.md) | [Next: Deploy and Verify →](07-deploy-and-verify.md)
