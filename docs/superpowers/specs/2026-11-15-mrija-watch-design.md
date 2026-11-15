# mrija-watch: protection and daily watch for mrija.org

Status: draft for owner approval (2026-11-15). Design decisions by the architect agent; see "Approaches".

## Why

mrija.org belongs to a Vienna NGO that supports Ukraine. The owner is its volunteer admin, and two incidents were found:

1. **Website infection, about 2025-10 to 2026-03-18.** Webshells, an mu-plugin C2 and more than 23,000 files. It was cleaned on 2026-03-18. Report: `~/Documents/Inbox/Downloads-Documents/mrija-incident-report-DE.pdf`, section 8 lists the open items.
2. **postmaster@ takeover, 2026-01-18..24.** The attacker sent spam through SMTP AUTH with the real password. That password is now changed.

Neither incident was noticed in time. The owner has dyslexia and ADHD and wants **one place to look**: a short daily phone message, plus an instant push only for real danger.

## Goals

- Raise the cost of attack with provider-side protection (2FA, Cloudflare Access, DKIM/DMARC, rotated passwords).
- Detect the two incident types that actually happened, within 24 h: a mailbox used to send spam, and web files planted on the server.
- Detect changes to the domain's DNS (NS/MX hijack, SPF/DMARC/DKIM tampering).
- Send one German daily digest at 07:00 to the owner's phone. Push instantly only for the rules listed under "Instant push".

## Non-goals (v1)

- Phishing-content classification of incoming mail. It is too noisy; deferred.
- Cloudflare API (WAF events, DMARC aggregate stats). Deferred until DMARC is enforced.
- Hidden WordPress admin users. That needs DB access; deferred.
- Any automatic change on TheHost, Cloudflare or WordPress. The job only reads.
- Attribution claims ("Russian attack"). Alerts report facts only.

## Anti-goals (failure even if it works)

- **Alert fatigue.** If the owner gets daily false pushes, they stop reading, and the job has failed.
- **Leaking content.** Notification text, the journal and stored state must never contain mail subjects, bodies, attachment names or third-party addresses. Some incident subjects contain a plaintext password.
- **Widening trust.** The job must not give the lab more power over the hosting account than it already has.
- **Breaking in-flight lab work.** Do not touch `services/monitoring/notify.nix` or `alerting.nix`; four open branches change them.

## Constraints

- TheHost shared hosting, panel ISPmanager, one account `mrija_org` that holds both the web root and all 20 Maildirs. There is no root, so no agent can be installed on the host.
- **Restricted SSH shell (confirmed 2026-11-15).** The account's SSH shell is a restricted shell. It allows only a fixed command list (`rsync`, `curl`, `find`, `grep`, `ls`, `php`, `wget`, `scp`, `git` is absent, …) and rejects shell metacharacters (`;`, `|`, `>`); a compound or `find -printf` command is refused with "forbidden command, This incident has been reported". So a forced-command `find` manifest is not possible. `rsync` is allowed, and the daily mail sync already uses it. The web manifest therefore comes from `rsync --list-only`.
- The web root is `~/www/mrija.org`. Siblings `atmosphaere.at`, `levinale.at`, `mail.mrija.org` are other sites in the same account. `~/www/mrija.org` is currently mode 0777 (world-writable) — a finding for Part 1.
- I/O limits on TheHost: limit notices were seen in 2026-05, -07 and -09. Do not hash the whole web root daily.
- The lab already rsyncs all Maildirs daily at 03:00 (`hosts/bandit-lab/services/mrija-archive/`), using a full-shell SSH key to the hosting account.
- ntfy on the lab: today the topic is `mcbots`, with the token in `/var/lib/mcbots/ntfy/publisher.env`. Scripts send with curl (see `jerry-box/report.sh`). According to the builder check, a new topic is one access line in the ntfy settings.
- The bandit-nix module layout: hosts build from `modules/` and `hosts/`. `nixos/` and `home/` are dead legacy.
- A full `nix flake check` is OOM-killed on the laptop, so run only the targeted check.

## Approaches

| | Approach | Trade-off |
|---|---|---|
| A | Provider tools only: Cloudflare Access/WAF, Wordfence alerts, 2FA everywhere | Little to build, but the warnings arrive scattered over several mailboxes and nothing joins them. Wordfence runs inside the hacked site, so it can be switched off by the attacker. |
| B | Everything on the lab: mail, web, DNS, Cloudflare API, a Grafana dashboard | One place for everything, but the most to build. It depends on the home lab, and a dashboard is something the owner must remember to open. |
| **C (chosen by owner)** | A as the protection layer, plus a small lab job `mrija-watch` that sends one daily digest and rare instant pushes | Strong protection plus a single phone inbox. The detection is outside the hacked host, and the build is small. |

## Design

### Part 1: protection (owner clicks; Claude prepares exact steps and texts)

Do these in order:

1. ISPmanager and the TheHost client account:
   - Set a new password and turn on 2FA.
   - List FTP users, SSH keys, cron jobs and mail forwarders; remove anything unknown.
2. Turn on 2FA at Cloudflare and at the registrar Ledl.net.
3. Delete `.htaccess.bak2` (an open item from the March report).
4. Put Cloudflare Access in front of `/wp-login.php` and `/wp-admin*`, with a bypass for `/wp-admin/admin-ajax.php`.
5. Rotate all 20 mailbox passwords, starting with postmaster@, admin@ and the mailboxes that read phishing. Claude writes the short team message.
6. Turn on DKIM in ISPmanager and publish the TXT record in Cloudflare. After 2–4 clean weeks of DMARC reports, set `p=quarantine`, then `p=reject` and SPF `-all`.
7. Fix the web-root permissions: `~/www/mrija.org` is currently 0777. It should be 0755 (owner-writable only). Confirm with TheHost that this does not break the panel.
8. Subscribe to the ntfy topic `mrija` on the phone.
9. With TheHost's written go-ahead (they said they will message when a test is approved), let Claude probe whether any allowed restricted-shell command (`php`, `curl`, `wget`, `scp`, `rsync`, `find`, `perl`, `python`) can escape the shell or read another account. Read-only, one command at a time, stop on the first "incident" warning. Not before their approval.
9. Send a ticket to TheHost about the sending limit, the Jan 2026 and May 2026 login logs for postmaster@, and DMARC checking on inbound mail. Claude drafts it.
10. Decide on the data-protection authority (DSB) report and the IC3 report. compliance-writer drafts them.

### Part 2: the lab job `mrija-watch`

- **Where:** bandit-nix, `hosts/bandit-lab/services/mrija-watch/` with `default.nix`, `mrija_watch.py` (Python stdlib only, plus `maxminddb` for GeoIP) and `test.nix`. One import line in `hosts/bandit-lab/default.nix`, and one check in `flake.nix` following the `jerry-box/report-test.nix` pattern.
- **When:** a timer at 04:00 (after the 03:00 Maildir sync) collects data and sends any instant pushes. A timer at 07:00 sends the digest. Both are systemd oneshots.
- **Runs as:** `vino` (the Maildir is 0700 vino), with the same sandbox as `mrija-archive-sync`. State lives in `/var/lib/mrija-watch`, mode 0700.
- **SSH key:** reuse `~/.ssh/thehost_mrija` (the archive sync key), by `LoadCredential`, as the sync service already does. No new key and no sops change.
- **Notification topic (Claude's call):** a new ntfy topic `mrija`, added as one `auth-access` line in `services/ntfy/default.nix` (`mrija:mcbots:wo` writer, `phone:mrija:ro` reader — reuse the existing two users, no re-seed). The owner subscribes to it once on the phone. This keeps NGO mailbox names out of `mcbots`.
- **Reachability and certificate (Claude's call):** checked inside `mrija_watch.py` (HTTP status plus days until certificate expiry) and shown only in the digest. Not added to `blackbox-wan`, because its existing critical rule would push to `mcbots` at any hour and outside the instant list.

**v1 checks**

1. **Mail.** Read the Maildirs, only the files that are new since the last run.
   - Counts of non-delivery reports (NDRs) per mailbox per 24 h.
   - NDRs whose included original was sent with an authenticated login from an IP outside AT.
     - Verified on the Jan 2026 incident: the NDRs land in the envelope sender's own mailbox (postmaster@) and include the original headers.
     - The line looks like `Received: from [IP] (helo=…) by s16.thehost.com.ua with esmtpsa (TLS…)`. All 44 sampled lines say `esmtpsa`. Match `with esmtps?a` and take the IP from the brackets.
     - The country comes from `dbip-country-lite`. If that is missing in nixpkgs, this rule runs without a country.
   - The password-test subject pattern `mrija.org:(25|465|587) …@mrija.org`. Match it, but never store or print the subject.
   - Counts of risky attachments (iso/img/vhd/js/vbs/hta/lnk/scr/exe, encrypted ZIP), and how many of them carry the Seen flag.
   - A count of `From: …@mrija.org` mails that failed SPF. Source: the `Authentication-Results:` header (in 2,304 archive files), with `Received-SPF:` (205 files) as a fallback.
2. **Web.** Over the existing rsync channel (restricted shell allows `rsync`, not `find -printf`):
   - `rsync --list-only -r -e 'ssh -i ~/.ssh/thehost_mrija' mrija_org@s16.thehost.com.ua:www/mrija.org/` returns `perms, size, mtime, path` for every file. A second `--list-only` of `.ssh/` covers `authorized_keys`. No file contents are transferred.
   - The manifest is `perms\tsize\tmtime\tpath`. The cleaned snapshot had about 35,500 files, so it is a few MB.
   - The job diffs the manifest against the last one: added paths, removed paths, and changed (size or mtime) paths. There are no file copies and no hashing; copying the PHP source for a true content diff is deferred to v2.
   - The WordPress version is read from the manifest's `wp-includes/version.php` mtime plus size change (a core update changes it); exact `$wp_version` is a v2 item (it needs file content).
   - Changes under `wp-content/plugins/<p>/`, `themes/<t>/`, `wp-includes/` and `wp-admin/` go into the digest, grouped by directory (for example "Plugin elementor: 812 Dateien geändert"). They never push, so normal updates stay quiet.
3. **DNS.** `dig @1.1.1.1` for NS, MX, SPF, DMARC and the DKIM selector, diffed against the day before.

**Instant push** (ntfy priority high, title "Mrija: …") only for:

- the password-test subject pattern
- 20 or more NDRs in 24 h in one mailbox, or 3 or more `esmtpa` NDRs from outside AT
- web, any of these:
  - any file in `mu-plugins`
  - a PHP-like file in `uploads`
  - a change to `.htaccess`, `.user.ini` or `wp-config.php`
  - a changed PHP file (size or mtime) directly in the web root or in `wp-includes`/`wp-admin` while `wp-includes/version.php` did not change (so a core update is excluded)
  - IOC names (`wp-inmri.php`, `*vgh/`, `.htaccess.bak*`)
  - any new top-level directory in the web root (the `*vgh/` mirror pattern)
  - a change to `~/.ssh/authorized_keys`
- a change to NS or MX

**Daily digest** (07:00, priority default). It is always sent, so it doubles as a heartbeat. It has at most 6 short German lines:

- the counts
- plugin and core updates, grouped
- TXT record changes
- the age of the last Maildir sync
- any SSH or check errors.

Soft errors go into the digest. Only a crash triggers `OnFailure`, which is set in this module and not in `notify.nix`.

**Allowed in text, journal and state:** mailbox name, numbers, country code, rule name, web path. Nothing else.

### Trust model

- **Reuse the existing archive key** (`~/.ssh/thehost_mrija` on the lab). It already has rsync access to the whole account, and the server-side restricted shell — not a forced command — is what limits it; `rsync --list-only` of the web root and `.ssh/` adds no capability the archive sync does not already have. This removes an owner step and the open question of whether TheHost honours `authorized_keys` options. A separate revocable watch key is a possible later hardening, noted under Risks.
- The output from TheHost is parsed strictly, because a webshell could change it.

## Risks

- A webshell runs as the same user as the mail. It could read all mailboxes and fake the manifest. The real fix is to separate web and mail (another host or account). This is noted, but out of scope.
- The first manifest trusts the current state. Claude reviews it by hand once: IOC names, PHP in `uploads`, `mu-plugins`. That also closes the March items "wp-inmri.php" and "search for injected shells".
- Mail detection relies on bounces, so it can be up to 24 h late. Someone quietly reading mail over IMAP stays invisible; that needs TheHost login logs.
- mtime, not ctime: the manifest shows mtime, which a webshell (running as this same account, with `touch`/PHP in reach) can backdate. So a planted file still shows as a new path (full detection), but an in-place edit of an existing file with a restored mtime would be missed. Closing this needs a real content diff (v2: rsync the PHP source) or server-side integrity the shared host does not offer.
- A separate revocable watch key was dropped: the restricted shell already blocks shell escape, so the extra key bought little against one owner step and an untested `authorized_keys` behaviour. If web and mail are ever split, revisit.

## Open questions for the owner

1. **Answered 2026-11-15:** yes, instant pushes may wake the owner at 04:00. They are sent right after the 04:00 run with priority high.
2. **Answered 2026-11-15:** no other service is believed to send as @mrija.org. Before enforcing DMARC, confirm this with the Cloudflare DMARC reports.
3. Not blocking: TheHost said they will approve a controlled escalation test of the restricted shell. Owner forwards the go-ahead; see Part 1 step 9.
4. Not blocking: is it okay with Mrija (DSGVO) that the NGO mail archive lives on your private lab? It already does today.

## Claude's calls after the builder check (check these while reading)

- The web manifest uses `rsync --list-only` over the existing archive key, because the restricted shell rejects a `find` forced command. No new key, no new owner `authorized_keys` step.
- A new ntfy topic `mrija`, reusing the existing ntfy users (no re-seed).
- Reachability and the certificate are checked in the digest only, not in blackbox.
- The manifest also covers `~/.ssh`. Plugin, theme and core changes never push.
- The ">500 new files" rule is replaced by "new top-level directory", which catches the `*vgh/` pattern without firing on updates.

## Left to the builder

- Exact parsing code, state file format, and test fixtures (synthetic Maildir and manifest, never real mail).
- German wording of the digest lines, kept to simple words and at most 6 lines.
- `dbip-country-lite` (`dbip-country-lite-2026-10`, mmdb at `share/dbip/dbip-country-lite.mmdb`) and `python3Packages.maxminddb` (3.1.1) are both in nixpkgs. Confirmed 2026-11-15.

## Checks

- `nix build .#checks.x86_64-linux.mrija-watch-test` (curl stub, synthetic Maildir, synthetic manifest).
- `alejandra`.
- After deploy (owner): the first manifest is reviewed by hand, and one test push arrives.
