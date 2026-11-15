{
  writeShellApplication,
  jq,
  curl,
  coreutils,
}:
writeShellApplication {
  name = "werbung-watch";
  runtimeInputs = [jq curl coreutils];
  text = builtins.readFile ./watch.sh;
}
