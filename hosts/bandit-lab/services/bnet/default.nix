{
  config,
  pkgs,
  ...
}: {
  # bandit-net router (docs/specs/bnet): lists the user's devices and runs Ollama requests on an idle PC
  # (albert, slayer) or else on the lab's own Ollama. Loopback only; published as Tailscale Service
  # svc:bnet (services/tailnet-https.nix). Every endpoint also needs the bearer token in /etc/bnet/token
  # (root 0600, never in git or the shared memory): Albert's PC is in the tailnet but he must not steer it.
  systemd.services.bnet-router = {
    description = "bandit-net router: device list and Ollama routing to idle PCs";
    after = ["network-online.target" "tailscaled.service"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    unitConfig.ConditionFileNotEmpty = "/etc/bnet/token";
    path = [config.services.tailscale.package];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./router.py} --devices ${./devices.json} --listen 127.0.0.1:47810 --lab-ollama http://127.0.0.1:11434";
      DynamicUser = true;
      LoadCredential = "token:/etc/bnet/token";
      Restart = "on-failure";
      RestartSec = 5;
      MemoryMax = "128M";
      TasksMax = 64;
    };
  };
}
