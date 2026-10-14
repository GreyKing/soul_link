# Deployment

Production runs in a virtual machine (`web-vm`) on the owner's dedicated server,
at https://4luckyclovers.com. It moved there from a Vultr VPS in October 2026.

## How a change reaches production

1. Push to `main`.
2. GitHub Actions runs the `test` job (`.github/workflows/deploy.yml`).
3. In the VM, `soul-link-deploy.timer` runs `/usr/local/bin/soul-link-deploy`
   every 3 minutes. It fetches `origin/main` and, if the commit is new and its
   `test` job succeeded, deploys it: fast-forward, `bundle install`,
   `db:migrate`, `assets:precompile`, EmulatorJS check, reinstall the systemd
   units and itself from `config/deploy/`, restart jobs, bot and web, then
   confirm the jobs worker started.

GitHub never connects to the server; the server takes no inbound SSH. No server
secrets live in GitHub. A failed deploy sends the same email as a failed
service (`notify-failure.sh`).

    journalctl -u soul-link-deploy -n 50      # what the last checks did
    sudo soul-link-deploy --force             # redeploy origin/main right now
    sudo systemctl stop soul-link-deploy.timer  # pause automatic deploys

## What runs where

| Piece | How |
|---|---|
| Web (Puma, port 3000) | `soul-link-web.service` |
| Discord bot | `soul-link-bot.service` (only ever one instance, anywhere) |
| Background jobs (Solid Queue) | `soul-link-jobs.service` |
| Database | MySQL 8 on localhost, database `soul_link_production` |
| HTTPS and routing | Caddy, shared by every site in the VM (`/opt/caddy/Caddyfile`), which proxies `4luckyclovers.com` to `127.0.0.1:3000` and manages certificates itself. This replaced nginx and certbot. |
| Settings and secrets | `/etc/soul_link/env` in the VM (`RAILS_MASTER_KEY`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `SOUL_LINK_HOST`). Edit there; nothing rewrites it. |
| Files outside git | `storage/` (ROMs, randomizer jar) and `config/soul_link/randomizer_settings.rnqs` |

System packages the app needs: Ruby 3.4.5 (rbenv, under root), MySQL server and
client headers, a Java 21 runtime (randomizer), p7zip (EmulatorJS install),
msmtp (failure emails).

The README's "Production Deployment" section describes the original VPS setup
and is kept for reference; where it differs from this file, this file is
current.
