"""Exercise the generated updater with real Git and isolated activation endpoints."""

import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


def executable(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!{shutil.which('bash')}\nset -eu\n" + body)
    path.chmod(0o755)


def scenario(source, failure="", already_active=False):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        remote = root / "remote"
        subprocess.run(["git", "init", "-q", "-b", "main", str(remote)], check=True)
        subprocess.run(
            ["git", "-C", str(remote), "-c", "user.name=Test", "-c",
             "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
             "commit", "-qm", "fixture", "--allow-empty"], check=True,
        )
        old, candidate = root / "old", root / "candidate"
        current, profile = root / "current", root / "profile"
        for system in (old, candidate):
            executable(system / "bin/switch-to-configuration", f'''
echo "{system.name}:$1" >> "$FIXTURE/actions"
ln -sfn {shlex.quote(str(system))} "$FIXTURE/current"
if [[ "$FAILURE" == switch && "{system.name}:$1" == candidate:switch ]]; then exit 1; fi
''')
            executable(system / "sw/bin/bandit-lab-health", '''
[[ "$FAILURE" != health ]]
''')
        current.symlink_to(candidate if already_active else old)
        profile.symlink_to(candidate if already_active else old)
        commands = root / "commands"
        executable(commands / "git", f'''
for arg in "$@"; do
  if [[ "$arg" == verify-commit ]]; then [[ "$FAILURE" != signature ]]; exit; fi
done
exec {shlex.quote(shutil.which('git'))} "$@"
''')
        executable(commands / "gpg", "cat >/dev/null || true\n")
        executable(commands / "nix", '''
echo build >> "$FIXTURE/actions"
echo "$FIXTURE/candidate"
''')
        executable(commands / "nix-env", '''
if [[ "$FAILURE" == profile && "$4" == "$FIXTURE/candidate" ]]; then exit 1; fi
ln -sfn "$4" "$2"
''')
        script = source
        for original, replacement in {
            "/etc/nixos/bandit-nix": str(root / "checkout"),
            "https://github.com/6FaNcY9/bandit-nix.git": str(remote),
            "/run/lab-update.lock": str(root / "lock"),
            "/run/current-system": str(current),
            "/nix/var/nix/profiles/system": str(profile),
        }.items():
            script = script.replace(original, replacement)
        for command in ("git", "gpg", "nix-env", "nix"):
            script = re.sub(r"/nix/store/[^/\s]+/bin/" + command + r"(?=[\s\"])",
                            str(commands / command), script)
        updater = root / "updater"
        updater.write_text(script)
        result = subprocess.run(
            ["bash", str(updater), "apply"], text=True, capture_output=True,
            env={**os.environ, "FIXTURE": str(root), "FAILURE": failure,
                 "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"},
        )
        actions = (root / "actions").read_text() if (root / "actions").exists() else ""
        detail = result.stdout + result.stderr + actions
        if failure:
            assert result.returncode != 0, detail
            assert current.resolve() == old and profile.resolve() == old, detail
            if failure == "signature":
                assert "build" not in actions, detail
        else:
            assert result.returncode == 0, detail
            assert "build" in actions, "Equal Git HEAD skipped deployment verification:\n" + detail
            assert current.resolve() == candidate and profile.resolve() == candidate, detail
            if already_active:
                assert "candidate:test" not in actions, detail
        print(f"PASS: {failure or ('already active' if already_active else 'fresh clone')}")


source = Path(sys.argv[1]).read_text()
scenario(source)
scenario(source, already_active=True)
for failure in ("signature", "health", "profile", "switch"):
    scenario(source, failure)
