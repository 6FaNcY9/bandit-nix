# Firefox userChrome.css — Gruvbox Retro Theming Research

## Overview

Firefox browser UI can be restyled with `userChrome.css` placed in the profile's `chrome/` directory.
Home Manager manages this via `programs.firefox.profiles.<name>.userChrome`.

`about:config` must have `toolkit.legacyUserProfileCustomizations.stylesheets = true` for userChrome to load.

## Community Resources

- **firefoxcss-store.github.io** — 121 community themes, searchable by tag
  - Tags: `gruvbox`, `retro`, `minimal`, `dark`
  - URL: https://firefoxcss-store.github.io/
- Known gruvbox Firefox themes on that store exist (search tag: gruvbox)

## Gruvbox userChrome.css — Bandit Design

Target: retro feel, minimal rounded corners (2px on URL bar only), gruvbox palette.

```css
/* userChrome.css — gruvbox retro */

/* === Variables === */
:root {
  --gruvbox-bg:      #282828;
  --gruvbox-bg-hard: #1d2021;
  --gruvbox-bg1:     #3c3836;
  --gruvbox-bg2:     #504945;
  --gruvbox-fg:      #ebdbb2;
  --gruvbox-fg4:     #a89984;
  --gruvbox-yellow:  #d79921;
  --gruvbox-blue:    #458588;
  --gruvbox-red:     #cc241d;
}

/* === Tab bar === */
.tabbrowser-tab .tab-background {
  background-color: var(--gruvbox-bg-hard) !important;
  border-radius: 2px 2px 0 0 !important;
  border: 1px solid var(--gruvbox-bg1) !important;
}
.tabbrowser-tab[selected] .tab-background {
  background-color: var(--gruvbox-bg) !important;
  border-color: var(--gruvbox-blue) !important;
}
.tab-label { color: var(--gruvbox-fg4) !important; }
.tabbrowser-tab[selected] .tab-label { color: var(--gruvbox-fg) !important; }

/* === Toolbar === */
#nav-bar {
  background-color: var(--gruvbox-bg) !important;
  border-bottom: 1px solid var(--gruvbox-bg1) !important;
}
#urlbar-background {
  background-color: var(--gruvbox-bg-hard) !important;
  border: 1px solid var(--gruvbox-blue) !important;
  border-radius: 2px !important;
}
#urlbar:focus-within > #urlbar-background {
  border-color: var(--gruvbox-yellow) !important;
}

/* === Bookmarks bar === */
#PersonalToolbar {
  background-color: var(--gruvbox-bg-hard) !important;
  border-bottom: 1px solid var(--gruvbox-bg1) !important;
}

/* === Remove rounded corners on menus/popups === */
menupopup, panel { border-radius: 0 !important; }
```

## NixOS Home Manager Config

```nix
programs.firefox = {
  enable = true;
  profiles.vino = {
    settings = {
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      "browser.tabs.inTitlebar" = 0;  # system titlebar (more compatible with i3)
      "browser.compactmode.show" = true;
      "browser.uidensity" = 1;  # compact UI
    };
    userChrome = builtins.readFile ./desktop/firefox-userchrome.css;
  };
};
```

## Sources
- firefoxcss-store.github.io — community themes directory
- MDN: CSS custom properties in Firefox chrome context
- NixOS Home Manager manual: programs.firefox.profiles.<name>.userChrome
