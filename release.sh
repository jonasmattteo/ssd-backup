#!/bin/zsh
# ============================================================================
#  release.sh – baut das Installationspaket und veröffentlicht es auf GitHub
#
#    ./release.sh 1.2.0             Paket nur bauen (landet in dist/)
#    ./release.sh 1.2.0 --publish   Version setzen, committen, taggen, pushen
#                                   und das GitHub-Release mit Paket anlegen
#
#  Vorher im CHANGELOG.md einen Abschnitt „## [1.2.0] – Datum“ anlegen –
#  er wird zu den Release-Notizen auf GitHub.
#
#  Das Paket (ssd-backup-<version>.zip) enthält das Programm, install.sh,
#  die fertig gebaute App (Apple Silicon + Intel) und die App-Quellen.
#  'ssd-backup update' und die App laden es von dort.
# ============================================================================
set -e
HERE="${0:A:h}"; cd "$HERE"
VER="$1"; PUBLISH=0; [[ "$2" == --publish ]] && PUBLISH=1
[[ "$VER" == <->.<->.<-> ]] || { print "Aufruf: ./release.sh 1.2.0 [--publish]"; exit 1; }

if (( PUBLISH )); then
  [[ -z "$(git status --porcelain)" ]] || { print "Erst alle Änderungen committen."; exit 1; }
  git rev-parse -q --verify "refs/tags/v$VER" >/dev/null && { print "Tag v$VER gibt es schon."; exit 1; }
  command -v gh >/dev/null || { print "GitHub-CLI fehlt: brew install gh && gh auth login"; exit 1; }
fi

# Release-Notizen = Abschnitt dieser Version im CHANGELOG.md
notes=$(awk -v v="$VER" '
  /^## \[/ { if (on) exit; if (index($0, "## [" v "]") == 1) { on = 1; next } }
  on { print }' CHANGELOG.md | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
if [[ -z "${notes//[[:space:]]/}" ]]; then
  print "Im CHANGELOG.md fehlt ein Abschnitt „## [$VER] – Datum“."; (( PUBLISH )) && exit 1
fi

# Version eintragen
sed -i '' "s/^SSD_BACKUP_VERSION=\"[^\"]*\"/SSD_BACKUP_VERSION=\"$VER\"/" ssd-backup
zsh -n ssd-backup

# App für beide Prozessoren bauen
zsh app/build.sh --no-install --universal

# Paket zusammenstellen
rm -rf dist; mkdir -p dist/ssd-backup/app
cp ssd-backup install.sh README.md CHANGELOG.md dist/ssd-backup/
cp app/SSDBackup.swift app/build.sh dist/ssd-backup/app/
ditto app/build/SSD-Backup.app dist/ssd-backup/SSD-Backup.app
(cd dist && ditto -c -k --keepParent ssd-backup "ssd-backup-$VER.zip")
cp get.sh dist/
rm -rf dist/ssd-backup
print "Paket: $HERE/dist/ssd-backup-$VER.zip"

if (( PUBLISH )); then
  if [[ -n "$(git status --porcelain ssd-backup)" ]]; then
    git commit -q -m "Version $VER" ssd-backup
  fi
  git tag -a "v$VER" -m "Version $VER"
  git push -q && git push -q origin "v$VER"
  print -r -- "$notes" > dist/notes.md
  gh release create "v$VER" "dist/ssd-backup-$VER.zip" dist/get.sh \
    --title "Version $VER" --notes-file dist/notes.md
  print "Veröffentlicht: Version $VER"
fi
