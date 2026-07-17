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

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
  };

  outputs = {
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
          ./nixos/server.nix
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
  };
}
