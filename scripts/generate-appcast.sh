#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/scripts/lib/toolchain.zsh"
APP="$PROJECT_ROOT/dist/ViaView.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(lipo -archs "$APP/Contents/MacOS/ViaView")"
case "$ARCH" in
  arm64|x86_64) ;;
  'x86_64 arm64'|'arm64 x86_64') ARCH=universal ;;
  *) print -u2 "不支持的发布架构：$ARCH"; exit 1 ;;
esac
ARCHIVE="$PROJECT_ROOT/dist/ViaView-$VERSION-$ARCH.zip"
TOOLS="$BUILD_ROOT/artifacts/sparkle/Sparkle/bin"
ACCOUNT="${VIAVIEW_SPARKLE_ACCOUNT:-ViaView}"
EXPECTED_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")"
ACTUAL_KEY="$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)"
if [[ "$EXPECTED_KEY" != "$ACTUAL_KEY" ]]; then
  print -u2 "Sparkle 钥匙串公钥与应用不匹配；未生成更新源。"
  exit 1
fi
[[ -f "$ARCHIVE" ]] || { print -u2 "请先运行 scripts/package.sh。"; exit 1; }
STAGING="$(mktemp -d "$PROJECT_ROOT/dist/.viaview-appcast.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cp "$ARCHIVE" "$STAGING/"
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/yangbo-s/ViaView/releases/download/v$VERSION/" \
  --link "https://github.com/yangbo-s/ViaView/releases/tag/v$VERSION" "$STAGING"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$STAGING/appcast.xml"
python3 "$PROJECT_ROOT/scripts/check-appcast.py" "$STAGING/appcast.xml" "$ARCHIVE" "$APP/Contents/Info.plist"
mv "$STAGING/appcast.xml" "$PROJECT_ROOT/dist/appcast.xml"
print "已生成并验证签名更新源：$PROJECT_ROOT/dist/appcast.xml"
