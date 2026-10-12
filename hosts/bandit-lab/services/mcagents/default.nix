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
    # bot2 no longer digs the shaft itself: its own shaft job held the shaft walls as stair steps and
    # every plan strip on that shaft failed ("holds up the base or a shaft step", lab 2026-10-11).
    bot2 = {
      goal = "You keep the shaft crew safe but do not run it: the hub plan's workers dig the shaft west of the base (-291, -222 to -276, -207). Stand guard at the shaft with !guardHere(16), pick up what lies around with !collectDrops(16), and tell bot1 with !startConversation when the crew needs torches or food. Never dig the shaft yourself and do not try to !assign workers.";
      workers = "";
    };
    # A third brain while the lab GPU idles (owner, 2026-10-11: more bots should think): bot3 left the
    # plan roster and mines the iron the iron-quota objective waits for.
    bot3 = {
      goal = "You are the crew's iron miner, while the hub plan assigns the other workers. Mine iron ore with !collectBlocks(\"iron_ore\", 16) (best around y 16, reached through the shaft west of the base), put the raw_iron and coal in the base chest with !putInChest, and take torches or food from the base chest when you run low. Never dig the shaft itself and do not try to !assign workers.";
      workers = "";
    };
  };
in {
  options.bandit-lab.mcagents = {
    enable = lib.mkEnableOption "the Andy-4.2 lead agent and its workers" // {default = true;};
    offlineHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # albert is away for now (owner, 2026-10-11): slayer takes the replays and the judge, the lab GPU alone
      # thinks for the live agents (it ran under 1 % with three of them). Back to ["albert"] when albert returns.
      default = ["albert" "slayer"];
      description = "Inference hosts kept for idle replays, the judge and training; they never get live agent or solver traffic.";
    };
    exportJudged = lib.mkEnableOption "judge-graded decisions (source judged) in the daily SFT export";
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services = {
        mcagents = {
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
              # agent.js splits AGENTS at ";": a goal holding one became a fourth "agent" and cut bot3's goal (2026-10-11).
              AGENTS = lib.concatStringsSep ";" (lib.mapAttrsToList (bot: a: assert lib.assertMsg (!lib.hasInfix ";" a.goal) "mcagents: the goal of ${bot} must not contain ';'"; "${bot}=${a.goal}") agents);
              # Every model call (prompt + reply) for a later LoRA fine-tune; agent.js
              # rotates it at 50 MB. The journal gets one line per reply.
              LOG = "/var/lib/mcagents/decisions.jsonl";
              # Fix memory (tools/mcagents/lessons.js): which fix followed which kind of failure and whether it
              # worked, from job results; the solver and the agents see it when the problem comes back.
              LESSONS = "/var/lib/mcagents/lessons.json";
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
        mcagents-idle-replay = lib.mkIf (offlineNames != []) {
          description = "Replay and judge logged Minecraft agent decisions on idle gaming PCs";
          # A deploy must not stop a running pass and then wait up to its 1 h start timeout for the new
          # one (lab-update apply sat 30 min on it, 2026-10-12); the next timer run picks up new code.
          restartIfChanged = false;
          environment =
            offlineEnv
            // {
              JUDGE_BATCH = "200";
              # The offline PCs replay, then grade; a live slayer grades meanwhile in mcagents-judge-slayer (below).
              JUDGE_NAMES = lib.concatStringsSep "," offlineNames;
              # grade batch after batch for up to 20 min per pass (replay first, all inside the 1 h start timeout)
              JUDGE_PASS_MS = "1200000"; # owner: use the idle PCs as much as possible (2026-10-11)
              LOG = "/var/lib/mcagents/decisions.jsonl";
              REPLAYS = "/var/lib/mcagents/replays";
              VARIANTS = "${../../../../tools/mcagents/variants.json}";
              NTFY_URL = "http://127.0.0.1:2586/mcbots";
              BUSY_FILE = "/run/mcagents-busy/players";
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
        # No batch pass while people play Minecraft (main or sandbox): the file lists who is online but the
        # bots, and replay/judge treat every PC as busy while it exists (routing.js peoplePlaying). A replay
        # pass kept slayer's GPU at 100 % and the owner's Minecraft on slayer stuttered (2026-10-12).
        mcagents-players = lib.mkIf (offlineNames != []) {
          description = "Note who plays Minecraft, so batch passes leave the gaming PCs alone";
          path = [pkgs.docker pkgs.coreutils pkgs.gnugrep pkgs.gnused];
          serviceConfig = {
            Type = "oneshot";
            RuntimeDirectory = "mcagents-busy";
            RuntimeDirectoryPreserve = true;
          };
          script = ''
            people=$(for c in minecraft minecraft-sandbox; do docker exec "$c" rcon-cli list 2>/dev/null; done |
              sed -n 's/\x1b\[[0-9;]*m//g; s/.*online: *//p' | tr ',' '\n' | tr -d ' \r' | grep -Evx 'bot[0-9]+|' || true)
            if [ -n "$people" ]; then echo "$people" > /run/mcagents-busy/players; else rm -f /run/mcagents-busy/players; fi
          '';
        };
        # slayer grades from the oldest end while albert replays (it sat at 0 % through every replay, owner
        # 2026-10-11); the two judges never pick the same decisions. Same sandbox as the idle replay.
        mcagents-judge-slayer = lib.mkIf (offlineNames != [] && inferenceHosts ? slayer && !(lib.elem "slayer" offlineNames)) {
          description = "Grade logged Minecraft agent decisions on slayer";
          restartIfChanged = false;
          environment =
            config.systemd.services.mcagents-idle-replay.environment
            // {
              JUDGE_NAMES = "slayer";
              JUDGE_FROM = "oldest";
            };
          serviceConfig =
            config.systemd.services.mcagents-idle-replay.serviceConfig
            // {
              ExecStart = ["-${pkgs.nodejs}/bin/node ${../../../../tools/mcagents}/judge.js"];
            };
        };
        # Daily training export (owner, 2026-10-11): good decisions, solver calls and crew demonstrations from the log as
        # sft.jsonl + stats.json for the LoRA run on the gaming PC (tools/slayer/train). The data is bot
        # prompts and state only (dataset.js drops secret-shaped and human-chat rows). The dynamic user's
        # state directory is private, so a root ExecStartPost publishes the result world-readable under
        # /var/lib/mcagents-export for the admin user. Empty or missing log: empty export, exit 0.
        mcagents-dataset = {
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
      };
      timers = {
        mcagents-players = lib.mkIf (offlineNames != []) {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "1min";
            OnUnitActiveSec = "1min";
          };
        };
        mcagents-judge-slayer = lib.mkIf (offlineNames != [] && inferenceHosts ? slayer && !(lib.elem "slayer" offlineNames)) {
          wantedBy = ["timers.target"];
          timerConfig = config.systemd.timers.mcagents-idle-replay.timerConfig;
        };
        mcagents-idle-replay = lib.mkIf (offlineNames != []) {
          wantedBy = ["timers.target"];
          timerConfig = {
            # A calendar time, not OnBootSec: a timer whose boot delay has long passed fires the
            # moment a deploy starts it, and a failed run then rolls the whole deploy back (2026-10-10).
            OnCalendar = "*-*-* *:15,45:00"; # every 30 min; a run still going simply skips the next start
            RandomizedDelaySec = "10min";
          };
        };
        mcagents-dataset = {
          wantedBy = ["timers.target"];
          # A calendar time, not OnBootSec (see the idle-replay timer).
          timerConfig = {
            OnCalendar = "*-*-* 04:20:00";
            RandomizedDelaySec = "10min";
          };
        };
      };
      # The export directory mcagents-dataset publishes to (see above).
      tmpfiles.rules = ["d /var/lib/mcagents-export 0755 root root -"];
    };
  };
}
