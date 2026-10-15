#!/usr/bin/env bash
# Build this app from the command line.
#
# Three environment values are required and none of them are obvious. They come from
# DevEco Studio's own installation, because the CLI toolchain is bundled there and is
# NOT on PATH by default:
#
#   DEVECO_SDK_HOME  the SDK root; hvigor fails with
#                    "Invalid value of 'DEVECO_SDK_HOME'" without it
#   JAVA_HOME        the packaging step shells out to Java; without it the build dies
#                    at PackageHap with "Unable to locate a Java Runtime"
#   PATH             DevEco's bundled node
#
# Adjust DEVECO if DevEco Studio is installed somewhere else.
set -euo pipefail

DEVECO=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME="$DEVECO/sdk"
export JAVA_HOME="$DEVECO/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$DEVECO/tools/node/bin:$PATH"

cd "$(dirname "$0")"
exec "$DEVECO/tools/hvigor/bin/hvigorw" assembleHap --mode module -p product=default --no-daemon "$@"
