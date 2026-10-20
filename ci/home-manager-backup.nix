# Exercises the Home Manager backupCommand (flake.nix hmBackupCommand, which
# hmBase also uses, so it stays in flake.nix and is passed in here).
{
  pkgs,
  hmBackupCommand,
}:
pkgs.runCommand "home-manager-backup-check" {} ''
  mkdir work
  printf first > work/config
  ${hmBackupCommand} work/config
  printf second > work/config
  ${hmBackupCommand} work/config
  test "$(cat work/config.hm-backup)" = second
  test "$(cat work/config.hm-backup.~1~)" = first

  mkdir work/source-dir work/source-dir.hm-backup
  printf source > work/source-dir/file
  printf prior > work/source-dir.hm-backup/file
  ${hmBackupCommand} work/source-dir
  test "$(cat work/source-dir.hm-backup/file)" = source
  test "$(cat work/source-dir.hm-backup.~1~/file)" = prior
  touch "$out"
''
