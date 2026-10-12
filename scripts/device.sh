#!/usr/bin/env bash
# Device helper: launch the app and pull a screenshot.
#
#   scripts/device.sh launch  [target]
#   scripts/device.sh shot    <name> [target]
#   scripts/device.sh tap     <x> <y> [target]
#   scripts/device.sh dark    [target]
#   scripts/device.sh light   [target]
#
# Default target is the real phone; pass the emulator serial to use that one.
set -euo pipefail

DEVECO="${DEVECO:-/Applications/DevEco-Studio.app}"
HDC="$DEVECO/Contents/sdk/default/openharmony/toolchains/hdc"
BUNDLE=com.example.imagedownloader
SHOTS="$(dirname "$0")/../.screenshots"

cmd="${1:?usage: device.sh <launch|shot|tap|dark|light> ...}"
shift

run() { "$HDC" -t "$TARGET" "$@"; }

case "$cmd" in
  launch)
    TARGET="${1:-10.155.89.11:45679}"
    run shell "aa start -b $BUNDLE -a EntryAbility" >/dev/null
    ;;
  shot)
    name="${1:?name required}"
    TARGET="${2:-10.155.89.11:45679}"
    mkdir -p "$SHOTS"
    run shell "snapshot_display -f /data/local/tmp/$name.jpeg" >/dev/null
    run file recv "/data/local/tmp/$name.jpeg" "$SHOTS/$name.jpeg" >/dev/null
    echo "$SHOTS/$name.jpeg"
    ;;
  tap)
    x="${1:?x required}"; y="${2:?y required}"
    TARGET="${3:-10.155.89.11:45679}"
    run shell "uitest uiInput click $x $y" >/dev/null
    ;;
  dark)
    TARGET="${1:-10.155.89.11:45679}"
    run shell "cmd overlay enable --user 0 $BUNDLE" >/dev/null 2>&1 || true
    run shell "aa start -b $BUNDLE -a EntryAbility" >/dev/null
    ;;
  light)
    TARGET="${1:-10.155.89.11:45679}"
    run shell "aa start -b $BUNDLE -a EntryAbility" >/dev/null
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 2
    ;;
esac
