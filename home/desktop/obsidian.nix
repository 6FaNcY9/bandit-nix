{
  config,
  pkgs,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;

  # Obsidian community plugins are not packaged in nixpkgs. Build each one as
  # a linkFarm of the upstream release assets (main.js + manifest.json +
  # styles.css); home-manager reads manifest.json for the plugin id and links
  # the directory into <vault>/.obsidian/plugins/<id>/.
  fetchAsset = url: hash: pkgs.fetchurl {inherit url hash;};
  mkPlugin = {
    pname,
    version,
    baseUrl,
    hashes,
  }:
    pkgs.linkFarm "${pname}-${version}" (
      map (file: {
        name = file;
        path = fetchAsset "${baseUrl}/${file}" hashes.${file};
      }) ["main.js" "manifest.json" "styles.css"]
    );

  obsidian-git = mkPlugin {
    pname = "obsidian-git";
    version = "2.38.6";
    baseUrl = "https://github.com/Vinzent03/obsidian-git/releases/download/2.38.6";
    hashes = {
      "main.js" = "sha256-Ma2J09lzy1UgZH1Sf1DYwj/NQhdnaDYXQaVDr1bVYoc=";
      "manifest.json" = "sha256-Zzke+oQJPVYBH0N2T/TxyEbditUrHx39AQq2KLIXwqM=";
      "styles.css" = "sha256-9auT9NW03RvR5XeGTFx5CH9639RIrDRuBInlhHzmki0=";
    };
  };

  copilot = mkPlugin {
    pname = "copilot";
    version = "3.3.3";
    baseUrl = "https://github.com/logancyang/obsidian-copilot/releases/download/3.3.3";
    hashes = {
      "main.js" = "sha256-QBihMZXmU8soIpM6VOlJrlHnphIHAKONzycl171C4e4=";
      "manifest.json" = "sha256-8htX39WmRMYd72NNFItaoT7Z3e+aaqwunB6o6hOcbEw=";
      "styles.css" = "sha256-c8Jzi9+vN7dVqO71m937SqV63Z4hwVvSuJZxk5OoxpI=";
    };
  };
in {
  programs.obsidian = {
    enable = true;

    vaults = {
      "security-research" = {
        enable = true;
        target = "Documents/vaults/security-research";
      };
    };

    defaultSettings = {
      # Serialized 1:1 into .obsidian/app.json — unmanaged keys keep Obsidian's
      # defaults, but GUI changes to managed keys do not persist (store symlink).
      app = {
        vimMode = true;
        defaultViewMode = "source"; # "source" = editing, "preview" = reading
        livePreview = true;
        showLineNumber = true;
        readableLineLength = true;
        foldHeading = true;
        foldIndent = true;
        spellcheck = true;
        spellcheckLanguages = ["en-US"];
        tabSize = 2;
        useTab = false;
        strictLineBreaks = false;
        alwaysUpdateLinks = true;
        promptDelete = false;
        trashOption = "system"; # "system" | "obsidian" | "none"
        newFileLocation = "folder"; # "folder" | "current" | "root"
        newFileFolderPath = "00-inbox";
        attachmentFolderPath = "assets";
        showUnsupportedFiles = true;
      };

      # Serialized into .obsidian/appearance.json. The module merges in
      # enabledCssSnippets and the active theme automatically.
      # Stylix's obsidian target already contributes interfaceFontFamily,
      # monospaceFontFamily, baseFontSize, and a "Stylix Config" CSS snippet
      # with the base16 palette — do not redeclare those keys here.
      appearance = {
        # Stylix polarity follows the light boot specialisation.
        theme =
          if config.stylix.polarity == "dark"
          then "obsidian" # built-in dark
          else "moonstone"; # built-in light
        # Orange accent to match the Hyprland borders; overrides Stylix's
        # purple --color-accent for interactive elements.
        accentColor = colors.base09;
        nativeMenus = false;
        translucency = false;
      };

      # Anything not listed here is explicitly disabled in core-plugins.json.
      corePlugins = [
        "file-explorer"
        "global-search"
        "switcher"
        "graph"
        "backlink"
        "outgoing-link"
        "tag-pane"
        "properties"
        "page-preview"
        "daily-notes"
        "templates"
        "note-composer"
        "outline"
        "word-count"
        "bookmarks"
        "canvas"
        "slash-command"
        "editor-status"
        "footnotes"
        "file-recovery"
        "command-palette"
      ];

      # Plugin settings (data.json) stay unmanaged on purpose: API keys and
      # per-machine state are entered once via the plugin GUI and must survive
      # rebuilds. Declaring `settings` here would freeze data.json read-only.
      communityPlugins = [
        obsidian-git
        copilot
      ];

      # No custom cssSnippets: Stylix's obsidian target injects a
      # "Stylix Config" snippet with the full base16 palette already.

      hotkeys = {
        "daily-notes" = [
          {
            modifiers = ["Mod" "Shift"];
            key = "D";
          }
        ];
        "graph:open" = [
          {
            modifiers = ["Mod" "Shift"];
            key = "G";
          }
        ];
      };
    };
  };
}
