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
  urlOf = name: "http://127.0.0.1:${toString inferenceHosts.${name}.localPort}";
  # Owner's split (2026-10-11): the lab GPU and slayer serve the live agents and the solver; the offline
  # hosts (albert) only get idle replays, the judge and training, never live traffic.
  offlineNames = lib.filter (name: inferenceHosts ? ${name}) cfg.offlineHosts;
  liveNames = lib.filter (name: !(lib.elem name offlineNames)) inferenceNames;
  liveUrls = map urlOf liveNames;
  # The offline services get the same name/url lists plus ANDY_OFFLINE_NAMES; routing.js keeps each side to its own.
  allUrls = map urlOf inferenceNames;
  offlineEnv = {
    ANDY_URLS = lib.concatStringsSep "," allUrls;
    ANDY_BACKEND_NAMES = lib.concatStringsSep "," inferenceNames;
    ANDY_OFFLINE_NAMES = lib.concatStringsSep "," offlineNames;
  };
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
  options.bandit-lab.mcagents.offlineHosts = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = ["albert"];
    description = "Inference hosts kept for idle replays, the judge and training; they never get live agent or solver traffic.";
  };
  options.bandit-lab.mcagents.exportJudged = lib.mkEnableOption "judge-graded decisions (source judged) in the daily SFT export";

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
          # Problem solver for the plan's roster bots (tools/mcagents/solver.js): a failed job,
          # an idle bot with an error, repeated deaths or a parked objective gets one fix from a
          # safe menu; 30 model calls/hour of its own. Set to 0 for no change in behaviour.
          SOLVER_ENABLE = "1";
          # The agents think far more often (owner, 2026-10-11): a check-in every minute, an immediate prompt
          # when a bot goes idle or a job fails, and a cap of 30 model calls a minute for the lab GPU and
          # slayer together. Orders still stick for 60 s (agent.js assignJob), so they do not flip-flop.
          CHECKIN_MS = "60000";
          MAX_DECISIONS_PER_MIN = "30";
          # Jobs of the scripted crew that finish become training rows (tools/mcagents/demos.js); DEMOS=0 switches it off.
          DEMOS = "1";
          ANDY_OFFLINE_NAMES = lib.concatStringsSep "," offlineNames;
        }
        // lib.optionalAttrs (liveNames != []) {
          ANDY_URLS = lib.concatStringsSep "," liveUrls;
          ANDY_BACKEND_NAMES = lib.concatStringsSep "," liveNames;
          # The lab's RTX 4090 thinks first; the gaming PCs only take the overflow and
          # are otherwise free for replays and training (owner, 2026-10-10).
          ANDY_PREFER = "lab";
        }
        // lib.optionalAttrs (inferenceHosts ? slayer && !(lib.elem "slayer" offlineNames)) {
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
    # Idle replay and judge (owner, 2026-10-10/11): while an offline gaming PC's llama-server (albert)
    # answers /health (nobody is gaming), replay logged decisions against it and record the scores in
    # /var/lib/mcagents/replays, then let it grade decisions with an unknown outcome (judge.js, appended
    # to judgments.jsonl). Never touches Ollama or the live backends; loopback and ntfy only.
    systemd.services.mcagents-idle-replay = lib.mkIf (offlineNames != []) {
      description = "Replay and judge logged Minecraft agent decisions on idle gaming PCs";
      environment =
        offlineEnv
        // {
          JUDGE_BATCH = "200";
          # slayer grades too (it sat idle: the lab GPU takes the live calls first); 200 per PC per pass.
          JUDGE_NAMES = "albert,slayer";
          # grade batch after batch for up to 20 min per pass (replay first, all inside the 1 h start timeout)
          JUDGE_PASS_MS = "1200000"; # owner: use the idle PCs as much as possible (2026-10-11)
          LOG = "/var/lib/mcagents/decisions.jsonl";
          REPLAYS = "/var/lib/mcagents/replays";
          VARIANTS = "${../../../../tools/mcagents/variants.json}";
          NTFY_URL = "http://127.0.0.1:2586/mcbots";
        };
      serviceConfig = {
        Type = "oneshot";
        # Both steps run even when the first fails (a PC that went back to gaming ends it early, not badly).
        ExecStart = [
          "-${pkgs.nodejs}/bin/node ${../../../../tools/mcagents}/idle-replay.js"
          "-${pkgs.nodejs}/bin/node ${../../../../tools/mcagents}/judge.js"
        ];
        LoadCredential = "ntfy:/var/lib/mcbots/ntfy/publisher.env";
        # Same dynamic user as mcagents.service, so the state directory is shared.
        DynamicUser = true;
        User = "mcagents";
        StateDirectory = "mcagents";
        Nice = 19;
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "idle";
        TimeoutStartSec = "1h";
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
        IPAddressAllow = ["localhost"];
        IPAddressDeny = "any";
        SystemCallFilter = "@system-service";
        MemoryMax = "512M";
      };
    };
    systemd.timers.mcagents-idle-replay = lib.mkIf (offlineNames != []) {
      wantedBy = ["timers.target"];
      timerConfig = {
        # A calendar time, not OnBootSec: a timer whose boot delay has long passed fires the
        # moment a deploy starts it, and a failed run then rolls the whole deploy back (2026-10-10).
        OnCalendar = "*-*-* *:15,45:00"; # every 30 min; a run still going simply skips the next start
        RandomizedDelaySec = "10min";
      };
    };
    # Daily training export (owner, 2026-10-11): good decisions, solver calls and crew demonstrations from the log as
    # sft.jsonl + stats.json for the LoRA run on the gaming PC (tools/slayer/train). The data is bot
    # prompts and state only (dataset.js drops secret-shaped and human-chat rows). The dynamic user's
    # state directory is private, so a root ExecStartPost publishes the result world-readable under
    # /var/lib/mcagents-export for the admin user. Empty or missing log: empty export, exit 0.
    systemd.tmpfiles.rules = ["d /var/lib/mcagents-export 0755 root root -"];
    systemd.services.mcagents-dataset = {
      description = "Export logged Minecraft agent decisions as an SFT dataset";
      environment = {
        LOG = "/var/lib/mcagents/decisions.jsonl";
        DEMO_RATIO = "3"; # demonstrations of the scripted crew: at most 3 x the agent rows
        JUDGED =
          if cfg.exportJudged
          then "1"
          else "0";
      };
      serviceConfig = {
        Type = "oneshot";
        # The frozen eval set first (built once, then kept), so the export can leave its situations out.
        ExecStart = [
          "${pkgs.nodejs}/bin/node ${../../../../tools/mcagents}/eval-set.js /var/lib/mcagents/decisions.jsonl /var/lib/mcagents/eval"
          "${pkgs.nodejs}/bin/node ${../../../../tools/mcagents}/export-sft.js /var/lib/mcagents/decisions.jsonl /var/lib/mcagents/export"
        ];
        ExecStartPost = "+${pkgs.coreutils}/bin/install -m 0644 /var/lib/mcagents/export/sft.jsonl /var/lib/mcagents/export/stats.json /var/lib/mcagents-export/";
        # Same dynamic user as mcagents.service, so the log is readable.
        DynamicUser = true;
        User = "mcagents";
        StateDirectory = "mcagents";
        Nice = 19;
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "idle";
        TimeoutStartSec = "10min";
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateNetwork = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictNamespaces = true;
        RestrictAddressFamilies = "none";
        SystemCallFilter = "@system-service";
        MemoryMax = "512M";
      };
    };
    systemd.timers.mcagents-dataset = {
      wantedBy = ["timers.target"];
      # A calendar time, not OnBootSec (see the idle-replay timer).
      timerConfig = {
        OnCalendar = "*-*-* 04:20:00";
        RandomizedDelaySec = "10min";
      };
    };
  };
}
