{pkgs, ...}: let
  brandingCss = pkgs.writeText "bandit-lab-cockpit-branding.css" ''
    :root,
    .pf-v6-theme-dark {
      --color-body-background: #1d1f21;
      --color-background: #2d2d2d;
      --color-secondary-background: #393939;
      --color-text: #f2f0ec;
      --color-secondary-text: #cccccc;
      --color-text-light: #999999;
      --color-text-lighter: #747369;
      --color-border: #515151;
      --color-border-light: #747369;
      --color-input-background: #1d1f21;
      --color-input: #f2f0ec;
      --color-primary: #ffcc66;
      --color-primary-active: #f99157;
      --color-link: #66cccc;
      --color-link-active: #99cc99;
      --pf-t--global--font--family--body: "JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Mono", "JetBrains Mono", monospace;
      --pf-t--global--font--family--heading: "JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Mono", "JetBrains Mono", monospace;
      --pf-t--global--border--radius--tiny: 0;
      --pf-t--global--border--radius--small: 0;
      --pf-t--global--border--radius--medium: 0;
      --pf-t--global--border--radius--large: 0;
      --pf-t--global--border--radius--pill: 0;
    }

    * {
      letter-spacing: 0 !important;
    }

    body,
    button,
    input,
    select,
    textarea {
      font-family: "JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Mono", "JetBrains Mono", monospace !important;
    }

    body,
    .pf-v6-c-page,
    .pf-v6-c-page__main,
    .pf-v6-c-page__sidebar,
    .pf-v6-c-masthead,
    .pf-v6-c-card,
    .pf-v6-c-table,
    .pf-v6-c-panel,
    .pf-v6-c-modal-box,
    .pf-v6-c-menu,
    .pf-v6-c-dropdown__menu,
    .pf-v6-c-popover,
    .pf-v6-c-drawer,
    .pf-v6-c-toolbar,
    .pf-v6-c-tabs,
    .pf-v6-c-nav {
      background: #2d2d2d !important;
      color: #f2f0ec !important;
    }

    .pf-v6-c-masthead,
    .pf-v6-c-page__sidebar,
    .pf-v6-c-card,
    .pf-v6-c-table,
    .pf-v6-c-panel,
    .pf-v6-c-modal-box,
    .pf-v6-c-menu,
    .pf-v6-c-dropdown__menu,
    .pf-v6-c-popover,
    .pf-v6-c-drawer {
      border: 1px solid #515151 !important;
      box-shadow: inset 1px 1px 0 #747369, inset -1px -1px 0 #1d1f21 !important;
    }

    .pf-v6-c-button,
    .pf-v6-c-menu-toggle,
    .pf-v6-c-form-control,
    .pf-v6-c-text-input-group,
    .form-control,
    input,
    select,
    textarea {
      background: #1d1f21 !important;
      border: 1px solid #515151 !important;
      border-radius: 0 !important;
      color: #f2f0ec !important;
      box-shadow: inset 1px 1px 0 #747369, inset -1px -1px 0 #111111 !important;
    }

    .pf-v6-c-button.pf-m-primary,
    .pf-v6-c-button.pf-m-progress {
      background: #393939 !important;
      border-color: #ffcc66 !important;
      color: #ffcc66 !important;
    }

    a,
    .pf-v6-c-nav__link.pf-m-current,
    .pf-v6-c-tabs__link[aria-selected="true"] {
      color: #66cccc !important;
    }

    .pf-v6-c-label,
    .pf-v6-c-badge {
      background: #393939 !important;
      border: 1px solid #515151 !important;
      border-radius: 0 !important;
      color: #cccccc !important;
    }

    #badge {
      display: none;
    }

    #brand::before {
      content: "bandit-lab";
      color: #ffcc66;
      font-family: "JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Mono", "JetBrains Mono", monospace;
      font-size: 1.75rem;
      font-weight: 700;
      text-shadow: 1px 1px 0 #1d1f21;
    }

    .login-pf .container {
      background: #2d2d2d !important;
      border: 1px solid #515151 !important;
      border-radius: 0 !important;
      box-shadow: inset 1px 1px 0 #747369, inset -1px -1px 0 #111111 !important;
    }

    #system-terminal-page,
    #terminal,
    .terminal,
    .terminal-wrapper,
    .xterm,
    .xterm-viewport,
    .xterm-screen,
    .xterm-rows {
      background: #1d1f21 !important;
      color: #f2f0ec !important;
      font-family: "JetBrainsMono Nerd Font Mono", "JetBrainsMono Nerd Font", "JetBrains Mono", monospace !important;
    }

    #terminal {
      border: 1px solid #515151 !important;
      box-shadow: inset 1px 1px 0 #747369, inset -1px -1px 0 #111111 !important;
    }

    .terminal .xterm-viewport,
    .xterm .xterm-viewport {
      scrollbar-color: #515151 #1d1f21 !important;
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
