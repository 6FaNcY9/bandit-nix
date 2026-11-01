{
  writeShellApplication,
  jq,
  curl,
  systemd,
  coreutils,
  gawk,
  unixtools,
  gnugrep,
}:
writeShellApplication {
  name = "jerry-report";
  runtimeInputs = [jq curl systemd coreutils gawk gnugrep unixtools.xxd];
  text = builtins.readFile ./report.sh;
}
