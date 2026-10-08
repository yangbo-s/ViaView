#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/scripts/lib/toolchain.zsh"
viaview_build_product ViaView
APP_SOURCES=("$PROJECT_ROOT"/Sources/ViaView/**/*.swift)
APP_SOURCES=("${(@)APP_SOURCES:#*/ViaViewApp.swift}")
# Use only current source objects; old incremental builds may retain renamed files.
CORE_OBJECTS=()
for source in "$PROJECT_ROOT"/Sources/ViewerCore/*.swift; do
  CORE_OBJECTS+=("$BUILD_ROOT/release/ViewerCore.build/${source:t}.o")
done
xcrun swiftc -swift-version 5 -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx14.0" \
  -I "$BUILD_ROOT/release/Modules" "${APP_SOURCES[@]}" \
  "$BUILD_ROOT/release/ViaView.build/DerivedSources/resource_bundle_accessor.swift" \
  "${CORE_OBJECTS[@]}" "$PROJECT_ROOT/Tests/AppKitChecks.swift" -o "$BUILD_ROOT/AppKitChecks"
"$BUILD_ROOT/AppKitChecks"
