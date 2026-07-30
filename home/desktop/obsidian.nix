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
      appearance = {
        # Stylix polarity follows the light boot specialisation.
        theme =
          if config.stylix.polarity == "dark"
          then "obsidian" # built-in dark
          else "moonstone"; # built-in light
        accentColor = colors.base09; # gruvbox orange
        baseFontSize = 16;
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

      # Gruvbox from the Stylix base16 palette, same approach as the Firefox
      # userChrome module. Registered as an enabled snippet automatically.
      cssSnippets = [
        {
          name = "stylix-gruvbox";
          text = ''
            /* Generated from the Stylix base16 palette — do not edit in Obsidian. */
            .theme-dark, .theme-light {
              --background-primary: ${colors.base00};
              --background-primary-alt: ${colors.base01};
              --background-secondary: ${colors.base01};
              --background-secondary-alt: ${colors.base00};
              --background-modifier-border: ${colors.base02};
              --background-modifier-hover: ${colors.base02};
              --text-normal: ${colors.base05};
              --text-muted: ${colors.base04};
              --text-faint: ${colors.base03};
              --text-accent: ${colors.base09};
              --text-accent-hover: ${colors.base0A};
              --text-error: ${colors.base08};
              --text-success: ${colors.base0B};
              --interactive-accent: ${colors.base09};
              --interactive-accent-hover: ${colors.base0A};
              --link-color: ${colors.base0C};
              --link-color-hover: ${colors.base0D};
              --code-background: ${colors.base01};
              --graph-line: ${colors.base02};
              --graph-node: ${colors.base09};
            }
          '';
        }
      ];

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
