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

    # The game and AI half (Minecraft, bots, Andy, the gaming PCs' tooling), split out 2026-10-12.
    # bandit-lab imports its modules (hosts/bandit-lab/default.nix); hosts, secrets and deployment stay here.
    bandit-craft = {
      url = "github:6FaNcY9/bandit-craft";
      inputs.nixpkgs.follows = "nixpkgs";
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
      stylix = repoConfig.mkStylixTheme pkgs "dark";
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
      security-lab = import ./ci/security-lab.nix {
        inherit pkgs securityLab securityLabOnline;
        inherit (nixpkgs) lib;
      };

      lab-reliability = import ./ci/lab-reliability.nix {
        inherit pkgs sops-nix;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      compose-adoption = import ./ci/compose-adoption.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      docker-discovery-proxy = import ./ci/docker-discovery-proxy.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      lab-update = import ./ci/lab-update.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      repository = import ./ci/repository.nix {
        inherit pkgs;
        src = ./.;
      };

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
        craft = inputs.bandit-craft;
        inherit (nixpkgs) lib;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      lab-mcbots = import ./ci/lab-mcbots.nix {
        inherit pkgs repoConfig;
        inherit (nixpkgs) lib;
        lab = self.nixosConfigurations.bandit-lab.config;
      };

      inherit (inputs.bandit-craft.checks.${system}) mcagents-tests;

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

      output-evaluation = import ./ci/output-evaluation.nix {
        inherit pkgs;
        inherit (self) nixosConfigurations homeConfigurations;
      };

      home-manager-backup = import ./ci/home-manager-backup.nix {
        inherit pkgs hmBackupCommand;
      };

      dotdir-tools = import ./ci/dotdir-tools.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
        homePackages = self.homeConfigurations.vino.config.home.packages;
      };
    };

    formatter.${system} = pkgs.alejandra;
    apps.${system} = {
      mcbots = {
        type = "app";
        program = nixpkgs.lib.getExe self.packages.${system}.mcbots;
      };
      mcbots-worker = {
        type = "app";
        program = nixpkgs.lib.getExe self.packages.${system}.mcbots-worker;
      };
    };
    packages.${system} = {
      inherit (pkgs) cachix vulnix;
      mcbots = pkgs.callPackage "${inputs.bandit-craft}/hosts/bandit-lab/services/mcbots/package.nix" {};
      mcbots-worker = pkgs.callPackage "${inputs.bandit-craft}/hosts/bandit-lab/services/mcbots/worker.nix" {
        inherit repoConfig;
        inherit (self.packages.${system}) mcbots;
      };
      security-lab = securityLab.config.system.build.vm;
      security-lab-online = securityLabOnline.config.system.build.vm;
    };
  };
}
