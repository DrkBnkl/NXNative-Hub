#!/bin/sh
# Builds and runs the save sync tests. An optional folder holds copies of real saves: <name>/astris and <name>/nx.
set -e
cd "$(dirname "$0")/../.."
OUT="$(mktemp -d)"
swiftc -O -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos14.0 Sources/Core/SaveSync.swift Tests/SaveSyncTests/main.swift -o "$OUT/savesync-tests"
"$OUT/savesync-tests" "$@"
rm -rf "$OUT"
