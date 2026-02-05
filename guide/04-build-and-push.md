# 4. Build Image and Push to GHCR

[← Back to README](../README.md)

Build the Clawdbot Docker image using Docker Bake and push it to GitHub Container Registry.

---

## 4.1 Authenticate with GHCR

Create a Personal Access Token (classic) for pushing images:

1. Go to https://github.com/settings/tokens
2. Click **Generate new token (classic)**
3. Configure:
   - **Note**: `clawdbot-ghcr-push`
   - **Expiration**: 90 days (or your preference)
   - **Scopes**: `write:packages`, `read:packages`
4. Copy the token

Login to GHCR from your local machine:

```bash
echo "<your-token>" | docker login ghcr.io -u <your-github-username> --password-stdin
```

Expected output:

```
Login Succeeded
```

---

## 4.2 Set Environment Variables

Export variables for the build:

```bash
export REGISTRY="ghcr.io"
export REPOSITORY="<your-github-username>/<your-repo-name>"
export TAG="latest"
export CLAWDBOT_VERSION="main"
```

---

## 4.3 Build and Push with Docker Bake

From your repository root:

```bash
docker buildx bake clawdbot
```

This will:
1. Build the image using the Dockerfile
2. Tag it as `ghcr.io/<user>/<repo>:latest`
3. Push to GHCR

Build output shows progress:

```
[+] Building 120.5s (15/15) FINISHED
 => [internal] load build definition from Dockerfile
 => [internal] load .dockerignore
 => ...
 => exporting to image
 => => pushing layers
 => => pushing manifest for ghcr.io/<user>/<repo>:latest
```

---

## 4.4 Build Locally (Without Push)

To test the build without pushing:

```bash
docker buildx bake clawdbot-local
```

This creates `clawdbot:local` in your local Docker:

```bash
docker images | grep clawdbot
```

Test it runs:

```bash
docker run --rm clawdbot:local node dist/index.js --version
```

---

## 4.5 Build Specific Version

To build a specific Clawdbot version (tag or branch):

```bash
export CLAWDBOT_VERSION="v1.2.3"
docker buildx bake clawdbot
```

Or with a custom tag:

```bash
export TAG="v1.2.3"
export CLAWDBOT_VERSION="v1.2.3"
docker buildx bake clawdbot
```

---

## 4.6 Verify Image on GHCR

Check the image exists:

1. Go to `https://github.com/<user>/<repo>/pkgs/container/<repo>`
2. Or via GitHub: Repository → **Packages** (right sidebar)

You should see:
- Image name
- Tags (latest, sha-xxx)
- Size and push date

---

## 4.7 Configure Package Visibility

By default, packages inherit repository visibility. To make the package accessible:

1. Go to your package page on GitHub
2. Click **Package settings**
3. Under **Danger Zone**, configure visibility:
   - **Private**: Only you and collaborators
   - **Public**: Anyone can pull

For private packages, ensure your deploy token has `read:packages` scope.

---

## 4.8 Pull and Test Image

From any machine authenticated with GHCR:

```bash
docker pull ghcr.io/<user>/<repo>:latest
docker run --rm ghcr.io/<user>/<repo>:latest node dist/index.js --version
```

---

## Automated Builds (GitHub Actions)

The workflow in [Step 5: GitHub Actions](05-github-actions.md) automates this process:
- Builds on every push to main
- Pushes to GHCR automatically
- Uses GitHub Actions cache for faster builds
- Tags with commit SHA and `latest`

Manual builds are useful for:
- Initial setup and testing
- Building from feature branches
- Debugging build issues

---

## Troubleshooting

### "unauthorized: unauthenticated"

```bash
# Re-authenticate
docker logout ghcr.io
echo "<token>" | docker login ghcr.io -u <username> --password-stdin
```

Verify token has `write:packages` scope.

### "denied: permission_denied"

- Check repository name matches exactly (case-sensitive)
- Verify token owner has write access to repository
- For org repos, ensure token has org package permissions

### Build fails: "pnpm install" errors

The Clawdbot repo may have updated dependencies. Try building a specific known-good version:

```bash
export CLAWDBOT_VERSION="v1.0.0"  # Use a stable tag
docker buildx bake clawdbot-local
```

### Image not visible on GitHub

- Packages tab may take a minute to update
- Check package visibility settings
- Verify push completed without errors

### "no match for platform"

Add platform explicitly:

```bash
docker buildx bake clawdbot --set clawdbot.platform=linux/amd64
```

---

## Checklist

| Item | Status |
|------|--------|
| PAT created with write:packages | ☐ |
| Logged in to GHCR | ☐ |
| Environment variables set | ☐ |
| Local build tested | ☐ |
| Image pushed to GHCR | ☐ |
| Image visible on GitHub | ☐ |
| Package visibility configured | ☐ |
| Pull and run tested | ☐ |

---

[← Back to README](../README.md) | [Previous: Repository Setup](03-repository-setup.md) | [Next: GitHub Actions →](05-github-actions.md)
