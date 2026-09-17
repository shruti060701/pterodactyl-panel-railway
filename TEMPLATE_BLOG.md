# Deploy and Host Pterodactyl Panel on Railway

Pterodactyl Panel is the control plane game server hosts use to create, monitor, and manage servers across one or more nodes. This template deploys it pinned to a known-good version, with its encryption key on a volume, an administrator account ready on first boot, and a first-deploy migration race closed — verified live, by actually logging in, not assumed from documentation.

## About Hosting Pterodactyl Panel

The panel is a fairly ordinary PHP/React web app — the real complexity is everything it needs *around* it: a stable encryption key across redeploys, a database genuinely finished initializing before migrations run, and an account to log in with on day one. Get any one wrong and the symptom is the same — Railway reports "successfully deployed," and the login page goes nowhere.

Pterodactyl splits into two halves this template's name makes easy to conflate. The **Panel** is purely the control plane: a Laravel app holding your users, nodes, and servers' metadata — it never runs a game server itself. **Wings** is the actual work: a Go daemon on each machine you dedicate to hosting, translating Panel instructions into Docker containers, one per game server. Servers are configured through **Eggs**, grouped into **Nests** (Minecraft, Source Engine, and so on) — the Panel seeds a default set on first install, visible right in this template's own deploy logs.

## What the Existing Template Gets Wrong

**No volume, so no stable key.** The entrypoint writes `APP_KEY` into `/app/var/.env`, regenerating it whenever that file is missing. Without a volume, every deploy gets a *different* key — and Pterodactyl encrypts node tokens and 2FA secrets with it, so after a redeploy they silently stop decrypting. Fixed here: `/app/var` is a volume, `APP_KEY` is a stable variable.

**No administrator, ever.** The stock image migrates and starts nginx; nothing creates a user — a working login page with zero accounts that can use it, unless you shell in and run `p:user:make` yourself.

**reCAPTCHA on by default** throws before credentials are checked on a fresh panel, so every login 500s regardless of password. Off by default here.

**`:latest`, and a Redis image that stopped pulling.** The stock Redis service uses a Bitnami image; Bitnami closed its public tag catalogue, so that pull now fails quietly. This template pins `panel:v1.14.1` and the official `redis:8.6.5-alpine`.

## The Bug That Only Shows Up in a Live Deploy

The fixes above are all visible just reading the Dockerfile. This one only showed up by actually deploying and trying to log in. Fresh MariaDB volume, no cache: admin created successfully, but `POST /auth/login` with the correct password came back `500 QueryException`. Flipping `APP_DEBUG` on got the same generic error — Pterodactyl's API handler doesn't leak stack traces even in debug mode.

The real signal: redeploying the same service, zero code changes, then the same login worked. That's a race, not a code bug. The base entrypoint checks database readiness with a bare TCP connect — MariaDB can open that port before it's finished creating its own database and user on a fresh volume, so migrations run against a database still finishing setup. Some land (enough for `users`, which is why admin creation still works), others silently don't.

The fix doesn't touch the base entrypoint. Instead, `start-with-admin.sh` re-runs `php artisan migrate --force` before the admin check, right where the entrypoint already hands off control. Migrations are idempotent, so this is a no-op on every later boot and closes the race on the first one.

**Verified, twice**, both on a brand-new project, brand-new volume, no build cache — without the fix, first login 500'd and a redeploy fixed it; with the fix, first login succeeded immediately with `root_admin: true`. Both runs also confirmed a wrong password correctly gets rejected.

MariaDB, not MySQL, because MySQL 9 requires TLS and rejects its own self-signed certificate on the way in, so migrations never run at all. MariaDB is what Pterodactyl's own docs use.

## Configuration

Almost nothing needs your input. `APP_KEY` is auto-generated once and stable via the volume — changing it later makes existing encrypted values unreadable. `ADMIN_EMAIL`/`ADMIN_USERNAME`/`ADMIN_PASSWORD` are your first login; change the email from inside the panel afterward. `DB_*`/`REDIS_*` are reference variables pointing at the MariaDB/Redis services this template also creates.

## Common Use Cases

- Running a Minecraft, Rust, or Source-engine hosting business across multiple Wings nodes
- Self-hosting for a friend group or community without a commercial panel provider's fee
- Learning Pterodactyl's Eggs/Nests system with a panel that's cheap to tear down and redeploy

## Dependencies for Pterodactyl Panel Hosting

Running Pterodactyl Panel means running three services together, plus at least one separate machine to actually host game servers.

### Deployment Dependencies

Three services, wired together automatically: the **Panel** (this repo, built from `ghcr.io/pterodactyl/panel:v1.14.1`), **Redis** (`redis:8.6.5-alpine`) for cache/session/queue, and **MariaDB** (`mariadb:11.8.8`) for the database. A **Wings node** is the one piece deliberately not provisioned here — a separate Docker-capable machine you register from inside the panel afterward, with its own open ports. See [pterodactyl.io](https://pterodactyl.io) for Wings installation.

### Implementation Details

This template replaces only the base image's entrypoint *command*, never the entrypoint itself, so the admin-creation step (and the migration re-run that fixes the race above) runs exactly at hand-off, without reimplementing any of Pterodactyl's own setup logic.

## Why Deploy Pterodactyl Panel on Railway

The alternative is a VPS: install Docker, configure MariaDB and Redis by hand, wire up networking and a domain, then deploy the panel and hope the encryption key survives your next redeploy. Railway replaces all of that with three pre-wired services, a public domain, and persistent volumes attached from the start — and this template additionally fixes the two bugs (missing admin, first-boot migration race) that would otherwise leave a fresh deploy unusable regardless of platform.

Against a commercial game-hosting panel provider: you trade a monthly per-slot fee for running the infrastructure yourself, worthwhile once you're comfortable operating servers.

## Frequently Asked Questions

### Why does my login fail right after deploying the stock template?
Two causes, both fixed here: no admin account gets created at all, and a first-boot migration race can leave the schema incomplete until a redeploy.

### Does this template run game servers?
No — the Panel only. Game servers run on separate Wings nodes, deliberately not part of this template.

### Do I need a Wings node right away?
No — you can log in and explore without one, but you'll need at least one before creating a real server.

### Is my APP_KEY safe to regenerate later?
No — it makes anything already encrypted with it (node tokens, 2FA secrets) unreadable. It's stable specifically so you never touch it.

### Where can I download Pterodactyl?
[github.com/pterodactyl/panel](https://github.com/pterodactyl/panel), Wings at [github.com/pterodactyl/wings](https://github.com/pterodactyl/wings).

Source for this template: https://github.com/shruti060701/pterodactyl-panel-railway (fork of https://github.com/ak40u/pterodactyl-railway-starter, MIT, with the migration-race fix applied)
