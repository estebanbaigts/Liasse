#!/bin/zsh
# Compile Liasse en version Release et l'installe dans /Applications.
# Usage : ./scripts/install.sh   (à relancer après chaque mise à jour du code)
# Tes données ne sont pas touchées : elles vivent dans le conteneur de l'app, pas dans le .app.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Génération du projet"
command -v xcodegen >/dev/null && xcodegen generate --quiet

echo "▸ Compilation (Release)…"
xcodebuild -project Cockpit.xcodeproj -scheme Cockpit -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/Release build -quiet

APP="build/Release/Build/Products/Release/Liasse.app"
DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"

echo "▸ Installation dans $DEST"
pkill -x Liasse 2>/dev/null || true
rm -rf "$DEST/Liasse.app"
ditto "$APP" "$DEST/Liasse.app"

# Enregistre l'app et son widget auprès de macOS (Launchpad, Spotlight, galerie de widgets).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$DEST/Liasse.app"
pluginkit -a "$DEST/Liasse.app/Contents/PlugIns/CockpitWidgetExtension.appex" 2>/dev/null || true

echo "✓ Liasse est installée : $DEST/Liasse.app"
open "$DEST/Liasse.app"
