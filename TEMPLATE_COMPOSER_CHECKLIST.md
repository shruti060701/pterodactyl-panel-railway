# Template Composer Checklist — Pterodactyl Panel

Full variable reference, pulled from a live, tested deployment (fresh MariaDB volume, no cache, verified by logging in on the first deploy).

## Service: Panel

Source: GitHub repo (this fork) · Volume: `/app/var`

| Variable | Value | Optional? | Description |
|---|---|---|---|
| `ADMIN_EMAIL` | `admin@example.com` | No | Login email for the administrator account created on first boot. Change it in the panel after logging in. |
| `ADMIN_PASSWORD` | `${{secret(24)}}` | No | Login password for the auto-created administrator. Auto-generated — copy it from this service's variables to log in. |
| `ADMIN_USERNAME` | `admin` | No | Login username for the auto-created administrator. |
| `APP_DEBUG` | `false` | No | Laravel debug mode. Keep off in production — on a public deploy it leaks stack traces in API error responses. |
| `APP_ENV` | `production` | No | Laravel environment name. Affects logging verbosity and error presentation; leave as `production`. |
| `APP_ENVIRONMENT_ONLY` | `false` | No | Pterodactyl setting restricting certain admin actions to non-production environments. Leave `false` for a real deployment. |
| `APP_KEY` | `base64:${{secret(43, 'abc...')}}=` | No | Encrypts node tokens and 2FA secrets. Stable because `/app/var` is a volume — changing this after first boot makes existing encrypted values unreadable, so leave it alone once the panel is running. |
| `APP_TIMEZONE` | `UTC` | No | Timezone used for logs and scheduled tasks. Change to your own timezone if you'd rather not read UTC timestamps. |
| `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | No | The panel's own public URL — used to build links it sends itself (e.g. in emails). Resolves automatically to your Railway domain. |
| `CACHE_DRIVER` | `redis` | No | Backend for Laravel's cache layer. Points at the Redis service — don't change unless you're replacing Redis entirely. |
| `DB_DATABASE` | `${{MariaDB.MARIADB_DATABASE}}` | No | Database name the panel connects to. References the MariaDB service's own `MARIADB_DATABASE` value. |
| `DB_HOST` | `${{MariaDB.RAILWAY_PRIVATE_DOMAIN}}` | No | MariaDB's private network hostname. Resolves automatically once the MariaDB service exists — private networking, not the public internet. |
| `DB_PASSWORD` | `${{MariaDB.MARIADB_PASSWORD}}` | No | Database password. References the MariaDB service's own `MARIADB_PASSWORD` value — kept in sync automatically. |
| `DB_PORT` | `3306` | No | MariaDB's port. Standard MySQL/MariaDB port — no reason to change it. |
| `DB_USERNAME` | `${{MariaDB.MARIADB_USER}}` | No | Database username. References the MariaDB service's own `MARIADB_USER` value. |
| `HASHIDS_SALT` | `${{secret(20)}}` | No | Salt used to obfuscate numeric IDs in URLs (e.g. server IDs). Auto-generated; changing it later just changes how existing IDs are encoded in links. |
| `LOG_CHANNEL` | `stderr` | No | Where Laravel writes application logs. `stderr` routes them into the container's log stream so they show up in Railway's deploy logs. |
| `MAIL_MAILER` | `log` | No | How the panel sends email (password resets, notifications). `log` writes mail to the log instead of actually sending — set up a real mailer if you need working email. |
| `PORT` | `8080` | No | The port nginx is rewritten to listen on at container boot — see `start-with-admin.sh`. Railway routes your public domain to this automatically. |
| `QUEUE_CONNECTION` | `redis` | No | Backend for Laravel's queued jobs. Points at the Redis service — don't change unless you're replacing Redis entirely. |
| `RAILWAY_RUN_UID` | `0` | No | Container user ID Railway runs the process as. `0` (root) is required here for the panel's file permission handling to work correctly. |
| `RECAPTCHA_ENABLED` | `false` | No | On by default in the stock image, and it breaks login on a fresh panel — the verification middleware throws before credentials are checked. Off here; turn on once you have your own reCAPTCHA keys configured. |
| `REDIS_HOST` | `${{Redis.RAILWAY_PRIVATE_DOMAIN}}` | No | Redis's private network hostname. Resolves automatically once the Redis service exists. |
| `REDIS_PASSWORD` | `${{Redis.REDIS_PASSWORD}}` | No | Redis password. References the Redis service's own `REDIS_PASSWORD` value — kept in sync automatically. |
| `REDIS_PORT` | `6379` | No | Redis's port. Standard Redis port — no reason to change it. |
| `SESSION_DRIVER` | `redis` | No | Backend for Laravel's session storage. Points at the Redis service — don't change unless you're replacing Redis entirely. |
| `TRUSTED_PROXIES` | `*` | No | Which upstream proxies Laravel trusts for forwarded IP/protocol headers. `*` trusts all, which is correct behind Railway's own edge proxy. |

Networking: a service domain (`<hasDomain>`) — no TCP proxy needed, this is a plain HTTP service.

## Service: Redis

Image: `redis:8.6.5-alpine` · Volume: `/data`

Start command (required — the image needs the password argument wired in):
```
/bin/sh -c 'redis-server --requirepass "$REDIS_PASSWORD" --appendonly yes --bind 0.0.0.0 :: --protected-mode no'
```

| Variable | Value | Optional? | Description |
|---|---|---|---|
| `RAILWAY_RUN_UID` | `0` | No | Container user ID Railway runs the process as. `0` (root) is required for the custom start command to bind correctly. |
| `REDIS_PASSWORD` | `${{secret(32)}}` | No | Auth password for this Redis instance. Auto-generated; the Panel service reads it back via `${{Redis.REDIS_PASSWORD}}`. |

## Service: MariaDB

Image: `mariadb:11.8.8` · Volume: `/var/lib/mysql`

| Variable | Value | Optional? | Description |
|---|---|---|---|
| `MARIADB_DATABASE` | `panel` | No | Name of the database MariaDB creates on first boot. The Panel service connects to this database by default via `${{MariaDB.MARIADB_DATABASE}}`. |
| `MARIADB_PASSWORD` | `${{secret(32)}}` | No | Password for `MARIADB_USER`. Auto-generated; the Panel service reads it back via `${{MariaDB.MARIADB_PASSWORD}}`. |
| `MARIADB_ROOT_PASSWORD` | `${{secret(32)}}` | No | Password for the MariaDB `root` superuser. Auto-generated. Not used by the Panel service day-to-day — only needed if you connect directly as root for maintenance. |
| `MARIADB_USER` | `pterodactyl` | No | Database user the panel connects as. Granted access to `MARIADB_DATABASE` automatically on first boot. |

## Composer Setup Notes — Read Before Publishing

**The migration-race fix requires this fork, not the upstream repo directly.** `start-with-admin.sh` re-runs `php artisan migrate --force` before the admin-account check. Point the Panel service's source at `shruti060701/pterodactyl-panel-railway`, not `ak40u/pterodactyl-railway-starter`.

**Verified live, twice, on a completely fresh deployment (new project, new MariaDB volume, no build cache):**
- Without the fix: first-ever login attempt returned `500 QueryException`; a redeploy with zero other changes fixed it.
- With the fix: first-ever login attempt succeeded immediately — `root_admin: true`, no redeploy needed.

Both runs confirmed the credential check itself is correct in both directions: a wrong password is rejected with `400 "No account matching those credentials could be found."`, and the generated `ADMIN_PASSWORD` returns the admin account.

No healthcheck path is required — Pterodactyl doesn't ship a dedicated `/health` endpoint, and `/auth/login` returning `200` is enough signal that migrations completed.
