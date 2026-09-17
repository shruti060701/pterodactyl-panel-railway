## Template Titles

**Railway Title:** `Pterodactyl Panel`
**Railway Description:** `Pterodactyl Panel — Pinned, Key on a Volume, Admin Created on First Boot`
**Spreadsheet Title:** `Pterodactyl Panel (Game Server Control Panel, Fixed Migration Race)`
**GitHub Description:** `Pterodactyl Panel on Railway — pinned image, encryption key on a volume, admin account created on first boot, and a first-deploy migration race fixed. Deploy with one click.`

---

# Deploy and Host Pterodactyl Panel on Railway

Pterodactyl Panel is the web control panel game server hosts use to create, manage, and monitor servers across one or more nodes. This template deploys the panel pinned to a known-good version, with its encryption key on a volume and an administrator account ready on first boot, so a fresh deploy is actually usable instead of an empty login page.

## About Hosting Pterodactyl Panel on Railway

Self-hosting Pterodactyl on Railway means the panel, its database, and its cache all run on infrastructure you control, wired together automatically. Railway provisions all three services, attaches persistent storage to the panel and the database, and creates your first admin login — from a single deploy, with no shell access required to get in.

## Common Use Cases

- **Running a Minecraft, Rust, or Ark hosting business**: the panel manages servers across your nodes with a real user-facing dashboard
- **Self-hosting for a friend group or community**: full admin control without paying a commercial game-hosting panel provider
- **Multi-node game server management**: the panel is the control plane; nodes (running Wings) are the machines actually running game servers
- **Learning Pterodactyl before committing to production infrastructure**: a working panel in one click, cheap to tear down and redeploy

## Dependencies for Pterodactyl Panel Hosting

- **MariaDB** — the panel's database (11.8.8, official image)
- **Redis** — cache, session, and queue driver (8.6.5-alpine, official image)
- **A Wings node** — separate infrastructure you run yourself to actually host game servers; the panel alone only manages them

### Deployment Dependencies

- Panel image: [ghcr.io/pterodactyl/panel](https://github.com/pterodactyl/panel/pkgs/container/panel)
- Panel source: https://github.com/pterodactyl/panel
- Wings (the node daemon, deployed separately): https://github.com/pterodactyl/wings

### Implementation Details

The panel's own container entrypoint handles migrations and startup; this template replaces only the final *command*, not the entrypoint, so a first-boot step can create an administrator without reimplementing any of Pterodactyl's own setup. That first-boot step also re-runs migrations before checking for an admin account — closing a real race where MariaDB can accept connections before it's finished creating its own database, which otherwise leaves a fresh deploy's login broken until a redeploy.

### Why Deploy Pterodactyl Panel on Railway?

The alternative is a VPS: install Docker, install and configure MariaDB and Redis by hand, get networking and a domain working, then deploy the panel and hope the encryption key survives your next `docker-compose up`. Railway replaces all of that with three pre-wired services, a public domain, and persistent volumes attached from the start.

## Official Pricing of Pterodactyl Panel

Pterodactyl is free and open-source. Self-hosting it costs only your infrastructure bill.

### Monthly Cost of Self-Hosting Pterodactyl Panel on Railway

Three lightweight services (panel, MariaDB, Redis) typically run in the $5–15/month range depending on traffic and database size — small for a handful of managed nodes, more if you're running a larger hosting operation.

## Frequently Asked Questions (FAQs)

### What is Pterodactyl Panel?
The web dashboard for managing game servers across one or more nodes — creating servers, managing users, and monitoring resource usage.

### Is Pterodactyl free to use?
Yes, fully open-source. You pay only for the infrastructure to run the panel and your Wings nodes.

### Do I need to set anything up before logging in?
No. The admin account, encryption key, and both database passwords are generated automatically. Log in with `admin@example.com` and the generated `ADMIN_PASSWORD`.

### Why does my login fail right after deploying the stock template?
Two likely causes, both fixed here: no administrator account gets created by the stock image at all, and a first-boot migration race against a brand-new MariaDB database can leave the schema incomplete until a redeploy. This template fixes both.

### Does this template run game servers?
No — it runs the panel only. Game servers run on separate Wings node machines, which need Docker and their own ports and are not part of this template.

### Where can I download Pterodactyl?
Source is on GitHub at [github.com/pterodactyl/panel](https://github.com/pterodactyl/panel). Use this template to deploy it correctly configured in one click.
