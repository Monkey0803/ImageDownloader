#!/usr/bin/env bash
# Build the app the way DevEco Studio does on this machine.
#
# hvigor's packaging step shells out to a JDK; the system has none on PATH, so
# we point JAVA_HOME at the JBR that ships inside DevEco Studio.
set -euo pipefail

DEVECO="${DEVECO:-/Applications/DevEco-Studio.app}"
export DEVECO_SDK_HOME="$DEVECO/Contents/sdk"
export JAVA_HOME="$DEVECO/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"

cd "$(dirname "$0")/.."
bash "$(pwd)/scripts/build-zip-deps.sh"
exec node "$DEVECO/Contents/tools/hvigor/bin/hvigorw.js" "$@" --no-daemon
