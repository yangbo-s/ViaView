# Sourced by build.sh and check.sh after PROJECT_ROOT is set.
# Keep developer tools, SDK and caches identical for app and checks.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  if DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift --version >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi
BUILD_ROOT="${VIAVIEW_BUILD_DIR:-$PROJECT_ROOT/.build}"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
if [[ -n "${VIA_VIEW_REQUIRE_MODERN:-}" && -z "${VIAVIEW_REQUIRE_MODERN:-}" ]]; then
  echo "VIA_VIEW_REQUIRE_MODERN 已更名为 VIAVIEW_REQUIRE_MODERN；本次兼容旧变量。" >&2
fi
if [[ "${VIAVIEW_REQUIRE_MODERN:-${VIA_VIEW_REQUIRE_MODERN:-0}}" == 1 && "${SDK_VERSION%%.*}" -lt 26 ]]; then
  echo "需要 macOS 26+ SDK；当前为 $SDK_VERSION。请先完成 Xcode 的许可与首次启动设置。" >&2
  exit 1
fi
mkdir -p "$BUILD_ROOT/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/module-cache"
# Native build currently preserves the selected SDK stamp, needed by AppKit's
# modern appearance. Keep this workaround until SwiftBuild passes the same check.
function viaview_build_product() {
  xcrun swift build --build-system native --sdk "$SDK_PATH" --package-path "$PROJECT_ROOT" --scratch-path "$BUILD_ROOT" \
    --cache-path "$BUILD_ROOT/cache" --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" \
    --disable-sandbox -c release --product "$1"
}
