# Deploy and Host Pterodactyl Panel on Railway

Pterodactyl Panel is the control plane game server hosts use to create, monitor, and manage servers across one or more nodes. This template deploys it pinned to a known-good version, with its encryption key on a volume, an administrator account ready on first boot, and a first-deploy migration race closed — verified live, by actually logging in, not assumed from documentation.

## About Hosting Pterodactyl Panel

The panel itself is a fairly ordinary PHP/React web app — the real complexity is everything it needs *around* it: a stable encryption key across redeploys, a database that's genuinely finished initializing before migrations run, and an account to log in with on day one. Get any one of those wrong and the symptom is the same — Railway reports "successfully deployed," and the login page goes nowhere.

## How Pterodactyl Panel Actually Works

Pterodactyl splits into two halves this template's name makes easy to conflate. The **Panel** — what this template deploys — is purely the control plane: a Laravel app backed by a database, holding your users, nodes, and servers' metadata. It never runs a game server itself.

**Wings** is the actual work: a Go daemon on each machine you dedicate to hosting, translating Panel instructions into Docker containers — one per game server. The Panel never touches Docker directly; Wings does, on infrastructure you provision and register separately.

Servers are configured through **Eggs**, grouped into **Nests** — a Nest is a category like "Minecraft," an Egg inside it is a specific startup config (Paper, Forge, Counter-Strike, and so on). The Panel seeds a default set on first install — you'll see it in this template's own deploy logs (`Updating Eggs for Nest: Minecraft`, `Created Paper`, and so on).

So this template gets you a fully working control plane with a real admin login on the first try. Hosting an actual game server still needs at least one Wings node — a separate Docker-capable machine, registered from inside the Panel, deliberately outside this template's scope.

## What the Existing Template Gets Wrong

**No volume, so no stable key.** The entrypoint writes `APP_KEY` into `/app/var/.env`, regenerating it whenever that file is missing. Without a volume, every deploy gets a *different* key — and Pterodactyl encrypts node tokens and 2FA secrets with it, so after a redeploy they silently stop decrypting. Fixed here: `/app/var` is a volume, `APP_KEY` is a stable variable.

**No administrator, ever.** The stock image migrates and starts nginx; nothing creates a user. You get a working login page with zero accounts that can use it, unless you shell into the container and run `p:user:make` yourself.

**reCAPTCHA on by default.** On a fresh panel the verification middleware throws before credentials are checked, so every login 500s regardless of password. Off by default here.

**`:latest`, and a Redis image that stopped pulling.** Two deploys a month apart aren't the same panel on `:latest`. The stock template's Redis uses a Bitnami image; Bitnami closed its public tag catalogue, so that pull now fails quietly. This template pins `panel:v1.14.1` and the official `redis:8.6.5-alpine`.

## The Bug That Only Shows Up in a Live Deploy

The four fixes above are all visible just reading the Dockerfile. The fifth only showed up by actually deploying and trying to log in.

Fresh MariaDB volume, no cache: the admin account was created successfully — logged with a UUID in the deploy output — but `POST /auth/login` with the correct password came back `500`, a generic `QueryException`. Flipping `APP_DEBUG` on and retrying got the same generic error — Pterodactyl's API handler doesn't leak stack traces even in debug mode, a dead end.

The real signal: redeploying the same service, zero code changes, then the same login worked immediately. That's the signature of a race, not a bug in the code. The base image's entrypoint checks database readiness with a bare TCP connect. MariaDB can open that port before it's finished creating its own database and user from `MARIADB_DATABASE`/`MARIADB_USER` on a fresh volume — so migrations run against a database still finishing its own setup. Some land (enough for `users`, which is why admin creation still works), others silently don't, leaving login broken on whichever table came later.

The fix doesn't touch the base entrypoint — reimplementing Pterodactyl's own migration logic would be fragile. Instead, `start-with-admin.sh`, right where the entrypoint already hands off control, re-runs `php artisan migrate --force` before the admin check. Migrations are idempotent, so this is a no-op on every later boot and closes the race on the first one.

## Verified, Twice

Both runs used a brand-new project, a brand-new MariaDB volume, and no build cache:

- **Without the fix:** admin created; first login returned `500 QueryException`; a redeploy with no other change fixed it.
- **With the fix:** admin created; first login succeeded immediately — `root_admin: true`, no redeploy needed.

Both runs also confirmed the credential check works both ways: a wrong password gets `400 "No account matching those credentials could be found."`, and the generated password logs straight in.

## Why MariaDB and Not MySQL

MySQL 9 requires TLS and rejects its own self-signed certificate on the way in, so migrations never run — a login page over an empty database. MariaDB is what Pterodactyl's own docs use, and doesn't have this problem.

## Configuration

Almost nothing needs your input. `APP_KEY` encrypts node tokens and 2FA secrets — auto-generated once, stable across redeploys via the volume; changing it later makes existing encrypted values unreadable. `ADMIN_EMAIL`/`ADMIN_USERNAME`/`ADMIN_PASSWORD` are your first login — change the email from inside the panel afterward. `RECAPTCHA_ENABLED` defaults off for the reason above. `DB_*`/`REDIS_*` are reference variables pointing at the MariaDB/Redis services this template also creates — no need to touch them.

## Common Use Cases

- Running a Minecraft, Rust, or Source-engine hosting business across multiple Wings nodes
- Self-hosting for a friend group or community without a commercial panel provider's fee
- Learning Pterodactyl's Eggs/Nests system with a panel that's cheap to tear down and redeploy

## Dependencies and Implementation Details

Three services, wired together: the **Panel** (this repo, built from `ghcr.io/pterodactyl/panel:v1.14.1`), **Redis** for cache/session/queue, and **MariaDB** for the database. This template replaces only the entrypoint's final *command*, never the entrypoint itself, so the admin-creation and migration-re-run steps run exactly at hand-off, without reimplementing Pterodactyl's own setup. A **Wings node** is the one piece deliberately not provisioned — a separate machine you register from inside the panel afterward. See [pterodactyl.io](https://pterodactyl.io) for Wings installation.

## How It Compares

**Vs. Pelican Panel**, a newer fork: smaller install base, fewer community Eggs, less battle-testing. **Vs. a from-scratch VPS**: you'd wire the same three services and solve the same key-persistence and first-account problems yourself before even reaching Wings. **Vs. a commercial panel provider**: trade a monthly fee for running it yourself.

## Getting Started

Deploy the template. Log in with `admin@example.com` and the generated `ADMIN_PASSWORD` on the Panel service — change the email from inside the panel. Then register a Wings node and create your first server from a pre-seeded Egg.

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
