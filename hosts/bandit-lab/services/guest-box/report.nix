{
  writeShellApplication,
  jq,
  curl,
  systemd,
  coreutils,
  gawk,
  unixtools,
  gnugrep,
  lib,
  guest ? "jerry",
}:
writeShellApplication {
  name = "${guest}-report";
  runtimeInputs = [jq curl systemd coreutils gawk gnugrep unixtools.xxd];
  # One script for every guest box: the guest's name is swapped in.
  text = builtins.replaceStrings ["jerry" "Jerry" "JERRY"] [guest (lib.toSentenceCase guest) (lib.toUpper guest)] (builtins.readFile ./report.sh);
}
