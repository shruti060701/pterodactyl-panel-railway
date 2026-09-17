# Deploy and Host Pterodactyl Panel on Railway

Pterodactyl Panel is the control plane game server hosts use to create, monitor, and manage servers across one or more nodes. This template deploys it pinned to a known-good version, with its encryption key on a volume, an administrator account ready on first boot, and a first-deploy migration race closed — verified live, by actually logging in, not assumed from documentation.

## About Hosting Pterodactyl Panel

The panel itself is just a Laravel web app — the real complexity is in what it needs to run correctly: a stable encryption key across redeploys, a database that's fully ready before migrations run against it, and an account to log in with. Get any of those wrong and you have a container that reports "successfully deployed" and a login page that goes nowhere.

## What the Existing Template Gets Wrong

**No volume, so no stable key.** The panel's entrypoint writes `APP_KEY` into `/app/var/.env`, generating a new one whenever that file is missing. Without a volume, every deploy is a fresh container — so every deploy gets a *different* key. Pterodactyl encrypts node tokens and 2FA secrets with that key; after a redeploy, they no longer decrypt. This isn't a cosmetic bug — it's silent, compounding data loss. Fixed here by making `/app/var` a volume and `APP_KEY` a stable template variable.

**No administrator, ever.** The stock image runs migrations and starts nginx; nothing creates a user. You get a real, working login *page* — with zero accounts able to use it — unless you open a shell into the container and run `p:user:make` by hand.

**reCAPTCHA on by default.** On a fresh self-hosted panel, the verification middleware throws before credentials are even checked, so every login attempt 500s regardless of whether the password is right. Off by default here; turn it on once you have your own reCAPTCHA keys.

**`:latest` and a Redis image that stopped pulling.** Two deploys a month apart aren't the same panel on `:latest`. And the stock template's Redis service uses a Bitnami image — Bitnami closed its public tag catalogue, so that pull now fails quietly, taking the whole stack down with it. This template pins `panel:v1.14.1` and uses the official `redis:8.6.5-alpine`.

## The Bug That Doesn't Show Up in the Code — Only in a Live Deploy

Fixing the four problems above was the easy part; they're all visible by reading the Dockerfile and entrypoint script. The fifth one only showed up by actually deploying the fixed template from scratch and trying to log in.

First deploy, fresh MariaDB volume, no cache: the admin account got created successfully (logged, with a UUID, right there in the deploy output), but `POST /auth/login` with the correct generated password came back `500`, with a generic `QueryException` — no useful detail, since `APP_DEBUG` is off by default in production. Turning debug mode on temporarily and retrying got the same generic error, because Pterodactyl's API error handler doesn't leak stack traces to the client even in debug mode. The real signal came from redeploying the exact same service with zero code changes: login worked immediately afterward.

That's the signature of a race, not a code bug. Here's what's actually happening: the base panel image's entrypoint checks database readiness with a bare TCP connect — "is port 3306 accepting connections?" MariaDB's own startup process opens that port *before* it's finished creating its database and user from the `MARIADB_DATABASE`/`MARIADB_USER` environment variables, on a completely fresh volume. So the panel's entrypoint sees "port's open, let's migrate" and starts running migrations against a database that's still finishing its own first-time setup. Some migrations land — enough to create the `users` table, which is why admin creation still succeeds — and others silently don't, leaving just enough of the schema in place to *look* deployed while login itself breaks.

The fix doesn't touch the base image's entrypoint — replacing that would mean reimplementing Pterodactyl's own migration and seeding logic, which is fragile and exactly what the reference author avoided by design. Instead, `start-with-admin.sh` — the one place a first-boot step already runs, right where the entrypoint hands off control — simply re-runs `php artisan migrate --force` before the admin-account check. Laravel migrations are idempotent: already-applied migrations are skipped, so this costs nothing on every later boot and closes the race on the very first one.

## Verified, Twice

Both runs used a brand-new Railway project, a brand-new MariaDB volume, and no Docker build cache — the closest reproduction of what a user hitting "Deploy Now" actually experiences.

- **Without the fix:** admin account created successfully; first login attempt returned `500 QueryException`; a redeploy with no other change fixed it.
- **With the fix:** admin account created successfully; first login attempt succeeded immediately — `root_admin: true`, no redeploy needed.

Both runs also confirmed the credential check works correctly in both directions: a wrong password is rejected with `400 "No account matching those credentials could be found."`, and the generated password logs in.

## Why MariaDB and Not MySQL

MySQL 9 requires TLS and rejects its own self-signed certificate on the way in, so migrations never run at all — you get a login page over a completely empty database. MariaDB is what Pterodactyl's own documentation uses anyway, and it doesn't have this problem.

## Configuration

Nothing to fill in. The admin password, encryption key, hashids salt, and both database passwords are generated automatically. Your login is `admin@example.com` with the generated `ADMIN_PASSWORD` — change the email in the panel afterward. Changing `APP_KEY` after first boot makes existing encrypted values unreadable, so leave it alone once the panel's running.

## Nodes Are Separate

The panel is only half of Pterodactyl. Game servers run on Wings daemons, which need Docker and their own ports — that's a machine you run yourself, not a service this template provisions.

Source: https://github.com/shruti060701/pterodactyl-panel-railway (fork of https://github.com/ak40u/pterodactyl-railway-starter, MIT, with the migration-race fix applied)
