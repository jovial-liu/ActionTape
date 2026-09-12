#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${1:-${PROJECT_DIR}/outputs}"
SOURCE_VERSION="$(sed -n 's/.*public static let version = "\([^"]*\)".*/\1/p' "${PROJECT_DIR}/Sources/ActionTapeCore/ActionTapeCore.swift")"
VERSION="${ACTIONTAPE_VERSION:-${SOURCE_VERSION}}"
CONFIGURATION="${ACTIONTAPE_CONFIGURATION:-release}"
BUILD_NUMBER="${ACTIONTAPE_BUILD_NUMBER:-1}"
ARCHITECTURE="$(uname -m)"

if (($# > 1)) || [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: bash scripts/package-preview.sh [output-directory]"
  echo "Default output: outputs/ActionTape-VERSION-ARCH-source-preview.zip and .sha256"
  echo "Environment: ACTIONTAPE_VERSION, ACTIONTAPE_BUILD_NUMBER, ACTIONTAPE_CONFIGURATION, ACTIONTAPE_SCRATCH_PATH"
  if (($# > 1)); then exit 2; fi
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Preview packaging requires macOS and a Swift 6 toolchain." >&2
  exit 1
fi
if [[ "${ARCHITECTURE}" != "arm64" && "${ARCHITECTURE}" != "x86_64" ]]; then
  echo "Unsupported host architecture: ${ARCHITECTURE}" >&2
  exit 2
fi
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "${SOURCE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "${BUILD_NUMBER}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "Use numeric x.y.z source/package versions and a numeric build number." >&2
  exit 2
fi
if [[ "${CONFIGURATION}" != "debug" && "${CONFIGURATION}" != "release" ]]; then
  echo "ACTIONTAPE_CONFIGURATION must be debug or release." >&2
  exit 2
fi
if [[ -z "${OUTPUT_DIR}" || "${OUTPUT_DIR}" == "/" ]]; then
  echo "Refusing unsafe output directory: '${OUTPUT_DIR}'" >&2
  exit 2
fi

mkdir -p -- "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd -- "${OUTPUT_DIR}" && pwd)"
STAGING_ROOT="$(mktemp -d "${OUTPUT_DIR}/.actiontape-preview.XXXXXX")"
cleanup() {
  rm -rf -- "${STAGING_ROOT}"
}
trap cleanup EXIT

PACKAGE_NAME="ActionTape-${VERSION}-${ARCHITECTURE}-source-preview"
PACKAGE_DIR="${STAGING_ROOT}/${PACKAGE_NAME}"
ARCHIVE_NAME="${PACKAGE_NAME}.zip"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"
mkdir -p -- "${PACKAGE_DIR}"

# A dedicated build directory avoids collisions with normal development builds.
export ACTIONTAPE_SCRATCH_PATH="${ACTIONTAPE_SCRATCH_PATH:-${PROJECT_DIR}/.build/preview}"
export ACTIONTAPE_CONFIGURATION="${CONFIGURATION}"
export ACTIONTAPE_VERSION="${VERSION}"
export ACTIONTAPE_BUILD_NUMBER="${BUILD_NUMBER}"

bash "${SCRIPT_DIR}/package-app.sh" "${PACKAGE_DIR}"
bash "${SCRIPT_DIR}/package-practice-app.sh" "${PACKAGE_DIR}"

cd -- "${PROJECT_DIR}"
SWIFT_OPTIONS=(--skip-update --scratch-path "${ACTIONTAPE_SCRATCH_PATH}" -c "${CONFIGURATION}")
swift build "${SWIFT_OPTIONS[@]}" --product actiontape
BIN_DIR="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
install -m 0755 "${BIN_DIR}/actiontape" "${PACKAGE_DIR}/actiontape"
if [[ "$("${PACKAGE_DIR}/actiontape" --version)" != "${SOURCE_VERSION}" ]]; then
  echo "Packaged CLI does not report the checked-in source version." >&2
  exit 1
fi
for EXECUTABLE in \
  "${PACKAGE_DIR}/actiontape" \
  "${PACKAGE_DIR}/ActionTape.app/Contents/MacOS/ActionTape" \
  "${PACKAGE_DIR}/ActionTape Practice.app/Contents/MacOS/ActionTapePractice"; do
  if [[ "$(/usr/bin/lipo -archs "${EXECUTABLE}")" != "${ARCHITECTURE}" ]]; then
    echo "Unexpected executable architecture: ${EXECUTABLE}" >&2
    exit 1
  fi
done

/usr/bin/ditto --norsrc --noextattr --noacl "${PROJECT_DIR}/examples" "${PACKAGE_DIR}/examples"
mkdir -p -- "${PACKAGE_DIR}/Licenses"
install -m 0644 "${PROJECT_DIR}/LICENSE" "${PACKAGE_DIR}/LICENSE"
install -m 0644 "${PROJECT_DIR}/Vendor/Yams/LICENSE" "${PACKAGE_DIR}/Licenses/Yams-LICENSE.txt"
install -m 0644 "${PROJECT_DIR}/Vendor/Yams/NOTICE.md" "${PACKAGE_DIR}/Licenses/ThirdParty-NOTICE.md"
install -m 0644 "${PROJECT_DIR}/docs/dev-bundle.md" "${PACKAGE_DIR}/START-HERE.md"

# Only the fresh package directory enters the archive, never old output bundles.
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr --noacl \
  "${PACKAGE_DIR}" "${STAGING_ROOT}/${ARCHIVE_NAME}"
/usr/bin/unzip -tq "${STAGING_ROOT}/${ARCHIVE_NAME}" >/dev/null
(
  cd -- "${STAGING_ROOT}"
  /usr/bin/shasum -a 256 "${ARCHIVE_NAME}" > "${CHECKSUM_NAME}"
)

if [[ -e "${OUTPUT_DIR}/${ARCHIVE_NAME}" || -L "${OUTPUT_DIR}/${ARCHIVE_NAME}" || -e "${OUTPUT_DIR}/${CHECKSUM_NAME}" || -L "${OUTPUT_DIR}/${CHECKSUM_NAME}" ]]; then
  BACKUP_ROOT="$(mktemp -d "${OUTPUT_DIR}/ActionTape-preview-previous.XXXXXX")"
  for NAME in "${ARCHIVE_NAME}" "${CHECKSUM_NAME}"; do
    if [[ -e "${OUTPUT_DIR}/${NAME}" || -L "${OUTPUT_DIR}/${NAME}" ]]; then
      mv -- "${OUTPUT_DIR}/${NAME}" "${BACKUP_ROOT}/${NAME}"
    fi
  done
  echo "Preserved previous preview artifacts in ${BACKUP_ROOT}"
fi
mv -- "${STAGING_ROOT}/${ARCHIVE_NAME}" "${OUTPUT_DIR}/${ARCHIVE_NAME}"
mv -- "${STAGING_ROOT}/${CHECKSUM_NAME}" "${OUTPUT_DIR}/${CHECKSUM_NAME}"
echo "Created ${OUTPUT_DIR}/${ARCHIVE_NAME}"
echo "Checksum: ${OUTPUT_DIR}/${CHECKSUM_NAME}"
echo "Local development preview: no Developer ID signature or notarization was added."
