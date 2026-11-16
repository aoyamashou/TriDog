#!/bin/bash
# TriDog.app（三语狗输入快切）を swiftc で組み立てて署名する（Xcode 不要）
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

# 署名は固定の証明書で行う（ad hoc だとビルドごとに署名が変わり、入力監視の許可が毎回無効になる）。
# 既定は鍵チェーンの「Apple Development」証明書。別の証明書を使うときは SIGN_IDENTITY で指定する
IDENTITY="${SIGN_IDENTITY:-Apple Development}"
if ! security find-identity -v -p codesigning | grep -q "${IDENTITY}"; then
  echo "error: 署名用の証明書 '${IDENTITY}' が見つかりません（SIGN_IDENTITY で指定できます）" >&2
  exit 1
fi
codesign --force --sign "${IDENTITY}" "${APP}"
echo "built: ${APP}"
