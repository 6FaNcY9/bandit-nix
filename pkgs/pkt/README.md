# pkt (pong-kernel-tool)

Termux tool that installs custom kernels on a rooted Nothing Phone (2) into the inactive A/B slot.
It never reboots. Tests: `python -m unittest` (stdlib only, no su, no network).

## Commands
- `pkt status`, `pkt find`, `pkt check <n|path>`: read only.
- `pkt rehearse-start`, `rehearse-check`, `rehearse-finish`: the slot test that must pass once before any install.
- `pkt prepare <n|path>`: backup and build; writes no partition.
- `pkt install --confirmed-copy=<code>`: writes the inactive slot, verifies it, sets it active. The user restarts.
- `pkt post-check`, `pkt switch-back`, `pkt mark-bad`, `pkt forgive <prefix>`, `pkt discard --i-restored-the-slot`: after a restart or a failed install.
- `pkt crawl-web [--limit N] [--days N] [--source NAME]`: public Telegram groups, no login. `pkt crawl` needs a Telegram login in a terminal.

`pkt crawl` reads Telegram credentials from `~/.config/pkt/telegram.json` (mode 600, `{"api_id": N, "api_hash": "..."}`); without the file it asks for them. A kernel older than the running one is rejected, and there is no override.

Rescue sheet: `/storage/emulated/0/Download/pkt-rescue.md`. The known-good slot and the running slot are never written.

Not built: Telegram as a kernel source (login code never arrived), and an OTA flow, so the tool refuses after an OTA until slots match.
