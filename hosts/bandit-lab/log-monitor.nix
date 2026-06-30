{pkgs, ...}: let
  logMonitorScript = pkgs.writeShellScript "llm-log-monitor" ''
    set -e
    LOGDIR="/var/log/llm-anomaly"
    mkdir -p "$LOGDIR"
    LOG="$LOGDIR/$(date +%Y-%m-%d).log"

    # Collect last 24h of errors/warnings from key services
    JOURNAL=$(${pkgs.systemd}/bin/journalctl \
      --since "24 hours ago" \
      --priority=warning \
      --no-pager \
      --output=short \
      -u traefik -u docker -u ollama -u smbd -u postgresql -u cloudflared \
      2>/dev/null | tail -200)

    [[ -z "$JOURNAL" ]] && echo "$(date): no anomalies" >> "$LOG" && exit 0

    PROMPT="You are a Linux sysadmin. Analyze these server logs from the last 24h.
    Identify real problems (ignore routine warnings). Group by service.
    Be concise. Format: SERVICE: issue — recommendation.
    Logs:
    $JOURNAL"

    echo "=== $(date) ===" >> "$LOG"
    ${pkgs.jq}/bin/jq -n --arg p "$PROMPT" \
      '{"model":"qwen3-coder:30b","prompt":$p,"stream":false}' \
    | ${pkgs.curl}/bin/curl -sf --max-time 120 \
        http://127.0.0.1:11434/api/generate -d @- \
    | ${pkgs.jq}/bin/jq -r .response >> "$LOG" 2>/dev/null \
    || echo "LLM unavailable" >> "$LOG"
  '';
in {
  systemd.services.llm-log-monitor = {
    description = "LLM-powered log anomaly detector";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${logMonitorScript}";
      User = "root";
    };
  };

  systemd.timers.llm-log-monitor = {
    description = "Nightly LLM log scan";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "02:30";
      Persistent = true;
    };
  };
}
