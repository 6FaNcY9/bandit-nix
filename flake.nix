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

    nixos-hardware.url = "github:NixOS/nixos-hardware";

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
    hmBase = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-backup";
      extraSpecialArgs = {inherit inputs;};
      users.vino = import ./home;
    };
  in {
    nixosConfigurations = {
      bandit = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
        modules = [
          {nixpkgs.hostPlatform = "x86_64-linux";}
          stylix.nixosModules.stylix
          nixos-hardware.nixosModules.framework-13-7040-amd
          sops-nix.nixosModules.sops
          ./hosts/bandit
          ./nixos
          home-manager.nixosModules.home-manager
          {home-manager = hmBase;}
        ];
      };

      bandit-ci = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
        modules = [
          {nixpkgs.hostPlatform = "x86_64-linux";}
          stylix.nixosModules.stylix
          nixos-hardware.nixosModules.framework-13-7040-amd
          sops-nix.nixosModules.sops
          ./hosts/bandit
          ./nixos
          ./nixos/ci-overrides.nix
          home-manager.nixosModules.home-manager
          {home-manager = hmBase;}
        ];
      };

      bandit-lab = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/bandit-lab
          ./nixos/server.nix
        ];
      };
    };
  };
}
