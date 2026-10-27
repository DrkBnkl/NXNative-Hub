#!/bin/bash
# Baut NXNative.app aus allen Swift-Dateien unter Sources/.
# Aufruf: ./build.sh [Zielpfad.app]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${1:-${HOME}/NXNative/NXNative.app}"

# Alle Quelldateien einsammeln (robust gegen Leerzeichen im Pfad)
SOURCES=()
while IFS= read -r -d '' file; do
    SOURCES+=("$file")
done < <(find "$DIR/Sources" -name '*.swift' -print0 | sort -z)

if [ ${#SOURCES[@]} -eq 0 ]; then
    echo "==> Fehler: keine Swift-Dateien unter $DIR/Sources gefunden." >&2
    exit 1
fi

echo "==> Building NXNative.app at: $APP_PATH (${#SOURCES[@]} Swift files)"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

cp "$DIR/Info.plist" "$APP_PATH/Contents/Info.plist"

swiftc -parse-as-library -O -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macos14.0 \
  -module-name NXNativeHub \
  "${SOURCES[@]}" \
  -o "$APP_PATH/Contents/MacOS/NXNativeGUI"

codesign --force --deep --sign - "$APP_PATH"

echo "==> Build successful: $APP_PATH"
