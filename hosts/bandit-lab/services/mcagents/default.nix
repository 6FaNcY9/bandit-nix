# Andy-4.2 lead agent (bot1) over scripted workers (tools/mcagents, H4/H5): the
# LLM decides, the scripted mcbots jobs execute. Talks only to the dashboard
# (127.0.0.1:8095, agent bearer: state, events and jobs for AGENT_BOTS) and to
# Ollama (127.0.0.1:11434). Stopping this service leaves running jobs alone.
# Switch off: `bandit-lab.mcagents.enable = false;`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.bandit-lab.mcagents;
  # Lead mode: one Andy-4.2 brain (bot1) plans and hands out shifts with
  # !assign; the workers are scripted and stick to their order. On the lab
  # four independent agents drifted off their goals (2026-10-10).
  goals = {
    # The base: an underground storage room under the base-v1 spot, which sits on
    # ground a block scan found flat (2026-10-10: 7x7 at ground Y 64, 9 blocks from
    # the base chest); the owner asked for it underground, for chests and beds.
    bot1 = "You lead the crew. Keep the base chest stocked with logs, cobblestone, coal, raw_iron and raw_gold: give every idle worker a shift with !assign so each resource has someone on it, and give a new order to a worker that finishes, fails or dies. Then build our underground storage room under the base: dig it out with !digRoom(-272, 58, -219, 7, 7, 4) (yourself, or give it to a worker with !assign), then place chests in a row along its north wall with !placeBlockAt for x -271 to -267, y 58, z -219. Later the crew will put their beds there. Do not mine yourself.";
  };
  workers = "bot2,bot3,bot4,bot16,bot17,bot18";
in {
  options.bandit-lab.mcagents.enable = lib.mkEnableOption "the Andy-4.2 lead agent and its workers" // {default = true;};

  config = lib.mkIf cfg.enable {
    systemd.services.mcagents = {
      description = "Andy-4.2 agents for the Minecraft bots";
      after = ["docker-mcbots.service" "ollama-andy.service"];
      wants = ["docker-mcbots.service" "ollama-andy.service"];
      wantedBy = ["multi-user.target"];
      environment = {
        API = "http://127.0.0.1:8095";
        OLLAMA_URL = "http://127.0.0.1:11434";
        BLUEPRINTS = "${../mcbots/blueprints}";
        AGENTS = lib.concatStringsSep ";" (lib.mapAttrsToList (bot: goal: "${bot}=${goal}") goals);
        # Every model call (prompt + reply) for a later LoRA fine-tune; agent.js
        # rotates it at 50 MB. The journal gets one line per reply.
        LOG = "/var/lib/mcagents/decisions.jsonl";
        WORKERS = workers;
      };
      serviceConfig = {
        ExecStart = "${pkgs.nodejs}/bin/node ${../../../../tools/mcagents}/agent.js";
        LoadCredential = "dashboard-token:/var/lib/mcbots/agent-token";
        Restart = "always";
        RestartSec = "30s";
        DynamicUser = true;
        StateDirectory = "mcagents";
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictNamespaces = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
        # Docker publishes the loopback ports by DNAT (no userland proxy), so the
        # packets leave with the container addresses: mcbots on 10.250.77.0/29
        # or the minecraft network, Ollama on the default bridge (172.16/12).
        # Internet, LAN and tailnet stay closed.
        IPAddressAllow = ["localhost" "10.250.77.0/29" "172.16.0.0/12"];
        IPAddressDeny = "any";
        SystemCallFilter = "@system-service";
        MemoryMax = "512M";
      };
    };
  };
}
