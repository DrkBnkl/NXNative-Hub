#!/bin/bash
# Packt eine gebaute NXNative.app als Release-Zip.
# Aufruf: ./create_release.sh [Pfad.app] [Version]
# Ohne Versionsangabe wird CFBundleShortVersionString aus Info.plist verwendet,
# damit Zip-Name und App-Version nicht mehr auseinanderlaufen.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${1:-${HOME}/NXNative/NXNative.app}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIR/Info.plist" 2>/dev/null || echo "1.0.0")"
VERSION="${2:-$PLIST_VERSION}"
OUTPUT_ZIP="$DIR/NXNative-Companion-v${VERSION}.zip"

if [ ! -d "$APP_PATH" ]; then
    echo "==> Error: $APP_PATH does not exist. Run ./build.sh first." >&2
    exit 1
fi

echo "==> Packaging $APP_PATH into $OUTPUT_ZIP..."
rm -f "$OUTPUT_ZIP"
# ditto erhält Code-Signatur, erweiterte Attribute und Symlinks zuverlässig
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_ZIP"

echo "==> Release archive created successfully:"
echo "    $OUTPUT_ZIP"
ls -lh "$OUTPUT_ZIP"
