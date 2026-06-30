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
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    standaloneStylix = {
      stylix = {
        enable = true;
        base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark.yaml";
        image = "${pkgs.nixos-artwork.wallpapers.nineish-dark-gray}/share/wallpapers/nineish-dark-gray/contents/images/nix-wallpaper-nineish-dark-gray.png";
        fonts = {
          monospace = {
            package = pkgs.nerd-fonts.jetbrains-mono;
            name = "JetBrainsMono Nerd Font Mono";
          };
          sansSerif = {
            package = pkgs.nerd-fonts.jetbrains-mono;
            name = "JetBrainsMono Nerd Font";
          };
          serif = {
            package = pkgs.nerd-fonts.jetbrains-mono;
            name = "JetBrainsMono Nerd Font";
          };
          sizes = {
            terminal = 14;
            applications = 14;
            desktop = 14;
            popups = 11;
          };
        };
      };
    };

    hmBase = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-backup";
      extraSpecialArgs = {inherit inputs;};
      users.vino = import ./home;
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
        specialArgs = {inherit inputs;};
        modules = banditModules;
      };

      bandit-ci = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
        modules = banditModules ++ [./nixos/ci-overrides.nix];
      };

      bandit-lab = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
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
      extraSpecialArgs = {inherit inputs;};
      modules = [
        stylix.homeModules.stylix
        standaloneStylix
        ./home
      ];
    };
  };
}
