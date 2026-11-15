# Mrija protection — owner checklist (Part 1)

These are the steps only the owner can do (panel clicks). Claude prepares the exact text for each. Do them in this order; none of them need the lab job to exist yet.

| # | Step | Where | Claude prepares | Done |
|---|------|-------|-----------------|------|
| 1 | New password + 2FA; remove unknown FTP users, SSH keys, cron jobs, mail forwarders | ISPmanager + TheHost client account | a click-by-click list; Claude can read-only list the current keys/cron over rsync first | ☐ |
| 2 | Turn on 2FA | Cloudflare, Ledl.net (registrar) | — | ☐ |
| 3 | Delete `.htaccess.bak2` (open item from the March report) | TheHost file manager | the exact path once found | ☐ |
| 4 | Cloudflare Access in front of `/wp-login.php` and `/wp-admin*`, bypass `/wp-admin/admin-ajax.php` | Cloudflare Access | the policy text | ☐ |
| 5 | Rotate all 20 mailbox passwords, start postmaster@, admin@, olena.stepura@ | ISPmanager mail | the mailbox list + short German team message | ☐ |
| 6 | Turn on DKIM, publish the TXT record; after 2–4 clean weeks set DMARC `p=quarantine`, then `p=reject` + SPF `-all` | ISPmanager + Cloudflare DNS | the TXT records; no other service sends as @mrija.org (owner, 2026-11-15) | ☐ |
| 7 | Fix web-root permissions: `~/www/mrija.org` is 0777, set 0755 | ISPmanager file manager | confirm with TheHost it won't break the panel | ☐ |
| 8 | Subscribe to the ntfy topic `mrija` on the phone | ntfy app | the topic URL once the lab job ships | ☐ |
| 9 | After TheHost's written go-ahead: controlled, read-only escalation test of the restricted shell | — | Claude runs it, one command at a time, stops on the first warning | ☐ |
| 10 | TheHost ticket: sending limit, postmaster@ login logs (Jan + 2–10 May 2026), inbound DMARC | TheHost support | the ticket draft | ☐ |
| 11 | Decide on the DSB (data-protection authority) report and the IC3 report | — | compliance-writer drafts both | ☐ |

Everything here only raises the attacker's cost; the lab job (Part 2) is the detection layer and is planned separately in `../plans/2026-11-15-mrija-watch.md`.
