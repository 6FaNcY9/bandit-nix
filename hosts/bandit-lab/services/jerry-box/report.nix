{
  writeShellApplication,
  jq,
  curl,
  systemd,
  coreutils,
  gawk,
  gnugrep,
}:
writeShellApplication {
  name = "jerry-report";
  runtimeInputs = [jq curl systemd coreutils gawk gnugrep];
  text = builtins.readFile ./report.sh;
}
