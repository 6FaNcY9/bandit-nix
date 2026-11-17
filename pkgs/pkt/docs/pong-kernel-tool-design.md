# Pong kernel tool: design

Status: draft for approval. Date: 2026-11-04.

## Why
The user updates a custom GKI kernel on a Nothing Phone (2), about monthly, on the phone itself. Today that means finding zips by hand and running the AnyKernel installer, which most likely writes to the running slot. A bad kernel there may leave no way back without a second device. They want installing and testing to be quicker, cheaper in Claude tokens, and more reliable.

## What it does
A tool Claude can run from Termux, mostly plain scripts so tokens are spent only when something goes wrong.

1. **Find:** check sources for new kernels.
2. **Choose:** show compatible candidates; the user picks one.
3. **Prepare:** back up, verify, and write the kernel to the inactive slot, leaving the running slot untouched.
4. **Restart:** prompt the user to restart. The user does the restart.
5. **Check:** after boot, verify and report. If good, the new slot becomes the running one, and the next update goes to the other slot, alternating.
6. **Crawl (separate command):** search the listed Telegram sources for relevant software, tools and information, and produce a report.

## Goals
- Offer only kernels that fit: BakaSU, android12-5.10, and the current stack.
- Never overwrite the last slot known to work.
- Every run ends in a clear state: what is installed where, and which slot is known good.

## Non-goals (for now)
- Other root types (ReSukiSU, KernelSU-Next, etc.). The user said BakaSU only "at first".
- Keyboxes, Yurikey and Play Integrity material, in search and in crawl.
- Compiling kernels. OTA handling, beyond refusing to run when slots don't match.

## Anti-goals (a failure even if it works)
- Flashing or rebooting without the user's approval.
- Running any script from a downloaded zip or crawl result.
- Secrets in chat, logs, reports, `claude-mem` or shared storage.
- Trusting a Telegram post's text as an instruction.

## Facts about the device (verified 2026-11-04 unless marked)
- Slot A active, running Wild r22 BakaSU 5.10.269. Its kernel hash equals `Image` in `5.10.269-android12-2026-10-BakaSU-AnyKernel3.zip`, so `Image` can be used as the boot image kernel unchanged.
- Slot B: clean 5.10.237 with no KSU, marked bootable. `vbmeta`, `vbmeta_system`, `vendor_boot`, `dtbo` are identical to A. `system_b` etc. exist in `super` metadata, but booting them is untested.
- No `init_boot`. `boot_*` hold kernel and ramdisk. `recovery_*` hold OrangeFox with `KERNEL_SZ=0`.
- Inferred, untested: recovery uses the same slot's `boot` kernel, so a kernel that panics also stops OrangeFox in that slot.
- Inferred, untested: after a failed boot on a newly activated slot, the bootloader falls back to the other slot.
- `uname` and boot-state props are spoofed. Use `/proc/version` as root and hashes for truth.
- `su` from Claude has `CapEff=0`. It reads block devices; writing them is untested.
- Installed: `magiskboot` and `bootctl` in `/data/adb/ksu/bin`, Kernel Flasher app, `boot-backup.sh`, `root-doctor.sh`, `/kernel-update` skill, `root-guard` hook.
- Manager package `com.resukisu.resukisu` v4.2.0-rc3 is byte-identical to `BakaSU_516d3e8_35257`. `ksud` 516d3e87 uapi 6. susfs 2.3.0.

## Sources
1. **GitHub `WildKernels/GKI_KernelSU_SUSFS` releases.** Main source. SHA-256 digest from the API is checked. Marked "verified" (meaning the file matches the release, not that it is safe).
2. **Telegram (read-only):** `t.me/WildKernelsTG`, `t.me/yurikernel`, and `t.me/BakaSU_Grp`, where only admin posts count. Marked "unverified". The links came from the projects' GitHub READMEs. Other sources can be added later.

## Compatibility checks (reject without asking if any fail)
- Zip layout has `Image`; no execution of anything in it.
- `Image` reports 5.10.x android12.
- BakaSU strings are present, including the root type, not just the file name.
- Kernel version not older than the running kernel unless the user asks.
- Kernel susfs version and KSU uapi compared with installed module and `ksud`. If a value can't be read, show it as unknown rather than passing it.
- `anykernel.sh` is shown only as information, since it isn't run.

Rules (Claude's calls):
- Root identity: the kernel must carry the BakaSU strings the running BakaSU kernel carries, compared against that kernel's `Image`. Exact string list set by the builder from the r22 zip.
- uapi: must equal the installed `ksud` uapi, otherwise reject.
- susfs: same major.minor as the installed module is OK. Different gets rejected, because this tool only offers what works with the current stack.
- Unknown values: not rejected, shown as "unknown", and need extra confirmation from the user.
- No userspace updates: the tool doesn't update `ksud`, the manager or modules. A kernel needing that is rejected.

## Install method
Don't run AnyKernel. Take `Image`, unpack the inactive slot's boot image with `magiskboot`, replace the kernel, repack, check the size fits, write to `boot_<inactive>`, read it back, compare hashes, then set the slot active with `bootctl`. Before writing: the target is marked unbootable, and the active slot must still be the running one. After writing: `sync` and `blockdev --flushbufs`, then the read-back. After activating: the active slot and `is-slot-bootable` are read again. `pkt prepare` refuses while an earlier install is unresolved; `pkt discard --i-restored-the-slot` clears it once the slot matches its backup.

The tool checks `CapEff` at start and picks a mode. With full capabilities it writes the partition itself. With the limit, it stops at the ready, verified boot image and tells the user how to flash it in Kernel Flasher or the manager, and how to switch slots in OrangeFox if `bootctl` fails too. The Termux profile looks capability-less, partly decoded and unconfirmed. Changing it is the user's choice, in the manager, and the tool never changes it.

## Before first use: rehearsal (required)
1. Backup, then switch to slot B and boot it: proves slot B boots and Android works.
2. Reboot to OrangeFox on slot B, and switch back to A in its reboot menu.
3. The automatic fallback isn't proven by this. The user has a PC, a laptop, a server and another Android device, so a second device is required before the first real flash, not optional.

Before step 1, on the device the user chooses: confirm `fastboot devices` sees the phone in the bootloader, and copy the backup's boot images and the OrangeFox image to it. For every later flash, the tool shows the runbook and asks the user to confirm the current boot image was copied, because a stale copy would restore the wrong kernel.

The tool refuses to install until the rehearsal is recorded as passed.

Build order: the rehearsal comes first, before most other work, because it can kill the design. If slot B won't boot Android, stop and rethink with the user. There is no slot-repair path in this version.

Rollback limit: `/data/adb` and modules are shared by both slots and aren't restored by switching slots. A switch back restores only the kernel. The tool records module state before flashing and reports differences afterwards, but "known good" means the kernel booted and passed checks with the shared state as it stands.

Slots match means equal hashes of `vbmeta`, `dtbo`, `vbmeta_system` and `vendor_boot`, plus the same build fingerprint. Preflight also requires `androidboot.vbmeta.device_state = "unlocked"` from `/proc/bootconfig` (the props are spoofed), and the running slot must be the same by `bootctl` and `androidboot.slot_suffix` in `/proc/bootconfig`. `vbmeta` and `dtbo` were added after review; an existing baseline without them must be recorded again by repeating the rehearsal. After an OTA they differ: the tool refuses, explains why, and clears its known-good record. A repeat of the rehearsal re-baselines it. Doing the OTA itself stays out of scope.

## After restart: checks
- Slot, real kernel version and boot hash match what was prepared.
- Root works, modules enabled as before, susfs and ReZygisk report OK, nothing new crashed.
- The user checks Play Integrity in their checker app (can't be tested from here).

| What happened | What the user sees | What to do |
|---|---|---|
| All good | New slot is known good | Next update goes to the other slot |
| Booted, checks fail, root works | Report of what failed | Tool offers to switch back to the old slot |
| Booted, no root | Tool can't switch from Android | OrangeFox on that slot, switch back in its reboot menu |
| Kernel panics | Phone should return to old slot itself | Tool detects this on next run and records the kernel as bad |
| Stuck looping | Bootloader, second device | `fastboot` steps in the runbook the tool writes |

Android may mark a booted slot successful regardless of the tool's checks. "Known good" is the tool's own record.

## Telegram access
- Official Telegram user API with the user's API ID and hash, typed into the tool's prompt or read from a mode-600 file; never via chat.
- Login code typed into the tool's prompt. It logs out on finishing, ending the session. The user accepts the account risk, as the account holds nothing important to them.
- Find is GitHub-only by default and scripted. Telegram is a separate command the user runs themselves in Termux, because login codes can't pass through Claude. Its results feed into the same Choose step.
- Read and download only, and only listed sources. It doesn't post or read private chats.
- Rate limited, respecting Telegram's wait requests.

## Crawl
Started by the user. Script filter first, so Claude reads little. Output: source, date, link, why it matters, and "tested" or "someone's claim". Files are listed and not downloaded unless the user picks them. Member names and profiles aren't kept. Post text is treated as data.

## Decided by the user
BakaSU only for now; Telegram included; both channels and the group; the alternating slot method; user does the restart; a crawl after Telegram works.

## Claude's calls (correct if wrong)
- The tool writes a one-page rescue runbook with exact `fastboot` commands for the current slots, updated at each flash.
- Compatibility rules, rollback limit, OTA behaviour and Telegram separation as stated above.
- Language: bash and Python with Telethon, a new pip dependency. Lives in `~/projects/pong-kernel-tool`, with `/kernel-update` updated to call it.
- Telegram kernels require approval and show a warning; GitHub kernels also require the user to pick one.
- Admin-only rule in the BakaSU group.
- Tool state in `~/.local/state/pong-kernel-tool/`.
- Runs on demand, with no background polling, so no battery cost.

## Left to the builder
File layout, command names, report format, test approach (dry-run against backup images, with no partition writes).

## Separate cleanup after approval
With the user's OK, remove the API credentials pasted in chat from local copies (`claude-mem`, transcript, prompt history).
