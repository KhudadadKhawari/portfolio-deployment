# Portfolio Deployment

Production deployment for the portfolio demo platform on a single VPS using Docker Compose, Nginx, Let's Encrypt, PostgreSQL, and MinIO.

## Runtime Contract

- `https://DOMAIN/` routes to the Next.js frontend.
- `https://DOMAIN/api/` routes to the FastAPI backend.
- MinIO is internal-only by default at `http://minio:9000` on the Docker network.
- MinIO console is not exposed publicly. Use an SSH tunnel if you need it: `ssh -L 9001:localhost:9001 deploy@SERVER` after temporarily exposing or proxying it locally.

## First VPS Setup

1. Point your DNS `A` record to the VPS public IP.
2. Copy this repository to `/opt/portfolio` on the VPS.
3. Run the bootstrap script as root:

```bash
sudo DEPLOY_USER=deploy APP_DIR=/opt/portfolio ./scripts/setup-vps.sh
```

4. Copy `.env.example` to `.env` and update every secret and domain value.
5. Start initial services and issue SSL:

```bash
./scripts/init-ssl.sh
```

6. Start the full stack:

```bash
docker compose --env-file .env -f docker-compose.prod.yml up -d
./scripts/healthcheck.sh
```

## GitHub Actions Deployment Entry Point

Backend and frontend workflows SSH into the VPS and call:

```bash
/opt/portfolio/scripts/deploy.sh backend docker.io/OWNER/portfolio-backend:SHA
/opt/portfolio/scripts/deploy.sh frontend docker.io/OWNER/portfolio-frontend:SHA
```

The script pulls the new image, updates `.env`, restarts only the target service, restarts Nginx if needed, and runs health checks.

## Required GitHub Secrets

- `VPS_HOST`
- `VPS_USER`
- `VPS_PORT`
- `VPS_SSH_KEY`
- `SONAR_HOST_URL`
- `SONAR_TOKEN`
- `DEPLOY_WEBHOOK_URL`
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

Docker Hub images can be public, so the VPS does not need registry credentials to pull them. If you want authenticated pulls for rate limits or private images, set `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` in `/opt/portfolio/.env`.

## SSL Renewal

Add a host cron entry for the deploy user:

```cron
0 3 * * * cd /opt/portfolio && ./scripts/renew-ssl.sh >> /opt/portfolio/logs/ssl-renew.log 2>&1
```

## Backups

Run:

```bash
./scripts/backup.sh
```

The script stores PostgreSQL dumps and MinIO volume archives under `./backups` and deletes files older than `BACKUP_RETENTION_DAYS`.

## Adding Monitoring Later

Add monitoring services to the same Compose project on a separate internal network, then scrape Nginx and app health endpoints. This repo deliberately leaves that stack out for a later lesson.
