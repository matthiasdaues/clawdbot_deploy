# 3. Repository Setup

[← Back to README](../README.md)

Create the files needed to build and deploy Clawdbot from your GitHub repository.

---

## Repository Structure

```
your-repo/
├── .github/
│   └── workflows/
│       └── deploy.yml          # Created in step 4
├── Dockerfile
├── docker-bake.hcl
├── docker-compose.yml
├── .env.example
├── .gitignore
└── README.md
```

---

## 3.1 Create Dockerfile

```dockerfile
FROM node:22-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    socat \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Enable corepack for pnpm
RUN corepack enable

WORKDIR /app

# Clone Clawdbot source
ARG CLAWDBOT_VERSION=main
RUN git clone --depth 1 --branch ${CLAWDBOT_VERSION} \
    https://github.com/clawdbot/clawdbot.git .

# Install dependencies
RUN pnpm install --frozen-lockfile

# Build
RUN pnpm build
RUN pnpm ui:install
RUN pnpm ui:build

# Runtime configuration
ENV NODE_ENV=production
ENV HOME=/home/node

# Create non-root user directories
RUN mkdir -p /home/node/.clawdbot /home/node/clawd \
    && chown -R node:node /home/node

USER node

CMD ["node", "dist/index.js", "gateway"]
```

---

## 3.2 Create Docker Bake Configuration

Create `docker-bake.hcl`:

```hcl
variable "REGISTRY" {
  default = "ghcr.io"
}

variable "REPOSITORY" {
  default = ""
}

variable "TAG" {
  default = "latest"
}

variable "CLAWDBOT_VERSION" {
  default = "main"
}

group "default" {
  targets = ["clawdbot"]
}

target "clawdbot" {
  context    = "."
  dockerfile = "Dockerfile"
  
  args = {
    CLAWDBOT_VERSION = "${CLAWDBOT_VERSION}"
  }
  
  tags = [
    "${REGISTRY}/${REPOSITORY}:${TAG}",
    "${REGISTRY}/${REPOSITORY}:latest"
  ]
  
  platforms = ["linux/amd64"]
  
  cache-from = ["type=gha"]
  cache-to   = ["type=gha,mode=max"]
  
  output = ["type=registry"]
}

target "clawdbot-local" {
  inherits = ["clawdbot"]
  output   = ["type=docker"]
  tags     = ["clawdbot:local"]
}
```

---

## 3.3 Create Docker Compose File

Create `docker-compose.yml`:

```yaml
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
      - ${CLAWDBOT_CONFIG_DIR:-./data/.clawdbot}:/home/node/.clawdbot
      - ${CLAWDBOT_WORKSPACE_DIR:-./data/workspace}:/home/node/clawd
    ports:
      - "127.0.0.1:18789:18789"
    healthcheck:
      test: ["CMD", "node", "dist/index.js", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

---

## 3.4 Create .gitignore

```gitignore
# Environment files
.env
.env.*
!.env.example

# Data directories
data/

# Local builds
*.local
```

---

## 3.5 Create Example Environment File

Create `.env.example`:

```bash
# Gateway authentication token (generate with: openssl rand -hex 32)
CLAWDBOT_GATEWAY_TOKEN=change-me

# GitHub repository (set automatically in CI, manual for local)
GITHUB_REPOSITORY=your-username/your-repo

# Data directories (optional, defaults shown)
CLAWDBOT_CONFIG_DIR=./data/.clawdbot
CLAWDBOT_WORKSPACE_DIR=./data/workspace
```

---

## 3.6 Test Local Build (Optional)

Before pushing, verify the image builds locally:

```bash
docker buildx bake clawdbot-local
docker run --rm clawdbot:local node dist/index.js --version
```

---

## Checklist

| Item | Status |
|------|--------|
| Dockerfile created | ☐ |
| docker-bake.hcl created | ☐ |
| docker-compose.yml created | ☐ |
| .gitignore created | ☐ |
| .env.example created | ☐ |
| Local build tested (optional) | ☐ |

---

[← Back to README](../README.md) | [Previous: Docker Installation](02-docker-installation.md) | [Next: Build and Push →](04-build-and-push.md)
