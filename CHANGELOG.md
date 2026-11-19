# Changelog

Alle Änderungen an SSD-Backup. Neue Versionen installiert die App über
**Aktualisieren** oder `ssd-backup update`.

## [1.1.0] – 2026-11-19

### Neu
- **Speicherlimit:** Das Backup lässt sich auf eine Höchstgröße begrenzen
  (Einstellungen → Speicher & Stände oder `ssd-backup set MAX_REPO_GB 500`).
  Zusätzlich gibt es eine Reserve, die im pCloud-Konto immer frei bleibt
  (Standard 10 GB, `MIN_FREE_GB`).
- **Aktive Speicherüberwachung:** Vor jedem Backup und während des Backups
  alle 2 Minuten wird der pCloud-Speicher geprüft. Ist das Limit erreicht oder
  wird das Konto zu voll, räumt das Backup zuerst nach den Aufbewahrungsregeln
  auf und hält sonst sauber an, statt erst am Ende zu scheitern. Bereits
  Hochgeladenes bleibt erhalten. Ab 90 % gibt es eine Warnung.
- **Stände manuell löschen:** Neue Seite „Speicher & Stände“ in den
  Einstellungen. Sie listet alle gesicherten Stände mit Datum, Quelle und neu
  hochgeladener Datenmenge. Ausgewählte Stände lassen sich löschen, der
  Speicher wird danach freigegeben (`ssd-backup delete ID …`).
- Speicheranzeige im Menü: Backup-Größe, Limit und freier Platz auf pCloud.
- `ssd-backup storage` zeigt Konto, Backup-Größe und Limit an.
- Dieser Changelog. Die Release-Notizen auf GitHub kommen jetzt von hier.

## [1.0.1] – 2026-11-18

### Behoben
- Das Menü öffnete sich teilweise erst nach rund einer Minute. Die App
  liest ihren Zustand jetzt im Hintergrund und schaut nicht mehr in den
  eingehängten Backup-Ordner, der bei einem hängenden Mount bis zu 60 Sekunden
  blockieren konnte. Auch schlafende Festplatten werden nicht mehr geweckt.
- „Durchstöbern“ hing dauerhaft, wenn die Platte mit dem Cache während des
  Einhängens abgesteckt wurde. Der Cache dafür liegt jetzt immer lokal.
- Aushängen (⏏︎) blockiert die App nicht mehr.

## [1.0.0] – 2026-11-18

Erstes Release.

### Neu
- Installationspaket auf GitHub mit fertig gebauter App (Apple Silicon und
  Intel). Installation per Einzeiler, siehe README.
- Updates direkt aus der App („Version X ist verfügbar – Aktualisieren“)
  oder mit `ssd-backup update`. Die App prüft alle 6 Stunden.
- Der Installer prüft Homebrew und bietet macFUSE fürs Durchstöbern an.
- Mehrere Quellen: externe und interne Platten oder einzelne Ordner.
- Ein Einstellungsfenster für Quellen, Ordner, Zeitplan und Aufbewahrung.
- Automatische Prüfung und Reparatur des Backups auf pCloud.

### Behoben
- „Durchstöbern“ schreibt Fehler jetzt ins Protokoll und zeigt die
  eigentliche Fehlermeldung in der App an.
