# Deploy and Host Pterodactyl Panel on Railway

Pterodactyl Panel is the control plane game server hosts use to create, monitor, and manage servers across one or more nodes — the same panel behind a large share of the Minecraft, Rust, and Source-engine hosting businesses you'd recognize by their dashboard alone. This template deploys it pinned to a known-good version, with its encryption key on a volume, an administrator account ready on first boot, and a first-deploy migration race closed — verified live, by actually logging in, not assumed from documentation.

## About Hosting Pterodactyl Panel

The panel itself is a fairly ordinary PHP/React web app — the real complexity is everything it needs *around* it to work correctly: a stable encryption key across redeploys, a database that's genuinely finished initializing before migrations run against it, and an account to log in with on day one. Get any one of those wrong and the visible symptom is the same either way — a container Railway reports as "successfully deployed," and a login page that goes nowhere.

## How Pterodactyl Panel Actually Works

Pterodactyl splits into two halves that this template's name makes easy to conflate: the Panel and Wings. The **Panel** — what this template deploys — is purely the control plane: a Laravel app backed by a database, holding your users, your nodes, your servers' metadata, and the permissions between them. It never runs a single game server itself.

**Wings** is the actual work: a Go daemon that runs on each physical or virtual machine you dedicate to hosting, listening for instructions from the Panel and translating them into Docker containers — one container per game server, isolated from each other and from the host. When you click "create server" in the Panel, it's really telling a specific Wings node "start this container, with this image, these resource limits, these files." The Panel never touches Docker directly; Wings does all of that, on infrastructure you provision and register separately.

Servers themselves are configured through **Eggs**, grouped into **Nests** — a Nest is a category like "Minecraft" or "Source Engine," and an Egg inside it is a specific startup configuration (Paper, Forge, Counter-Strike, Garry's Mod, and so on), covering the Docker image, the startup command template, and the variables a server of that type needs. The Panel ships with a default set of Nests and Eggs seeded on first install — you'll see that seeding happen in this template's own deploy logs (`Updating Eggs for Nest: Minecraft`, `Created Sponge (SpongeVanilla)`, and so on down the list) — and you can add community or custom Eggs afterward for anything not covered out of the box.

So this template gets you a fully working control plane with a real admin login on the first try. To actually host a game server, you still need at least one Wings node: a separate Docker-capable machine, registered from inside the Panel, with its own ports open for whatever games run on it. That's infrastructure you run yourself — deliberately outside the scope of what a Panel-only template should provision.

## What the Existing Template Gets Wrong

**No volume, so no stable key.** The panel's entrypoint writes `APP_KEY` into `/app/var/.env`, generating a new one whenever that file is missing. Without a volume, every deploy is a fresh container — so every deploy gets a *different* key. Pterodactyl encrypts node tokens and 2FA secrets with that key; after a redeploy, they no longer decrypt, silently. It's not a crash you'd notice immediately — it's a working panel that quietly can't talk to its own nodes anymore. Fixed here by making `/app/var` a volume and `APP_KEY` a stable template variable.

**No administrator, ever.** The stock image runs migrations and starts nginx; nothing creates a user. You get a real, working login *page* — with zero accounts able to use it — unless you open a shell into the container and run `p:user:make` by hand, which most people deploying a template have no path to do at all.

**reCAPTCHA on by default.** On a fresh self-hosted panel, the verification middleware throws before credentials are even checked, so every login attempt 500s regardless of whether the password is right — meaning even someone who *did* manually create an account through a shell would still be locked out at the login form. Off by default here; turn it on once you have your own reCAPTCHA keys.

**`:latest`, and a Redis image that stopped pulling.** Two deploys a month apart aren't the same panel on `:latest` — a breaking upstream change lands on your production panel with zero warning. And the stock template's Redis service uses a Bitnami image; Bitnami closed its public tag catalogue, so that pull now fails quietly, taking the whole stack down with it on any fresh deploy. This template pins `panel:v1.14.1` and uses the official `redis:8.6.5-alpine`.

## The Bug That Doesn't Show Up in the Code — Only in a Live Deploy

Fixing the four problems above was the easy part; they're all visible just by reading the Dockerfile and entrypoint script. The fifth one only showed up by actually deploying the fixed template from scratch and trying to log in.

First deploy, fresh MariaDB volume, no cache: the admin account got created successfully — logged, with a UUID, right there in the deploy output — but `POST /auth/login` with the correct generated password came back `500`, with a generic `QueryException` and no useful detail, since `APP_DEBUG` is off by default in production. The obvious next move was flipping `APP_DEBUG` to `true` and retrying, expecting a full stack trace back from the API. That came back exactly as generic as before — Pterodactyl's API error handler simply doesn't leak stack traces to the client regardless of debug mode, so that particular diagnostic path was a dead end.

The real signal came from doing nothing clever at all: redeploying the exact same service, zero code changes, and trying the same login again. It worked immediately.

That's the signature of a race, not a code bug — a bug you can toggle by redeploying isn't in the code, it's in *timing*. Here's what's actually happening: the base panel image's entrypoint checks database readiness with a bare TCP connect — "is port 3306 accepting connections?" MariaDB's own startup process opens that port *before* it's finished creating its database and user from the `MARIADB_DATABASE`/`MARIADB_USER` environment variables, on a completely fresh volume. So the panel's entrypoint sees "port's open, let's migrate" and starts running migrations against a database that's still finishing its own first-time setup. Some migrations land — enough to create the `users` table, which is why admin creation still succeeds — and others silently don't, leaving just enough of the schema in place to *look* deployed while login itself breaks on whatever table came later in migration order.

The fix doesn't touch the base image's entrypoint — replacing that would mean reimplementing Pterodactyl's own migration and seeding logic, which is fragile and exactly what the original repo's author avoided by design, for good reason. Instead, `start-with-admin.sh` — the one place a first-boot step already runs, right where the entrypoint hands off control — simply re-runs `php artisan migrate --force` before the admin-account check. Laravel migrations are idempotent: already-applied migrations are skipped, so this costs nothing on every later boot and closes the race on the very first one.

## Verified, Twice

Both runs used a brand-new Railway project, a brand-new MariaDB volume, and no Docker build cache — the closest reproduction of what a user hitting "Deploy Now" actually experiences, rather than testing against an already-warm environment that would mask exactly this kind of race.

- **Without the fix:** admin account created successfully; first login attempt returned `500 QueryException`; a redeploy with no other change fixed it.
- **With the fix:** admin account created successfully; first login attempt succeeded immediately — `root_admin: true`, no redeploy needed.

Both runs also confirmed the credential check works correctly in both directions: a wrong password is rejected with `400 "No account matching those credentials could be found."`, and the generated password logs straight in.

## Why MariaDB and Not MySQL

MySQL 9 requires TLS and rejects its own self-signed certificate on the way in, so migrations never run at all — you get a login page over a completely empty database, a different flavor of the same "looks deployed, isn't" problem this template is built around avoiding. MariaDB is what Pterodactyl's own documentation uses anyway, and it doesn't have this problem.

## Understanding the Configuration Variables

Almost nothing here needs your input. `APP_KEY` is the encryption key for node tokens and 2FA secrets — auto-generated once, and because `/app/var` is a volume, stable across every future redeploy. Changing it after first boot makes existing encrypted values unreadable, so once the panel's running, leave it alone.

`ADMIN_EMAIL`, `ADMIN_USERNAME`, and `ADMIN_PASSWORD` are your first login — the password is auto-generated and visible in this service's variables. Change the email address from inside the panel once you're in; the template only uses it to create the account.

`RECAPTCHA_ENABLED` defaults to `false` for the reason covered above — turn it on later from inside the panel once you've registered your own reCAPTCHA site/secret keys with Google.

`DB_*` and `REDIS_*` variables are reference variables pointing at the MariaDB and Redis services this template also creates — you shouldn't need to touch any of them; they resolve automatically and stay in sync if you ever regenerate a password on either service.

## Common Use Cases

- **Running a Minecraft, Rust, or Source-engine hosting business**: the panel manages servers across your Wings nodes with a real user-facing dashboard and per-user permissions
- **Self-hosting for a friend group or community**: full admin control without paying a commercial game-hosting panel provider a monthly fee
- **Multi-node game server management**: one panel, many Wings nodes — scale hosting capacity by adding machines, not by re-deploying the panel
- **Learning Pterodactyl before committing to production infrastructure**: a working, logged-in panel in one click, cheap to tear down and redeploy while you learn the Eggs/Nests system

## Dependencies and Implementation Details

Three services, wired together automatically: the **Panel** (this repo, built from `ghcr.io/pterodactyl/panel:v1.14.1`), **Redis** for cache/session/queue, and **MariaDB** for the panel's own database. The panel image's own entrypoint handles migrations and seeding; this template replaces only the final *command* — never the entrypoint itself — so the first-boot admin-creation step (and the migration re-run that fixes the race above) runs at exactly the moment the entrypoint hands off control, without reimplementing any of Pterodactyl's own setup logic.

A **Wings node** is the one piece this template deliberately doesn't provision: a separate Docker-capable machine you register from inside the panel afterward, with its own open ports for whichever games you plan to host. See [pterodactyl.io](https://pterodactyl.io) for Wings installation.

## How Pterodactyl Compares to Alternatives

**Against Pelican Panel**, a newer fork covering similar ground: Pelican is younger and has a smaller install base, which shows up as fewer community Eggs and less battle-testing across edge cases; Pterodactyl's much larger community means more pre-built Eggs for obscure games and more prior art when something goes wrong.

**Against a from-scratch VPS setup** (Docker Compose, by hand): you'd be wiring together the same three services this template already wires — a database, a cache, and the panel itself — plus solving the same encryption-key persistence and first-account-creation problems this template solves for you, from scratch, before you'd even get to Wings and your first real game server.

**Against a commercial game-hosting panel provider**: you trade a monthly per-slot fee for running the infrastructure yourself. Worth it if you're already comfortable operating servers; not worth it if you'd rather pay someone else to handle uptime and updates.

## Getting Started

Deploy the template. Log in at your assigned domain with `admin@example.com` and the `ADMIN_PASSWORD` generated on the Panel service — change the email from inside the panel once you're in. From there, register a Wings node (a separate machine you provision), and you're ready to create your first server from one of the pre-seeded Eggs.

## Frequently Asked Questions

### Why does my login fail right after deploying the stock template?
Two separate causes, both fixed here: no administrator account gets created by the stock image at all, and a first-boot migration race against a brand-new MariaDB database can leave the schema incomplete until a redeploy. This template fixes both, verified by actually logging in on the first deploy.

### Does this template run game servers?
No — it runs the Panel only, the control plane. Game servers run on separate Wings node machines, which need Docker and their own open ports and aren't part of this template by design.

### What is a Wings node, and do I need one right away?
Wings is the daemon that actually runs game servers in Docker containers, on a machine you register from inside the panel. You don't need one to log in and explore the panel, but you'll need at least one before you can create a real server.

### Can I change the admin email or password after deploying?
Yes, from inside the panel once you've logged in with the generated credentials. The template's `ADMIN_EMAIL`/`ADMIN_PASSWORD` variables only matter for the very first login.

### Why MariaDB instead of MySQL?
MySQL 9 requires TLS and rejects its own self-signed certificate during setup, so migrations never run and you get a login page over an empty database. MariaDB is what Pterodactyl's own docs use, and it doesn't have this problem.

### Is my `APP_KEY` safe to regenerate later?
No — regenerating it after first boot makes any values it already encrypted (node tokens, 2FA secrets) unreadable. It's stable across redeploys specifically so you never need to touch it.

### Where can I download Pterodactyl?
Source is on GitHub at [github.com/pterodactyl/panel](https://github.com/pterodactyl/panel), with Wings at [github.com/pterodactyl/wings](https://github.com/pterodactyl/wings). Use this template to deploy the Panel correctly configured in one click.

Source for this template: https://github.com/shruti060701/pterodactyl-panel-railway (fork of https://github.com/ak40u/pterodactyl-railway-starter, MIT, with the migration-race fix applied)
