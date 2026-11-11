# Laptop side of the phone link (system side: modules/desktop/phone-link.nix).
{
  pkgs,
  bandit,
  ...
}: let
  phone = "${bandit.workstation.phoneTailscaleIp}:5555";
  hyprctl = "/run/current-system/sw/bin/hyprctl";

  # `handy`: the phone's screen as a window, over the tailnet.
  handy = pkgs.writeShellScriptBin "handy" ''
    ${pkgs.android-tools}/bin/adb connect ${phone} >/dev/null
    exec ${pkgs.scrcpy}/bin/scrcpy -s ${phone} --stay-awake --window-title Handy "$@"
  '';

  # Half the phone's landscape resolution, so the phone shows it at 2x.
  createOutput = pkgs.writeShellScript "phone-screen-create" ''
    ${hyprctl} output create headless PHONE
    ${hyprctl} eval 'hl.monitor({output="PHONE", mode="1206x540@60", position="auto", scale=1})'
  '';
in {
  home.packages = [handy];

  # Started on demand from the phone (`pc-screen`): a phone-sized virtual
  # monitor, served on localhost only and reached through the SSH tunnel.
  systemd.user.services.phone-screen = {
    Unit.Description = "Phone-sized virtual screen for the phone link";
    Service = {
      ExecStartPre = "${createOutput}";
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o PHONE 127.0.0.1 5900";
      ExecStopPost = "${hyprctl} output remove PHONE";
    };
  };
}
