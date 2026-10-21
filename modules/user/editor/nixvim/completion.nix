_: {
  programs.nixvim.plugins = {
    # Completion — dropdown menu
    cmp = {
      enable = true;
      autoEnableSources = true;
      settings = {
        sources = [
          {name = "copilot";}
          {name = "nvim_lsp";}
          {name = "luasnip";}
          {name = "path";}
          {name = "buffer";}
        ];
        mapping = {
          "<C-Space>" = "cmp.mapping.complete()";
          "<C-d>" = "cmp.mapping.scroll_docs(-4)";
          "<C-f>" = "cmp.mapping.scroll_docs(4)";
          "<CR>" = "cmp.mapping.confirm({ select = true })";
          "<Tab>" = ''
            cmp.mapping(function(fallback)
              if cmp.visible() then cmp.select_next_item()
              else fallback() end
            end, { "i", "s" })
          '';
          "<S-Tab>" = ''
            cmp.mapping(function(fallback)
              if cmp.visible() then cmp.select_prev_item()
              else fallback() end
            end, { "i", "s" })
          '';
        };
        window = {
          completion.border = "rounded";
          documentation.border = "rounded";
        };
      };
    };
    copilot-cmp.enable = true;

    # Snippets
    luasnip.enable = true;
    friendly-snippets.enable = true;
  };
}
