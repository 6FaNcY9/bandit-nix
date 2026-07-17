{repoConfig, ...}: {
  programs.nixvim.keymaps = [
    {
      mode = "n";
      key = "<leader>nr";
      action.__raw = ''
        function()
          vim.cmd("botright 15split")
          vim.cmd("terminal")
          vim.api.nvim_chan_send(
            vim.b.terminal_job_id,
            "cd ${repoConfig.workstation.repoPath} && sudo nixos-rebuild test --flake .#bandit\n"
          )
        end
      '';
      options.desc = "Test NixOS config asynchronously";
    }
    {
      mode = "n";
      key = "<leader>ne";
      action.__raw = ''
        function()
          vim.notify("Evaluating bandit configuration…", vim.log.levels.INFO)
          vim.system(
            { "nix", "eval", ".#nixosConfigurations.bandit.config.system.build.toplevel" },
            { cwd = "${repoConfig.workstation.repoPath}", text = true },
            function(result)
              vim.schedule(function()
                if result.code == 0 then
                  vim.notify(vim.trim(result.stdout), vim.log.levels.INFO)
                else
                  vim.fn.setqflist({}, " ", {
                    title = "Nix evaluation",
                    lines = vim.split(result.stderr, "\n", { trimempty = true }),
                  })
                  vim.cmd("copen")
                  vim.notify("Nix evaluation failed", vim.log.levels.ERROR)
                end
              end)
            end
          )
        end
      '';
      options.desc = "Evaluate NixOS config asynchronously";
    }
  ];
}
