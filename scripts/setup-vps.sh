#!/usr/bin/env bash
set -euo pipefail

APP_DIR=${APP_DIR:-/opt/portfolio}
DEPLOY_USER=${DEPLOY_USER:-deploy}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root or with sudo."
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl git ufw
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if ! id "${DEPLOY_USER}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "${DEPLOY_USER}"
fi

usermod -aG docker "${DEPLOY_USER}"
mkdir -p "${APP_DIR}"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}"

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "Docker and firewall are ready. Copy portfolio-deployment into ${APP_DIR}, create ${APP_DIR}/.env, then run scripts/init-ssl.sh."
