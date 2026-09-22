{
  lib,
  inputs,
  pkgs,
  ...
}: let
  pdfreader-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "pdfreader.nvim";
    version = "0.1.7";
    src = inputs.pdfreader-nvim;

    # pdfreader.nvim imports snacks.image at module-load time.  The plugin's
    # isolated package check intentionally has no external plugin runtimepath;
    # Nixvim supplies snacks-nvim below.
    nvimSkipModules = [
      "pdfreader"
      "pdfreader.book"
      "pdfreader.bookmarks"
      "pdfreader.commands"
      "pdfreader.image"
      "pdfreader.pages.base"
      "pdfreader.pages.image"
      "pdfreader.pages.page"
      "pdfreader.pages.text"
      "pdfreader.state"
    ];
  };
in {
  programs.nixvim = {
    extraPlugins = [
      pkgs.vimPlugins.snacks-nvim
      pdfreader-nvim
    ];

    extraPackages = with pkgs; [
      ghostscript
      imagemagick
      poppler-utils
    ];

    extraConfigLua = ''
      require("snacks").setup({
        image = { enabled = true },
      })

      require("pdfreader").setup()
    '';

    # mkAfter keeps these behind the main nixvim keymaps (nixvim/keymaps.nix),
    # preserving the registration order from before the nixvim.nix split.
    keymaps = lib.mkAfter [
      {
        mode = "n";
        key = "<leader>fp";
        action = "<cmd>PDFReader showRecentBooks<CR>";
        options.desc = "Show recent PDFs";
      }
    ];
  };
}
