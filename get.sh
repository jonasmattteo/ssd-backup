#!/bin/zsh
# ============================================================================
#  get.sh – lädt die neueste Version von SSD-Backup und startet die Einrichtung
#
#    zsh -c "$(curl -fsSL https://github.com/jonasmattteo/ssd-backup/releases/latest/download/get.sh)"
# ============================================================================
set -e
REPO="jonasmattteo/ssd-backup"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

print "Suche neueste Version von SSD-Backup …"
url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
      | grep -o '"browser_download_url": *"[^"]*/ssd-backup-[0-9.]*\.zip"' | head -1 \
      | sed 's/.*"\(https:[^"]*\)"$/\1/')
[[ -n "$url" ]] || { print "Kein Release gefunden."; exit 1; }

print "Lade ${url:t} …"
curl -fL --progress-bar -o "$tmp/release.zip" "$url"
ditto -x -k "$tmp/release.zip" "$tmp"
zsh "$tmp/ssd-backup/install.sh" "$@"
