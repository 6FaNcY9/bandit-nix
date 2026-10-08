{
  description = "bandit nixos config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim.url = "github:nix-community/nixvim";

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fzf-tab-source = {
      url = "github:Freed-Wu/fzf-tab-source";
      flake = false;
    };

    zsh-kimi-cli = {
      url = "github:MoonshotAI/zsh-kimi-cli";
      flake = false;
    };

    pdfreader-nvim = {
      url = "github:r-pletnev/pdfreader.nvim/v0.1.7";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    sops-nix,
    stylix,
    nixos-hardware,
    ...
  } @ inputs: let
    repoConfig = import ./lib/repository.nix {inherit (nixpkgs) lib;};
    inherit (repoConfig) system;
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfreePredicate = repoConfig.allowUnfreePredicate;
    };
    hmBackupCommand = pkgs.writeShellScript "home-manager-backup" ''
      set -euo pipefail

      target="$1"
      backup="$target.hm-backup"
      ${pkgs.coreutils}/bin/mv --backup=numbered --no-target-directory -- "$target" "$backup"
      printf 'Home Manager: moved %s to %s (older copies use .~N~ suffixes)\n' "$target" "$backup"
    '';
    standaloneStylix = {
      stylix = repoConfig.mkStylixTheme pkgs;
    };
    sharedArgs = {inherit inputs repoConfig;};
    securityLab = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [./labs/security];
    };
    securityLabOnline = securityLab.extendModules {
      modules = [{virtualisation.restrictNetwork = nixpkgs.lib.mkForce false;}];
    };

    hmBase = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupCommand = hmBackupCommand;
      extraSpecialArgs = sharedArgs;
      users.${repoConfig.workstation.username} = import ./home;
    };
  in {
    nixosConfigurations = let
      banditModules = [
        {nixpkgs.hostPlatform = system;}
        stylix.nixosModules.stylix
        nixos-hardware.nixosModules.framework-13-7040-amd
        sops-nix.nixosModules.sops
        ./hosts/bandit
        ./nixos
        home-manager.nixosModules.home-manager
        {home-manager = hmBase;}
      ];
    in {
      bandit = nixpkgs.lib.nixosSystem {
        specialArgs = sharedArgs;
        modules = banditModules;
      };

      bandit-ci = nixpkgs.lib.nixosSystem {
        specialArgs = sharedArgs;
        modules = banditModules ++ [./nixos/ci-overrides.nix];
      };

      bandit-lab = nixpkgs.lib.nixosSystem {
        specialArgs = sharedArgs;
        modules = [
          inputs.nixvim.nixosModules.nixvim
          sops-nix.nixosModules.sops
          ./hosts/bandit-lab
          ./nixos/server
        ];
      };
    };

    homeConfigurations.vino = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = sharedArgs;
      modules = [
        stylix.homeModules.stylix
        standaloneStylix
        ./home
      ];
    };

    checks.${system} = {
      security-lab-atomic = securityLab.config.system.build.atomicCheck;
      security-lab = let
        inherit (nixpkgs) lib;
        noSharedDirs = name: cfg:
          lib.assertMsg (cfg.config.virtualisation.sharedDirectories == {})
          "${name} must not share host directories with the VM";
      in
        assert noSharedDirs "security-lab" securityLab;
        assert noSharedDirs "security-lab-online" securityLabOnline;
          pkgs.runCommand "security-lab-compose-check" {
            nativeBuildInputs = [pkgs.docker-compose pkgs.gnugrep];
          } ''
            docker-compose -f ${./labs/security/stacks/bloodhound.yml} config --quiet
            docker-compose -f ${./labs/security/stacks/crapi.yml} config --quiet
            # Port contract with labs/security/default.nix labPorts
            # (8080 bloodhound, 8888 crapi gateway, 8025 mail UI): the VM
            # forwards exactly these host ports, so they must stay published.
            docker-compose -f ${./labs/security/stacks/bloodhound.yml} config | grep -q 'published: "8080"'
            docker-compose -f ${./labs/security/stacks/crapi.yml} config | grep -q 'published: "8888"'
            docker-compose -f ${./labs/security/stacks/crapi.yml} config | grep -q 'published: "8025"'
            touch "$out"
          '';
      lab-reliability = let
        lab = self.nixosConfigurations.bandit-lab.config;
      in
        assert nixpkgs.lib.assertMsg (builtins.elem "docker-vaultwarden.service" lab.sops.templates."vaultwarden.env".restartUnits)
        "vaultwarden container must restart on sops secret rotation";
          import ./ci/lab-reliability.nix {inherit pkgs sops-nix;};
      compose-adoption = let
        lab = self.nixosConfigurations.bandit-lab.config;
        monitoringUnit = lab.systemd.services.compose-monitoring;
        mrijaUnit = lab.systemd.services.compose-mrija-archive;
        monitoringExec = monitoringUnit.serviceConfig.ExecStart;
        mrijaExec = mrijaUnit.serviceConfig.ExecStart;
      in
        assert nixpkgs.lib.assertMsg (nixpkgs.lib.hasInfix "--project-name monitoring" monitoringExec)
        "monitoring lifecycle unit must use the monitoring Compose project";
        assert nixpkgs.lib.assertMsg (nixpkgs.lib.hasInfix "--project-name deploy" mrijaExec)
        "Mrija lifecycle unit must preserve the live deploy Compose project";
        assert nixpkgs.lib.assertMsg (monitoringUnit.wantedBy == [] && mrijaUnit.wantedBy == [])
        "Compose adoption units must remain manual until the approved live handoff";
        assert nixpkgs.lib.assertMsg (!monitoringUnit.restartIfChanged && !mrijaUnit.restartIfChanged)
        "Nix activation must not restart adopted Compose projects";
        assert nixpkgs.lib.assertMsg (nixpkgs.lib.hasSuffix " start" monitoringExec && nixpkgs.lib.hasSuffix " start" mrijaExec)
        "Compose lifecycle units must start existing containers without reconciling them";
          pkgs.runCommand "compose-adoption-check" {
            nativeBuildInputs = [pkgs.gnugrep];
          } ''
            ! grep -q '^[[:space:]]*ports:' ${./hosts/bandit-lab/services/monitoring/compose.yml}
            grep -q '/run/secrets/rendered/mrija-archive.env' ${./hosts/bandit-lab/services/mrija-archive/compose.yml}
            touch "$out"
          '';
      docker-discovery-proxy =
        pkgs.runCommand "docker-discovery-proxy-regressions" {
          nativeBuildInputs = [pkgs.python3];
        } ''
          python3 ${./ci/test-docker-discovery-proxy.py} ${pkgs.lib.escapeShellArg self.nixosConfigurations.bandit-lab.config.systemd.services.traefik-docker-proxy.serviceConfig.ExecStart}
          touch "$out"
        '';

      lab-update = let
        inherit (nixpkgs) lib;
        updater =
          lib.findFirst (p: p.name or "" == "lab-update") (throw "lab-update package missing from bandit-lab systemPackages")
          self.nixosConfigurations.bandit-lab.config.environment.systemPackages;
        # The manual history-rewrite override must never be reachable from a
        # unit (timer or otherwise): unattended runs are fast-forward only.
        # This is a lint (a wrapper script hides its text); the updater itself
        # also refuses the flag whenever INVOCATION_ID shows a systemd unit.
        unitText = svc:
          lib.concatStringsSep " " (
            lib.concatMap (k: map toString (lib.toList (svc.serviceConfig.${k} or [])))
            ["ExecStart" "ExecStartPre" "ExecStartPost" "ExecStop" "ExecStopPost" "ExecReload"]
            ++ map (k: toString (svc.${k} or "")) ["script" "preStart" "postStart" "preStop" "postStop" "reload"]
            ++ map toString (lib.toList (svc.scriptArgs or []))
          );
        labConfig = self.nixosConfigurations.bandit-lab.config;
        overrideUnits =
          lib.attrNames (lib.filterAttrs (_: svc: lib.hasInfix "--allow-non-ff" (unitText svc))
            (labConfig.systemd.services // labConfig.systemd.user.services));
      in
        assert nixpkgs.lib.assertMsg (overrideUnits == [])
        "units must not pass --allow-non-ff to lab-update: ${toString overrideUnits}";
          pkgs.runCommand "lab-update-regressions" {
            nativeBuildInputs = [pkgs.python3 pkgs.git pkgs.bash pkgs.coreutils];
          } ''
            python3 ${./ci/test-lab-update.py} ${updater}/bin/lab-update
            touch "$out"
          '';

      repository =
        pkgs.runCommand "bandit-nix-repository-checks" {
          nativeBuildInputs = with pkgs; [alejandra deadnix statix];
          src = ./.;
        } ''
          cp -r "$src" source
          chmod -R u+w source
          cd source
          alejandra --check .
          deadnix --fail .
          statix check .
          touch "$out"
        '';

      sops-isolation = import ./ci/sops-isolation.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
        hosts = {inherit (self.nixosConfigurations) bandit bandit-lab;};
      };

      lab-backup = import ./ci/lab-backup.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
        labOn =
          (self.nixosConfigurations.bandit-lab.extendModules {
            modules = [{bandit-lab.backups.enable = true;}];
          })
          .config;
        labOff = self.nixosConfigurations.bandit-lab.config;
      };

      backup-peer = import ./ci/backup-peer.nix {
        inherit pkgs repoConfig;
        inherit (nixpkgs) lib;
        hosts = {inherit (self.nixosConfigurations) bandit bandit-lab;};
      };

      lab-kernel = import ./ci/lab-kernel.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      lab-minecraft = import ./ci/lab-minecraft.nix {
        inherit pkgs repoConfig;
        inherit (nixpkgs) lib;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      lab-mcbots = import ./ci/lab-mcbots.nix {
        inherit (nixpkgs) lib;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      lab-surface = import ./ci/lab-surface.nix {
        inherit pkgs repoConfig;
        inherit (nixpkgs) lib;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      local-privilege = import ./ci/local-privilege.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
        hosts = {inherit (self.nixosConfigurations) bandit bandit-lab;};
      };

      theme-contract = import ./ci/theme-contract.nix {
        inherit pkgs repoConfig;
        inherit (nixpkgs) lib;
      };

      output-evaluation = let
        evaluatedPath = builtins.unsafeDiscardStringContext;
      in
        pkgs.writeText "bandit-nix-output-evaluation.json" (builtins.toJSON {
          bandit = evaluatedPath self.nixosConfigurations.bandit.config.system.build.toplevel.drvPath;
          bandit-ci = evaluatedPath self.nixosConfigurations.bandit-ci.config.system.build.toplevel.drvPath;
          bandit-lab = evaluatedPath self.nixosConfigurations.bandit-lab.config.system.build.toplevel.drvPath;
          home = evaluatedPath self.homeConfigurations.vino.activationPackage.drvPath;
        });

      home-manager-backup = pkgs.runCommand "home-manager-backup-check" {} ''
        mkdir work
        printf first > work/config
        ${hmBackupCommand} work/config
        printf second > work/config
        ${hmBackupCommand} work/config
        test "$(cat work/config.hm-backup)" = second
        test "$(cat work/config.hm-backup.~1~)" = first

        mkdir work/source-dir work/source-dir.hm-backup
        printf source > work/source-dir/file
        printf prior > work/source-dir.hm-backup/file
        ${hmBackupCommand} work/source-dir
        test "$(cat work/source-dir.hm-backup/file)" = source
        test "$(cat work/source-dir.hm-backup.~1~/file)" = prior
        touch "$out"
      '';

      dotdir-tools = import ./ci/dotdir-tools.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
        homePackages = self.homeConfigurations.vino.config.home.packages;
      };
    };

    formatter.${system} = pkgs.alejandra;
    apps.${system}.mcbots = {
      type = "app";
      program = nixpkgs.lib.getExe self.packages.${system}.mcbots;
    };
    packages.${system} = {
      inherit (pkgs) cachix vulnix;
      mcbots = pkgs.callPackage ./hosts/bandit-lab/services/mcbots/package.nix {};
      security-lab = securityLab.config.system.build.vm;
      security-lab-online = securityLabOnline.config.system.build.vm;
    };
  };
}
