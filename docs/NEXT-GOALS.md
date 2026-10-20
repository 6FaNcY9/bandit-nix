# Next goals (2026-10-10)

Evidence is from `origin/main` at `74f15c4` unless a branch is named. Lines marked
**guess** are not established by the repo.

## 1. Where each area stands

| Area | State (evidence) | Unfinished / risky |
| --- | --- | --- |
| Laptop `bandit` | GRUB+EFI, no LUKS block in `hosts/bandit/hardware.nix`; `trusted-users = ["root"]`, MCP servers sandboxed, libvirt needs admin auth (SECURITY-PLAN). Peer backup to the lab (`nixos/backup-peer.nix`). Recent laptop work is small (Prism Launcher). | No disk encryption, boot chain undecided: **parked by the owner (2026-10-10), the laptop stays at home.** Prep work waits on branch `luks-prepare`. Pick it up again when the laptop starts travelling. |
| Lab services | 14 service modules imported in `hosts/bandit-lab/default.nix`; Portainer and Wazuh removed from config; signed fast-forward-only auto-deploy (`lab-update`, `ci/test-lab-update.py`); 10 flake checks incl. `lab-surface`, `local-privilege`, `sops-isolation`. | Backblaze job exists but `bandit-lab.backups.enable` is off (secrets missing). **No restore has ever been tested** (SECURITY-PLAN, `backup-restore.md`). No container sets `no-new-privileges` or a read-only root (`container-hardening.md`). |
| Security hardening | Phases 1-2, 5, D3-D7 done; attack surface cut to tailnet; sops split into per-host files. | LUKS and boot chain parked (see laptop). Legacy `secrets/secrets.yaml` + its `TEMPORARY` rule in `.sops.yaml` still present (`sops-split.md` step 4 not done). GitHub branch protection is a manual step; whether it is set is **unknown**. |

## 2. Next goals, ranked

| # | Goal | Why | Done when | Size | Depends on |
| --- | --- | --- | --- | --- | --- |
| 1 | Restore drill from the peer backup | A backup never restored is a hope. Covers Vaultwarden and DBs (Minecraft world: see bandit-craft). | One lab snapshot and one laptop snapshot restored into scratch dirs, result dated in `backup-restore.md`. | S | - |
| 2 | ~~Reconcile stale docs~~ **done 2026-10-10** | Agents act on docs; several gave the wrong state. | Section 4. | S | - |
| 3 | Finish sops split cleanup | Legacy file still readable by the laptop host key; `TEMPORARY` rule lingers. | `secrets/secrets.yaml` and its rule gone, `github.yaml` rotated, `sops-isolation` check updated. | S | both hosts verified on split files |
| 7 | Off-site copy (B2) | The laptop stays home, so both peer copies sit in one house: one fire, flood or theft takes everything. | 4 secrets added (`tools/add-backup-secrets.sh`), `backups.enable = true`, first snapshot listed, alert fires on a failed run. | S | #1 |
| 8 | Container hardening, first candidates | No container has `no-new-privileges`; one privileged (cAdvisor). | Flag added one container at a time with a health check each; `lab-surface` (or a new check) asserts it. | M | - |
| 9 | Confirm GitHub branch protection on `main` | A push to `main` deploys the lab within the hour; protection against force-push/deletion is a manual setting nobody has confirmed. | Ruleset active, the rejection test in `bandit-lab-updates.md` run, date noted there. | S | owner (GitHub UI) |

## 3. Minecraft and bots

Minecraft, the bots (mcbots), the LLM agents and their roadmap moved to [bandit-craft](https://github.com/6FaNcY9/bandit-craft) on 2026-10-12; track those goals there.

## 4. Contradictions and stale content

Fixed 2026-10-10 (docs only): panel/BlueMap shown as deployed (VoxelDash since retired) in `PANEL.md`,
`MIGRATION.md` (now historical), `ADMIN.md`, `services.md`, `backup-restore.md`; PGP removal marked
done and laptop encryption parked in `SECURITY-PLAN.md`; retired containers marked in
`container-hardening.md`; markers and safe digging marked done in `CONTROL-CENTRE-GOAL.md` and
`AUTOPILOT-REPORT.md`; `BOTS.md` intro, jobs table (`shift`, `guard`, `craft`, `smelt`) and Limits
match the code.

Still open:

- Local checkout `~/src/bandit-nix` is behind `origin/main` and has an uncommitted `flake.lock`.
  Side branches with unshipped work: `luks-prepare` (parked), `claude/autopilot` (`mcbots-soak`),
  `adr-community-alternatives`, `docs-redaction`.
