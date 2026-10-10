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
  inferenceHosts = lib.filterAttrs (_: host: host.enable) config.bandit-lab.inferenceHosts;
  inferenceNames = lib.optional (inferenceHosts ? slayer) "slayer" ++ lib.filter (name: name != "slayer") (builtins.attrNames inferenceHosts);
  inferenceUrls = map (name: "http://127.0.0.1:${toString inferenceHosts.${name}.localPort}") inferenceNames;
  # Two Andy-4.2 brains, each with its own scripted crew (lead mode, H4):
  # bot1 keeps the base chest stocked, bot2 builds; they talk with
  # !startConversation. One lead with four independent goals drifted, and one
  # lead with every task did not get to the building (2026-10-10).
  agents = {
    bot1 = {
      goal = "You help the crew but do not run it: the hub plan assigns the workers. Gather what the base chest lacks (logs, cobblestone, coal, raw_iron, torches) yourself with !collectBlocks or !startShift, fight mobs near the base, and answer bot2. Do not try to !assign workers.";
      workers = "";
    };
    # The storage room goes under the base-v1 hut (-272 65 -219, on ground a block
    # scan found flat); the owner asked for it underground, for chests and beds.
    bot2 = {
      goal = "You help on the building site but do not run it: the hub plan assigns the workers. Dig on the big shaft west of the base yourself with !digShaft(-291, -222, -276, -207), build what is needed, and tell bot1 if the site needs materials with !startConversation. Do not try to !assign workers.";
      workers = "";
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
        // lib.optionalAttrs (inferenceNames != []) {
          ANDY_URLS = lib.concatStringsSep "," inferenceUrls;
          ANDY_BACKEND_NAMES = lib.concatStringsSep "," inferenceNames;
        }
        // lib.optionalAttrs (inferenceHosts ? slayer) {
          ANDY_URL_2 = "http://127.0.0.1:${toString inferenceHosts.slayer.localPort}";
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
