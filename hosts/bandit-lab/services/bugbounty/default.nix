# Bug-bounty mode for bandit-lab: the specialisation "bugbounty" adds recon and
# web tools and stops the heavy services (Minecraft, bots, AI on the GPU, side
# dashboards). The AiiA site, Jerry's box, Grafana with Prometheus and its
# PostgreSQL datasource, and the system base keep running.
#
#   bugbounty            show the running mode
#   sudo bugbounty dry   list what the switch would stop and start; changes nothing
#   sudo bugbounty on    activate the specialisation
#   sudo bugbounty off   back to normal mode (the current system profile)
#
# Both directions use switch-to-configuration test, which never touches the boot
# loader: a reboot always comes back in normal mode. The specialisation only masks
# units and adds packages, so sshd, tailscaled, the firewall and the network units
# are byte-identical in both modes and are not restarted by the switch.
# lab-update-apply.timer is masked too, so no unattended deploy switches the lab
# back during a session; after "off" it resumes and applies whatever is pending.
# A deploy with lab-apply from the laptop also returns the lab to normal mode.
{
  config,
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  user = config.users.users.${repoConfig.workstation.username};

  # Masking a unit makes switch-to-configuration stop it; switching back unmasks
  # and starts it again through its target.
  stopServices =
    [
      # Minecraft, its bridges and the public server with its guild bot
      "minecraft-server-paper"
      "minecraft-server-velocity"
      "minecraft-datapacks" # oneshot that waits for the server; would hang the switch
      "mc-bridge-botui"
      "mc-bridge-map"
      "mc-bridge-rcon"
      "mc-bridge-rcon-sandbox"
      "playit"
      "container@mc-public"
      "discord-admin"
      # AI on the lab's GPU; albert-tunnel and slayer-tunnel stay, so albert's RTX 5080
      # and slayer's RTX 5070 can serve models in this mode (vino, 2026-11-24)
      "docker-ollama"
      "docker-comfyui"
      "bnet-router"
      # Side dashboards; Grafana and Prometheus stay
      "beszel-hub"
      "beszel-agent"
      "ntopng"
      "redis-ntopng"
    ]
    # the bot hub and however many workers bandit-craft defines
    ++ lib.filter (lib.hasPrefix "docker-mcbots") (lib.attrNames config.systemd.services);
  # nix-minecraft's console sockets would start the servers again on any write
  stopSockets = ["minecraft-server-paper" "minecraft-server-velocity"];
  stopTimers = ["minecraft-backup" "restic-backups-mc-public" "werbung-bump" "werbung-members" "lab-update-apply"];

  mask = _: {enable = lib.mkForce false;};

  bugbounty = pkgs.writeShellApplication {
    name = "bugbounty";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      profile=/nix/var/nix/profiles/system
      spec="$profile/specialisation/bugbounty"
      mode() {
        if [ "$(readlink -f /run/current-system)" = "$(readlink -f "$spec")" ]; then echo on; else echo off; fi
      }
      cmd="''${1:-status}"
      case "$cmd" in
        status) echo "bugbounty: $(mode)" ;;
        on | off | dry)
          [ "$(id -u)" -eq 0 ] || exec /run/wrappers/bin/sudo "$0" "$cmd"
          if [ ! -x "$spec/bin/switch-to-configuration" ]; then
            echo "bugbounty: $profile has no bugbounty specialisation; deploy it first" >&2
            exit 1
          fi
          case "$cmd" in
            on)
              [ "$(mode)" = off ] || { echo "bugbounty: already on"; exit 0; }
              "$spec/bin/switch-to-configuration" test
              echo "bugbounty: on. 'sudo bugbounty off' or a reboot returns to normal mode."
              ;;
            off)
              [ "$(mode)" = on ] || { echo "bugbounty: already off"; exit 0; }
              "$profile/bin/switch-to-configuration" test
              echo "bugbounty: off, normal mode"
              ;;
            dry)
              if [ "$(mode)" = on ]; then
                "$profile/bin/switch-to-configuration" dry-activate
              else
                "$spec/bin/switch-to-configuration" dry-activate
              fi
              ;;
          esac
          ;;
        *)
          echo "usage: bugbounty [status|dry|on|off]" >&2
          exit 2
          ;;
      esac
    '';
  };
in {
  imports = [./claude.nix];

  # A renamed or removed unit would otherwise be masked silently and keep running.
  assertions =
    map (n: {
      assertion = config.systemd.services ? ${n};
      message = "bugbounty: service ${n} does not exist on bandit-lab";
    })
    stopServices
    ++ map (n: {
      assertion = config.systemd.sockets ? ${n};
      message = "bugbounty: socket ${n} does not exist on bandit-lab";
    })
    stopSockets
    ++ map (n: {
      assertion = config.systemd.timers ? ${n};
      message = "bugbounty: timer ${n} does not exist on bandit-lab";
    })
    stopTimers;

  environment.systemPackages = [bugbounty];

  # `bugbounty dry` as root without sudo, for the claude account (claude.nix); output in its journal.
  systemd.services.bugbounty-dry = {
    description = "bugbounty: what on/off would stop and start (dry-activate, changes nothing)";
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bugbounty}/bin/bugbounty dry";
    };
  };

  # Notes, scope files and scan output; kept in both modes.
  systemd.tmpfiles.rules = ["d ${user.home}/bugbounty 0700 ${user.name} ${user.group} -"];

  specialisation.bugbounty.configuration = {
    systemd = {
      services = lib.genAttrs stopServices mask;
      sockets = lib.genAttrs stopSockets mask;
      timers = lib.genAttrs stopTimers mask;
    };

    # SecLists at /run/current-system/sw/share/wordlists/seclists
    environment.pathsToLink = ["/share/wordlists"];
    environment.systemPackages = with pkgs; [
      # recon
      subfinder
      amass
      dnsx
      httpx
      naabu
      nmap
      katana
      gau
      tlsx
      cdncheck
      uncover
      whatweb
      gowitness
      # web
      nuclei
      ffuf
      feroxbuster
      sqlmap
      dalfox
      arjun
      interactsh
      # proxies: Caido's web UI over an SSH tunnel, Burp on the VNC desktop (lab-desktop)
      caido-cli
      burpsuite
      # wordlists and URL helpers
      seclists
      unfurl
      qsreplace
    ];
  };
}
