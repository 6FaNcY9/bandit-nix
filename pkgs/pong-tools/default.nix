# The phone's root helper scripts, unchanged except for the shebang (they were
# written for Termux bash). Both only read partitions; they run su themselves.
{
  runCommandLocal,
  runtimeShell,
}:
runCommandLocal "pong-tools" {} ''
  mkdir -p $out/bin
  for s in boot-backup root-doctor; do
    { echo "#!${runtimeShell}"; tail -n +2 ${./.}/$s.sh; } > $out/bin/$s
    chmod 755 $out/bin/$s
  done
''
