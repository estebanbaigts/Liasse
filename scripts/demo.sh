#!/bin/zsh
# Lance Cockpit avec des données d'exemple dans un dossier séparé (tes vraies données ne sont pas touchées).
set -e
cd "$(dirname "$0")/.."
APP=build/DD/Build/Products/Debug/Liasse.app
DEMO="$HOME/Library/Containers/fr.cockpit.app/Data/Library/Application Support/CockpitDemo"
pkill -f "Liasse.app/Contents/MacOS/Cockpit" 2>/dev/null || true
[[ "$1" == "--reset" ]] && rm -rf "$DEMO"
open -n "$APP" --args -cockpitDataDir "$DEMO" -cockpitSample -cockpitToday 21/10/2026
