# Andy-4.2 brains for bot1-bot4 (tools/mcagents, H5 in docs/NEXT-GOALS.md): the
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
  goals = {
    bot1 = "Keep the base chest stocked with logs: run a shift for logs and keep it running. If it stops, find out why (tools, food, health) and fix it.";
    bot2 = "Keep the base chest stocked with cobblestone: run a shift for stone and keep it running. If it stops, find out why and fix it.";
    bot3 = "Gather iron and coal for the base: mine iron_ore and coal_ore and put raw_iron and coal into the base chest. Smelt raw_iron into iron_ingot when you have coal.";
    bot4 = "Gather gold and diamonds for the base: mine gold_ore and diamond_ore deep underground and put raw_gold and diamond into the base chest.";
  };
in {
  options.bandit-lab.mcagents.enable = lib.mkEnableOption "the Andy-4.2 agents for bot1-bot4" // {default = true;};

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
      };
      serviceConfig = {
        ExecStart = "${pkgs.nodejs}/bin/node ${../../../../tools/mcagents}/agent.js";
        LoadCredential = "dashboard-token:/var/lib/mcbots/agent-token";
        Restart = "always"; # it exits when the dashboard is down at start
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
        IPAddressAllow = "localhost";
        IPAddressDeny = "any";
        SystemCallFilter = "@system-service";
        MemoryMax = "512M";
      };
    };
  };
}
