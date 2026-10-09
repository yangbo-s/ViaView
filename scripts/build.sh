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
mkdir -p "$STAGED_APP/Contents/Frameworks"
ditto "$BUILD_ROOT/release/Sparkle.framework" "$STAGED_APP/Contents/Frameworks/Sparkle.framework"
cp "$BUILD_ROOT/artifacts/sparkle/Sparkle/LICENSE" "$STAGED_APP/Contents/Resources/Sparkle-LICENSE"
xcrun swift -module-cache-path "$BUILD_ROOT/module-cache" "$PROJECT_ROOT/scripts/Icon.swift" "$BUILD_ROOT/AppIcon.iconset"
iconutil -c icns "$BUILD_ROOT/AppIcon.iconset" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
SIGNING_IDENTITY="${VIAVIEW_SIGNING_IDENTITY:--}"
FRAMEWORK="$STAGED_APP/Contents/Frameworks/Sparkle.framework"
# Sign nested helpers individually; --deep would apply the app's sandbox to them.
for component in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$FRAMEWORK/Versions/B/$component"
done
codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$FRAMEWORK"
cp "$PROJECT_ROOT/Resources/Entitlements.plist" "$STAGING_ROOT/Entitlements.plist"
if [[ "$SIGNING_IDENTITY" == - ]]; then
  # Ad-hoc signatures have no Team ID for library validation. Developer ID builds
  # retain library validation; this fallback matches the project's local releases.
  /usr/libexec/PlistBuddy -c 'Add com.apple.security.cs.disable-library-validation bool true' "$STAGING_ROOT/Entitlements.plist"
fi
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --entitlements "$STAGING_ROOT/Entitlements.plist" "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
if [[ -e "$APP_DIR" ]]; then mv "$APP_DIR" "$PREVIOUS_APP"; fi
mv "$STAGED_APP" "$APP_DIR"
echo "构建完成：$APP_DIR"
