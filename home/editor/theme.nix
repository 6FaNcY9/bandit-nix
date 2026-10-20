{config, ...}: let
  r = config.bandit.theme.roles;
in {
  # Re-applied after every :colorscheme; maps syntax groups to palette roles
  # (keywords bright and bold, strings amber; magenta stays reserved for ops context).
  programs.nixvim.extraConfigLua = ''
    local function apply_bandit_highlights()
      local highlights = {
        Comment = { fg = "${r.muted}", italic = true },
        Function = { fg = "${r.info}" },
        Keyword = { fg = "${r.bright}", bold = true },
        String = { fg = "${r.warn}" },
        Type = { fg = "${r.info}" },
        ["@comment"] = { fg = "${r.muted}", italic = true },
        ["@function"] = { fg = "${r.info}" },
        ["@function.call"] = { fg = "${r.info}" },
        ["@keyword"] = { fg = "${r.bright}", bold = true },
        ["@string"] = { fg = "${r.warn}" },
        ["@string.escape"] = { fg = "${r.warn}" },
        ["@type"] = { fg = "${r.info}" },
        ["@variable"] = { fg = "${r.fg}" },
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
