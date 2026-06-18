FROM ubuntu:24.04

LABEL maintainer="ralph-multi"
LABEL description="Ralph autonomous AI agent loop with Amp, Claude Code, and Google Antigravity CLIs"

# Avoid interactive prompts during install
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    bash \
    screen \
    ca-certificates \
    gnupg \
    lsb-release \
    tzdata \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (v20 LTS is stable and supported by Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Install Amp CLI
RUN curl -fsSL https://ampcode.com/install.sh | bash

# Install Google Antigravity CLI (agy)
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash || echo "Antigravity CLI install failed or requires authentication"

# Make sure all binaries are in the PATH
ENV PATH="/root/.local/bin:/root/bin:${PATH}"

# Verify CLI tools are installed or in path
RUN command -v claude || echo "claude CLI not globally installed"
RUN command -v amp || echo "amp CLI not globally installed"
RUN command -v agy || echo "agy CLI not globally installed"

# Set working directory
WORKDIR /workspace

# Copy ralph scripts
COPY ralph.sh /usr/local/bin/ralph.sh
RUN chmod +x /usr/local/bin/ralph.sh

COPY prompt.md /workspace/prompt.md
COPY CLAUDE.md /workspace/CLAUDE.md
COPY ralph.config.json.example /workspace/ralph.config.json.example

# Copy dashboard files
COPY server.js /workspace/server.js
COPY dashboard.html /workspace/dashboard.html

# Create directories that are commonly mounted or used
RUN mkdir -p /workspace/project /workspace/archive

# Configurations directory for credentials persistence (mount these from host)
RUN mkdir -p /root/.config/amp /root/.config/agy /root/.claude

# Copy and setup entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose Web UI port
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
