# 8. OpenClaw Configuration

[← Back to README](../README.md) | [Previous: Deploy and Verify](07-deploy-and-verify.md)

Configure the OpenClaw gateway inside the container, authenticate with an AI provider, connect messaging channels, and start using your assistant.

---

## Background

OpenClaw (formerly Clawdbot) is a self-hosted personal AI assistant gateway. It routes conversations between AI models (Claude, GPT, Gemini) and messaging platforms (WhatsApp, Telegram, Discord, Slack, Signal, and others). The gateway runs as a Node.js process, exposes a WebSocket + HTTP control plane on a single port (default `18789`), and persists all configuration and state in `~/.openclaw/`.

### Architecture

```
  Messaging Channels          OpenClaw Gateway          AI Providers
┌──────────────────┐      ┌─────────────────────┐    ┌──────────────┐
│ WhatsApp         │      │                     │    │ Anthropic    │
│ Telegram         │◄────►│  Session Manager     │◄──►│ (Claude)     │
│ Discord          │      │  Channel Router      │    │              │
│ Slack            │      │  Web Dashboard       │    │ OpenAI       │
│ Signal           │      │  Skills Engine        │    │ (GPT)        │
│ ...              │      │                     │    │              │
└──────────────────┘      └─────────────────────┘    └──────────────┘
                               ▲
                               │ SSH Tunnel
                               │ http://127.0.0.1:18789
                          ┌────┴────┐
                          │ Browser │
                          └─────────┘
```

---

## 8.1 Fix the Naming Mismatch

The upstream project was renamed from **Clawdbot** to **OpenClaw**. The application now expects `OPENCLAW_*` environment variables and the `~/.openclaw/` state directory. Our Dockerfile and docker-compose.yml still use the old names, which causes two errors:

```
Missing config. Run `openclaw setup` or set gateway.mode=local (or pass --allow-unconfigured).
State dir migration skipped: target already exists (/home/node/.openclaw). Remove or merge manually.
```

### Dockerfile

Update the directory names in the Dockerfile:

```dockerfile
# Before (old names)
RUN mkdir -p /home/node/.clawdbot /home/node/clawd \
    && chown -R node:node /home/node

# After (new names)
RUN mkdir -p /home/node/.openclaw /home/node/openclaw-workspace \
    && chown -R node:node /home/node
```

Add `--allow-unconfigured` to the CMD so the gateway starts without a pre-existing config file (configuration is provided via environment variables and mounted volumes):

```dockerfile
# Before
CMD ["node", "dist/index.js", "gateway"]

# After
CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured"]
```

### docker-compose.yml

Update environment variable names and volume mount paths:

```yaml
services:
  clawdbot-gateway:
    image: ghcr.io/${GITHUB_REPOSITORY}:latest
    container_name: clawdbot
    restart: unless-stopped
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - OPENCLAW_GATEWAY_BIND=lan
      - OPENCLAW_GATEWAY_PORT=18789
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
    volumes:
      - ${OPENCLAW_CONFIG_DIR:-./data/.openclaw}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR:-./data/workspace}:/home/node/openclaw-workspace
    ports:
      - "127.0.0.1:18789:18789"
    healthcheck:
      test: ["CMD", "node", "dist/index.js", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### .env on server

Update the `.env` file at `/opt/clawdbot/.env`:

```bash
OPENCLAW_GATEWAY_TOKEN=<your-token>
GITHUB_REPOSITORY=matthiasdaues/clawdbot_deploy
```

---

## 8.2 Create the Configuration File

OpenClaw reads its configuration from `~/.openclaw/openclaw.json` (JSON5 format — comments and trailing commas are allowed). Inside the container, this maps to the mounted volume.

**Important**: The container runs as user `node` (uid 1000), but the `deploy` user on the server is uid 1001. Files created by `deploy` are not writable by the container. Use a temporary Alpine container to set ownership after creating files:

```bash
# Fix ownership of the entire data directory
docker run --rm -v /opt/clawdbot/data:/data alpine chown -R 1000:1000 /data
```

### Create the config directory and file

SSH to the server and create the configuration:

```bash
ssh -i ~/.ssh/clawdbot-deploy deploy@<tailscale-ip>

# Create config directory (maps to the volume mount)
mkdir -p /opt/clawdbot/data/.openclaw

# Create minimal configuration
cat > /opt/clawdbot/data/.openclaw/openclaw.json << 'EOF'
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "lan",
    "auth": {
      "mode": "token"
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-opus-4-6"
      },
      "workspace": "/home/node/openclaw-workspace"
    }
  }
}
EOF

# Fix ownership so the container's node user (uid 1000) can write
docker run --rm -v /opt/clawdbot/data:/data alpine chown -R 1000:1000 /data
```

**Config schema note**: OpenClaw's config schema evolves between versions. The `agent.model` key was replaced by `agents.defaults.model.primary`. If the gateway logs show "Legacy config keys detected", run `docker exec clawdbot node dist/index.js doctor --fix` or update the keys manually. The gateway will auto-migrate on load but will warn until the file is updated.

### Why `gateway.auth.mode` matters

Without `"auth": { "mode": "token" }` in the config, the gateway refuses to bind to non-loopback addresses — even if `OPENCLAW_GATEWAY_BIND=lan` is set via environment variable. The gateway enforces this as a safety measure to prevent accidental exposure without authentication. If you see the gateway binding to `ws://127.0.0.1:18789` instead of `ws://0.0.0.0:18789`, check that auth mode is configured.

---

## 8.3 Authenticate with an AI Provider

OpenClaw needs credentials to call AI model APIs. For Anthropic (Claude), you have two options.

### Option A: API Key (recommended)

Create an API key at [console.anthropic.com](https://console.anthropic.com/) and store it in the OpenClaw environment file inside the container's config directory:

```bash
# On the server
cat >> /opt/clawdbot/data/.openclaw/.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-...
EOF

chmod 600 /opt/clawdbot/data/.openclaw/.env
```

### Option B: Claude Subscription Token

If you use a Claude Pro or Max subscription instead of an API key:

```bash
# In a separate terminal, generate a token
claude setup-token

# Then paste into the container
docker exec -it clawdbot node dist/index.js models auth setup-token --provider anthropic
```

### Verify authentication

```bash
docker exec clawdbot node dist/index.js models status
```

This should show your configured provider and model.

**Note**: In our custom Docker image, the `openclaw` CLI binary is not in `$PATH`. Use `node dist/index.js <command>` instead. All `openclaw <command>` examples in this guide use this form for container execution.

---

## 8.4 Restart and Verify

After updating the Dockerfile, docker-compose.yml, and creating the configuration:

```bash
# Rebuild and redeploy (via GitHub Actions or manually)
cd /opt/clawdbot
docker compose pull
docker compose up -d

# Check container status
docker ps

# Check logs
docker logs clawdbot -f
```

Look for:

```
[gateway] listening on ws://0.0.0.0:18789
```

Run the health check:

```bash
docker exec clawdbot node dist/index.js health
```

---

## 8.5 Access the Web Dashboard

The gateway binds to `127.0.0.1` on the host (the `ports` directive in docker-compose.yml restricts this). Access it via an SSH tunnel.

### Open the SSH tunnel

From your **local machine**, open a tunnel and leave it running:

```bash
ssh -L 18789:127.0.0.1:18789 -i ~/.ssh/clawdbot-deploy deploy@<tailscale-ip> -N
```

The `-N` flag keeps the tunnel open without executing a remote command.

### Get the dashboard URL

The gateway token must be passed as a URL query parameter — there is no login form. Generate the dashboard URL from the server:

```bash
docker exec clawdbot node dist/index.js dashboard --no-open
```

This outputs a URL like:

```
http://127.0.0.1:18789/?token=<your-gateway-token>
```

Open that URL in your browser with the SSH tunnel active.

### Approve device pairing

On first connection, the Control UI registers as a new device. The gateway requires explicit approval before allowing access. You will see `disconnected (1008): pairing required` in the dashboard.

List pending devices and approve:

```bash
# List devices (shows pending and paired)
docker exec clawdbot node dist/index.js devices list

# Approve the pending request (use the Request ID from the list)
docker exec clawdbot node dist/index.js devices approve <request-id>
```

After approval, the dashboard connects automatically. The device remains paired across restarts as long as the config volume is preserved.

### Dashboard features

- Live session view
- Model and provider status
- Channel connection status
- Configuration editor
- Logs viewer
- WebChat (direct conversation with the agent)

---

## 8.6 Configure Messaging Channels

Channels connect OpenClaw to messaging platforms. Configure them via the CLI inside the container or by editing `openclaw.json`.

### Interactive Setup

```bash
docker exec -it clawdbot node dist/index.js channels login
```

This walks through channel selection and credential entry.

### Telegram

1. Create a bot via [@BotFather](https://t.me/BotFather) on Telegram
2. Copy the bot token
3. Add the channel:

```bash
docker exec -it clawdbot node dist/index.js channels add --channel telegram --token "<bot-token>"
```

Or add to `openclaw.json`:

```json5
{
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "<bot-token>",
      "dmPolicy": "pairing",
      "allowFrom": ["tg:<your-telegram-user-id>"]
    }
  }
}
```

### WhatsApp

```bash
docker exec -it clawdbot node dist/index.js channels add --channel whatsapp
```

This displays a QR code in the terminal. Scan it with WhatsApp on your phone (Linked Devices).

### Discord

1. Create a bot at [discord.com/developers](https://discord.com/developers/applications)
2. Copy the bot token
3. Add the channel:

```bash
docker exec -it clawdbot node dist/index.js channels add --channel discord --token "<bot-token>"
```

### Slack

```bash
docker exec -it clawdbot node dist/index.js channels add --channel slack \
  --bot-token "xoxb-..." \
  --app-token "xapp-..."
```

---

## 8.7 DM Policy and Pairing

By default, OpenClaw uses a **pairing policy** for direct messages: unknown senders receive a pairing code and the bot ignores their messages until you approve them.

### Approve a sender

```bash
docker exec -it clawdbot node dist/index.js pairing approve <channel> <code>
```

### Allow specific senders in config

```json5
{
  "channels": {
    "whatsapp": {
      "dmPolicy": "pairing",
      "allowFrom": ["+49123456789"]
    },
    "telegram": {
      "dmPolicy": "pairing",
      "allowFrom": ["tg:123456789"]
    }
  }
}
```

---

## 8.8 Interacting with OpenClaw

Once a channel is connected, send messages to your bot. OpenClaw supports several slash commands within any connected channel:

| Command | Description |
|---------|-------------|
| `/status` | Show session status (model, tokens, cost) |
| `/new` or `/reset` | Clear session context |
| `/compact` | Summarise session history |
| `/think <level>` | Set thinking depth: `off`, `minimal`, `low`, `medium`, `high`, `xhigh` |
| `/verbose on\|off` | Toggle verbose output |
| `/model <name>` | Switch model mid-session |
| `/restart` | Restart the gateway |

### Assigning tasks

Send natural language messages through any connected channel. OpenClaw routes them to the configured AI model and streams the response back.

Examples:

- `Summarise the last 10 commits in my project`
- `Write a Python script that converts CSV to JSON`
- `Review this code for security issues: <paste>`

### Group chats

In group chats, OpenClaw defaults to **mention-only** mode — it only responds when explicitly mentioned. Configure this per-group in `openclaw.json`:

```json5
{
  "agents": {
    "list": [{
      "id": "main",
      "groupChat": {
        "mentionPatterns": ["@openclaw", "@bot"]
      }
    }]
  }
}
```

---

## 8.9 Diagnostics

### Health check

```bash
docker exec clawdbot node dist/index.js health
```

This shows agent status, heartbeat interval, and session count.

For a deeper diagnostic:

```bash
docker exec clawdbot node dist/index.js doctor
```

This checks configuration validity, provider authentication, channel connections, and reports any issues.

### Logs

```bash
# Live logs
docker logs clawdbot -f

# Last 100 lines
docker logs clawdbot --tail=100

# Filter by channel
docker logs clawdbot 2>&1 | grep -i telegram
```

### Configuration validation

OpenClaw enforces strict schema validation. Unknown keys, malformed values, or invalid types prevent startup. If the gateway won't start after a config change, check the logs for the specific validation error.

---

## 8.10 Security Considerations

| Concern | Mitigation |
|---------|------------|
| Gateway exposed to network | Port bound to `127.0.0.1` only; access via SSH tunnel |
| API keys in config | Store in `~/.openclaw/.env` with `600` permissions |
| Unknown senders | `dmPolicy: "pairing"` requires explicit approval |
| File system access | Container runs as non-root `node` user (uid 1000) |
| Gateway token | Generated with `openssl rand -hex 32`; required for dashboard access |

Review the [CVE-2026-25253](https://github.com/openclaw/openclaw/issues?q=CVE-2026-25253) advisory regarding unauthenticated WebSocket access. Ensure `gateway.auth` is always configured when binding to non-loopback addresses.

---

## Configuration Reference

### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `OPENCLAW_GATEWAY_PORT` | Gateway port | `18789` |
| `OPENCLAW_GATEWAY_BIND` | Bind mode: `loopback`, `lan`, `tailnet` | `loopback` |
| `OPENCLAW_GATEWAY_TOKEN` | Auth token (overrides config) | — |
| `OPENCLAW_CONFIG_PATH` | Override config file location | `~/.openclaw/openclaw.json` |
| `OPENCLAW_STATE_DIR` | Override state directory | `~/.openclaw` |
| `ANTHROPIC_API_KEY` | Anthropic API key | — |

### Useful CLI Commands

All commands use `node dist/index.js` because the `openclaw` binary is not in `$PATH` in our custom image.

```bash
# Check overall health
docker exec clawdbot node dist/index.js health

# Run diagnostics
docker exec clawdbot node dist/index.js doctor

# List connected channels
docker exec -it clawdbot node dist/index.js channels login

# Check model authentication
docker exec clawdbot node dist/index.js models status

# List and approve devices
docker exec clawdbot node dist/index.js devices list
docker exec clawdbot node dist/index.js devices approve <request-id>

# Generate dashboard URL
docker exec clawdbot node dist/index.js dashboard --no-open
```

---

## Checklist

| Item | Status |
|------|--------|
| Dockerfile updated (`.openclaw` dirs, `--allow-unconfigured`) | ☐ |
| docker-compose.yml updated (`OPENCLAW_*` env vars, volume paths) | ☐ |
| `.env` on server updated | ☐ |
| Data directory ownership set to uid 1000 | ☐ |
| `openclaw.json` created with correct schema | ☐ |
| AI provider authenticated | ☐ |
| Gateway starts and passes health check | ☐ |
| Gateway binds to `ws://0.0.0.0:18789` (not loopback) | ☐ |
| SSH tunnel opened, dashboard URL loaded | ☐ |
| Device pairing approved | ☐ |
| At least one channel connected | ☐ |
| DM policy configured | ☐ |

---

[← Back to README](../README.md) | [Previous: Deploy and Verify](07-deploy-and-verify.md)
