{
  config,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
  inherit (config.virtualisation.quadlet) pods;
in {
  # The shop is a Podman pod (phase 4): ghost, mysql and redis share one
  # network namespace, so the database and cache are reachable on localhost
  # only and nothing but Ghost's port leaves the pod, on loopback, for Traefik.
  systemd = {
    tmpfiles.rules = [
      "d /srv/containers/aiia 0750 ${username} users -"
      "d /srv/containers/aiia/content-images 0750 ${username} users -"
      "d /srv/containers/aiia/content-media 0750 ${username} users -"
      "d /srv/containers/aiia/content-files 0750 ${username} users -"
      "d /srv/containers/aiia/content-logs 0750 ${username} users -"
      "d /srv/containers/aiia/content-data 0750 ${username} users -"
      # Ownership left unset on purpose: the mysql:8.4 container runs as
      # uid/gid 999, and tmpfiles re-applying ${username}:users 0750 after
      # every boot revokes all access for the mysqld process (InnoDB
      # EACCES, "Operating system error number 13"). The image entrypoint
      # chowns the datadir itself. Pre-existing hosts still need a one-time
      # `chown 999:999 /srv/containers/aiia/mysql`.
      "d /srv/containers/aiia/mysql 0750 - - -"
    ];
  };

  # Declared here instead of modules/server/sops.nix so the shop credentials are only
  # decrypted on bandit-lab.
  sops = {
    secrets = {
      "aiia-fal-key" = {mode = "0400";};
      "aiia-gelato-api-key" = {mode = "0400";};
      "aiia-stripe-secret-key" = {mode = "0400";};
      "aiia-stripe-publishable-key" = {mode = "0400";};
      "aiia-stripe-webhook-secret" = {mode = "0400";};
      "aiia-mysql-password" = {mode = "0400";};
      "aiia-mysql-root-password" = {mode = "0400";};
    };

    templates = {
      # No automatic restart: this template also contains the SQL password.
      # Coordinate the persisted MySQL account first; see
      # docs/runbooks/secret-rotation.md for database and provider-only rotation.
      # Sandbox deployment: AIIA_ORDER_MODE=draft pins Stripe test keys and
      # Gelato review-only drafts. Flip to `live` together with live Stripe
      # keys for real charges and fulfilment (the app refuses to boot on a
      # mismatch).
      "aiia.env" = {
        mode = "0400";
        content = ''
          FAL_KEY=${config.sops.placeholder."aiia-fal-key"}
          GELATO_API_KEY=${config.sops.placeholder."aiia-gelato-api-key"}
          STRIPE_TSHIRT_SECRET_KEY=${config.sops.placeholder."aiia-stripe-secret-key"}
          STRIPE_TSHIRT_PUBLISHABLE_KEY=${config.sops.placeholder."aiia-stripe-publishable-key"}
          STRIPE_TSHIRT_WEBHOOK_SECRET=${config.sops.placeholder."aiia-stripe-webhook-secret"}
          AIIA_ORDER_MODE=draft
          AIIA_PUBLIC_URL=https://aiia.at
          database__connection__password=${config.sops.placeholder."aiia-mysql-password"}
        '';
      };

      # Initialization inputs only: changing these does not rotate existing
      # accounts in the persistent /srv/containers/aiia/mysql database.
      "aiia-mysql.env" = {
        mode = "0400";
        content = ''
          MYSQL_ROOT_PASSWORD=${config.sops.placeholder."aiia-mysql-root-password"}
          MYSQL_DATABASE=ghost
          MYSQL_USER=ghost
          MYSQL_PASSWORD=${config.sops.placeholder."aiia-mysql-password"}
        '';
      };
    };
  };

  virtualisation.quadlet = {
    pods.aiia.podConfig = {
      publishPorts = ["127.0.0.1:2368:2368"];
      # The former Docker network names, so the image's configuration keeps resolving them.
      addHosts = ["aiia-mysql:127.0.0.1" "aiia-redis:127.0.0.1"];
    };
    containers = {
      aiia-mysql.containerConfig = {
        image = "docker.io/library/mysql:8.4@sha256:b3b90af2a6552ae30c266fdb7d5dd55f3afb72404bb78d37fe8a23eb857fd3fb";
        pod = pods.aiia.ref;
        # The datadir is owned by 999:999; started as that user the entrypoint
        # skips its chown and needs no capability.
        user = "999:999";
        # Low-churn Ghost DB: cap binlog point-in-time recovery at 7 days
        # instead of the 30-day default.
        exec = ["--binlog-expire-logs-seconds=604800"];
        volumes = ["/srv/containers/aiia/mysql:/var/lib/mysql"];
        environmentFiles = [config.sops.templates."aiia-mysql.env".path];
      };

      aiia-redis.containerConfig = {
        image = "docker.io/library/redis:7-alpine@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf";
        pod = pods.aiia.ref;
        user = "999:999";
      };

      # Custom Ghost 6 fork build (github.com/6FaNcY9/AiiA). The image is loaded
      # into Podman's store by hand (docs/runbooks/aiia-shop.md, "Updating the
      # shop") because the GHCR package is private and the host holds no
      # registry credentials; `pull = "never"` keeps Podman off the registry.
      # Referenced by tag: a hand-loaded archive carries no registry digest,
      # the runbook verifies the image ID instead.
      aiia-ghost = {
        containerConfig = {
          image = "ghcr.io/6fancy9/aiia:main";
          pull = "never";
          pod = pods.aiia.ref;
          # The image runs as ghost (1000:1000); the content dirs are owned by 1000.
          user = "1000:1000";
          # Ghost writes generated assets (sitemaps, cards) here at runtime.
          tmpfses = ["/home/ghost/content/public"];
          # Persist only the mutable content subdirs. The app root in this image
          # is /home/ghost (not the upstream /var/lib/ghost), and themes — the
          # aiia theme included — ship inside the image, so a whole-content mount
          # would shadow them on first boot.
          # Theme activation is a DB setting, not an image property: the image
          # still seeds active_theme="source" (default-settings.json), so after
          # any DB rebuild the storefront silently falls back to the Source theme.
          # Fix: UPDATE settings SET value='aiia' WHERE settings.key='active_theme'
          # in aiia-mysql + restart aiia-ghost. Durable fix belongs in the
          # AiiA repo (change the defaultValue to "aiia").
          volumes = [
            "/srv/containers/aiia/content-images:/home/ghost/content/images"
            "/srv/containers/aiia/content-media:/home/ghost/content/media"
            "/srv/containers/aiia/content-files:/home/ghost/content/files"
            "/srv/containers/aiia/content-logs:/home/ghost/content/logs"
            "/srv/containers/aiia/content-data:/home/ghost/content/data"
          ];
          environments = {
            # Canonical storefront domain. Ghost 301-redirects the old
            # aiia.bandit-lab.mrija.org hostname here.
            url = "https://aiia.at";
            # Ghost 6 defaults server.host to 127.0.0.1; the pod publishes the
            # port from its own namespace, so bind all interfaces inside it.
            # Exposure is still gated by the tunnel + Traefik router.
            server__host = "0.0.0.0";
            database__client = "mysql";
            database__connection__host = "aiia-mysql";
            database__connection__port = "3306";
            database__connection__user = "ghost";
            database__connection__database = "ghost";
            # Member sign-in uses magic-link email. Direct transport works for
            # testing but lands in spam without SPF/DKIM; before a real launch,
            # point this at a proper SMTP relay via additional mail__* entries.
            mail__transport = "Direct";
            mail__from = "noreply@aiia.bandit-lab.mrija.org";
          };
          environmentFiles = [config.sops.templates."aiia.env".path];
        };
        unitConfig = {
          After = ["aiia-mysql.service" "aiia-redis.service"];
          Requires = ["aiia-mysql.service" "aiia-redis.service"];
        };
        serviceConfig.RestartSec = 5;
      };
    };
  };
}
