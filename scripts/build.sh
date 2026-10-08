#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/scripts/lib/toolchain.zsh"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$PROJECT_ROOT/Resources/Info.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$PROJECT_ROOT/Resources/Info.plist")"
APP_DIR="$PROJECT_ROOT/dist/$APP_NAME.app"
if [[ -e "$APP_DIR" ]]; then
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")" != "$BUNDLE_ID" ]]; then
    echo "同名产物不属于本项目，已停止。" >&2
    exit 1
  fi
fi
echo "构建 $APP_NAME · macOS SDK $SDK_VERSION"
viaview_build_product "$APP_NAME"
LINKED_SDK="$(xcrun vtool -show-build "$BUILD_ROOT/release/$APP_NAME" | awk '$1 == "sdk" {print $2; exit}')"
if [[ "$LINKED_SDK" != "$SDK_VERSION" && "$LINKED_SDK" != "$SDK_VERSION.0" ]]; then
  echo "产物 SDK ($LINKED_SDK) 与所选 SDK ($SDK_VERSION) 不一致；停止打包。" >&2
  exit 1
fi
# Never discard the runnable app until its replacement is built and signed.
mkdir -p "$PROJECT_ROOT/dist"
STAGING_ROOT="$(mktemp -d "$PROJECT_ROOT/dist/.viaview-build.XXXXXX")"
STAGED_APP="$STAGING_ROOT/$APP_NAME.app"
PREVIOUS_APP="$STAGING_ROOT/previous.app"
function cleanup_staging() {
  if [[ -d "$PREVIOUS_APP" && ! -e "$APP_DIR" ]]; then
    mv "$PREVIOUS_APP" "$APP_DIR"
  fi
  rm -rf "$STAGING_ROOT"
}
trap cleanup_staging EXIT
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BUILD_ROOT/release/$APP_NAME" "$STAGED_APP/Contents/MacOS/$APP_NAME"
cp -R "$BUILD_ROOT/release/ViaView_ViaView.bundle" "$STAGED_APP/Contents/Resources/"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$PROJECT_ROOT/LICENSE" "$STAGED_APP/Contents/Resources/LICENSE"
xcrun swift -module-cache-path "$BUILD_ROOT/module-cache" "$PROJECT_ROOT/scripts/Icon.swift" "$BUILD_ROOT/AppIcon.iconset"
iconutil -c icns "$BUILD_ROOT/AppIcon.iconset" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime --entitlements "$PROJECT_ROOT/Resources/Entitlements.plist" "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
if [[ -e "$APP_DIR" ]]; then mv "$APP_DIR" "$PREVIOUS_APP"; fi
mv "$STAGED_APP" "$APP_DIR"
echo "构建完成：$APP_DIR"
