#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
OUTPUT="${1:-$ROOT/dist/RoadRover Map.app}"
CONTENTS="$OUTPUT/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"
swiftc -O -parse-as-library \
  -target arm64-apple-macos13.0 \
  -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/*.swift \
  -o "$MACOS/RoadRover Map"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/minecraft_overworld.rrmap" "$RESOURCES/minecraft_overworld.rrmap"
codesign --force --deep --sign - "$OUTPUT"
echo "$OUTPUT"
