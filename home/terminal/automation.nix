{pkgs, ...}: let
  ollamaUrl = "http://192.168.1.2:11434";
  ollamaModel = "bandit-coder";
  firecrawlKeyFile = "/run/secrets/firecrawl-api-key";

  fcScript = pkgs.writeShellScriptBin "fc" ''
    # Usage: fc <url> [output-file]
    # Scrapes URL via Firecrawl and saves markdown
    set -e
    URL="$1"
    OUT="''${2:-/tmp/fc-content.md}"
    [[ -z "$URL" ]] && { echo "Usage: fc <url> [output-file]" >&2; exit 1; }
    API_KEY=$(cat ${firecrawlKeyFile})
    ${pkgs.curl}/bin/curl -sf --max-time 30 \
      -X POST https://api.firecrawl.dev/v1/scrape \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"url\":\"$URL\",\"formats\":[\"markdown\"]}" \
    | ${pkgs.jq}/bin/jq -r '.data.markdown' > "$OUT"
    echo "Saved to $OUT" >&2
    echo "$OUT"
  '';

  llmWebScript = pkgs.writeShellScriptBin "llm-web" ''
    # Usage: llm-web <url> "<prompt about the page>"
    set -e
    URL="$1"
    PROMPT="$2"
    [[ -z "$URL" || -z "$PROMPT" ]] && {
      echo "Usage: llm-web <url> \"<prompt>\"" >&2; exit 1
    }
    TMP=$(${fcScript}/bin/fc "$URL" 2>/dev/null)
    CONTENT=$(cat "$TMP" | head -c 6000)
    ${pkgs.jq}/bin/jq -n --arg p "$PROMPT\n\nPage content:\n$CONTENT" \
      '{"model":"${ollamaModel}","prompt":$p,"stream":false}' \
    | ${pkgs.curl}/bin/curl -sf --max-time 120 \
        ${ollamaUrl}/api/generate -d @- \
    | ${pkgs.jq}/bin/jq -r .response
  '';

  llmQuery = pkgs.writeShellScriptBin "llm" ''
    # Usage: llm "your prompt"
    ${pkgs.jq}/bin/jq -n --arg p "$1" \
      '{"model":"${ollamaModel}","prompt":$p,"stream":false}' \
    | ${pkgs.curl}/bin/curl -sf --max-time 120 \
        ${ollamaUrl}/api/generate -d @- \
    | ${pkgs.jq}/bin/jq -r .response
  '';

  genPanelScript = pkgs.writeShellScriptBin "gen-panel-script" ''
    # Usage: gen-panel-script <name> "<description>"
    set -e
    NAME="$1"
    DESC="$2"
    if [[ -z "$NAME" || -z "$DESC" ]]; then
      echo "Usage: gen-panel-script <name> <description>" >&2
      exit 1
    fi
    OUT="$HOME/.local/bin/panel-$NAME"
    PROMPT="Write a bash script for XFCE genmon panel. Task: $DESC.
    Rules: output only <txt>PANGO_MARKUP</txt>, bracket color #504945 (dim),
    use nerd font icons, no deps beyond standard unix tools.
    Shebang #!/usr/bin/env bash. Output the script only, no explanation."
    echo "Generating panel-$NAME via ${"$"}{${ollamaModel}}..." >&2
    ${llmQuery}/bin/llm "$PROMPT" > "$OUT"
    chmod +x "$OUT"
    echo "Written: $OUT" >&2
  '';

  preCommitHook = pkgs.writeShellScript "llm-pre-commit" ''
    DIFF=$(git diff --cached --stat)
    [[ -z "$DIFF" ]] && exit 0
    FULL=$(git diff --cached | head -c 4000)
    PROMPT="Review this git diff for bugs, security issues, or obvious mistakes.
    Be brief. Only flag real problems, not style. If nothing serious, say OK.
    Diff:\n$FULL"
    echo "── LLM review ──────────────────────────────────" >&2
    ${pkgs.jq}/bin/jq -n --arg p "$PROMPT" \
      '{"model":"${ollamaModel}","prompt":$p,"stream":false}' \
    | ${pkgs.curl}/bin/curl -sf --max-time 30 \
        ${ollamaUrl}/api/generate -d @- 2>/dev/null \
    | ${pkgs.jq}/bin/jq -r .response 2>/dev/null \
    || echo "(LLM unavailable — skipping review)" >&2
    echo "────────────────────────────────────────────────" >&2
    exit 0  # never block the commit
  '';
in {
  # ── llm: one-shot prompt to bandit-coder ────────────────────
  # ── gen-panel-script: generate XFCE genmon scripts via LLM ──
  home.packages = [llmQuery genPanelScript fcScript llmWebScript];

  # ── Pre-commit LLM review (warns, never blocks) ─────────────
  home.file.".config/git/hooks/pre-commit" = {
    executable = true;
    source = preCommitHook;
  };

  programs.git.extraConfig.core.hooksPath = "~/.config/git/hooks";

  # ── Nightly TODO scan ────────────────────────────────────────
  systemd.user.services.llm-todo-scan = {
    Unit.Description = "LLM-assisted TODO scan of bandit-nix";
    Service = {
      Type = "oneshot";
      ExecStart = let
        script = pkgs.writeShellScript "llm-todo-scan" ''
          REPO="$HOME/src/bandit-nix"
          LOGDIR="$HOME/.local/share/llm-todo-scan"
          mkdir -p "$LOGDIR"
          LOG="$LOGDIR/$(date +%Y-%m-%d).log"
          TODOS=$(grep -rn "TODO\|FIXME\|HACK\|XXX" "$REPO" \
            --include="*.nix" --include="*.sh" \
            --exclude-dir=".git" 2>/dev/null | head -50)
          [[ -z "$TODOS" ]] && echo "No TODOs found." > "$LOG" && exit 0
          PROMPT="Prioritize these code TODOs from a NixOS flake repo.
          Group by severity (critical/medium/low). Be concise.
          TODOs:\n$TODOS"
          ${pkgs.jq}/bin/jq -n --arg p "$PROMPT" \
            '{"model":"${ollamaModel}","prompt":$p,"stream":false}' \
          | ${pkgs.curl}/bin/curl -sf --max-time 120 \
              ${ollamaUrl}/api/generate -d @- \
          | ${pkgs.jq}/bin/jq -r .response > "$LOG" 2>/dev/null \
          || echo "LLM unavailable" > "$LOG"
        '';
      in "${script}";
    };
  };

  systemd.user.timers.llm-todo-scan = {
    Unit.Description = "Nightly LLM TODO scan";
    Timer = {
      OnCalendar = "03:00";
      Persistent = true;
    };
    Install.WantedBy = ["default.target"];
  };
}
