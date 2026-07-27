#!/bin/bash
# Einfacher, zuverlässiger Polling-Watcher nur mit macOS-Bordmitteln.
# Läuft im workspace-Ordner und kopiert geänderte .lua-Dateien ins Ziel.

WORKSPACE="${1:-${PWD}}"
DEST="/Users/stefantippl/Library/Mobile Documents/com~apple~CloudDocs/Documents/Modellbau/Ethos RC/Simulator/1.6.6/persist/XE/scripts/BmpPro"
TMP="/tmp/vscode-lua-mtimes-$$.txt"

cd "$WORKSPACE" || exit 1
mkdir -p "$DEST"

# initiale Liste (mtime + Pfad)
find . -type f -name '*.lua' -print0 | xargs -0 stat -f "%m %N" > "$TMP"

while true; do
  sleep 1
  find . -type f -name '*.lua' -print0 | xargs -0 stat -f "%m %N" > "${TMP}.new"
  if ! cmp -s "$TMP" "${TMP}.new"; then
    # für jede Zeile in der neuen Liste prüfen, ob mtime anders ist oder Datei neu
    while IFS= read -r line; do
      file="${line#* }"
      # alte Zeile (falls vorhanden)
      oldline=$(grep -F -- "$file" "$TMP" 2>/dev/null || true)
      if [ "$oldline" != "$line" ]; then
        # kopieren (Pfad quoted wegen Leerzeichen)
        rsync -av "$file" "$DEST/" #&& echo "$(date '+%F %T') COPIED $file" || echo "$(date '+%F %T') COPY FAILED $file"
      fi
    done < "${TMP}.new"
    mv "${TMP}.new" "$TMP"
  else
    rm -f "${TMP}.new"
  fi
done
