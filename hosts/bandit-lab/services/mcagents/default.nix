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
  # Two Andy-4.2 brains, each with its own scripted crew (lead mode, H4):
  # bot1 keeps the base chest stocked, bot2 builds; they talk with
  # !startConversation. One lead with four independent goals drifted, and one
  # lead with every task did not get to the building (2026-10-10).
  agents = {
    bot1 = {
      goal = "You lead the gathering crew: bot4 and bot16. Keep the base chest at -271 66 -214 stocked with what the builders need: logs, cobblestone, coal, raw_iron and torches. Give every idle worker a shift with !assign (one on logs, one on coal or iron, whichever the chest lacks) and give a new order to a worker that finishes, fails or dies. bot2 runs the building site; if bot2 asks for something, get it. Do not mine yourself.";
      workers = "bot4,bot16";
    };
    # The storage room goes under the base-v1 hut (-272 65 -219, on ground a block
    # scan found flat); the owner asked for it underground, for chests and beds.
    bot2 = {
      goal = "You are the overseer of the building site and you work on it yourself. Your crew is bot3, bot17 and bot18. The main project is the big shaft west of the base: keep your crew on it with !assign !digShaft(-291, -222, -276, -207) and dig on it yourself; when a worker is stuck or dies, give it the shaft again. Also finish the underground storage rooms under the base: room 1 is !digRoom(-272, 58, -219, 7, 7, 4) with chests along its north wall (!placeBlockAt for x -271 to -267, y 58, z -219), room 2 is !digRoom(-272, 58, -211, 7, 7, 4) with chests along its north wall (z -211). Each crew member gets its bed with !setHomeBed. Leave the base chest at -271 66 -214 alone. If the site needs materials, ask bot1 with !startConversation.";
      workers = "bot3,bot17,bot18";
    };
  };
in {
  options.bandit-lab.mcagents.enable = lib.mkEnableOption "the Andy-4.2 lead agent and its workers" // {default = true;};

  config = lib.mkIf cfg.enable {
    systemd.services.mcagents = {
      description = "Andy-4.2 agents for the Minecraft bots";
      after = ["docker-mcbots.service" "ollama-andy.service"];
      wants = ["docker-mcbots.service" "ollama-andy.service"];
      wantedBy = ["multi-user.target"];
      environment =
        lib.mapAttrs' (bot: a: lib.nameValuePair "WORKERS_${bot}" a.workers) agents
        // {
          API = "http://127.0.0.1:8095";
          OLLAMA_URL = "http://127.0.0.1:11434";
          BLUEPRINTS = "${../mcbots/blueprints}";
          AGENTS = lib.concatStringsSep ";" (lib.mapAttrsToList (bot: a: "${bot}=${a.goal}") agents);
          # Every model call (prompt + reply) for a later LoRA fine-tune; agent.js
          # rotates it at 50 MB. The journal gets one line per reply.
          LOG = "/var/lib/mcagents/decisions.jsonl";
        }
        // lib.optionalAttrs config.bandit-lab.slayerTunnel.enable {
          ANDY_URL_2 = "http://127.0.0.1:18081";
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
