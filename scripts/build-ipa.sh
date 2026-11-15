#!/usr/bin/env bash
# 在 macOS 上编出未签名 ipa（不需要 Apple 开发者账号）。
# 用法：./scripts/build-ipa.sh [Release|Debug]
set -euo pipefail

CONFIG="${1:-Release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "需要先安装 Xcode（xcodebuild 不在 PATH 里）。" >&2
  exit 1
fi

if [ -f project.yml ] && ! [ -d MusicHall.xcodeproj ] || [ project.yml -nt MusicHall.xcodeproj ]; then
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
  else
    echo "提示：装了 xcodegen（brew install xcodegen）可以按 project.yml 重新生成工程。" >&2
  fi
fi

xcodebuild \
  -project MusicHall.xcodeproj \
  -scheme MusicHall \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="build/Build/Products/$CONFIG-iphoneos/MusicHall.app"
[ -d "$APP_PATH" ] || { echo "没找到产物：$APP_PATH" >&2; exit 1; }

rm -rf out && mkdir -p out/Payload
cp -R "$APP_PATH" out/Payload/
( cd out && zip -qry ../MusicHall-unsigned.ipa Payload )
rm -rf out
echo "完成：$ROOT/MusicHall-unsigned.ipa"
echo "下一步：用 Sideloadly / AltStore 用自己的 Apple ID 签名后装到 iPhone。"
