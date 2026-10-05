"""Exercise the generated updater with real Git and isolated activation endpoints."""

import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

GIT_ENV = {
    **os.environ,
    "GIT_AUTHOR_NAME": "Test",
    "GIT_AUTHOR_EMAIL": "test@example.invalid",
    "GIT_COMMITTER_NAME": "Test",
    "GIT_COMMITTER_EMAIL": "test@example.invalid",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
}


def git(*args, repo=None):
    cmd = ["git"] + (["-C", str(repo)] if repo else []) + list(args)
    return subprocess.run(
        cmd, env=GIT_ENV, check=True, capture_output=True, text=True
    ).stdout.strip()


def executable(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!{shutil.which('bash')}\nset -eu\n" + body)
    path.chmod(0o755)


def scenario(source, failure="", already_active=False, history="fresh",
             args=("apply",), expect="ok", env=None):
    """history: how the deployed checkout relates to the remote tip.
    fresh      no checkout yet (the updater clones)
    ff         remote is one commit ahead of the checkout
    downgrade  remote was force-moved back to an older commit
    diverged   remote history was rewritten (force-push)
    tagshadow  a tag named origin/main points at an off-main commit
    expect: ok | refused | usage | check-warns | manual-only
    """
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        remote = root / "remote"
        git("init", "-q", "-b", "main", str(remote))
        git("commit", "-q", "--allow-empty", "-m", "fixture", repo=remote)
        checkout = root / "checkout"
        if history == "ff":
            git("clone", "-q", str(remote), str(checkout))
            git("commit", "-q", "--allow-empty", "-m", "next", repo=remote)
        elif history in ("downgrade", "diverged"):
            git("commit", "-q", "--allow-empty", "-m", "next", repo=remote)
            git("clone", "-q", str(remote), str(checkout))
            git("reset", "-q", "--hard", "HEAD~1", repo=remote)
            if history == "diverged":
                git("commit", "-q", "--allow-empty", "-m", "rewritten", repo=remote)
        elif history == "tagshadow":
            # A signed commit on a side branch, tagged with the ambiguous name
            # `origin/main`, present in the mirror because it was cloned after
            # the tag was pushed. `main` then advances normally.
            git("checkout", "-q", "-b", "wip", repo=remote)
            git("commit", "-q", "--allow-empty", "-m", "wip", repo=remote)
            git("tag", "origin/main", repo=remote)
            git("checkout", "-q", "main", repo=remote)
            git("clone", "-q", str(remote), str(checkout))
            git("commit", "-q", "--allow-empty", "-m", "next", repo=remote)
        deployed = git("rev-parse", "HEAD", repo=checkout) if checkout.exists() else None
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
  if [[ "$arg" == verify-commit ]]; then echo "verify:${{@: -1}}" >> "$FIXTURE/actions"; [[ "$FAILURE" != signature ]]; exit; fi
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
            "/etc/nixos/bandit-nix": str(checkout),
            "https://github.com/6FaNcY9/bandit-nix.git": str(remote),
            "/run/lab-update.lock": str(root / "lock"),
            "/run/current-system": str(current),
            "/nix/var/nix/profiles/system": str(profile),
        }.items():
            # Fail loudly when the updater script stops containing a path we
            # redirect, instead of silently testing against real system paths.
            assert original in script, f"updater no longer references {original}"
            script = script.replace(original, replacement)
        for command in ("git", "gpg", "nix-env", "nix"):
            script, count = re.subn(r"/nix/store/[^/\s]+/bin/" + command + r"(?=[\s\"])",
                                    str(commands / command), script)
            assert count >= 1, f"updater no longer invokes {command} via a store path"
        updater = root / "updater"
        updater.write_text(script)
        result = subprocess.run(
            ["bash", str(updater), *args], text=True, capture_output=True,
            stdin=subprocess.DEVNULL,
            env={**{k: v for k, v in os.environ.items() if k != "INVOCATION_ID"},
                 "FIXTURE": str(root), "FAILURE": failure,
                 "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
                 **(env or {})},
        )
        actions = (root / "actions").read_text() if (root / "actions").exists() else ""
        output = result.stdout + result.stderr
        detail = output + actions
        label = " ".join(args)
        if expect == "usage":
            assert result.returncode == 2 and "Usage:" in output, detail
            assert actions == "", detail
        elif expect == "manual-only":
            assert result.returncode == 2 and "manual-only" in output, detail
            assert actions == "", detail
        elif expect == "check-warns":
            assert result.returncode == 0, detail
            assert "Non-fast-forward (" in output and "will refuse" in output, detail
            assert actions == "", detail
        elif expect == "refused":
            assert result.returncode != 0 and f"Refusing {history} update" in output, detail
            # Refused before any signature check, build or activation, and the
            # mirror is untouched.
            assert "verify:" not in actions and "build" not in actions, detail
            assert "switch" not in actions, detail
            assert current.resolve() == old and profile.resolve() == old, detail
            assert git("rev-parse", "HEAD", repo=checkout) == deployed, detail
        elif failure:
            assert result.returncode != 0, detail
            assert current.resolve() == old and profile.resolve() == old, detail
            # A failed or rolled-back run must leave the mirror at the deployed commit.
            if deployed:
                assert git("rev-parse", "HEAD", repo=checkout) == deployed, detail
            if failure == "signature":
                assert "build" not in actions, detail
        else:
            assert result.returncode == 0, detail
            assert "build" in actions, "Equal Git HEAD skipped deployment verification:\n" + detail
            assert current.resolve() == candidate and profile.resolve() == candidate, detail
            # The mirror always ends at the remote main tip (fast-forward or
            # reset), and exactly that commit was signature-checked.
            tip = git("rev-parse", "main", repo=remote)
            assert git("rev-parse", "HEAD", repo=checkout) == tip, detail
            assert f"verify:{tip}" in actions, detail
            if already_active:
                assert "candidate:test" not in actions, detail
        name = failure or ("already active" if already_active else history)
        print(f"PASS: {name} [{label}] -> {expect if failure == '' else 'rolled back'}")


source = Path(sys.argv[1]).read_text()
scenario(source)
scenario(source, already_active=True)
for failure in ("signature", "health", "profile", "switch"):
    scenario(source, failure)

# Fast-forward only: a normal update moves the mirror forward ...
scenario(source, history="ff")
# ... but a signed older commit and a force-pushed rewrite are refused ...
scenario(source, history="downgrade", expect="refused")
scenario(source, history="diverged", expect="refused")
# ... the manual override still works for a reviewed rewrite ...
scenario(source, history="downgrade", args=("apply", "--allow-non-ff"))
scenario(source, history="diverged", args=("apply", "--allow-non-ff"))
# ... and `check` reports it without acting. Bad arguments are rejected.
scenario(source, history="downgrade", args=("check",), expect="check-warns")
scenario(source, args=("check", "--allow-non-ff"), expect="usage")
scenario(source, args=("apply", "--nope"), expect="usage")
# The override is refused inside a systemd unit (INVOCATION_ID), even through
# a wrapper script that the flake lint cannot read.
scenario(source, history="diverged", args=("apply", "--allow-non-ff"),
         env={"INVOCATION_ID": "x"}, expect="manual-only")
# A failed run leaves the mirror at the deployed commit (not only on fresh clones).
scenario(source, failure="health", history="ff")
scenario(source, failure="switch", history="ff")
# A tag named origin/main must not steer the deployment away from main.
scenario(source, history="tagshadow")
