#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)) || [[ ! -f "$1" ]]; then
  echo "Usage: bash scripts/create-app-icon.sh source.png output.icns" >&2
  exit 2
fi

ICON_SOURCE="$1"
ICON_OUTPUT="$2"
ICON_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/actiontape-icon.XXXXXX")"
ICONSET_DIR="${ICON_ROOT}/ActionTape.iconset"
cleanup() {
  rm -rf -- "${ICON_ROOT}"
}
trap cleanup EXIT

mkdir -p -- "${ICONSET_DIR}"
for SPEC in \
  "16:icon_16x16.png" "32:icon_16x16@2x.png" \
  "32:icon_32x32.png" "64:icon_32x32@2x.png" \
  "128:icon_128x128.png" "256:icon_128x128@2x.png" \
  "256:icon_256x256.png" "512:icon_256x256@2x.png" \
  "512:icon_512x512.png" "1024:icon_512x512@2x.png"; do
  SIZE="${SPEC%%:*}"
  NAME="${SPEC#*:}"
  /usr/bin/sips -z "${SIZE}" "${SIZE}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/${NAME}" >/dev/null
done
/usr/bin/iconutil -c icns "${ICONSET_DIR}" -o "${ICON_OUTPUT}"
