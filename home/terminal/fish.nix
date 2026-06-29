{pkgs, ...}: let
  sharedAliases = import ./aliases.nix;
in {
  programs = {
    # ─── Fish ─────────────────────────────────────────────────
    fish = {
      enable = true;

      plugins = [
        # fzf keybindings: ctrl-r history, ctrl-f dir, ctrl-v vars, ctrl-alt-p procs
        {
          name = "fzf-fish";
          src = pkgs.fishPlugins.fzf-fish.src;
        }
        # Reminds you when a shorter alias/abbr exists
        {
          name = "fish-you-should-use";
          src = pkgs.fishPlugins.fish-you-should-use.src;
        }
        # fzf on top of fish's native tab completion engine
        {
          name = "fifc";
          src = pkgs.fishPlugins.fifc.src;
        }
        # Auto-close (), [], {}, "", ''
        {
          name = "autopair";
          src = pkgs.fishPlugins.autopair.src;
        }
        # Colorized man pages
        {
          name = "colored-man-pages";
          src = pkgs.fishPlugins.colored-man-pages.src;
        }
        # Remove failed / typo commands from history
        {
          name = "sponge";
          src = pkgs.fishPlugins.sponge.src;
        }
        # Desktop notification when long command finishes
        {
          name = "done";
          src = pkgs.fishPlugins.done.src;
        }
        # Text expansions: . → ./, ... → ../..
        {
          name = "puffer";
          src = pkgs.fishPlugins.puffer.src;
        }
      ];

      shellAbbrs = {
        # Nix rebuilds
        nrs = "sudo nixos-rebuild switch --flake .#bandit";
        nrt = "sudo nixos-rebuild test --flake .#bandit";
        nfc = "nix flake check --no-update-lock-file";
        # Git
        gst = "git status";
        gcm = "git commit -m";
        gco = "git checkout";
        gpsh = "git push";
        # Systemd
        jfu = "journalctl -fu";
        jb = "journalctl -b";
        sc = "systemctl";
        scu = "systemctl --user";
        # Safety — abbrs expand only at the prompt, never inside plugins/functions
        rm = "rm -i";
        cp = "cp -i";
        mv = "mv -i";
      };

      shellAliases =
        sharedAliases
        // {
          nsn = "nix search nixpkgs#";
          # Fish-specific (different syntax from zsh)
          reload = "exec fish";
          paths = "string split : $PATH";
        };

      interactiveShellInit = ''
        # ── Vi mode ───────────────────────────────────────────
        fish_vi_key_bindings
        # Restore fzf bindings clobbered by vi mode
        # ctrl-r=history  ctrl-f=dir  ctrl-v=shell-vars  ctrl-alt-p=processes
        fzf_configure_bindings --history=\cr --directory=\cf --git_log=\cg --git_status=\cs --variables=\cv --processes=\ca\cp

        # ── Retro greeter ─────────────────────────────────────
        function fish_greeting
            set -l nixver (nixos-version 2>/dev/null | string split ' ' --max 2 --field 1)
            set -l kern (uname -r)
            echo ""
            set_color ffcc66
            echo "  λ  bandit · NixOS $nixver"
            set_color 999999
            echo "  kernel $kern  ·  fish $version"
            set_color normal
            echo ""
        end

        # ── Silence you-should-use for git shorthand aliases ──
        set -gx YSU_IGNORED_GLOBAL_ALIASES '^(g|ga|gc|gca|gp|gl|gs|gd|glog)$'

        # ── Cachix — token from sops secret, never global ─────
        function cachix
          if test -r /run/secrets/cachix-secret
            set -lx CACHIX_AUTH_TOKEN (cat /run/secrets/cachix-secret)
            command cachix $argv
          else
            command cachix $argv
          end
        end
      '';
    };

    fish.functions.cb = {
      description = "Copy file contents to clipboard (or stdin if no arg)";
      body = ''
        if test (count $argv) -eq 0
          xclip -selection clipboard
        else if test -f $argv[1]
          xclip -selection clipboard < $argv[1]
        else
          echo "cb: '$argv[1]' is not a file" >&2
          return 1
        end
      '';
    };
  };
}
