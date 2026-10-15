#!/usr/bin/env bash
# Device helper: launch the app and pull a screenshot.
#
#   scripts/device.sh launch  [target]
#   scripts/device.sh install [target]
#   scripts/device.sh shot    <name> [target]
#   scripts/device.sh tap     <x> <y> [target]
#   scripts/device.sh swipe   <x1> <y1> <x2> <y2> [target]
#   scripts/device.sh dark    [target]
#   scripts/device.sh light   [target]
#
# Target device, in order of precedence:
#   1. the command's last positional argument
#   2. $DEVICE_TARGET  (e.g. export DEVICE_TARGET=192.0.2.10:45679 for a phone over TCP)
#   3. 127.0.0.1:5555  (the emulator)
# The repo does not hard-code any device address.
set -euo pipefail

DEVECO="${DEVECO:-/Applications/DevEco-Studio.app}"
HDC="$DEVECO/Contents/sdk/default/openharmony/toolchains/hdc"
BUNDLE=com.example.imagedownloader
DEFAULT_TARGET="${DEVICE_TARGET:-127.0.0.1:5555}"
HAP="$(dirname "$0")/../entry/build/default/outputs/default/entry-default-signed.hap"
SHOTS="$(dirname "$0")/../.screenshots"

cmd="${1:?usage: device.sh <launch|install|shot|tap|swipe|dark|light> ...}"
shift

run() { "$HDC" -t "$TARGET" "$@"; }

case "$cmd" in
  launch)
    TARGET="${1:-$DEFAULT_TARGET}"
    run shell "aa start -b $BUNDLE -a EntryAbility" >/dev/null
    ;;
  install)
    TARGET="${1:-$DEFAULT_TARGET}"
    run install -r "$HAP"
    ;;
  shot)
    name="${1:?name required}"
    TARGET="${2:-$DEFAULT_TARGET}"
    mkdir -p "$SHOTS"
    run shell "snapshot_display -f /data/local/tmp/$name.jpeg" >/dev/null
    run file recv "/data/local/tmp/$name.jpeg" "$SHOTS/$name.jpeg" >/dev/null
    echo "$SHOTS/$name.jpeg"
    ;;
  tap)
    x="${1:?x required}"; y="${2:?y required}"
    TARGET="${3:-$DEFAULT_TARGET}"
    run shell "uitest uiInput click $x $y" >/dev/null
    ;;
  # 一次拖动：坐标是 px，和 tap 一致。滑动手势用 uiInput swipe 而不是 click 连点。
  swipe)
    x1="${1:?x1 required}"; y1="${2:?y1 required}"
    x2="${3:?x2 required}"; y2="${4:?y2 required}"
    TARGET="${5:-$DEFAULT_TARGET}"
    run shell "uitest uiInput swipe $x1 $y1 $x2 $y2 400" >/dev/null
    ;;
  dark)
    TARGET="${1:-$DEFAULT_TARGET}"
    run shell "cmd overlay enable --user 0 $BUNDLE" >/dev/null 2>&1 || true
    run shell "aa start -b $BUNDLE -a EntryAbility" >/dev/null
    ;;
  light)
    TARGET="${1:-$DEFAULT_TARGET}"
    run shell "aa start -b $BUNDLE -a EntryAbility" >/dev/null
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 2
    ;;
esac
