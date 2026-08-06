# Fehlerbericht für Framework Support: Leertaste erzeugt Mehrfachsignale und fällt aus

## Betreff

Framework Laptop 13 AMD Ryzen 7040: Leertaste erzeugt unkontrollierte Mehrfachsignale und funktioniert anschließend nicht mehr zuverlässig

## Gerät

- Modell: Framework Laptop 13
- Bestellnummer: `R958282780`
- Mainboard: AMD Ryzen 7040 Series
- Tastaturlayout: Deutsch, ISO
- Betroffene Taste: Leertaste
- Interne Tastaturerkennung unter Linux: `AT Translated Set 2 keyboard` über `i8042`

## Fehlerverlauf

Die Leertaste funktionierte am Vortag noch normal. Am nächsten Morgen begann sie plötzlich, ohne normale Einzelbetätigung sehr schnell und wiederholt Leerzeichen einzugeben. Später reagierte die Leertaste nicht mehr zuverlässig beziehungsweise gar nicht mehr in Anwendungen.

Nach Auftreten des Fehlers wurde ein nichtleitendes, ausdrücklich für Tastaturen vorgesehenes Reinigungsspray verwendet. Der ursprüngliche Fehler trat jedoch bereits **vor** der Anwendung des Reinigungsmittels auf.

Anschließend wurde das Gerät geöffnet und die zugänglichen Kontakte beziehungsweise Steckverbindungen wurden neu eingesetzt. Danach waren in Anwendungen keine unkontrollierten Leerzeichen mehr sichtbar. Zu diesem Zeitpunkt war allerdings bereits ein Linux-Workaround aktiv, der die physische Leertaste unterdrückt. Deshalb kann nicht sicher festgestellt werden, ob das erneute Einsetzen der Verbindung die spontanen Signale tatsächlich beendet hat.

## Kontrollierter Funktionstest

Die physische Leertaste wurde zehnmal bewusst und einzeln betätigt. Die Kernel-Ereignisse wurden dabei unabhängig von der normalen Tastaturbelegung ausgewertet.

Ergebnis:

- 10 physische Betätigungen
- 64 registrierte Tastendruck-Ereignisse
- 32 registrierte Loslass-Ereignisse
- Betroffener AT-Tastatur-Scan-Code: `0x39`
- Während eines anschließenden Beobachtungszeitraums ohne Berührung wurden keine weiteren Ereignisse registriert

Beispiel der Kernelmeldung:

```text
atkbd serio0: Unknown key pressed (translated set 2, code 0x39 on isa0060/serio0)
```

Die deutlich zu hohe Anzahl an Druck- und Loslass-Ereignissen zeigt, dass eine einzelne mechanische Betätigung mehrere elektrische Signale auslöst. Das Verhalten ist aktuell intermittierend und wird vor allem durch Druck auf die Leertaste ausgelöst.

## Technische Einschätzung

Die Messergebnisse sprechen mit hoher Wahrscheinlichkeit für einen Hardwarefehler im elektrischen Tastenkreis der Leertaste. Mögliche Ursachen sind beispielsweise:

- eine verunreinigte oder beschädigte Membran beziehungsweise Kontaktfläche,
- eine beschädigte leitfähige Beschichtung oder Leiterbahn,
- eine mechanische Vorspannung durch Scherenmechanik oder Stabilisator,
- oder eine lokale Beschädigung der Tastatureinheit beziehungsweise ihrer Verbindung.

Ein reiner Fehler der Linux-Tastenbelegung ist unwahrscheinlich, da der Scan-Code `0x39` mehrfach direkt vom Tastaturcontroller an den Kernel übertragen wird. Die genaue interne Schadstelle lässt sich ohne weitere Prüfung der Tastatureinheit nicht eindeutig bestimmen.

## Aktueller Workaround

Damit das Gerät weiter benutzbar bleibt und keine unkontrollierten Leerzeichen eingegeben werden, ist vorübergehend folgende Hardware-Datenbank-Zuordnung unter Linux aktiv:

```text
KEYBOARD_KEY_0039=reserved
KEYBOARD_KEY_003a=space
```

Dadurch wird die physische Leertaste unterdrückt und Caps Lock vorübergehend als Leertaste verwendet. Dieser Workaround verhindert nur die Auswirkungen im Betriebssystem und repariert den Hardwarefehler nicht.

## Bitte an Framework Support

Ich bitte um:

1. Prüfung beziehungsweise Bestätigung der Diagnose anhand der beschriebenen Messergebnisse.
2. Auskunft, ob der Fehler durch Garantie oder Kulanz abgedeckt werden kann.
3. Bestätigung, dass als Ersatzteil die eigenständige **Framework Laptop 13 Tastatur, Deutsch ISO** ausreicht und kein vollständiges Input Cover benötigt wird.
4. Hinweise, falls vor einem Austausch noch ein von Framework empfohlener, zerstörungsfreier Prüfschritt durchgeführt werden soll.

Die physische Leertaste bleibt bis zur Klärung deaktiviert, um weitere unkontrollierte Eingaben zu verhindern.
