# Alerts leave the lab: a host-side poller forwards firing Grafana alerts to ntfy
# (the pod cannot reach the host's loopback ntfy, and the token must not enter
# the pod), and a template unit reports failed critical units.
{
  config,
  lib,
  pkgs,
  ...
}: let
  ntfyEnv = {
    EnvironmentFile = "/var/lib/mcbots/ntfy/publisher.env";
    Environment = ["NTFY_URL=http://127.0.0.1:2586" "NTFY_TOPIC=mcbots"];
  };
  ntfy = {
    after = ["ntfy-seed.service"];
    wants = ["ntfy-seed.service"];
  };
  passwordFile = config.sops.secrets."grafana-admin-password".path;

  # Notify on newly firing and on resolved alerts. State: "fingerprint<TAB>name" per firing alert.
  grafanaNotify = pkgs.writeShellApplication {
    name = "grafana-ntfy";
    runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils pkgs.gnugrep];
    text = ''
      state=$STATE_DIRECTORY/firing
      down=$STATE_DIRECTORY/grafana-down
      touch "$state"
      send() { # title priority body
        curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: $1" -H "Priority: $2" \
          -d "$3" "$NTFY_URL/$NTFY_TOPIC" >/dev/null
      }
      auth() { printf 'user = "admin:%s"\n' "$(cat ${passwordFile})"; }
      if ! alerts=$(curl -fsS -K <(auth) \
        "http://127.0.0.1:3000/api/alertmanager/grafana/api/v2/alerts?active=true&silenced=false&inhibited=false"); then
        # the pod starts after this timer's first run at boot: only page once the lab has been up 10 minutes
        [ -e "$down" ] || [ "$(cut -d. -f1 /proc/uptime)" -lt 600 ] || { send "Grafana unreachable" high "Alert polling failed; the monitoring pod may be down." && touch "$down"; }
        exit 0
      fi
      rm -f "$down"
      # a 200 with a body that is not an alert list must not turn every firing alert into "Resolved"
      jq -e 'type == "array"' <<<"$alerts" >/dev/null || exit 0

      next=$(mktemp -p "$STATE_DIRECTORY")
      trap 'rm -f "$next"' EXIT
      jq -r '.[] | [.fingerprint, .labels.alertname, (.labels.severity // "warning"), (.annotations.summary // "")] | @tsv' <<<"$alerts" |
        while IFS=$'\t' read -r fp name sev summary; do
          if grep -q "^$fp"$'\t' "$state"; then
            printf '%s\t%s\n' "$fp" "$name" >>"$next"
          else
            prio=default; [ "$sev" = critical ] && prio=high
            send "Lab alert: $name" "$prio" "$summary" && printf '%s\t%s\n' "$fp" "$name" >>"$next"
          fi
        done || true # a failed send is retried next run; the resolved notices below still go out
      while IFS=$'\t' read -r fp name; do
        [ -n "$fp" ] || continue
        grep -q "^$fp"$'\t' "$next" && continue
        send "Resolved: $name" default "$name is no longer firing" || printf '%s\t%s\n' "$fp" "$name" >>"$next"
      done <"$state"
      mv "$next" "$state"
    '';
  };

  failureNotify = pkgs.writeShellScript "notify-failure" ''
    # a restart loop fails the unit every few seconds: one push per unit per 10 minutes
    stamp=/run/notify-failure-$1
    [ -n "$(${pkgs.findutils}/bin/find "$stamp" -mmin -10 2>/dev/null)" ] && exit 0
    ${pkgs.curl}/bin/curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: Unit failed: $1" -H "Priority: high" \
      -d "$(${pkgs.systemd}/bin/systemctl status --no-pager -n 5 "$1" 2>&1 | head -c 1500)" "$NTFY_URL/$NTFY_TOPIC" &&
      touch "$stamp"
  '';
  criticalUnits =
    ["minecraft-server-paper" "minecraft-server-velocity" "restic-backups-peer" "minecraft-backup" "postgresqlBackup"]
    ++ lib.optional config.bandit-lab.mcbots.enable "docker-mcbots";
in {
  systemd.services =
    {
      grafana-ntfy =
        ntfy
        // {
          description = "Forward firing Grafana alerts to ntfy";
          serviceConfig =
            ntfyEnv
            // {
              Type = "oneshot";
              StateDirectory = "grafana-ntfy";
              ExecStart = "${grafanaNotify}/bin/grafana-ntfy";
            };
        };
      "notify-failure@" =
        ntfy
        // {
          description = "ntfy: %I failed";
          serviceConfig = ntfyEnv // {ExecStart = "${failureNotify} %I";};
        };
    }
    // lib.genAttrs criticalUnits (_: {unitConfig.OnFailure = "notify-failure@%n.service";});

  systemd.timers.grafana-ntfy = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
    };
  };

  # The monitoring pod (proxy network) probes Velocity on the host gateway.
  networking.firewall.extraCommands = "iptables -A nixos-fw -s 10.89.0.0/24 -d 10.89.0.1 -p tcp --dport 25565 -j nixos-fw-accept";
  networking.firewall.extraStopCommands = "iptables -D nixos-fw -s 10.89.0.0/24 -d 10.89.0.1 -p tcp --dport 25565 -j nixos-fw-accept || true";
}
