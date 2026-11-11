# AiiA design generator runbook (bandit-lab)

**Address change 2026-11-11:** the generator is the main site at
`https://aiia.at`. `create.aiia.at`, `www.aiia.at` and the old lab hostname
redirect there in Traefik. Where this runbook says `create.aiia.at`, read
`aiia.at`. The Ghost shop is off the net; its pod and data stay on the host.

**Status: evaluated, not deployed.** The module
`hosts/bandit-lab/services/aiia-create/default.nix` evaluates and passes the
`lab-containers`, `lab-surface` and `lab-backup` checks (2026-11-11); port 3080
is free on the host. Nothing has been activated or runtime-verified: the
commands below were written without access to bandit-lab.

The generator ("Create your character") is a second AiiA application next to the
Ghost shop: a Next.js web app, a FastAPI service and Redis in one Podman pod
(`aiia-create`), published through Traefik and the Cloudflare Tunnel at
`https://create.aiia.at`. Source: the `aiia-generator` repository (not on GitHub
yet, see "Image transfer"). Its `CLAUDE.md` and `README.md` describe the
application; the README section "Orders and printing (Gelato)" covers stage 3.

```
Cloudflare edge ─► cloudflared ─► Traefik :80 ─► 127.0.0.1:3080 ─► web :3000 ─┐ (pod aiia-create)
                                                                     api :8000 ◄┤ localhost only
                                                                   redis :6379 ◄┘
api ─► fal.ai (images) · Cloudflare R2 (print files) · later: Shopify, Gelato
```

## Stages

The application is switched on in three steps; each can be verified alone.

| Stage | What works | Needs |
| --- | --- | --- |
| 1 | The site and the creator: visitors make designs. Checkout answers "shop is still being set up". | fal key (exists), Turnstile widget, R2 bucket, two random secrets |
| 2 | Checkout: the cart is created in the owner's Shopify shop. | Shopify store domain, Storefront private token, variant ids in `config/shopify-variants.json` (generator repo, new image) |
| 3 | Order handling: paid orders wait on `/orders`, the owner releases them to Gelato, Gelato's shipping notice fulfils the Shopify order. | `ORDERS_ENABLED=true`, Shopify app client id and secret, Gelato webhook secret, product ids in `config/gelato-products.json` (new image), two webhooks |

## One-time manual steps (stage 1)

1. **Secrets** in `secrets/lab.yaml` (sops; the module declares them, so the
   build fails until they exist):
   - `aiia-create-internal-token`, `aiia-create-session-secret`: two different
     random values, 32+ characters each (`openssl rand -base64 32`).
   - `aiia-create-turnstile-secret`: secret key of a Cloudflare Turnstile widget
     for the hostname `create.aiia.at`. The API refuses Cloudflare's test secrets
     in production. The widget's **site key** is public and goes into the web
     image at build time (repository variable `TURNSTILE_SITE_KEY`).
   - `aiia-create-s3-access-key-id`, `aiia-create-s3-secret-access-key`: an R2
     API token with object read and write on the one bucket.
   The fal key is the shop's existing `aiia-fal-key`.
2. **R2 bucket** for the print files: public read through a custom domain (the
   module assumes `https://cdn.aiia.at`), and a CORS rule allowing `GET` from
   `https://create.aiia.at` (the 3D mockup uses the image as a WebGL texture).
   Fill `r2Endpoint`, `r2Bucket` and `assetBase` at the top of the module. The
   same public domain is the web image's `ASSET_ORIGIN` build variable; it ends
   up in the page's Content-Security-Policy.
3. **Cloudflare Tunnel hostname** (dashboard, authoritative): add
   `create.aiia.at` → `http://localhost:80`, then keep the mirror in
   `hosts/bandit-lab/wan.nix`. No Cloudflare Access app: the site is public, like
   the shop. If Bot Fight Mode or a WAF challenge is active on the zone, exempt
   `POST /hooks/*` before stage 3: Shopify and Gelato post there from their
   servers and cannot solve a challenge.
4. **Image transfer** (same idea as `aiia-shop.md`). The generator repository's
   CI builds both images on a push to `main` and uploads them as the artifact
   `docker-images-production` (two `.tar.gz` files and `BUILD-INFO.txt`):

   ```bash
   gh run download <run-id> --repo <owner>/aiia-generator --name docker-images-production
   scp aiia-generator-api.tar.gz aiia-generator-web.tar.gz bandit-lab:/tmp/
   ssh bandit-lab 'sudo sh -c "gunzip -c /tmp/aiia-generator-api.tar.gz | podman load"'
   ssh bandit-lab 'sudo sh -c "gunzip -c /tmp/aiia-generator-web.tar.gz | podman load"'
   ssh bandit-lab 'sudo podman image inspect ghcr.io/6fancy9/aiia-generator-api:main ghcr.io/6fancy9/aiia-generator-web:main --format "{{.Id}} {{.Os}}/{{.Architecture}}"'
   ssh bandit-lab 'rm /tmp/aiia-generator-*.tar.gz'
   ```

   The tags must match the units' `image` names exactly. Check `BUILD-INFO.txt`:
   the web image must have been built with the real `APP_ORIGIN`, Turnstile site
   key and asset origin (repository variables), otherwise the pages carry CI
   placeholders and the bot check fails for every visitor.

   Until the first load, `aiia-create-api.service` and `aiia-create-web.service`
   fail (`pull = "never"`). Keep them out of `criticalUnits` in the health check
   until they have run once, as was done for `aiia-ghost`.
5. **Deploy** the signed commit as usual, then start the units if they failed
   before the images were there:

   ```bash
   ssh bandit-lab 'sudo systemctl reset-failed aiia-create-api aiia-create-web'
   ssh bandit-lab 'sudo systemctl restart aiia-create-api aiia-create-web'
   ```

## Verify (stage 1)

```bash
ssh bandit-lab 'systemctl is-active aiia-create-pod aiia-create-redis aiia-create-api aiia-create-web'
ssh bandit-lab 'curl -fsS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3080/healthz'
ssh bandit-lab 'curl -sS -o /dev/null -w "%{http_code}\n" -H "Host: create.aiia.at" http://127.0.0.1/api/session'
curl -sS -o /dev/null -w "%{http_code}\n" https://create.aiia.at/
curl -sS -o /dev/null -w "%{http_code}\n" -X POST https://create.aiia.at/hooks/shopify -d '{}'
```

Expected: all `active`; `200`; `200` (the web app reaches the API with the
internal token); `200`; `404` (order handling is off). Then make one design in a
browser at `https://create.aiia.at/create`: it costs one fal generation and
proves fal, Turnstile and R2 in one go. A failed start of the API is almost
always its settings guard: `journalctl -u aiia-create-api` names the variable.

## Updating

Push to `main` of the generator repository, wait for the artifact, transfer and
load as above, then `sudo systemctl restart aiia-create-api aiia-create-web`.
Rollback: the previous image stays in the store until `podman image prune`;
re-tag its id to the `:main` name and restart.

`config/*.json` (styles, prices, variant and product ids, protected names) is
part of the images, and the web pages are pre-rendered from it: a config change
is a new image for both containers.

## Data and backup

All state is in Redis under `/srv/containers/aiia-create/redis` (append-only
file): rate limits, generation jobs, design records, accounts with password
hashes, community data and, from stage 3, the orders with customer addresses.
It is application data, not a cache. **Not yet in the backup**: decide how to
snapshot it (copying the append-only directory of a running Redis can tear;
`redis-cli --rdb` into the staging area is the consistent way) and add it to
`hosts/bandit-lab/services/backup/shared.nix`. The print files live in R2, not
on the host.

## Stage 2 and 3

- Stage 2: add `aiia-create-shopify-storefront-token` to sops and the env
  template (`SHOPIFY_STOREFRONT_PRIVATE_TOKEN`), set `SHOPIFY_STORE_DOMAIN`, and
  ship an image whose `config/shopify-variants.json` holds the real variant ids.
- Stage 3: follow "Orders and printing (Gelato)" in the generator's README. On
  this host that means: `ORDERS_ENABLED = "true"`, `SHOPIFY_ADMIN_CLIENT_ID`,
  `GELATO_API_KEY` (the shop's `aiia-gelato-api-key`), and the new secrets
  `SHOPIFY_ADMIN_CLIENT_SECRET` and `GELATO_WEBHOOK_SECRET` (32 to 128
  characters, only letters, digits, `-` and `_`). The Gelato secret is part of
  the webhook URL, so it appears in Traefik's access log: treat that log as
  sensitive. The setup commands run in the API container:

  ```bash
  ssh bandit-lab 'sudo podman exec aiia-create-api python -m app.moderation owner add <owner e-mail>'
  ssh bandit-lab 'sudo podman exec aiia-create-api python -m app.orders_cli check'
  ssh bandit-lab 'sudo podman exec aiia-create-api python -m app.orders_cli webhooks https://create.aiia.at'
  ```

  The shop still runs with `AIIA_ORDER_MODE=draft`; the generator has no draft
  mode: with `ORDERS_ENABLED=true`, a release on `/orders` is a real, billed
  Gelato order.
