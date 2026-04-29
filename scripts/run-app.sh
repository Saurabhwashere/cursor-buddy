#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/debug/AI Cursor Buddy.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"

swift build

mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/.build/debug/CodexCursor" "$MACOS_DIR/CodexCursor"
chmod +x "$MACOS_DIR/CodexCursor"

exec "$MACOS_DIR/CodexCursor"
