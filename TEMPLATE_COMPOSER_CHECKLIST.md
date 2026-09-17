# Template Composer Checklist — Pterodactyl Panel

Full variable reference, pulled from a live, tested deployment (fresh MariaDB volume, no cache, verified by logging in on the first deploy).

## Service: Panel

Source: GitHub repo (this fork) · Volume: `/app/var`

| Variable | Value | Optional? | Description |
|---|---|---|---|
| `ADMIN_EMAIL` | `admin@example.com` | No | Login email for the auto-created administrator. |
| `ADMIN_PASSWORD` | `${{secret(24)}}` | No | Login password for the auto-created administrator. |
| `ADMIN_USERNAME` | `admin` | No | Login username. |
| `APP_DEBUG` | `false` | No | Keep off in production — debug mode leaks stack traces in API error responses. |
| `APP_ENV` | `production` | No | |
| `APP_ENVIRONMENT_ONLY` | `false` | No | |
| `APP_KEY` | `base64:${{secret(43, 'abc...')}}=` | No | Encrypts node tokens and 2FA secrets. Stable because `/app/var` is a volume — changing this after first boot makes existing encrypted values unreadable. |
| `APP_TIMEZONE` | `UTC` | No | |
| `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | No | |
| `CACHE_DRIVER` | `redis` | No | |
| `DB_DATABASE` | `${{MariaDB.MARIADB_DATABASE}}` | No | |
| `DB_HOST` | `${{MariaDB.RAILWAY_PRIVATE_DOMAIN}}` | No | |
| `DB_PASSWORD` | `${{MariaDB.MARIADB_PASSWORD}}` | No | |
| `DB_PORT` | `3306` | No | |
| `DB_USERNAME` | `${{MariaDB.MARIADB_USER}}` | No | |
| `HASHIDS_SALT` | `${{secret(20)}}` | No | |
| `LOG_CHANNEL` | `stderr` | No | |
| `MAIL_MAILER` | `log` | No | |
| `PORT` | `8080` | No | nginx is rewritten to listen on this at boot — see `start-with-admin.sh`. |
| `QUEUE_CONNECTION` | `redis` | No | |
| `RAILWAY_RUN_UID` | `0` | No | |
| `RECAPTCHA_ENABLED` | `false` | No | On by default in the stock image, and it breaks login on a fresh panel — see README. |
| `REDIS_HOST` | `${{Redis.RAILWAY_PRIVATE_DOMAIN}}` | No | |
| `REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | No | |
| `REDIS_PORT` | `6379` | No | |
| `SESSION_DRIVER` | `redis` | No | |
| `TRUSTED_PROXIES` | `*` | No | |

Networking: a service domain (`<hasDomain>`) — no TCP proxy needed, this is a plain HTTP service.

## Service: Redis

Image: `redis:8.6.5-alpine` · Volume: `/data`

Start command (required — the image needs the password argument wired in):
```
/bin/sh -c 'redis-server --requirepass "$REDIS_PASSWORD" --appendonly yes --bind 0.0.0.0 :: --protected-mode no'
```

| Variable | Value | Optional? |
|---|---|---|
| `RAILWAY_RUN_UID` | `0` | No |
| `REDIS_PASSWORD` | `${{secret(32)}}` | No |

## Service: MariaDB

Image: `mariadb:11.8.8` · Volume: `/var/lib/mysql`

| Variable | Value | Optional? |
|---|---|---|
| `MARIADB_DATABASE` | `panel` | No |
| `MARIADB_PASSWORD` | `${{secret(32)}}` | No |
| `MARIADB_ROOT_PASSWORD` | `${{secret(32)}}` | No |
| `MARIADB_USER` | `pterodactyl` | No |

## Composer Setup Notes — Read Before Publishing

**The migration-race fix requires this fork, not the upstream repo directly.** `start-with-admin.sh` re-runs `php artisan migrate --force` before the admin-account check. Point the Panel service's source at `shruti060701/pterodactyl-panel-railway`, not `ak40u/pterodactyl-railway-starter`.

**Verified live, twice, on a completely fresh deployment (new project, new MariaDB volume, no build cache):**
- Without the fix: first-ever login attempt returned `500 QueryException`; a redeploy with zero other changes fixed it.
- With the fix: first-ever login attempt succeeded immediately — `root_admin: true`, no redeploy needed.

Both runs confirmed the credential check itself is correct in both directions: a wrong password is rejected with `400 "No account matching those credentials could be found."`, and the generated `ADMIN_PASSWORD` returns the admin account.

No healthcheck path is required — Pterodactyl doesn't ship a dedicated `/health` endpoint, and `/auth/login` returning `200` is enough signal that migrations completed.
