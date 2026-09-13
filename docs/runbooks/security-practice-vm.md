# BloodHound, crAPI and Atomic Red Team practice VM

These tools live in a separate, opt-in NixOS QEMU VM. They do not run in
the production bandit-lab service set. The VM has 4 CPUs, 12 GiB RAM and a
40 GiB persistent disk. KVM access is recommended.

## Prepare and start

From the repository, build both launchers:

```sh
nix build path:.#security-lab -o result-security-lab
nix build path:.#security-lab-online -o result-security-lab-online
mkdir -p "$HOME/.local/share/security-practice/tmp"
cd "$HOME/.local/share/security-practice"
export TMPDIR="$PWD/tmp"
/path/to/bandit-nix/result-security-lab-online/bin/run-security-lab-vm
```

Keep the disk in a dedicated directory and always launch both variants from
that directory. Set `TMPDIR` as above each time so disk creation and the copied
Nix store use disk space rather than the host's RAM-backed `/tmp`. The VM disk
survives host reboots. Never run both variants simultaneously.
The forwarded host ports must be free; stop conflicting local services or use
a temporary launcher copy with different host ports before starting the VM.
The console logs in as root. In this **online preparation VM**, download images:

```sh
lab-compose bloodhound pull
lab-compose crapi pull
poweroff
```

Then launch `result-security-lab/bin/run-security-lab-vm` from the same disk
directory. This default variant restricts guest network access to the explicit
forwarded ports. Inside the VM:

```sh
lab-compose bloodhound up -d --wait
lab-compose crapi up -d --wait
lab-compose bloodhound logs bloodhound
```

Read BloodHound's generated initial admin password in its logs. On the host:

| Tool | URL |
|---|---|
| BloodHound CE | http://127.0.0.1:8080 |
| crAPI | http://127.0.0.1:8888 |
| crAPI exercise mailbox | http://127.0.0.1:8025 |

No containers or Atomic tests start automatically. Stop stacks with
`lab-compose bloodhound down` and `lab-compose crapi down`; add `--volumes`
only when intentionally discarding that stack's data. Run `sync`, then power off
after use. With the current pinned NixOS VM, shutdown was observed hanging
after `Failed unmounting /nix/store`. If this happens after stopping both stacks
and syncing, press Ctrl+A, then C to open the QEMU monitor, and enter `quit`.
This forcibly exits the VM; normal shutdown remains an unresolved limitation.
For a remote host, tunnel the localhost ports over SSH instead of exposing them.

## Atomic Red Team

Run `atomic-console` inside the restricted VM. It imports the pinned runner
and copies test definitions into `/var/lib/security-lab/atomics`. For example:

```powershell
Invoke-AtomicTest T1059.004 -ShowDetailsBrief
Invoke-AtomicTest T1059.004 -CheckPrereqs
```

Review and select an individual test before invoking it. Prerequisite downloads
need online access; do not run attack tests in the online preparation variant.
NixOS differs from conventional Linux distributions: some tests require paths,
packages or services that are absent. Windows tests need a separate Windows
guest. Wazuh enrollment and detection validation are not configured here.

## Isolation and pins

Only host loopback ports are forwarded. The VM uses a copied Nix store image;
no host directories, Docker socket or secrets are shared. The online variant
has normal outbound access, including reachable LAN services, and exists only
for preparation. The restricted variant is the practice environment.

The Compose files vendor upstream BloodHound 9.7.0 and crAPI 1.1.6-rc8,
with every image pinned by digest. crAPI's stable 1.1.6 image set was incomplete
in the registry when checked; the complete rc8 set is used instead. Its seeded
database credentials and vulnerable services are disposable exercise data.
Local runtime fixes give MongoDB 512 MiB to avoid disk thrashing during health
checks and explicitly use Bash for the gateway's TCP health probe.
The chatbot needs an external model API key and is not configured for use.
BloodHound needs an authorized AD dataset; the VM does not provision a domain.
Atomic source, runner and powershell-yaml archives are revision/hash pinned
in `labs/security/default.nix`. Review upstream changes before updating pins.
