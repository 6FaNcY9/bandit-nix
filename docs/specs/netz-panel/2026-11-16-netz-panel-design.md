# Netz-Panel für bandit-lab — Design

Datum: 2026-11-16. Besitzer: der User (Admin aller Geräte). Geschrieben auf pong aus dem Brainstorming.
Ziel-Repo: `bandit-nix` (Laptop `~/src/bandit-nix`), Lab-Teile unter `hosts/bandit-lab/services/`.

## Warum

Der User ist Admin vom Netz: Tailnet plus Heimnetz hinter dem Router `192.168.0.1`. bandit-lab ist seit heute
der DNS-Server mit Werbeblocker für das ganze Tailnet. Der User will an **einer Stelle** sehen und steuern,
was im Netz passiert:

- was geblockt wird (Werbung, Tracker, Schadseiten), pro Gerät
- welches Gerät wie viel Internet-Verkehr macht und welche Art (App, Dienst)
- Firewall und Sicherheit: Gefahr erkennen, selbst blocken, ihn warnen

Das soll gelten: zu Hause für alle Geräte am Router, unterwegs für Handy `pong` und Laptop `bandit`, wenn sie
mit Tailscale verbunden sind.

## Ziele

1. **Ein Panel**, nur im Tailnet erreichbar. Der User darf alles. Albert darf später nur lesen.
2. **Geblockt-Ansicht:** Top geblockte Domains, Anfragen pro Gerät, Verlauf, Suche nach Domain.
3. **Verkehr pro Gerät:** Bytes rein/raus pro Gerät; auf dem Handy pro App.
4. **Schutz:** Schadseiten-Liste zusätzlich zur Werbung; Warnung per ntfy, wenn ein Gerät auffällig viele
   Schadseiten anfragt oder ein neues Gerät im Heimnetz auftaucht.
5. **Steuern** (Phase 2): Domain erlauben oder sperren, Blocken kurz pausieren, IP bei CrowdSec bannen/entbannen.

## Nicht-Ziele

- Kein Aufbrechen von HTTPS (kein eigenes Zertifikat auf Geräten). Inhalte bleiben verschlüsselt; das Panel
  sieht Domains und Mengen, nicht Inhalte.
- Das Lab wird **nicht** Tor ins Internet: kein Exit-Node, kein Lab als Gateway im Heimnetz. Grund: das macht
  unterwegs langsam und zu Hause ist sonst das Internet weg, wenn das Lab neu startet.
- Kein Gegenangriff. „Bekämpfen“ heißt nur blocken, bannen, warnen.
- Keine Router-Steuerung: die Magenta-Box hat keine Web-Oberfläche, nur die App.
- Verkehrsmenge von Heimgeräten **ohne** Tailscale (TV, Gäste) ist in v1 nicht sichtbar, nur ihr DNS.

## Anti-Ziele (wäre ein Fehlschlag, auch wenn es läuft)

- Internet wird für irgendein Gerät spürbar langsamer (DNS-Antwort oder Durchsatz).
- Das Panel oder die DNS-Logs sind von außen erreichbar (Grafana hängt auch an Cloudflare, siehe Grenzen).
- Root-Verstecken auf pong bricht (HMA, susfs, Play Integrity) oder Banking-Apps gehen nicht mehr.
- Ein Lab-Neustart nimmt einem Gerät länger als bisher das Internet.
- Albert kann etwas ändern.

## Was es schon gibt (Recon 2026-11-16, nur gelesen)

| Teil | Wo | Stand |
|---|---|---|
| Blocky DNS | `services/dns/default.nix` | nur `100.125.161.81:53` (Tailnet), `queryLog.type = "none"`, Listen StevenBlack + OISD big |
| ntopng | `services/ntopng.nix`, svc:ntopng | schaut `enp44s0` + `tailscale0` an, sieht aber fast nur den Lab-eigenen Verkehr (Switch) |
| CrowdSec + Firewall-Bouncer, fail2ban | `services/crowdsec` | schützt das Lab selbst |
| Grafana + Prometheus | `services/monitoring`, svc:grafana | Dashboards als Nix-JSON in `dashboards.nix`; Grafana zusätzlich öffentlich über Cloudflare (`grafana.atmosphaere.at`, hinter Access) |
| Beszel Hub + Agents | `services/beszel`, Runbook `bnet-beszel-agents.md` | misst Netz-Bytes pro PC (albert, slayer) |
| ntfy | `services/ntfy` | Warnungen aufs Handy |
| Postgres | Lab | läuft |
| bnet Geräteliste | `services/bnet/devices.json` | Namen der eigenen Geräte |
| Handy-DNS | `~/projects/pong-dnsfilter` auf pong | fängt alle DNS ab, fragt zuerst Blocky, sonst DoH |
| Wächter | `~/projects/pong-dnsfilter/dns-watch.sh` | schaltet Tailnet-DNS auf Quad9, wenn das Lab 3 Min weg ist |

Lab: 30 Kerne, 62 GiB RAM, 1 Gbit am Router, Last ~3.5. Heimnetz `192.168.0.0/24`, ~26 Nachbarn bekannt.

## Wie es gebaut wird (Entscheidungen)

**Vom User entschieden:**
- Nur der User ist Admin; Albert später nur lesen; sonst niemand.
- Heimnetz (ganzer Router) + unterwegs pong und Laptop über Tailscale.
- Nicht langsamer werden ist harte Grenze.
- Der User hat die empfohlenen Wege freigegeben („mach weiter mit den recommended Sachen“).

**Meine Entscheidungen (Claude), bitte prüfen:**

1. **Panel = Grafana** (läuft schon, Rollen gibt es fertig: User = Admin, Albert = Viewer). Neues Dashboard
   „Netzwerk“ als Startpunkt mit Links zu ntopng und Beszel. Kein neues Web-Framework für die Ansicht.
2. **Blocky schreibt Anfragen in Postgres**, 7 Tage, dann gelöscht (`queryLog` Typ postgresql,
   `logRetentionDays = 7`). Dazu Blocky-Prometheus-Metriken an. Gerätenamen: feste Zuordnung IP → Name
   (Tailnet-IPs aus `tailscale status`, Heim-IPs über Blocky `clientLookup` am Router oder statische Liste).
3. **Heimnetz über die Geräte, nicht über den Router:** Der Router ist eine Magenta Home Box Fiber+
   (CGA4336DTA1). Sie hat keine Web-Oberfläche; Einstellungen nur über die Mein-Magenta-App, und dort gibt
   es laut Anleitung nur WLAN-Name/Passwort, Teilen und Router-Details, keinen DNS (Recon 2026-11-16).
   Darum: eigene Heimgeräte bekommen Tailscale (DNS kommt dann schon vom Lab, Ausfall fängt `dns-watch.sh`
   ab) oder den Lab-DNS von Hand. Geräte ohne beides (TV, Gäste) bleiben in v1 ungefiltert und unsichtbar.
   Kein zweiter DHCP-Server im Heimnetz (würde mit dem Router streiten). Später möglich: Magenta um
   Bridge-Modus bitten und eigenen Router davor, dann geht der ganze Router-Weg.
4. **Verkehr pro Gerät durch Melder statt Umleiten:**
   - Laptop und PCs: Beszel-Agent (gibt es schon für albert/slayer; Laptop dazu).
   - pong: kleines Root-Skript in Termux liest alle 5 Min die Bytes pro App (`dumpsys netstats` o. ä.) und
     schickt sie per Tailnet an das Lab (z. B. Prometheus Pushgateway, nur auf Tailnet-IP). Läuft wie
     `dns-watch.sh` aus Termux, ändert nichts an Modulen, HMA, susfs oder Props.
5. **Schadseiten:** eine Malware-/Phishing-Liste zu Blocky dazu (Vorschlag: HaGeZi Threat Intelligence Feeds,
   Variante mit wenig Fehlalarmen). Blocktyp wie bisher `zeroIp`.
6. **Warnungen** über Grafana-Alerting oder Prometheus → ntfy (Weg wie `monitoring/notify.nix`):
   Gerät fragt > N Schadseiten in 10 Min; neues Gerät im Heimnetz (neue Client-IP bei Blocky).
7. **Phase 2, Steuern:** kleine Seite als Tailscale-Service (`svc:netz`, Muster `tailnet-https.nix`),
   Policy-Grant nur für den User. Aktionen: Domain auf eigene Allow-/Deny-Datei setzen (Blocky liest
   lokale Listen-Dateien und lädt sie über seine API neu), Blocken X Minuten pausieren (Blocky API),
   CrowdSec-Ban an/aus (`cscli decisions`). Jede Aktion landet in einem Log und schickt ntfy.
8. **Albert sieht keine DNS-Logs** (nach Builder-Check): In Grafana OSS kann ein Viewer jede Datasource
   seiner Org per API abfragen. Darum: DNS-Log-Datasource nur in der Admin-Org des Users, mit einer
   Postgres-Rolle, die nur lesen darf. Albert bekommt später eine eigene Org mit nur Summen
   (Anfragen gesamt, % geblockt, Bytes pro eigenem Gerät), ohne Domains.
9. **Neues Gerät = neue MAC im Heimnetz**, nicht neue IP (IPv6-Privacy-Adressen wechseln täglich).
    Passiv über ARP/NDP auf `enp44s0` (ntopng sieht das schon, sonst ein kleiner ARP-Wächter).
10. **Lab-Adresse fest:** nur nötig, wenn Geräte den Lab-DNS von Hand eingetragen bekommen: dann
    `192.168.0.160` statisch in NixOS (Router kann keine Reservierung). Für IPv6 keine Provider-Adresse.
11. **CrowdSec-Bans schützen nur das Lab.** Das Lab ist kein Gateway, darum kann Phase 2 keine IPs fürs
    ganze Netz sperren; fürs Netz gibt es nur Domain-Sperren über DNS. So im Panel beschriften.
12. **Reihenfolge:** Phase 1 = Sehen (2–6, 8–10 + Dashboard). Phase 2 = Steuern (7, 11). Phase 2 erst, wenn
   Phase 1 eine Woche ohne Tempo-Problem läuft.

## Grenzen und Sicherheit

- Grafana ist auch über Cloudflare erreichbar. Vor dem Freischalten prüfen, dass Access dort nur den User
  durchlässt, oder das Netzwerk-Dashboard/Datasource nur über svc:grafana erreichbar machen.
- DNS-Logs zeigen das Surfen **aller** im Netz, auch fremde Tailnet-Geräte (jerrecode, reumanno,
  klapetz.velislav, 6m9jsftdky) und Gäste. Darum nur 7 Tage, kein Export, nur Tailnet-Zugang.
- Tempo messen vor/nach: DNS-Antwortzeit (`dig` von Laptop, pong, slayerpc; heute ~25 ms) und Speedtest
  von einem Heimgerät. Mehr als +5 ms DNS-Mittelwert = Fehlschlag, zurückbauen.
- Deploy nur durch den User (`lab-apply` o. ä.); Claude pusht und deployt nicht.
- Auf pong: kein Schreiben in `/data/adb` ohne eigenes OK; Boot-Start des Melders nur mit OK.
- Andere Arbeit läuft parallel: ungespeicherte ntopng-GeoIP-Änderung auf dem Laptop
  (Zweig `fix/bandit-space-key`, `services/ntopng.nix`). Nicht überschreiben; in eigenem Worktree arbeiten.

## Rückweg

- Blocky-Log: `queryLog.type = "none"` zurück, Tabelle droppen.
- Heimnetz: von Hand gesetzten DNS an den Geräten zurück auf automatisch; Port 53 auf `enp44s0` wieder zu.
- pong-Melder: Skript stoppen und löschen.
- Phase 2: Import von `svc:netz` entfernen, Policy-Grant löschen.
- Runbook `docs/runbooks/lab-netz-panel.md` mit genau diesen Schritten.

## Geklärt nach dem Builder-Check

- Router lässt DNS nicht umstellen (siehe Entscheidung 3). Damit fällt auch die Frage weg, was bei einem
  Lab-Neustart zu Hause passiert: Heimgeräte ohne Tailscale hängen gar nicht am Lab.

## Dem Builder überlassen

- Genaue Panels und Abfragen im Dashboard.
- Wie die Handy-Bytes pro App am saubersten gelesen werden.
- Pushgateway oder anderer Weg ins Lab, solange nur im Tailnet erreichbar.
- Wahl der genauen Schadseiten-Liste (wenig Fehlalarme ist wichtiger als viel blocken).
- Tests: Nix-Check/`lab-surface`-Muster wie bei DNS; ein Test, dass Blocky-Logs nach 7 Tagen weg sind.
