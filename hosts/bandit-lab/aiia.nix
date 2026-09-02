{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;

  # Inspect-then-create, same rationale as docker-network-proxy in traefik.nix.
  ensureAiiaNetwork = pkgs.writeShellScript "ensure-aiia-network" ''
    set -euo pipefail

    if ! ${pkgs.docker}/bin/docker network inspect aiia >/dev/null 2>&1; then
      ${pkgs.docker}/bin/docker network create aiia
    fi
  '';
in {
  # Internal service network for ghost <-> mysql <-> redis. The ghost container
  # additionally joins the `proxy` network (postStart below) so Traefik can
  # reach it; mysql and redis stay off `proxy` on purpose.
  systemd = {
    tmpfiles.rules = [
      "d /srv/containers/aiia 0750 ${username} users -"
      "d /srv/containers/aiia/content-images 0750 ${username} users -"
      "d /srv/containers/aiia/content-media 0750 ${username} users -"
      "d /srv/containers/aiia/content-files 0750 ${username} users -"
      "d /srv/containers/aiia/content-logs 0750 ${username} users -"
      "d /srv/containers/aiia/content-data 0750 ${username} users -"
      "d /srv/containers/aiia/mysql 0750 ${username} users -"
    ];

    services = {
      docker-network-aiia = {
        description = "Create aiia Docker network";
        after = ["docker.service"];
        requires = ["docker.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = ensureAiiaNetwork;
        };
      };

      docker-aiia-mysql = {
        after = ["docker-network-aiia.service"];
        requires = ["docker-network-aiia.service"];
      };
      docker-aiia-redis = {
        after = ["docker-network-aiia.service"];
        requires = ["docker-network-aiia.service"];
      };
      docker-aiia-ghost = {
        after = ["docker-network-aiia.service" "docker-network-proxy.service"];
        requires = ["docker-network-aiia.service" "docker-network-proxy.service"];
        # Traefik only watches the `proxy` network; connect it after container
        # start (docker create accepts exactly one --network).
        postStart = ''
          ${pkgs.docker}/bin/docker network connect proxy aiia-ghost 2>/dev/null || true
        '';
      };
    };
  };

  # Declared here instead of nixos/sops.nix so the shop credentials are only
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
          AIIA_PUBLIC_URL=https://aiia.bandit-lab.mrija.org
          database__connection__password=${config.sops.placeholder."aiia-mysql-password"}
        '';
      };

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

  virtualisation.oci-containers.containers = {
    aiia-mysql = {
      image = "mysql:8.4@sha256:b3b90af2a6552ae30c266fdb7d5dd55f3afb72404bb78d37fe8a23eb857fd3fb";
      volumes = ["/srv/containers/aiia/mysql:/var/lib/mysql"];
      environmentFiles = [config.sops.templates."aiia-mysql.env".path];
      extraOptions = ["--network=aiia"];
    };

    aiia-redis = {
      image = "redis:7-alpine@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf";
      extraOptions = ["--network=aiia"];
    };

    # Custom Ghost 6 fork build (github.com/6FaNcY9/AiiA). The image is loaded
    # onto the host from the CI `docker-image-production` workflow artifact
    # (gh run download + ssh docker load) because the GHCR package is private
    # and the host holds no registry credentials. `pull = "missing"` keeps
    # docker from contacting GHCR; updates repeat the artifact transfer and
    # restart docker-aiia-ghost.service.
    aiia-ghost = {
      image = "ghcr.io/6fancy9/aiia:main";
      pull = "missing";
      dependsOn = ["aiia-mysql" "aiia-redis"];
      # Persist only the mutable content subdirs. The app root in this image
      # is /home/ghost (not the upstream /var/lib/ghost), and themes — the
      # aiia theme included — ship inside the image, so a whole-content mount
      # would shadow them on first boot.
      volumes = [
        "/srv/containers/aiia/content-images:/home/ghost/content/images"
        "/srv/containers/aiia/content-media:/home/ghost/content/media"
        "/srv/containers/aiia/content-files:/home/ghost/content/files"
        "/srv/containers/aiia/content-logs:/home/ghost/content/logs"
        "/srv/containers/aiia/content-data:/home/ghost/content/data"
      ];
      environment = {
        url = "https://aiia.bandit-lab.mrija.org";
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
      extraOptions = [
        "--network=aiia"
        "--label=traefik.enable=true"
        "--label=traefik.docker.network=proxy"
        "--label=traefik.http.routers.aiia.rule=Host(`aiia.bandit-lab.mrija.org`)"
        "--label=traefik.http.routers.aiia.entrypoints=web"
        "--label=traefik.http.services.aiia.loadbalancer.server.port=2368"
      ];
    };
  };
}
