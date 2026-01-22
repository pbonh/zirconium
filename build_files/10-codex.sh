#!/bin/bash
set -ouex pipefail

# Install Node.js and npm from Fedora repos

dnf5 install -y nodejs npm

# Install OpenAI Codex globally for all users
install -d /var/cache/npm /var/cache/npm-home
HOME=/var/cache/npm-home NPM_CONFIG_CACHE=/var/cache/npm npm install -g @openai/codex

# Cleanup
rm -rf /var/cache/npm /var/cache/npm-home
npm cache clean --force || true
