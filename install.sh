#!/bin/zsh
# ============================================================================
#  install.sh – richtet das SSD-Backup nach pCloud ein (oder aktualisiert es).
#  Kann gefahrlos mehrfach ausgeführt werden: erledigte Schritte werden
#  übersprungen, vorhandene Einstellungen und Ordnerlisten bleiben erhalten.
# ============================================================================
set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

HERE="${0:A:h}"
LABEL="com.user.ssd-backup"
BIN_DIR="$HOME/bin"
CMD="$BIN_DIR/ssd-backup"
OLD_SCRIPT="$BIN_DIR/ssd-backup.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONF_DIR="$HOME/.config/ssd-backup"
SETTINGS="$CONF_DIR/settings.conf"

step() { print -P "\n%F{cyan}==> $*%f"; }
ok()   { print -P "    %F{green}✓%f $*"; }

# 1) Programme ----------------------------------------------------------------
step "1/8  restic, rclone und jq installieren"
for tool in restic rclone jq; do
  if command -v $tool >/dev/null; then ok "$tool vorhanden"; else brew install $tool; fi
done

# 2) Befehl installieren + Standard-Konfiguration anlegen ----------------------
step "2/8  Befehl 'ssd-backup' installieren"
mkdir -p "$BIN_DIR" "${PLIST:h}" "$HOME/Library/Logs"
install -m 755 "$HERE/ssd-backup" "$CMD"
"$CMD" help >/dev/null          # legt ~/.config/ssd-backup/* an, falls nötig
ok "installiert: $CMD"
ok "Einstellungen: $CONF_DIR"
source "$SETTINGS"

# Werte aus der alten Version (ssd-backup.sh) übernehmen
if [[ -f "$OLD_SCRIPT" ]]; then
  old_name=$(sed -n 's/^SSD_NAME="\(.*\)".*/\1/p' "$OLD_SCRIPT" | head -1)
  if [[ -n "$old_name" && "$SSD_NAME" == "MeineSSD" ]]; then
    SSD_NAME="$old_name"
    ok "SSD-Name aus alter Version übernommen: $SSD_NAME"
  fi
fi

set_setting() {   # set_setting KEY WERT
  local tmp="$SETTINGS.tmp"
  awk -v k="$1" -v v="$2" 'BEGIN{FS="="; gsub(/&/, "\\\\&", v)} $1==k {sub(/=[^#]*/, "=\"" v "\"   "); print; next} {print}' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
}

# 3) Quellen (Platten/Ordner) ----------------------------------------------
step "3/8  Was soll gesichert werden?"
if [[ -n "$("$CMD" sources 2>/dev/null | grep -v 'Noch keine')" ]]; then
  "$CMD" sources | sed 's/^/  /'
  ok "Weitere Platten/Ordner: in der App unter „Quellen & Ordner …“ oder mit 'ssd-backup source add'"
else
  vols=()
  for v in /Volumes/*(N/); do [[ "${v:t}" != "Macintosh HD" ]] && vols+=("${v:t}"); done
  if (( ${#vols} )); then
    print "    Eingehängte Laufwerke:"
    for i in {1..${#vols}}; do print "      $i) ${vols[$i]}"; done
  fi
  read "ans?    Nummer, Name oder Pfad (z. B. ~/Documents) eingeben: "
  if [[ "$ans" == <-> ]] && (( ans >= 1 && ans <= ${#vols} )); then src="/Volumes/${vols[$ans]}"
  elif [[ "$ans" == /* || "$ans" == ~* ]]; then src="${~ans}"
  else src="/Volumes/$ans"; fi
  [[ -n "$ans" ]] || { print "Nichts angegeben – Abbruch."; exit 1; }
  "$CMD" source add "$src" | sed 's/^/    /'
  [[ "$src" == /Volumes/* ]] && set_setting SSD_NAME "${${src#/Volumes/}%%/*}"
fi

# 4) pCloud verbinden ---------------------------------------------------------
step "4/8  pCloud mit rclone verbinden"
if rclone listremotes | grep -qx "${RCLONE_REMOTE}:"; then
  ok "rclone-Remote '$RCLONE_REMOTE' existiert bereits"
else
  read "region?    Liegt dein pCloud-Konto in der EU (e) oder den USA (u)? [e/u]: "
  host="eapi.pcloud.com"; [[ "$region" == [uU]* ]] && host="api.pcloud.com"
  print "    Gleich öffnet sich der Browser – dort bei pCloud anmelden und Zugriff erlauben."
  rclone config create "$RCLONE_REMOTE" pcloud hostname "$host"
  ok "Remote '$RCLONE_REMOTE' angelegt"
fi

# 5) Passwort -----------------------------------------------------------------
step "5/8  Backup-Passwort im Schlüsselbund"
if [[ -n "$PASSWORD_COMMAND" ]]; then
  ok "eigener PASSWORD_COMMAND in settings.conf"
elif security find-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
  ok "Passwort bereits im Schlüsselbund"
else
  print "    Wähle ein langes Passwort und speichere es ZUSÄTZLICH im Passwort-Manager."
  print "    Ohne dieses Passwort ist das Backup für immer unlesbar!"
  security add-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w
  ok "Passwort gespeichert"
fi

# 6) Repository anlegen -------------------------------------------------------
step "6/8  Backup-Repository auf pCloud"
if "$CMD" restic cat config >/dev/null 2>&1; then
  ok "Repository existiert bereits (pCloud → $REPO_PATH)"
else
  "$CMD" restic init
  ok "Repository angelegt: pCloud → $REPO_PATH"
fi

# 7) launchd ------------------------------------------------------------------
step "7/8  Automatik einrichten"
# Zeitplan aus settings.conf (in der App unter ⚙︎ → Einstellungen änderbar)
"$CMD" schedule apply | sed 's/^/    /'
ok "launchd-Job '$LABEL' aktiv"

if [[ -f "$OLD_SCRIPT" ]]; then rm -f "$OLD_SCRIPT"; ok "alte Version ssd-backup.sh entfernt"; fi

# ~/bin in den PATH, damit 'ssd-backup' überall funktioniert
if [[ ":$PATH:" != *":$BIN_DIR:"* ]] && ! grep -qs 'HOME/bin' "$HOME/.zshrc"; then
  read "addp?    '~/bin' zum PATH in ~/.zshrc hinzufügen (damit 'ssd-backup' direkt geht)? [J/n]: "
  if [[ "$addp" != [nN]* ]]; then
    print '\nexport PATH="$HOME/bin:$PATH"   # ssd-backup' >> "$HOME/.zshrc"
    ok "PATH ergänzt – gilt in neuen Terminal-Fenstern"
  fi
fi

# 8) Menüleisten-App ----------------------------------------------------------
step "8/8  Menüleisten-App bauen"
if command -v swiftc >/dev/null; then
  zsh "$HERE/app/build.sh" | sed 's/^/    /'
  APP_AGENT="$HOME/Library/LaunchAgents/com.user.ssd-backup-app.plist"
  if [[ ! -f "$APP_AGENT" ]]; then
    cat > "$APP_AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.user.ssd-backup-app</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>$HOME/Applications/SSD-Backup.app</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
  fi
  ok "App startet beim Anmelden (abschaltbar im App-Menü ⚙︎)"
else
  print "    ⚠︎ swiftc fehlt – App übersprungen. Installieren mit: xcode-select --install"
fi

print -P "\n%F{green}Fertig!%f"
print "  Hilfe:                       ssd-backup help"
print "  Weitere Platte/Ordner:       ssd-backup source add"
print "  Ordner auswählen:            ssd-backup include add"
print "  Ordner ausschließen:         ssd-backup exclude add"
print "  Backup jetzt starten:        ssd-backup run --force"
print "  Fortschritt live ansehen:    ssd-backup status -w"
