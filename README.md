# SSD-Backup → pCloud (verschlüsselt, automatisch)

Sichert externe Platten, interne Platten oder einzelne Ordner mit **restic**
(Verschlüsselung + Versionen) über **rclone** nach pCloud. **launchd** startet
das Backup automatisch.

## Einrichten / Aktualisieren

SSD anstecken, dann im Terminal:
```bash
cd ~/Documents/SSD-Backup/ssd-backup && zsh install.sh
```
Der Installer ist auch für Updates da: Vorhandenes (pCloud-Verbindung,
Passwort, SSD-Name, Ordnerlisten) bleibt erhalten.

**Passwort zusätzlich im Passwort-Manager sichern.** Ohne es ist das Backup
unlesbar – auch für pCloud.

> Scheitert das automatische Backup mit „Operation not permitted“ (betrifft vor
> allem interne Ordner wie Dokumente oder Schreibtisch):
> Systemeinstellungen → Datenschutz & Sicherheit → **Festplattenvollzugriff**
> → `/bin/zsh` hinzufügen.

## Menüleisten-App „SSD-Backup“

Der Installer baut eine kleine App für die Menüleiste (`~/Applications/SSD-Backup.app`)
und startet sie beim Anmelden. Ein Klick auf das Laufwerk-Symbol oben rechts zeigt:

- Zustand, Fortschritt mit Restzeit und welche Quelle gerade gesichert wird
- alle Quellen mit angesteckt ja/nein, letztem Backup und ▶︎ zum Einzeln-Sichern
- **Backup starten** (alle verfügbaren Quellen) / **Abbrechen** (bereits Hochgeladenes bleibt erhalten)
- **Durchstöbern**: hängt das Backup im Finder ein und öffnet die Übersicht aller Stände;
  ⏏︎ hängt es wieder aus
- **Einstellungen …**: ein Fenster für alles – links die Seitenleiste mit
  - **Quellen**: Platten/Ordner hinzufügen (+) oder entfernen (−); je Quelle
    gesicherte und ausgeschlossene Ordner, „Automatisch sichern“, „Jetzt sichern“
  - **Zeitplan**: beim Einstecken, alle X Stunden oder täglich, Mindestabstand, pausieren
  - **Aufbewahrung & Weiteres**: Stände behalten, Mitteilungen, Autostart, Uploads
- **Protokoll**, ⚙︎ als Abkürzung zu Quellen, Zeitplan, Pausieren und Beenden

Während des Backups zeigt das Symbol die Prozentzahl an. Neu bauen nach
Änderungen: `zsh app/build.sh`

## Das eingehängte Backup im Finder

| Ordner | Inhalt |
|---|---|
| `snapshots/` | **Hier hineinschauen.** Ein Unterordner pro Stand, benannt nach Datum und Uhrzeit. `latest` ist immer der neueste. |
| `hosts/MacBook-Pro/` | Dieselben Stände, gruppiert nach Computer |
| `ids/` | Dieselben Stände, benannt nach ihrer Kennung (z. B. `9f334e82`) |
| `tags/ssd/` | Dieselben Stände, gruppiert nach Stichwort |

Alle vier zeigen also **dieselben Daten**, nur anders sortiert. Innerhalb eines
Stands steht der volle Pfad, z. B. `latest/Volumes/MeineSSD/Bilder/…`.
**Wiederherstellen = Datei oder Ordner aus dem Finder herausziehen.** Das
eingehängte Backup ist schreibgeschützt; Öffnen dauert etwas, weil die Daten aus
pCloud geladen und entschlüsselt werden.

Solange das Backup eingehängt ist, können Prüfung und Reparatur nicht laufen.
Nach dem Stöbern also wieder aushängen.

## Stand anzeigen (Terminal)

```bash
ssd-backup status       # einmal anzeigen
ssd-backup status -w    # live mitverfolgen (Ctrl-C beendet)
```
```
SSD-Backup  MeineSSD → pCloud:Backups/SSD

  Zustand      ● läuft – Sichere Dateien  (seit 1 Std. 12 Min.)
  Fortschritt  ████████████████░░░░░░░░░░░░░░  55.0 %
  Daten        660.0 GB von 1.2 TB
  Dateien      137'500 von 250'000
  Restzeit     ca. 2 Std. 1 Min.
  Aktuell      Fotos/2025/Urlaub/IMG_4711.CR3

  Letztes erfolgreiches Backup   08.11.2026 12:03  (vor 1 Tg. 8 Std.)
  SSD                            angesteckt
  Umfang                         ganze SSD, 3 Ausschlüsse
```
Zusätzlich gibt es macOS-Mitteilungen bei Start, 25/50/75 %, Ende und Fehler
(abschaltbar in `settings.conf`). Ist das letzte Backup älter als 7 Tage,
weist die Statusanzeige darauf hin.

## Mehrere Platten oder Ordner (Quellen)

Jede Quelle ist eine Platte oder ein Ordner. Alle landen im selben
verschlüsselten pCloud-Backup (ein Passwort, gleiche Dateien werden nur einmal
hochgeladen), jede mit eigenem Stichwort, eigener Ordnerliste und eigenem
„zuletzt gesichert“.

```bash
ssd-backup sources                          # alle Quellen anzeigen
ssd-backup source add                       # Finder-Dialog: Platte oder Ordner wählen
ssd-backup source add "/Volumes/Archiv"     # externe Platte
ssd-backup source add ~/Documents           # interner Ordner
ssd-backup source add /                     # ganze interne Platte (ohne System/Caches)
ssd-backup source disable archiv            # vorübergehend nicht automatisch sichern
ssd-backup source remove archiv             # entfernen (Stände in pCloud bleiben)
ssd-backup start archiv                     # nur diese Quelle jetzt sichern
```

- Externe Platten werden gesichert, wenn sie angesteckt sind; interne Quellen
  sind immer da und laufen nach dem Zeitplan mit.
- Der Mindestabstand (`MIN_HOURS_BETWEEN`) gilt je Quelle.
- Beim Durchstöbern zeigt `tags/<stichwort>/` die Stände einer einzelnen Quelle.
- Bei einem Update wird die bisherige SSD zur ersten Quelle und behält das Stichwort `ssd`,
  damit ihre Versionsgeschichte weiterläuft.

## Ordner auswählen oder ausschließen

Gilt je Quelle – mit `-s ID` wählen (ohne Angabe: die erste Quelle). Ohne
Ordnerangabe öffnet sich ein **Finder-Dialog** (Mehrfachauswahl mit ⌘).

```bash
ssd-backup include -s meinessd add   # nur bestimmte Ordner sichern
ssd-backup include add Fotos "Projekte/2026"
ssd-backup exclude add              # Ordner ausschließen
ssd-backup exclude add "Filme/Rohmaterial" "*.tmp" "**/node_modules"
ssd-backup include remove           # zeigt Liste zum Auswählen
ssd-backup exclude remove "*.tmp"
ssd-backup lists                    # beide Listen anzeigen
ssd-backup edit                     # Einstellungen + Listen im Texteditor
```

Regeln:
- **include leer** → die ganze Quelle wird gesichert.
- **exclude ohne `* ? [ ]`** → genauer Pfad relativ zur Quelle.
- **exclude mit `* ? [ ]`** → Muster, gilt überall in der Quelle.
- Eine leere Datei **`.nobackup`** in einem Ordner schließt ihn ebenfalls aus.
- Änderungen gelten ab dem nächsten Backup. Bereits gesicherte Daten werden
  nicht neu hochgeladen (Deduplizierung).

Die Dateien liegen in `~/.config/ssd-backup/`: `settings.conf` und je Quelle
`sources/<id>/source.conf`, `include.txt`, `exclude.txt`.

## Wann läuft das Backup?

- Sobald eine Platte eingesteckt wird, **und**
- stündlich (für angesteckte Platten und interne Quellen). So werden abgebrochene oder
  fehlgeschlagene Backups (Internet weg, Mac im Ruhezustand) nachgeholt,
- aber nach einem erfolgreichen Backup erst wieder nach 20 Stunden
  (`MIN_HOURS_BETWEEN`).
- Sofort: `ssd-backup run --force`

Das ist die Standardeinstellung. Ändern lässt sie sich in der App unter
Einstellungen → Zeitplan, oder im Terminal:
```bash
ssd-backup schedule                                   # aktuellen Zeitplan anzeigen
ssd-backup set SCHEDULE daily DAILY_TIME 03:00        # täglich um 3 Uhr
ssd-backup set SCHEDULE interval INTERVAL_HOURS 6     # alle 6 Stunden
ssd-backup set RUN_ON_MOUNT 0 MIN_HOURS_BETWEEN 12    # nicht beim Einstecken, max. alle 12 Std.
ssd-backup schedule apply                             # Änderung aktivieren
```

Ein unterbrochenes Backup macht dort weiter, wo es aufgehört hat: Bereits
hochgeladene Daten werden erkannt und nicht erneut übertragen. Wird die SSD
während des Backups abgezogen, zählt das nicht als Erfolg – beim nächsten
Einstecken geht es weiter.

## Prüfung & automatische Reparatur

Nach jedem Backup prüft das Skript, ob alle Dateien vollständig auf pCloud
angekommen sind. pCloud antwortet gelegentlich mit Serverfehlern und kann
dabei abgeschnittene Dateien hinterlassen. Findet die Prüfung solche Dateien,
werden sie automatisch entfernt und die fehlenden Daten neu hochgeladen
(`restic repair packs` + erneutes Backup + erneute Prüfung). Klappt das nicht
sofort, wird es beim nächsten Lauf wiederholt.

Um solche Fehler seltener zu machen, lädt restic nur mit 2 parallelen
Verbindungen hoch (`RCLONE_CONNECTIONS` in `settings.conf`).

Aufbewahrt werden 7 tägliche, 4 wöchentliche, 12 monatliche und 3 jährliche
Stände. Einmal pro Woche werden alte Daten endgültig entfernt, einmal im Monat
wird eine 5-%-Stichprobe auf Integrität geprüft.

## Wiederherstellen & Weiteres

| Was | Befehl |
|---|---|
| Alle Stände auflisten | `ssd-backup snapshots` |
| Protokoll live ansehen | `ssd-backup log` |
| Dateien eines Stands durchsuchen | `ssd-backup restic ls latest \| grep Urlaub` |
| Ordner zurückholen | `ssd-backup restic restore latest --target ~/Desktop/restore --include "/Volumes/MeineSSD/Fotos/2025"` |
| Alles auf eine neue Platte | `ssd-backup restic restore latest --target /Volumes/NeuePlatte` |
| Backup wie ein Laufwerk durchstöbern* | `ssd-backup restic mount ~/restic-mount` |
| Speicherverbrauch in pCloud | `ssd-backup restic stats --mode raw-data` |

\* braucht macFUSE (`brew install --cask macfuse`).

**Tipp:** Hol ab und zu testweise eine Datei zurück.

## Deinstallieren

```bash
launchctl bootout gui/$(id -u)/com.user.ssd-backup
rm ~/Library/LaunchAgents/com.user.ssd-backup.plist ~/bin/ssd-backup
```
(Backup in pCloud, Passwort im Schlüsselbund und `~/.config/ssd-backup`
bleiben erhalten.)
