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

    nur-szanko = {
      url = "github:SZanko/nur-packages";
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
        assert theme.name == "Gruvbox";
        assert builtins.pathExists ./themes/gruvbox-light.yaml;
        assert actualColorKeys == expectedColorKeys;
        assert theme.geometry.unit == 4;
        assert theme.geometry.radius == 0;
        assert (repoConfig.mkStylixTheme pkgs).base16Scheme == ./themes/gruvbox-dark.yaml;
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

      dotdir-tools = let
        packageByName = name:
          nixpkgs.lib.findFirst
          (package: (package.name or "") == name)
          (throw "missing Home Manager package: ${name}")
          self.homeConfigurations.vino.config.home.packages;
        dotdirAudit = packageByName "bandit-dotdir-audit";
        dotdirAdopt = packageByName "bandit-dotdir-adopt";
      in
        pkgs.runCommand "bandit-nix-dotdir-tools-check" {} ''
          export HOME="$PWD/home"
          export XDG_DATA_HOME="$PWD/data"
          export XDG_CONFIG_HOME="$PWD/config"
          export XDG_CACHE_HOME="$PWD/cache"
          mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

          if ${dotdirAdopt}/bin/bandit-dotdir-adopt >/dev/null 2>&1; then
            echo "adopt accepted missing arguments" >&2
            exit 1
          fi
          if ${dotdirAdopt}/bin/bandit-dotdir-adopt safe data extra >/dev/null 2>&1; then
            echo "adopt accepted too many arguments" >&2
            exit 1
          fi

          mkdir -p "$HOME/.nested/tool" "$XDG_DATA_HOME/nested"
          printf source > "$HOME/.nested/tool/value"
          if ${dotdirAdopt}/bin/bandit-dotdir-adopt nested/tool >/dev/null 2>&1; then
            echo "adopt accepted a name containing a path separator" >&2
            exit 1
          fi
          test -f "$HOME/.nested/tool/value"

          mkdir "$HOME/.blocked" "$XDG_DATA_HOME/blocked-target"
          printf source > "$HOME/.blocked/value"
          ln -s "$XDG_DATA_HOME/blocked-target" "$XDG_DATA_HOME/blocked"
          if ${dotdirAdopt}/bin/bandit-dotdir-adopt blocked >/dev/null 2>&1; then
            echo "adopt accepted a non-directory destination" >&2
            exit 1
          fi
          test "$(cat "$HOME/.blocked/value")" = source
          test -L "$XDG_DATA_HOME/blocked"
          test ! -e "$XDG_DATA_HOME/blocked-target/value"
          mv "$HOME/.nested" "$PWD/nested-leftovers"
          mv "$HOME/.blocked" "$PWD/blocked-leftovers"

          mkdir "$HOME/.fresh"
          printf moved > "$HOME/.fresh/value"
          ${dotdirAdopt}/bin/bandit-dotdir-adopt fresh >/dev/null
          test ! -e "$HOME/.fresh"
          test "$(cat "$XDG_DATA_HOME/fresh/value")" = moved

          mkdir "$HOME/.merge" "$XDG_DATA_HOME/merge"
          printf source > "$HOME/.merge/source-only"
          printf source-conflict > "$HOME/.merge/conflict"
          printf target-conflict > "$XDG_DATA_HOME/merge/conflict"
          ln -s missing "$HOME/.merge/source-dangling"
          ln -s missing "$HOME/.merge/target-dangling"
          ln -s missing "$XDG_DATA_HOME/merge/target-dangling"
          if ${dotdirAdopt}/bin/bandit-dotdir-adopt merge >/dev/null 2>&1; then
            echo "adopt did not report merge conflicts" >&2
            exit 1
          fi
          test "$(cat "$XDG_DATA_HOME/merge/source-only")" = source
          test "$(cat "$XDG_DATA_HOME/merge/conflict")" = target-conflict
          test "$(cat "$HOME/.merge/conflict")" = source-conflict
          test -L "$XDG_DATA_HOME/merge/source-dangling"
          test -L "$XDG_DATA_HOME/merge/target-dangling"
          test -L "$HOME/.merge/target-dangling"
          mv "$HOME/.merge" "$PWD/merge-leftovers"

          mkdir "$HOME/.unknown"
          if ${dotdirAudit}/bin/bandit-dotdir-audit >/dev/null 2>&1; then
            echo "audit missed an unshimmed dotdir" >&2
            exit 1
          fi
          rmdir "$HOME/.unknown"
          mkdir "$HOME/.cache"
          ln -s "$XDG_DATA_HOME/fresh" "$HOME/.shim"
          ${dotdirAudit}/bin/bandit-dotdir-audit >/dev/null

          touch "$out"
        '';
    };

    formatter.${system} = pkgs.alejandra;
    packages.${system} = {
      inherit (pkgs) cachix vulnix;
    };
  };
}
