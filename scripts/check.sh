#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/scripts/lib/toolchain.zsh"
viaview_build_product ViewerChecks
"$BUILD_ROOT/release/ViewerChecks"
