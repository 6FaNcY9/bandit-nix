{
  pkgs,
  repoConfig,
  ...
}: let
  # Same roles as the laptop (themes/palette.nix): flat grey, amber focus,
  # cyan links. No hex literals here; ci/theme-contract.nix enforces it.
  r = repoConfig.palette.roles "dark";
  mono = ''"FiraCode Nerd Font Mono", "FiraCode Nerd Font", monospace'';
  brandingCss = pkgs.writeText "bandit-lab-cockpit-branding.css" ''
    :root,
    .pf-v6-theme-dark {
      --color-body-background: ${r.bg};
      --color-background: ${r.surface};
      --color-secondary-background: ${r.raised};
      --color-text: ${r.fg};
      --color-secondary-text: ${r.dim};
      --color-text-light: ${r.dim};
      --color-text-lighter: ${r.muted};
      --color-border: ${r.line};
      --color-border-light: ${r.borderInactive};
      --color-input-background: ${r.bg};
      --color-input: ${r.fg};
      --color-primary: ${r.accent};
      --color-primary-active: ${r.accent};
      --color-link: ${r.info};
      --color-link-active: ${r.bright};
      --pf-t--global--font--family--body: ${mono};
      --pf-t--global--font--family--heading: ${mono};
      --pf-t--global--border--radius--tiny: 0;
      --pf-t--global--border--radius--small: 0;
      --pf-t--global--border--radius--medium: 0;
      --pf-t--global--border--radius--large: 0;
      --pf-t--global--border--radius--pill: 0;
    }

    * { letter-spacing: 0 !important; box-shadow: none !important; }

    body, button, input, select, textarea { font-family: ${mono} !important; }

    body, .pf-v6-c-page, .pf-v6-c-page__main, .pf-v6-c-page__sidebar, .pf-v6-c-masthead,
    .pf-v6-c-card, .pf-v6-c-table, .pf-v6-c-panel, .pf-v6-c-modal-box, .pf-v6-c-menu,
    .pf-v6-c-dropdown__menu, .pf-v6-c-popover, .pf-v6-c-drawer, .pf-v6-c-toolbar,
    .pf-v6-c-tabs, .pf-v6-c-nav {
      background: ${r.surface} !important;
      color: ${r.fg} !important;
    }

    .pf-v6-c-masthead, .pf-v6-c-page__sidebar, .pf-v6-c-card, .pf-v6-c-table, .pf-v6-c-panel,
    .pf-v6-c-modal-box, .pf-v6-c-menu, .pf-v6-c-dropdown__menu, .pf-v6-c-popover, .pf-v6-c-drawer,
    .login-pf .container, #terminal {
      border: 1px solid ${r.line} !important;
      border-radius: 0 !important;
    }

    .pf-v6-c-button, .pf-v6-c-menu-toggle, .pf-v6-c-form-control, .pf-v6-c-text-input-group,
    .form-control, input, select, textarea {
      background: ${r.bg} !important;
      border: 1px solid ${r.line} !important;
      border-radius: 0 !important;
      color: ${r.fg} !important;
    }

    .pf-v6-c-button.pf-m-primary, .pf-v6-c-button.pf-m-progress {
      background: ${r.raised} !important;
      border-color: ${r.accent} !important;
      color: ${r.accent} !important;
    }

    a, .pf-v6-c-nav__link.pf-m-current, .pf-v6-c-tabs__link[aria-selected="true"] {
      color: ${r.info} !important;
    }

    .pf-v6-c-label, .pf-v6-c-badge {
      background: ${r.raised} !important;
      border: 1px solid ${r.line} !important;
      border-radius: 0 !important;
      color: ${r.dim} !important;
    }

    #badge { display: none; }

    #brand::before {
      content: "bandit-lab";
      color: ${r.accent};
      font-family: ${mono};
      font-size: 1.75rem;
      font-weight: 700;
    }

    .login-pf .container { background: ${r.surface} !important; }

    #system-terminal-page, #terminal, .terminal, .terminal-wrapper, .xterm,
    .xterm-viewport, .xterm-screen, .xterm-rows {
      background: ${r.bg} !important;
      color: ${r.fg} !important;
      font-family: ${mono} !important;
    }

    .terminal .xterm-viewport, .xterm .xterm-viewport {
      scrollbar-color: ${r.line} ${r.bg} !important;
    }
  '';
  bindBranding = [
    "${brandingCss}:${pkgs.cockpit}/share/cockpit/branding/nixos/branding.css"
  ];
in {
  systemd.services = {
    "cockpit-wsinstance-http".serviceConfig.BindReadOnlyPaths = bindBranding;
    "cockpit-wsinstance-https@".serviceConfig.BindReadOnlyPaths = bindBranding;
  };
}
