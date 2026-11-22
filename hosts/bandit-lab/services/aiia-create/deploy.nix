# Direct deploy for Albert (vino's decision 2026-11-20: aiia only, no shell, no sudo).
#
# Albert's key logs in as aiia-deploy, only from his PC's tailnet address, and can only run
# deploy-gate.sh (forced command, `restrict`: no terminal, no forwarding). The gate takes a git
# push of deploy/bandit-lab, builds both images rootless as aiia-deploy, and starts fixed root
# units for the steps that need root: load the images under the units' names, save Redis,
# restart, check, and go back to the old images when the check fails (deploy-root.sh). polkit
# lets aiia-deploy start exactly those units, nothing else; their scripts are in the store.
# vino gets an ntfy push for every deploy and rollback. The builds run in podman's rootless
# network namespace and may reach the IPv4 internet only (no address of this host, no private
# or tailnet network); they are capped at 12 GB, 8 cores, 30 min, and the home is a btrfs
# subvolume with a 50G qgroup (made once by vino, see the runbook).
#
# Stays with vino: everything in default.nix (settings, switches, secrets, routes) and the data
# (Redis snapshots in /srv/containers/aiia-create/redis-deploy-*). Albert's code still runs
# in the pod with the app's secrets, as with the bundles; what changes is that nobody reads
# it before it goes live. Runbook: docs/runbooks/aiia-create.md, "Direct deploy (Albert)".
{
  config,
  lib,
  pkgs,
  ...
}: let
  user = "aiia-deploy";
  # fixed, so the firewall and the slice below can name it before the account exists
  uid = 2610;
  home = "/srv/aiia-deploy";
  stateDir = "/var/lib/aiia-deploy";
  albertIp = config.bandit-lab.inferenceHosts.albert.address;
  albertKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIEq8b8SBlgydQc9urE5FvdnWKXk4ms5XN5AI5j8t7To albert@aiia-deploy";
  podman = config.virtualisation.podman.package;

  # Build arguments of the web image, the same the laptop used (aiia-2-images.sh). Not secret:
  # the Turnstile site key and both origins are in every page's HTML.
  inherit (config.virtualisation.quadlet.containers) aiia-create-api aiia-create-web;
  build = {
    AIIA_APP_ORIGIN = aiia-create-web.containerConfig.environments.APP_ORIGIN;
    AIIA_ASSET_ORIGIN = aiia-create-api.containerConfig.environments.PUBLIC_ASSET_BASE_URL;
    AIIA_TURNSTILE_SITE_KEY = "0x4AAAAAAF8aIAaN6C_ZKkkC";
  };

  # The Dockerfiles use short image names (python:…, node:…).
  registries = pkgs.writeText "aiia-deploy-registries.conf" ''
    unqualified-search-registries = ["docker.io"]
  '';
  hooks = pkgs.linkFarm "aiia-deploy-hooks" [
    {
      name = "pre-receive";
      path = pkgs.writeShellScript "aiia-deploy-pre-receive" (builtins.readFile ./deploy-pre-receive.sh);
    }
  ];

  gate = pkgs.writeShellApplication {
    name = "aiia-gate";
    runtimeInputs = [pkgs.git pkgs.coreutils pkgs.gnutar pkgs.util-linux pkgs.curl pkgs.systemd podman];
    text =
      ''
        # rootless podman needs the setuid newuidmap/newgidmap
        export PATH="$PATH:/run/wrappers/bin"
        export AIIA_DEPLOY_HOOKS=${hooks} AIIA_REGISTRIES=${registries}
      ''
      + lib.concatStrings (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") build)
      + builtins.readFile ./deploy-gate.sh;
  };

  root = pkgs.writeShellApplication {
    name = "aiia-deploy-root";
    runtimeInputs = [podman pkgs.skopeo pkgs.coreutils pkgs.findutils pkgs.util-linux pkgs.curl pkgs.systemd];
    text = builtins.readFile ./deploy-root.sh;
  };

  # The only units aiia-deploy may start; the polkit rule below and the gate use these names.
  rootUnits = ["aiia-deploy-install.service" "aiia-deploy-rollback.service" "aiia-deploy-logs@api.service" "aiia-deploy-logs@web.service"];
  rootUnit = description: args: {
    inherit description;
    after = ["ntfy-seed.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${root}/bin/aiia-deploy-root ${args}";
      # same ntfy publisher as the lab alerts (monitoring/notify.nix); "-": a missing file is no error
      EnvironmentFile = "-/var/lib/mcbots/ntfy/publisher.env";
      Environment = ["NTFY_URL=http://127.0.0.1:2586" "NTFY_TOPIC=mcbots"];
      # loading, two checks of up to ~6 min each and the way back must fit
      TimeoutStartSec = "30min";
    };
  };

  # Pinned right below systemd-nspawn's private-users range (from 524288), so the firewall can
  # name them; lab-surface checks that no other account gets an automatic range that could reach it.
  subStart = 458752;
  subCount = 65536;
  owners = ["${toString uid}" "${toString subStart}-${toString (subStart + subCount - 1)}"];
in {
  users.groups.${user} = {};
  users.users.${user} = {
    # A normal user: rootless podman needs subuid ranges and a logind session.
    isNormalUser = true;
    inherit uid;
    group = user;
    inherit home;
    createHome = true;
    homeMode = "750";
    # sshd runs the forced command through the login shell; dash -c reads no rc file
    shell = pkgs.dash;
    subUidRanges = [
      {
        startUid = subStart;
        count = subCount;
      }
    ];
    subGidRanges = [
      {
        startGid = subStart;
        count = subCount;
      }
    ];
    openssh.authorizedKeys.keys = [''from="${albertIp}",restrict,command="${gate}/bin/aiia-gate" ${albertKey}''];
  };
  environment.shells = [pkgs.dash];

  services.openssh.settings.AllowUsers = ["${user}@${albertIp}"];

  # The image builds run Albert's Dockerfiles with network (npm, pip, base images), inside
  # podman's rootless network namespace (deploy-gate.sh), so every packet leaves through pasta
  # as this uid (or one of its subuids). They may reach the internet over IPv4 and the local
  # DNS stub; nothing on this host (any of its addresses: loopback services, Traefik, anything
  # bound to 0.0.0.0), no private, tailnet, link-local or multicast address, and no IPv6 at all.
  networking.firewall.extraCommands = let
    v4 = ["10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "100.64.0.0/10" "169.254.0.0/16" "224.0.0.0/4" "255.255.255.255/32"];
    jump = ipt: o: "${ipt} -w -C OUTPUT -m owner --uid-owner ${o} -j aiia-deploy-out 2>/dev/null || ${ipt} -w -I OUTPUT -m owner --uid-owner ${o} -j aiia-deploy-out\n";
  in
    ''
      iptables -w -N aiia-deploy-out 2>/dev/null || iptables -w -F aiia-deploy-out
      iptables -w -A aiia-deploy-out -d 127.0.0.53 -p udp --dport 53 -j RETURN
      iptables -w -A aiia-deploy-out -d 127.0.0.53 -p tcp --dport 53 -j RETURN
      iptables -w -A aiia-deploy-out -m addrtype --dst-type LOCAL -j REJECT
    ''
    + lib.concatMapStrings (n: "iptables -w -A aiia-deploy-out -d ${n} -j REJECT\n") v4
    + ''
      ip6tables -w -N aiia-deploy-out 2>/dev/null || ip6tables -w -F aiia-deploy-out
      ip6tables -w -A aiia-deploy-out -j REJECT
    ''
    + lib.concatMapStrings (o: jump "iptables" o + jump "ip6tables" o) owners;
  networking.firewall.extraStopCommands =
    lib.concatMapStrings (o: ''
      iptables -w -D OUTPUT -m owner --uid-owner ${o} -j aiia-deploy-out 2>/dev/null || true
      ip6tables -w -D OUTPUT -m owner --uid-owner ${o} -j aiia-deploy-out 2>/dev/null || true
    '')
    owners;

  # A build must not starve the lab (Minecraft, the bots, the site itself).
  systemd.slices."user-${toString uid}" = {
    overrideStrategy = "asDropin";
    sliceConfig = {
      MemoryMax = "12G";
      MemorySwapMax = "1G";
      CPUQuota = "800%";
      CPUWeight = 50;
      IOWeight = 50;
      TasksMax = 4096;
    };
  };

  systemd.tmpfiles.rules = [
    # The home must be its own btrfs subvolume with a qgroup limit (made once by vino, runbook);
    # the gate refuses to work without it.
    "d ${home} 0750 ${user} ${user} -"
    "d ${home}/out 0750 ${user} ${user} -"
    "d ${stateDir} 0750 root ${user} -"
    "d /var/lib/aiia-deploy-root 0700 root root -"
  ];

  systemd.services = {
    aiia-deploy-install = rootUnit "aiia deploy: load Albert's images, save Redis, restart, check" "install";
    aiia-deploy-rollback = rootUnit "aiia deploy: back to the previous images" "rollback";
    "aiia-deploy-logs@" = rootUnit "aiia deploy: last log lines of aiia-create-%i" "logs %i";
  };

  security.polkit.enable = true;
  security.polkit.extraConfig = lib.mkAfter ''
    // aiia-deploy (Albert's deploy key, services/aiia-create/deploy.nix) may start exactly these
    // root units and nothing else.
    polkit.addRule(function (action, subject) {
      if (subject.user !== "${user}") return polkit.Result.NOT_HANDLED;
      if (action.id === "org.freedesktop.systemd1.manage-units" &&
          action.lookup("verb") === "start" &&
          ${builtins.toJSON rootUnits}.indexOf(action.lookup("unit")) >= 0)
        return polkit.Result.YES;
      return polkit.Result.NO;
    });
  '';
}
