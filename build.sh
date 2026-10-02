#!/bin/bash
# TriDog.app（三语狗输入快切）を swiftc で組み立てて ad hoc 署名する（Xcode 不要）
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${DIR}/build/TriDog.app"

rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
cp "${DIR}/Info.plist" "${APP}/Contents/Info.plist"
mkdir -p "${APP}/Contents/Resources"
cp "${DIR}/Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

# -Osize: サイズ優先の最適化 / dead_strip: 未使用コードを除去 / strip: シンボルを除去
swiftc -Osize -target arm64-apple-macos13 -Xlinker -dead_strip \
  "${DIR}/Sources/main.swift" \
  -o "${APP}/Contents/MacOS/TriDog"
strip -x "${APP}/Contents/MacOS/TriDog"

codesign --force --sign - "${APP}"
echo "built: ${APP}"
