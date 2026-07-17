{config, ...}: let
  colors = config.lib.stylix.colors.withHashtag;
in {
  programs.nixvim.extraConfigLua = ''
    local function apply_bandit_highlights()
      local highlights = {
        Comment = { fg = "${colors.base03}", italic = true },
        Function = { fg = "${colors.base0D}" },
        Keyword = { fg = "${colors.base0E}", bold = true },
        String = { fg = "${colors.base0A}" },
        Type = { fg = "${colors.base0C}" },
        ["@comment"] = { fg = "${colors.base03}", italic = true },
        ["@function"] = { fg = "${colors.base0D}" },
        ["@function.call"] = { fg = "${colors.base0D}" },
        ["@keyword"] = { fg = "${colors.base0E}", bold = true },
        ["@string"] = { fg = "${colors.base0A}" },
        ["@string.escape"] = { fg = "${colors.base09}" },
        ["@type"] = { fg = "${colors.base0C}" },
        ["@variable"] = { fg = "${colors.base05}" },
      }

      for group, spec in pairs(highlights) do
        vim.api.nvim_set_hl(0, group, spec)
      end
    end

    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = apply_bandit_highlights,
      desc = "Keep Bandit Retro syntax colors after theme changes",
    })
    apply_bandit_highlights()

    vim.api.nvim_create_user_command("BanditInspectHighlight", function()
      vim.notify(vim.inspect(vim.treesitter.get_captures_at_cursor(0)))
    end, { desc = "Show Treesitter captures under the cursor" })
  '';
}
