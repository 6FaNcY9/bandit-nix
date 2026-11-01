{
  writeShellApplication,
  curl,
  coreutils,
  gawk,
  gnugrep,
}:
writeShellApplication {
  name = "jerry-watch";
  runtimeInputs = [curl coreutils gnugrep gawk];
  text = builtins.readFile ./watch.sh;
}
