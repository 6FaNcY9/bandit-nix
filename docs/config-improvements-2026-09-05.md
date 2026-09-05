# Configuration review — 2026-09-05

## Applied changes

- **Keybinding browser:** use SUPER+F2. On the inspected Austrian keyboard,
  SUPER+SHIFT+7 matched the workspace-move binding rather than SUPER+slash.
  The menu was imported and installed; rebuilding did not resolve that conflict.
- **Lab updater:** compare the built candidate with both the running system and
  boot profile. Matching Git revisions alone did not prove activation and caused
  a fresh clone to skip deployment. Restore both prior states on activation
  failure; retain signature verification before building.
- **Docker discovery:** place an HAProxy Unix-socket allowlist between Traefik
  and Docker. Permit discovery GET/HEAD endpoints and deny mutation and unrelated
  reads. Traefik no longer belongs to the Docker group. The proxy still has Docker
  privileges, and container inspection still exposes container environment data.
- **Ghost:** use native OCI `networks` for network attachment at creation and
  `pull = "never"` for the existing manually loaded private image workflow.
  A missing local image still requires the documented image transfer.
- **Health checks:** test PostgreSQL readiness and local Traefik routes to
  Portainer and Vaultwarden, with retries, before accepting a deployment.
- **Lab defaults:** enable daily local PostgreSQL dumps and require DNS-over-TLS.
  These dumps do not protect against loss of the server or cover other databases.
- **Desktop defaults:** replace the deprecated LibreOffice package alias;
  disable automatic inbound Steam Remote Play and LAN-transfer firewall openings.
  Those Steam features require an explicit firewall opt-in if wanted.

## Further improvements, in priority order

| Candidate | Benefit | Required evidence or decision |
| --- | --- | --- |
| Encrypted off-host backups, using a tool such as Restic | Recover from server/disk loss; cover PostgreSQL, MySQL, Vaultwarden, Portainer and Ghost content | Choose destination, credentials and retention; coordinate consistent database snapshots and prove restoration. Local PostgreSQL dumps are only a first step. |
| Immutable Ghost release artifacts | Make deploys and rollbacks identify the exact application image | Obtain the actual image digest and automate authenticated transfer or loading. Do not invent a digest or assume the mutable `main` tag is reproducible. |
| Separate management and public application networks | Reduce exposure of Portainer to applications sharing the `proxy` bridge | Preserve Traefik routing and the dedicated `portainer-control` network; verify access policy and connectivity before migration. |
| Complete laptop disk-encryption plan | Protect data when the laptop is powered off | Follow `docs/runbooks/bandit-luks-reinstall.md`; requires verified backups and a separately authorized reinstall. |
| Review PostgreSQL memory settings | Avoid excessive per-query memory under concurrency | Measure workload and memory pressure before changing `work_mem = 64MB`, `max_connections = 100`, `shared_buffers = 4GB` and the planner's `effective_cache_size = 48GB`. |
| Remove hardcoded SSH agent socket UID | Make the user configuration portable and avoid a stale socket path | `home/default.nix` sets `/run/user/1000/gcr/ssh`; verify which agent owns the live session before moving to module-managed session setup. |

No evidence from this review justifies replacing Hyprland, Traefik, or the browser
wholesale. The strongest opportunities are deployment correctness, backups and
service isolation, while using native module options where available.

## Verification and deployment boundary

- Full `rtk nix flake check path:. --no-update-lock-file` passed.
- Both host system build dry-runs passed; full closures were not built.
- The generated lab health-check package built successfully, including ShellCheck.
- Six updater regression scenarios passed: fresh clone, already active,
  signature rejection, health failure, profile failure and switch failure.
- Twelve Docker proxy allow/deny cases passed against actual HAProxy with a
  fixture backend. This is not a live Docker/Traefik integration test.
- New test files are untracked, so validation used `path:.` to include them.
  Include them in any eventual commit; ordinary Git-backed flake evaluation
  omits untracked files.
- No host activation, reboot, commit or push was performed. After deployment,
  verify SUPER+F2 on the laptop, lab DNS connectivity, Docker discovery and
  application readiness, and the PostgreSQL backup timer/output.

## Reference checks

- [Pinned Traefik Docker provider source](https://raw.githubusercontent.com/traefik/traefik/v3.7.10/pkg/provider/docker/pdocker.go): discovery API requirements.
- [Docker container run reference](https://docs.docker.com/reference/cli/docker/container/run/): multiple networks and pull policy.
- [HAProxy configuration reference](https://docs.haproxy.org/3.2/configuration.html): HTTP ACL and Unix-socket configuration; the actual packaged HAProxy was also tested.
