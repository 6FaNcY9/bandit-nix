# home/dap.nix
#
# DAP (Debug Adapter Protocol) configuration for nixvim.
# Adapters and launch configs are split here to keep editor.nix readable.
# Supports: Bash/Shell, Python, Rust, C, C++
#
# Existing keymaps (in editor.nix):
#   <leader>db  toggle breakpoint     <leader>dc  continue / start
#   <leader>di  step into             <leader>do  step over
#   <leader>dO  step out              <leader>dr  open REPL
#   <leader>du  toggle DAP UI         <leader>dt  terminate
#
# New keymaps added here:
#   <leader>dB  conditional breakpoint  <leader>dl  log point
#   <leader>dL  run last session        <leader>de  evaluate expression
#   <F5>        continue / start        <S-F5>      terminate
#   <F10>       step over               <F11>       step into
#   <F12>       step out

{pkgs, ...}: {
  programs.nixvim = {
    # ─── Adapter binaries ─────────────────────────────────────────────────
    # These are added to nixvim's runtime PATH so DAP can find them.
    extraPackages = with pkgs; [
      bash-debug-adapter          # sh / bash
      python3Packages.debugpy     # python
      lldb                        # lldb-dap → Rust / C / C++
    ];

    # ─── Adapter registration + launch configs ────────────────────────────
    # Done in Lua because nixvim's dap.adapters / dap.configurations module
    # options don't expose all fields needed (e.g. executable.args for servers,
    # function() expressions in program fields, table aliasing for c/cpp/rust).
    extraConfigLua = ''
      local dap    = require("dap")
      local dapui  = require("dapui")

      -- ── Adapters ────────────────────────────────────────────────────────

      -- Bash / Shell
      dap.adapters.sh = {
        type    = "executable",
        command = "${pkgs.bash-debug-adapter}/bin/bash-debug-adapter",
      }

      -- Python (debugpy)
      dap.adapters.python = {
        type    = "executable",
        command = "${pkgs.python3Packages.debugpy}/bin/python",
        args    = { "-m", "debugpy.adapter" },
      }

      -- LLDB — covers Rust, C, C++ (lldb-dap is the DAP frontend for LLDB)
      dap.adapters.lldb = {
        type    = "executable",
        command = "${pkgs.lldb}/bin/lldb-dap",
        name    = "lldb",
      }

      -- ── Configurations ─────────────────────────────────────────────────

      -- Shell / Bash
      dap.configurations.sh = {
        {
          type    = "sh",
          name    = "Bash: launch current file",
          request = "launch",
          program = function() return vim.fn.expand("%:p") end,
          cwd     = vim.fn.getcwd(),
        },
      }

      -- Python
      dap.configurations.python = {
        {
          type       = "python",
          name       = "Python: launch current file",
          request    = "launch",
          program    = function() return vim.fn.expand("%:p") end,
          pythonPath = "python3",
          justMyCode = false,
          console    = "integratedTerminal",
        },
        {
          -- Attach to a running debugpy server (e.g. `python -m debugpy --listen 5678 script.py`)
          type       = "python",
          name       = "Python: attach localhost:5678",
          request    = "attach",
          connect    = { host = "127.0.0.1", port = 5678 },
          justMyCode = false,
        },
      }

      -- Rust / C / C++ share the same LLDB config; pick binary interactively
      local lldb_launch = {
        {
          type       = "lldb",
          name       = "Launch binary (prompt)",
          request    = "launch",
          program    = function()
            return vim.fn.input("Binary path: ", vim.fn.getcwd() .. "/", "file")
          end,
          cwd        = function() return vim.fn.getcwd() end,
          stopOnEntry = false,
          args       = {},
        },
      }
      dap.configurations.rust = lldb_launch
      dap.configurations.c    = lldb_launch
      dap.configurations.cpp  = lldb_launch

      -- ── Auto open / close DAP UI ────────────────────────────────────────
      -- Opens the UI automatically when a session starts, closes on exit.
      dap.listeners.before.attach.dapui_config            = function() dapui.open() end
      dap.listeners.before.launch.dapui_config            = function() dapui.open() end
      dap.listeners.before.event_terminated.dapui_config  = function() dapui.close() end
      dap.listeners.before.event_exited.dapui_config      = function() dapui.close() end
    '';

    # ─── Additional keymaps ───────────────────────────────────────────────
    # Basic bindings (db/dc/di/do/dO/dr/du/dt) are already in editor.nix.
    keymaps = [
      # Conditional breakpoint
      {
        mode = "n";
        key = "<leader>dB";
        action.__raw = ''function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end'';
        options.desc = "Conditional breakpoint";
      }
      # Log point (prints message without stopping)
      {
        mode = "n";
        key = "<leader>dl";
        action.__raw = ''function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log message: ")) end'';
        options.desc = "Log point";
      }
      # Re-run the last debug session
      {
        mode = "n";
        key = "<leader>dL";
        action.__raw = ''function() require("dap").run_last() end'';
        options.desc = "Run last session";
      }
      # Evaluate expression under cursor / selection
      {
        mode = ["n" "v"];
        key = "<leader>de";
        action.__raw = ''function() require("dapui").eval() end'';
        options.desc = "Evaluate expression";
      }

      # F-key bindings — muscle-memory compatible with VS Code / IntelliJ
      {
        mode = "n";
        key = "<F5>";
        action.__raw = ''function() require("dap").continue() end'';
        options.desc = "DAP: continue / start";
      }
      {
        mode = "n";
        key = "<S-F5>";
        action.__raw = ''function() require("dap").terminate() end'';
        options.desc = "DAP: terminate";
      }
      {
        mode = "n";
        key = "<F10>";
        action.__raw = ''function() require("dap").step_over() end'';
        options.desc = "DAP: step over";
      }
      {
        mode = "n";
        key = "<F11>";
        action.__raw = ''function() require("dap").step_into() end'';
        options.desc = "DAP: step into";
      }
      {
        mode = "n";
        key = "<F12>";
        action.__raw = ''function() require("dap").step_out() end'';
        options.desc = "DAP: step out";
      }
    ];
  };
}
