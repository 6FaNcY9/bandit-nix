# Laptop only: on the tailnet only Blocky (bandit-lab) answers DNS, and dns-guard falls back by itself.
# Design: docs/specs/2026-11-17-laptop-dns-design.md, rollback: docs/runbooks/lab-dns.md.
{
  config,
  lib,
  pkgs,
  ...
}: let
  guard = pkgs.writeShellApplication {
    name = "dns-guard";
    runtimeInputs = [pkgs.dig config.services.tailscale.package pkgs.systemd pkgs.coreutils];
    text = builtins.readFile ../../tools/dns-guard.sh;
  };
in {
  # A global "~." ties with tailscale0's "~." and resolved races both, so Cloudflare often beats Blocky.
  # Without it tailscale0 wins alone; network.nix keeps "~." for the lab.
  services.resolved.settings.Resolve.Domains = lib.mkForce [];

  systemd.services.dns-guard = {
    description = "Tailnet DNS guard (Blocky or fallback)";
    wantedBy = ["multi-user.target"];
    wants = ["tailscaled.service"];
    after = ["tailscaled.service"];
    serviceConfig = {
      ExecStart = "${guard}/bin/dns-guard";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
