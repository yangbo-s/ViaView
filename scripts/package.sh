#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
zsh "$PROJECT_ROOT/scripts/build.sh"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$PROJECT_ROOT/Resources/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PROJECT_ROOT/Resources/Info.plist")"
APP_DIR="$PROJECT_ROOT/dist/$APP_NAME.app"
ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_DIR/Contents/MacOS/$APP_NAME")"
case "$ARCHITECTURES" in
  arm64|x86_64) PACKAGE_ARCH="$ARCHITECTURES" ;;
  'x86_64 arm64'|'arm64 x86_64') PACKAGE_ARCH=universal ;;
  *) print -u2 "不支持的发布架构：$ARCHITECTURES"; exit 1 ;;
esac
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "版本号需要使用 major.minor.patch：$VERSION"
  exit 1
fi
PACKAGE_NAME="$APP_NAME-$VERSION-$PACKAGE_ARCH"
STAGING_ROOT="$(mktemp -d "$PROJECT_ROOT/dist/.viaview-package.XXXXXX")"
MOUNT_PATH=""
function cleanup_package() {
  if [[ -n "$MOUNT_PATH" ]]; then hdiutil detach "$MOUNT_PATH" >/dev/null || true; fi
  rm -rf "$STAGING_ROOT"
}
trap cleanup_package EXIT
mkdir -p "$STAGING_ROOT/volume"
ditto "$APP_DIR" "$STAGING_ROOT/volume/$APP_NAME.app"
ln -s /Applications "$STAGING_ROOT/volume/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_ROOT/volume" -format UDZO "$STAGING_ROOT/$PACKAGE_NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$STAGING_ROOT/$PACKAGE_NAME.zip"
hdiutil verify "$STAGING_ROOT/$PACKAGE_NAME.dmg"
MOUNT_PATH="$STAGING_ROOT/mounted"
mkdir -p "$MOUNT_PATH"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_PATH" "$STAGING_ROOT/$PACKAGE_NAME.dmg" >/dev/null
codesign --verify --deep --strict "$MOUNT_PATH/$APP_NAME.app"
cmp "$APP_DIR/Contents/MacOS/$APP_NAME" "$MOUNT_PATH/$APP_NAME.app/Contents/MacOS/$APP_NAME"
[[ "$(readlink "$MOUNT_PATH/Applications")" == /Applications ]]
hdiutil detach "$MOUNT_PATH" >/dev/null
MOUNT_PATH=""
ditto -x -k "$STAGING_ROOT/$PACKAGE_NAME.zip" "$STAGING_ROOT/unpacked"
codesign --verify --deep --strict "$STAGING_ROOT/unpacked/$APP_NAME.app"
cmp "$APP_DIR/Contents/MacOS/$APP_NAME" "$STAGING_ROOT/unpacked/$APP_NAME.app/Contents/MacOS/$APP_NAME"
(cd "$STAGING_ROOT" && shasum -a 256 "$PACKAGE_NAME.dmg" "$PACKAGE_NAME.zip" > "$PACKAGE_NAME-SHA256SUMS.txt")
for artifact in "$PACKAGE_NAME.dmg" "$PACKAGE_NAME.zip" "$PACKAGE_NAME-SHA256SUMS.txt"; do
  mv -f "$STAGING_ROOT/$artifact" "$PROJECT_ROOT/dist/$artifact"
done
print "发布包已生成：$PROJECT_ROOT/dist/$PACKAGE_NAME.{dmg,zip}"
