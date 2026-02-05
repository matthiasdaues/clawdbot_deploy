# 5. GitHub Actions Configuration

[← Back to README](../README.md)

Set up the automated build and deployment workflow.

---

## 5.1 Create Workflow File

Create `.github/workflows/deploy.yml`:

```yaml
name: Build and Deploy Clawdbot

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      clawdbot_version:
        description: 'Clawdbot version (branch/tag)'
        required: false
        default: 'main'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    outputs:
      image_tag: ${{ steps.meta.outputs.version }}
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push with Bake
        uses: docker/bake-action@v4
        with:
          files: docker-bake.hcl
          targets: clawdbot
          push: true
        env:
          REGISTRY: ${{ env.REGISTRY }}
          REPOSITORY: ${{ env.IMAGE_NAME }}
          TAG: ${{ steps.meta.outputs.version }}
          CLAWDBOT_VERSION: ${{ inputs.clawdbot_version || 'main' }}

  deploy:
    needs: build
    runs-on: ubuntu-latest
    
    steps:
      - name: Setup Tailscale
        uses: tailscale/github-action@v2
        with:
          authkey: ${{ secrets.TAILSCALE_AUTHKEY }}
          tags: tag:ci

      - name: Setup SSH key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key

      - name: Deploy to server
        env:
          HOST: ${{ secrets.DEPLOY_HOST }}
          USER: ${{ secrets.DEPLOY_USER }}
          REGISTRY: ${{ env.REGISTRY }}
          IMAGE_NAME: ${{ env.IMAGE_NAME }}
        run: |
          ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=accept-new ${USER}@${HOST} << ENDSSH
            cd /opt/clawdbot
            
            # Login to GHCR
            echo "${{ secrets.GHCR_DEPLOY_TOKEN }}" | docker login ghcr.io -u ${{ secrets.GHCR_DEPLOY_USER }} --password-stdin
            
            # Update image reference
            export GITHUB_REPOSITORY="${IMAGE_NAME}"
            
            # Pull latest image
            docker compose pull
            
            # Restart with new image
            docker compose up -d
            
            # Prune old images
            docker image prune -f
            
            # Health check (wait up to 60s)
            echo "Waiting for gateway to start..."
            for i in {1..12}; do
              if docker exec clawdbot node dist/index.js health 2>/dev/null; then
                echo "✓ Health check passed"
                exit 0
              fi
              sleep 5
            done
            
            echo "✗ Health check failed"
            docker compose logs --tail=50
            exit 1
          ENDSSH

      - name: Cleanup SSH key
        if: always()
        run: rm -f ~/.ssh/deploy_key
```

---

## 5.2 Configure Repository Secrets

Go to your repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `TAILSCALE_AUTHKEY` | `tskey-auth-...` | From Tailscale admin console |
| `DEPLOY_SSH_KEY` | Private key contents | From `~/.ssh/clawdbot-deploy` |
| `DEPLOY_HOST` | `100.x.y.z` | Server's Tailscale IP |
| `DEPLOY_USER` | `deploy` | Deploy user on server |
| `GHCR_DEPLOY_USER` | Your GitHub username | For server to pull images |
| `GHCR_DEPLOY_TOKEN` | PAT with `read:packages` | For server to pull images |

---

## 5.3 Generate Tailscale Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Click **Generate auth key**
3. Configure:
   - **Reusable**: Yes
   - **Ephemeral**: Yes
   - **Tags**: `tag:ci`
   - **Expiry**: 90 days
4. Copy the key

---

## 5.4 Create GHCR Deploy Token

1. Go to https://github.com/settings/tokens
2. Click **Generate new token (classic)**
3. Configure:
   - **Note**: `clawdbot-deploy-ghcr`
   - **Expiration**: 90 days
   - **Scopes**: `read:packages` only
4. Copy the token

---

## 5.5 Configure Repository Permissions

1. Go to your repository → **Settings** → **Actions** → **General**
2. Under **Workflow permissions**, select **Read and write permissions**
3. Click **Save**

---

## 5.6 Configure Tailscale ACLs (Optional)

Go to https://login.tailscale.com/admin/acls/file

Restrict CI runner access:

```json
{
  "tagOwners": {
    "tag:ci": ["your-email@example.com"],
    "tag:server": ["your-email@example.com"]
  },
  "grants": [
    {
      "src": ["autogroup:member"],
      "dst": ["*"],
      "ip":  ["*"]
    },
    {
      "src": ["tag:ci"],
      "dst": ["tag:server"],
      "ip":  ["22"]
    }
  ]
}
```

Tag your server:

```bash
sudo tailscale up --advertise-tags=tag:server
```

---

## Troubleshooting

### Build fails: "unauthorized"

- Verify workflow permissions are set to "Read and write"
- Check that `GITHUB_TOKEN` has `packages: write` permission

### Deploy fails: "Connection refused"

- Verify Tailscale auth key hasn't expired
- Check `DEPLOY_HOST` is the Tailscale IP, not public IP
- Verify `tag:ci` is allowed to connect to `tag:server` in ACLs

### Deploy fails: "Permission denied (publickey)"

- Verify `DEPLOY_SSH_KEY` contains the complete private key
- Check the public key is in `/home/deploy/.ssh/authorized_keys` on server

### Image pull fails on server

- Verify `GHCR_DEPLOY_TOKEN` has `read:packages` scope
- Check token hasn't expired
- Verify image exists: `https://github.com/<user>/<repo>/pkgs/container/<repo>`

---

## Checklist

| Item | Status |
|------|--------|
| Workflow file created | ☐ |
| `TAILSCALE_AUTHKEY` secret added | ☐ |
| `DEPLOY_SSH_KEY` secret added | ☐ |
| `DEPLOY_HOST` secret added | ☐ |
| `DEPLOY_USER` secret added | ☐ |
| `GHCR_DEPLOY_USER` secret added | ☐ |
| `GHCR_DEPLOY_TOKEN` secret added | ☐ |
| Repository permissions configured | ☐ |
| Tailscale ACLs configured (optional) | ☐ |

---

[← Back to README](../README.md) | [Previous: Build and Push](04-build-and-push.md) | [Next: Server Preparation →](06-server-preparation.md)
