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
    bot1 = "You lead the crew. Keep the base chest stocked with logs, cobblestone, coal, raw_iron and raw_gold. Give every idle worker a shift with !assign so each resource has someone working on it, and give a new order to a worker that finishes, fails or dies. Do not mine yourself.";
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
        LOG = ""; # one line per reply goes to the journal; full prompts are not kept
        WORKERS = workers;
      };
      serviceConfig = {
        ExecStart = "${pkgs.nodejs}/bin/node ${../../../../tools/mcagents}/agent.js";
        LoadCredential = "dashboard-token:/var/lib/mcbots/agent-token";
        Restart = "always";
        RestartSec = "30s";
        DynamicUser = true;
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
