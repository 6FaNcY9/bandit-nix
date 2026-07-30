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

    checks.${system} = {
      repository =
        pkgs.runCommand "bandit-nix-repository-checks" {
          nativeBuildInputs = with pkgs; [alejandra bash deadnix gnugrep shellcheck statix];
          src = ./.;
        } ''
          cp -r "$src" source
          chmod -R u+w source
          cd source
          alejandra --check .
          deadnix --fail .
          statix check .
          shellcheck install-nixos.sh install-bandit-lab.sh

          bash ./install-nixos.sh --help | grep -q -- '--root-dev DEV'
          bash ./install-bandit-lab.sh --help | grep -q -- '--boot-mount PATH'
          if bash ./install-nixos.sh --not-a-real-option >installer-error 2>&1; then
            echo 'install-nixos.sh accepted an unknown option' >&2
            exit 1
          fi
          grep -q 'unknown argument: --not-a-real-option' installer-error
          touch "$out"
        '';

      theme-contract = let
        inherit (nixpkgs) lib;
        theme = repoConfig.workstationTheme;
        actualColorKeys = lib.sort builtins.lessThan (builtins.attrNames theme.colors);
        expectedColorKeys = lib.sort builtins.lessThan [
          "active"
          "canvas"
          "critical"
          "foreground"
          "info"
          "muted"
          "primary"
          "raised"
          "secondary"
          "shadow"
          "structure"
          "success"
          "surface"
        ];
      in
        assert repoConfig ? workstationTheme;
        assert theme.name == "Chinatown Pixel";
        assert actualColorKeys == expectedColorKeys;
        assert theme.geometry.unit == 4;
        assert theme.geometry.radius == 0;
        assert (repoConfig.mkStylixTheme pkgs).base16Scheme == ./home/chinatown-pixel.yaml;
        assert theme.fonts.shell.name == "Departure Mono";
        assert theme.fonts.technical.name == "JetBrainsMono Nerd Font Mono";
        assert theme.fonts.interface.name == "Noto Sans";
        assert theme.icons.name == "Papirus-Dark";
        assert theme.cursor.name == "Bibata-Modern-Ice";
          pkgs.runCommand "bandit-nix-theme-contract" {} ''
            touch "$out"
          '';

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
    };

    formatter.${system} = pkgs.alejandra;
    packages.${system} = {
      inherit (pkgs) cachix vulnix;
    };
  };
}
