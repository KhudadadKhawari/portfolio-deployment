#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-${APP_DIR}/docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-${APP_DIR}/.env}"
NGINX_TEMPLATE="${NGINX_TEMPLATE:-${APP_DIR}/nginx/templates/app.conf.template}"
DEFAULT_DOMAIN="portfolio.seferyak.com"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy .env.example to .env and update values first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

DOMAIN="${DOMAIN:-${DEFAULT_DOMAIN}}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
LETSENCRYPT_CERT_NAME="${DOMAIN}"
CERTBOT_STAGING="${CERTBOT_STAGING:-0}"
FORCE_RENEWAL="${FORCE_RENEWAL:-0}"
ACME_PROBE_RETRIES="${ACME_PROBE_RETRIES:-30}"
ACME_PROBE_INTERVAL="${ACME_PROBE_INTERVAL:-2}"

if [[ "${DOMAIN}" != "${DEFAULT_DOMAIN}" ]]; then
  echo "DOMAIN must be ${DEFAULT_DOMAIN} for this deployment. Current value: ${DOMAIN}" >&2
  echo "Update ${ENV_FILE}, or run with DOMAIN=${DEFAULT_DOMAIN}." >&2
  exit 1
fi

if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
  echo "LETSENCRYPT_EMAIL must be set in ${ENV_FILE}." >&2
  exit 1
fi

if [[ ! -f "${NGINX_TEMPLATE}" ]]; then
  echo "Missing Nginx template: ${NGINX_TEMPLATE}" >&2
  exit 1
fi

cd "${APP_DIR}"

compose() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

restore_nginx_template() {
  if [[ -n "${template_backup:-}" && -f "${template_backup}" ]]; then
    cp "${template_backup}" "${NGINX_TEMPLATE}"
    rm -f "${template_backup}"
  fi
}

show_nginx_logs() {
  echo "--- docker logs: portfolio nginx ---" >&2
  compose logs --tail 80 nginx >&2 || true
}

show_nginx_status() {
  echo "--- docker compose ps nginx ---" >&2
  compose ps nginx >&2 || true
}

write_http_bootstrap_template() {
  cat > "${NGINX_TEMPLATE}" <<'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }

    location /.well-known/health {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }

    location / {
        return 200 "ACME bootstrap is ready.\n";
        add_header Content-Type text/plain;
    }
}
NGINX
}

probe_acme_webroot() {
  local probe_token probe_dir probe_file local_response public_response attempt

  probe_token="portfolio-acme-probe-$(date +%s)"
  probe_dir="${APP_DIR}/certbot/www/.well-known/acme-challenge"
  probe_file="${probe_dir}/${probe_token}"

  install -d -m 0755 "${probe_dir}"
  printf '%s\n' "${probe_token}" > "${probe_file}"

  echo "Waiting for local ACME challenge endpoint on ${DOMAIN}..."
  for ((attempt = 1; attempt <= ACME_PROBE_RETRIES; attempt++)); do
    local_response="$({ curl --silent --show-error --fail --max-time 5 \
      --resolve "${DOMAIN}:80:127.0.0.1" \
      "http://${DOMAIN}/.well-known/acme-challenge/${probe_token}"; } 2>&1)" && {
      if [[ "${local_response}" == "${probe_token}" ]]; then
        break
      fi
    }

    if (( attempt == ACME_PROBE_RETRIES )); then
      rm -f "${probe_file}"
      echo "Local ACME probe failed for ${DOMAIN}: ${local_response}" >&2
      show_nginx_status
      show_nginx_logs
      exit 1
    fi

    sleep "${ACME_PROBE_INTERVAL}"
  done

  echo "Waiting for public ACME challenge endpoint on ${DOMAIN}..."
  for ((attempt = 1; attempt <= ACME_PROBE_RETRIES; attempt++)); do
    public_response="$({ curl --silent --show-error --fail --max-time 10 \
      "http://${DOMAIN}/.well-known/acme-challenge/${probe_token}"; } 2>&1)" && {
      if [[ "${public_response}" == "${probe_token}" ]]; then
        rm -f "${probe_file}"
        return 0
      fi
    }

    if (( attempt == ACME_PROBE_RETRIES )); then
      rm -f "${probe_file}"
      echo "Public ACME probe failed for ${DOMAIN}: ${public_response}" >&2
      echo "Check that DNS A/AAAA records for ${DOMAIN} point to this VPS and that ports 80/443 are open." >&2
      show_nginx_status
      show_nginx_logs
      exit 1
    fi

    sleep "${ACME_PROBE_INTERVAL}"
  done
}

install -d -m 0755 \
  "${APP_DIR}/certbot/www" \
  "${APP_DIR}/letsencrypt" \
  "${APP_DIR}/nginx/templates"

template_backup="$(mktemp)"
cp "${NGINX_TEMPLATE}" "${template_backup}"
trap 'restore_nginx_template' EXIT

write_http_bootstrap_template
compose up -d --force-recreate nginx
compose exec -T nginx nginx -t
probe_acme_webroot

certbot_args=(
  certonly
  --webroot
  --webroot-path /var/www/certbot
  --email "${LETSENCRYPT_EMAIL}"
  --agree-tos
  --no-eff-email
  --cert-name "${LETSENCRYPT_CERT_NAME}"
  -d "${DOMAIN}"
)

if [[ "${CERTBOT_STAGING}" == "1" ]]; then
  certbot_args+=(--staging)
fi

if [[ "${FORCE_RENEWAL}" == "1" ]]; then
  certbot_args+=(--force-renewal)
fi

compose run --rm certbot "${certbot_args[@]}"

restore_nginx_template
trap - EXIT

compose up -d --force-recreate nginx
compose exec nginx nginx -t
compose exec nginx nginx -s reload

cat <<EOF
Let's Encrypt certificate issued for ${DOMAIN}.
Certificate files are stored on the VPS under:
  ${APP_DIR}/letsencrypt/live/${LETSENCRYPT_CERT_NAME}/fullchain.pem
  ${APP_DIR}/letsencrypt/live/${LETSENCRYPT_CERT_NAME}/privkey.pem
Nginx now mounts ${APP_DIR}/letsencrypt read-only at /etc/letsencrypt.
EOF
