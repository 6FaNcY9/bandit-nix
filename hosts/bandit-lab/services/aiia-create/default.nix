# AiiA design generator ("Create your character") at https://create.aiia.at.
#
# Evaluated and checked (2026-11-11), not deployed yet: the lab build fails
# until the five secrets below are in secrets/lab.yaml, so this stays off main
# until then. Read docs/runbooks/aiia-create.md first.
#
# One Podman pod, like the shop: web (Next.js), api (FastAPI) and redis share a
# network namespace, so the API and Redis are reachable on localhost only and
# nothing but the web port leaves the pod, on loopback, for Traefik. The browser
# never talks to the API: the web app proxies an allow-list of paths to it and
# adds the internal token.
{
  config,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
  inherit (config.virtualisation.quadlet) pods;

  origin = "https://create.aiia.at";

  # Not secret, but they must be filled in before the first deploy: the API
  # refuses to start in production with incomplete storage settings.
  # Cloudflare R2: account-scoped S3 endpoint, the bucket, and the public
  # domain the bucket is served from (also the ASSET_ORIGIN the web image was
  # built with, see the runbook).
  r2Endpoint = "https://812eb80b2ffe7e6ce3beb8ac39f8cd81.r2.cloudflarestorage.com";
  r2Bucket = "aiia-designs";
  assetBase = "https://cdn.aiia.at";
in {
  systemd.tmpfiles.rules = [
    "d /srv/containers/aiia-create 0750 ${username} users -"
    # redis:7-alpine runs as 999:999 here, like aiia-redis. Redis holds the
    # rate limits, generation jobs, design records, accounts, community data
    # and (once order handling is on) the orders: it is application data, not
    # a cache, so it is persisted and belongs in the backup.
    "d /srv/containers/aiia-create/redis 0750 999 999 -"
  ];

  # Declared here so they are only decrypted on bandit-lab. The fal key is the
  # shop's (services/aiia): one provider account, one secret.
  sops = {
    secrets = {
      # Shared secret between the web app and the API. 32+ characters, and
      # different from the session secret (the API checks both at start).
      "aiia-create-internal-token" = {mode = "0400";};
      # Signs the anonymous session cookie. 32+ characters.
      "aiia-create-session-secret" = {mode = "0400";};
      # Cloudflare Turnstile secret key of the widget for create.aiia.at. The
      # API refuses Cloudflare's published test secrets in production.
      "aiia-create-turnstile-secret" = {mode = "0400";};
      # R2 API token (object read and write on the one bucket).
      "aiia-create-s3-access-key-id" = {mode = "0400";};
      "aiia-create-s3-secret-access-key" = {mode = "0400";};
      # Stage 2 (checkout):  "aiia-create-shopify-storefront-token"
      # Stage 3 (printing):  "aiia-create-shopify-admin-client-secret",
      #                      "aiia-create-gelato-webhook-secret"
      #                      (the Gelato key is the shop's "aiia-gelato-api-key")
    };

    templates = {
      "aiia-create-api.env" = {
        mode = "0400";
        restartUnits = ["aiia-create-api.service"];
        content = ''
          FAL_KEY=${config.sops.placeholder."aiia-fal-key"}
          INTERNAL_API_TOKEN=${config.sops.placeholder."aiia-create-internal-token"}
          SESSION_SECRET=${config.sops.placeholder."aiia-create-session-secret"}
          TURNSTILE_SECRET=${config.sops.placeholder."aiia-create-turnstile-secret"}
          S3_ACCESS_KEY_ID=${config.sops.placeholder."aiia-create-s3-access-key-id"}
          S3_SECRET_ACCESS_KEY=${config.sops.placeholder."aiia-create-s3-secret-access-key"}
        '';
      };

      # The web container gets the internal token and nothing else.
      "aiia-create-web.env" = {
        mode = "0400";
        restartUnits = ["aiia-create-web.service"];
        content = ''
          INTERNAL_API_TOKEN=${config.sops.placeholder."aiia-create-internal-token"}
        '';
      };
    };
  };

  virtualisation.quadlet = {
    # 3000 on the host is Grafana; the pod publishes the web app on 3080.
    pods.aiia-create.podConfig.publishPorts = ["127.0.0.1:3080:3000"];

    containers = {
      aiia-create-redis.containerConfig = {
        # Same pinned image as aiia-redis.
        image = "docker.io/library/redis:7-alpine@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf";
        pod = pods.aiia-create.ref;
        user = "999:999";
        # Append-only file plus a periodic snapshot: limits, jobs, designs and
        # orders survive a restart.
        exec = ["--appendonly" "yes" "--save" "300" "10"];
        volumes = ["/srv/containers/aiia-create/redis:/data"];
      };

      # Both application images come from the generator repository's CI
      # artifact and are loaded by hand (docs/runbooks/aiia-create.md), like the
      # shop image: the host holds no registry credentials.
      aiia-create-api = {
        containerConfig = {
          image = "ghcr.io/6fancy9/aiia-generator-api:main";
          pull = "never";
          pod = pods.aiia-create.ref;
          # The image's own unprivileged user (uid 10001, gid 999).
          user = "10001:999";
          # Image work with Pillow and NumPy; the limit the compose file used.
          memory = "1g";
          # Read-only root (the default here); Pillow and uvicorn need /tmp.
          tmpfses = ["/tmp"];
          environments = {
            ENVIRONMENT = "production";
            SESSION_COOKIE_SECURE = "true";
            REDIS_URL = "redis://127.0.0.1:6379/0";
            # The styles, palettes, prompt and the variant and product tables
            # are inside the image at /config (the API's default paths).
            STORAGE_BACKEND = "s3";
            S3_ENDPOINT_URL = r2Endpoint;
            S3_REGION = "auto";
            S3_BUCKET = r2Bucket;
            PUBLIC_ASSET_BASE_URL = assetBase;
            TURNSTILE_EXPECTED_HOSTNAMES = ''["create.aiia.at"]'';
            # Stage 2 (checkout): SHOPIFY_STORE_DOMAIN and, in the env template,
            # SHOPIFY_STOREFRONT_PRIVATE_TOKEN.
            # Stage 3 (printing): ORDERS_ENABLED = "true" plus the values listed
            # in the runbook. Until then every order route answers 404.
          };
          environmentFiles = [config.sops.templates."aiia-create-api.env".path];
        };
        unitConfig = {
          After = ["aiia-create-redis.service"];
          Requires = ["aiia-create-redis.service"];
        };
        serviceConfig.RestartSec = 5;
      };

      aiia-create-web = {
        containerConfig = {
          image = "ghcr.io/6fancy9/aiia-generator-web:main";
          pull = "never";
          pod = pods.aiia-create.ref;
          # The image's own unprivileged user (uid 100, gid 101).
          user = "100:101";
          memory = "512m";
          # The image's own HEALTHCHECK is off: its first run, a second after
          # the start, fails as a transient unit, and the deploy counts that as
          # a failed switch and rolls back (2026-11-11).
          healthCmd = "none";
          # Next.js writes its image and fetch cache under /app/.next/cache.
          readOnly = false;
          environments = {
            API_INTERNAL_URL = "http://127.0.0.1:8000";
            APP_ORIGIN = origin;
            # The immediate peers are Traefik and cloudflared on loopback; the
            # visitor's address is the header Cloudflare's edge sets. It feeds
            # the per-address rate limits, so it must be one the edge overwrites.
            CLIENT_IP_HEADER = "cf-connecting-ip";
          };
          environmentFiles = [config.sops.templates."aiia-create-web.env".path];
        };
        unitConfig = {
          After = ["aiia-create-api.service"];
          Requires = ["aiia-create-api.service"];
        };
        serviceConfig.RestartSec = 5;
      };
    };
  };
}
