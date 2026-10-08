# `nix run .#mcbots-worker -- bot5`: run bots on this machine under the lab
# hub. They join Velocity from the laptop's tailnet address (BotGate admits
# bot1..bot99 from there), show up in the lab dashboard and take their jobs and
# block reservations from the hub. The token is the sops secret
# mcbots-worker-token (nixos/secrets-workstation.nix).
{
  writeShellApplication,
  mcbots,
  repoConfig,
}:
writeShellApplication {
  name = "mcbots-worker";
  text = ''
    export HUB_URL="''${HUB_URL:-wss://${repoConfig.lab.tailnetFqdn}:${toString repoConfig.lab.mcbotsWorkerServePort}/worker}"
    export HUB_TOKEN_FILE="''${HUB_TOKEN_FILE:-/run/secrets/mcbots-worker-token}"
    export MC_HOST="''${MC_HOST:-${repoConfig.lab.tailscaleIp}}"
    exec ${mcbots}/bin/mcbots-worker "$@"
  '';
}
