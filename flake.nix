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
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
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
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    sharedModules = [
      stylix.nixosModules.stylix
      sops-nix.nixosModules.sops
      ./nixos
      home-manager.nixosModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = {inherit inputs;};
          users.vino = import ./home;
        };
      }
    ];
  in {
    nixosConfigurations.bandit = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};
      modules =
        sharedModules
        ++ [
          {nixpkgs.hostPlatform = system;}
          nixos-hardware.nixosModules.framework-13-7040-amd
          ./hosts/bandit
        ];
    };

    checks.${system}.bandit-test = pkgs.testers.runNixOSTest {
      name = "bandit-test";
      nodes.bandit = {lib, ...}: {
        imports = sharedModules;
        # Avoid duplicate overlay definitions from runNixOSTest read-only nixpkgs + Stylix modules.
        nixpkgs.overlays = lib.mkForce [];
        virtualisation.graphics = false;
        virtualisation.memorySize = 2048;
        virtualisation.cores = 2;
        networking.hostName = "bandit";
        system.stateVersion = "25.11";
        users.users.vino.password = "test"; # test-only credential
        users.users.root.password = "test"; # test-only credential
        users.mutableUsers = true;
      };
      testScript = builtins.readFile ./tests/bandit.nix;
    };
  };
}
