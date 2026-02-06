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
RUN mkdir -p /home/node/.openclaw /home/node/openclaw-workspace \
    && chown -R node:node /home/node

USER node

CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured"]
