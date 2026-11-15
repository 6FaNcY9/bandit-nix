{
  writeShellApplication,
  curl,
  coreutils,
  gawk,
  gnugrep,
  lib,
  guest ? "jerry",
}:
writeShellApplication {
  name = "${guest}-watch";
  runtimeInputs = [curl coreutils gnugrep gawk];
  # One script for every guest box: the guest's name is swapped in.
  text = builtins.replaceStrings ["jerry" "Jerry"] [guest (lib.toSentenceCase guest)] (builtins.readFile ./watch.sh);
}
