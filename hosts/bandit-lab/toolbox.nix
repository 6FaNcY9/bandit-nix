{lib, ...}: let
  # Analyst toolbox (docs/specs/2026-09-09-security-lab.md, phase 4).
  # All three are unauthenticated by design, so they must stay behind their
  # Cloudflare Access applications — Traefik is their only ingress.
  toolbox = {
    juice-shop = {
      # Intentionally vulnerable practice target — extra reason the Access
      # gate is non-negotiable.
      image = "bkimminich/juice-shop@sha256:73c53fbf442e8337b3ea3d98c7e8550308854701ebdfce4cc39768f36b75430e";
      host = "juice.bandit-lab.mrija.org";
      port = "3000";
    };
    cyberchef = {
      image = "ghcr.io/gchq/cyberchef@sha256:379c6cbcfd8cc10b8e045548f3ebaa82ce429e4b40cf60e4532e116a4c67884d";
      host = "cyberchef.bandit-lab.mrija.org";
      port = "8080";
    };
    it-tools = {
      image = "corentinth/it-tools@sha256:8b8128748339583ca951af03dfe02a9a4d7363f61a216226fc28030731a5a61f";
      host = "tools.bandit-lab.mrija.org";
      port = "80";
    };
  };
in {
  virtualisation.oci-containers.containers =
    builtins.mapAttrs (_name: cfg: {
      inherit (cfg) image;
      extraOptions = [
        "--network=proxy"
        "--label=traefik.enable=true"
        "--label=traefik.http.routers.${_name}.rule=Host(`${cfg.host}`)"
        "--label=traefik.http.routers.${_name}.entrypoints=web"
        "--label=traefik.http.services.${_name}.loadbalancer.server.port=${cfg.port}"
      ];
    })
    toolbox;

  systemd.services = lib.mapAttrs' (name: _:
    lib.nameValuePair "docker-${name}" {
      after = ["docker-network-proxy.service"];
      requires = ["docker-network-proxy.service"];
    })
  toolbox;
}
