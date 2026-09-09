# AiiA shop deploy runbook (bandit-lab)

The AiiA Ghost fork runs as three Docker containers (`aiia-ghost`, `aiia-mysql`,
`aiia-redis`) on the internal `aiia` network, published through Traefik and the
Cloudflare Tunnel at `https://aiia.bandit-lab.mrija.org`.

## One-time manual steps

1. **Cloudflare Tunnel hostname** (Zero Trust dashboard → Networks → Tunnels →
   bandit-lab → Public Hostnames): add `aiia.bandit-lab.mrija.org` →
   `http://localhost:80`. The dashboard is authoritative; `hosts/bandit-lab/wan.nix`
   only mirrors it. No Cloudflare Access app — the storefront must be public
   (same reasoning as Vaultwarden).
2. **Image transfer**: the GHCR package is private and the host holds no
   registry credentials, so the image travels as a CI artifact over SSH:

   Choose a run for the intended source revision with a successful production
   image build and an unexpired `docker-image-production` artifact. If the
   artifact has expired, a fresh CI build is needed before downloading it.
   The configured image is `ghcr.io/6fancy9/aiia:main`; a package named
   `aiia-ghost:v1` is a different image reference, even when linked to the same
   repository. Verify its source revision and contents before substituting it.

   The `aiia-ghost:v1` image inspected on 2026-09-09 (index digest
   `sha256:7cb0de296dc7f736b26523847a0fd241ee84f5b788c30be84b4b6300025a6cde`)
   reports source revision `abca48385e2032affc8eb4adf9081fd3b5ee2c59` in its
   build provenance. That revision predates the `AIIA_ORDER_MODE` guard added
   in `ee3b0e2bf4`; do not substitute that image for this draft-mode deployment.

   ```bash
   gh run download <run-id> --repo 6FaNcY9/AiiA --name docker-image-production
   scp docker-image-production.tar.gz bandit-lab:/tmp/
   ssh bandit-lab 'sudo docker load < /tmp/docker-image-production.tar.gz && rm /tmp/docker-image-production.tar.gz'
   ssh bandit-lab 'sudo docker image inspect ghcr.io/6fancy9/aiia:main --format "{{.Id}} {{.Os}}/{{.Architecture}}"'
   ```

   Confirm the expected tag exists and reports `linux/amd64` before starting
   Ghost. If inspection fails, stop and resolve the image mismatch first.

   ```bash
   ssh bandit-lab 'sudo systemctl reset-failed docker-aiia-ghost'
   ssh bandit-lab 'sudo systemctl restart docker-aiia-ghost'
   ssh bandit-lab 'systemctl is-active docker-aiia-ghost'
   ```

   These transfer and service commands modify the server; they are deployment
   steps, not read-only diagnostic checks.

   Until the first load, `docker-aiia-ghost.service` fails because its image is
   unavailable locally (`pull = "never"`); it is excluded from `criticalUnits` in
   `health-check.nix` so this does not roll back deploys. After the first
   successful startup and application health verification, add it to
   `criticalUnits`.
3. **Ghost first-run setup** (needs the tunnel hostname live):
   - `https://aiia.bandit-lab.mrija.org/ghost/` → create the staff account.
   - Settings → Design → activate the **aiia** theme.
   - Settings → Membership → enable sign-up.
   - Seed `/terms/` and `/privacy/` pages (in the AiiA repo:
     `node ghost/core/dev/seed-pages.cjs`, or create them in the admin UI).
4. **Stripe webhook** (test mode while `AIIA_ORDER_MODE=draft`): Stripe
   Dashboard → Webhooks → endpoint for `checkout.session.completed` →
   `https://aiia.bandit-lab.mrija.org/members/api/aiia/webhooks/stripe`.
   Update `aiia-stripe-webhook-secret` in `secrets/secrets.yaml` with the new
   signing secret.

## Updating the shop

Push to `main` on `6FaNcY9/AiiA`, wait for the CI `docker-image-production`
artifact, then repeat step 2 and `git -C /etc/nixos/bandit-nix` does not change.

## Going live (real charges)

1. Replace `aiia-stripe-secret-key` / `aiia-stripe-publishable-key` with the
   `sk_live_…` / `pk_live_…` pair and update the webhook secret (step 4, live
   mode) in `secrets/secrets.yaml`.
2. Set `AIIA_ORDER_MODE=live` in `hosts/bandit-lab/aiia.nix` (the
   `sops.templates."aiia.env"` content).
3. Signed commit + push; `lab-update apply` (or wait for the hourly timer).
   The app refuses to boot on a key/mode mismatch, so a half-flipped config
   surfaces immediately.

## Email caveat

Member sign-in uses magic-link email. The container currently sends via
`mail__transport = "Direct"`, which lands in spam without SPF/DKIM. Before a
real launch, point `mail__*` at a proper SMTP relay in `aiia.nix`.
