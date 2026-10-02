#!/bin/bash
# ImeSwitch.app を swiftc で組み立てて ad hoc 署名する（Xcode 不要）
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${DIR}/build/ImeSwitch.app"

rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
cp "${DIR}/Info.plist" "${APP}/Contents/Info.plist"

# -Osize: サイズ優先の最適化 / dead_strip: 未使用コードを除去 / strip: シンボルを除去
swiftc -Osize -target arm64-apple-macos13 -Xlinker -dead_strip \
  "${DIR}/Sources/main.swift" \
  -o "${APP}/Contents/MacOS/ImeSwitch"
strip -x "${APP}/Contents/MacOS/ImeSwitch"

codesign --force --sign - "${APP}"
echo "built: ${APP}"
