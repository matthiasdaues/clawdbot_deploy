# Clawdbot Deployment Guide

Deploy Clawdbot on a hardened Ubuntu 24.04 server using Docker, with automated builds via GitHub Actions and images hosted on GitHub Container Registry (GHCR).

## Architecture

```
GitHub Repository
    │
    │ Push to main
    ▼
GitHub Actions
    ├─► Docker Bake → Build image
    ├─► GHCR → Push image
    │
    │   Tailscale VPN
    └─► SSH → Deploy
            │
            ▼
┌─────────────────────────────────────┐
│  Clawdbot Server                    │
│  ├─ Ubuntu 24.04 (hardened)         │
│  ├─ Docker + Compose                │
│  ├─ Tailscale VPN                   │
│  └─ Clawdbot container (from GHCR)  │
└─────────────────────────────────────┘
```

## Prerequisites

- Fresh Ubuntu 24.04 server with root access
- Tailscale account
- GitHub account and repository
- SSH key pair on your local machine

## Deployment Steps

1. [Server Hardening](guide/01-server-hardening.md)  
   Create admin user, configure SSH, install Fail2ban, set up UFW firewall, install Tailscale, restrict SSH to VPN only.

2. [Docker Installation](guide/02-docker-installation.md)  
   Install Docker CE, configure localhost binding, set up DOCKER-USER firewall rules via systemd.

3. [Repository Setup](guide/03-repository-setup.md)  
   Create Dockerfile, docker-bake.hcl, docker-compose.yml, and supporting files.

4. [Build Image and Push to GHCR](guide/04-build-and-push.md)  
   Authenticate with GHCR, build image with Docker Bake, push to registry, verify.

5. [GitHub Actions Configuration](guide/05-github-actions.md)  
   Create deployment workflow, configure repository secrets, set up GHCR permissions.

6. [Server Deployment Preparation](guide/06-server-preparation.md)  
   Create deploy user, set up directories, generate gateway token, configure environment.

7. [Deploy and Verify](guide/07-deploy-and-verify.md)  
   Trigger workflow, verify deployment, access gateway, configure channels.

## Security Summary

| Layer | Protection |
|-------|------------|
| Network | Tailscale VPN—server invisible to public internet |
| Firewall | UFW deny all, SSH only on tailscale0 |
| SSH | Key-only, password disabled, root disabled |
| Brute-force | Fail2ban (1h ban after 5 failures) |
| Containers | Docker binds localhost only, DOCKER-USER blocks external |
| Deployment | Dedicated deploy user, restricted SSH key |
| Images | Private GHCR registry |

## Quick Reference

```bash
# Check deployment status
ssh <user>@<tailscale-ip> "docker ps"

# View logs
ssh <user>@<tailscale-ip> "docker logs clawdbot -f"

# Manual redeploy
ssh <user>@<tailscale-ip> "cd /opt/clawdbot && docker compose pull && docker compose up -d"

# Access gateway (via SSH tunnel)
ssh -L 18789:127.0.0.1:18789 <user>@<tailscale-ip>
# Then open http://127.0.0.1:18789
```

## Maintenance

- **Update Clawdbot**: Push to main branch or trigger workflow manually
- **Backup**: `tar -czf backup.tar.gz -C /opt/clawdbot/data .`
- **Logs**: `docker compose -f /opt/clawdbot/docker-compose.yml logs`

## Troubleshooting

See individual guide sections for step-specific troubleshooting, or check:

- [Server Hardening](guide/01-server-hardening.md#troubleshooting) — SSH access issues
- [Docker Installation](guide/02-docker-installation.md#troubleshooting) — Container networking
- [Build and Push](guide/04-build-and-push.md#troubleshooting) — Image build and registry issues
- [GitHub Actions](guide/05-github-actions.md#troubleshooting) — Workflow failures
- [Deploy and Verify](guide/07-deploy-and-verify.md#troubleshooting) — Runtime issues
