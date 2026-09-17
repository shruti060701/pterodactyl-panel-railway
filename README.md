# Deploy and Host Pterodactyl Panel on Railway

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new/template/TEMPLATE_CODE)

Pterodactyl Panel is the game-server control panel used to manage nodes, servers, and users. This template deploys the panel pinned to a specific version, with its encryption key on a volume and an administrator account created for you on first boot — fixing the two problems that make the existing marketplace template lose data or leave you locked out.

## What's Included

| Service | Image / Source | Purpose |
|---|---|---|
| **Panel** | `ghcr.io/pterodactyl/panel:v1.14.1` (built from this repo) | The web control panel |
| **Redis** | `redis:8.6.5-alpine` | Cache, session, and queue driver |
| **MariaDB** | `mariadb:11.8.8` | Panel database |

## What This Fixes

**No volume, so no stable encryption key.** The panel's entrypoint writes `APP_KEY` into `/app/var/.env` and generates a new one whenever that file is missing. Without a volume, every deploy gets a *different* key — and Pterodactyl encrypts node tokens and 2FA secrets with it, so after a redeploy they stop decrypting. Here `/app/var` is a volume and `APP_KEY` is a template variable, so the key is stable.

**No administrator account.** The stock image runs migrations and starts the web server; nothing creates the first user. You'd get a login page and no way in except a shell into the container. This template's `start-with-admin.sh` runs `p:user:make` after the image's own entrypoint has migrated — first boot only, so a redeploy never resets your password.

**A first-boot migration race.** MariaDB can accept TCP connections before it's actually finished creating its own database and user, and the base image's readiness check is a bare TCP connect — so on a brand-new database, a handful of migrations can silently fail to apply while others succeed. Reproduced live: fresh deploy, login 500'd with a generic `QueryException`, worked after a redeploy with no other change. Fixed by re-running `php artisan migrate --force` in `start-with-admin.sh` before the admin check — migrations are idempotent, so this is a no-op on every later boot and closes the race on the first one.

**reCAPTCHA on by default breaks login.** On a fresh self-hosted panel the verification middleware throws before credentials are checked, so every login attempt 500s. Off here by default; turn it on once you have your own keys.

**Unpinned image, and a Redis image that no longer pulls reliably.** The stock template uses `:latest` — two deploys a month apart aren't the same panel. This one pins `v1.14.1`. The Redis service uses the official `redis:8.6.5-alpine` rather than a Bitnami image (Bitnami closed its public tag catalogue, so that pull now fails quietly).

## Verified

By logging in — twice. Deployed fresh from this repo (new MariaDB volume, no cache), `POST /auth/login` with the generated `ADMIN_PASSWORD` returned the admin account with `root_admin: true` on the very first deploy. A wrong password is rejected with "No account matching those credentials could be found."

## Post-Deployment

Nothing to configure. Log in at your assigned domain with `admin@example.com` and the generated `ADMIN_PASSWORD` (see the Panel service's variables) — change the email in the panel afterwards.

**Nodes are separate.** The panel is only half of Pterodactyl. Game servers run on Wings daemons, which need Docker and their own ports — that's a machine you run yourself, not a service in this template.

## Why MariaDB, Not MySQL

MySQL 9 requires TLS and rejects its own self-signed certificate on the way in, so migrations never run and you get a login page over an empty database. MariaDB is what Pterodactyl's own docs use anyway.

## Environment Variables

See `TEMPLATE_COMPOSER_CHECKLIST.md` for the full variable reference. Everything needed to log in is generated automatically — `APP_KEY`, `ADMIN_PASSWORD`, `HASHIDS_SALT`, and both database passwords.

## Dependencies for Pterodactyl Panel Hosting

- Panel image: [ghcr.io/pterodactyl/panel](https://github.com/pterodactyl/panel/pkgs/container/panel)
- Panel source: https://github.com/pterodactyl/panel
- This repo (start script + Dockerfile): https://github.com/ak40u/pterodactyl-railway-starter (MIT), with a migration-race fix applied

## Why Deploy Pterodactyl Panel on Railway?

Self-hosting the panel usually means provisioning a VPS, installing Docker, MariaDB, and Redis by hand, and wiring them together yourself. Railway collapses that into a one-click deploy with all three services pre-wired, persistent storage attached, and a public domain generated automatically.
