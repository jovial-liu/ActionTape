#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DESTINATION_DIR="${HOME}/Applications"
FORCE=0

usage() {
  cat <<'EOF'
Usage: ./scripts/install-local.sh [--system] [--destination DIR] [--force]

Build and install ActionTape for local development.

  --system           Install into /Applications (no automatic sudo).
  --destination DIR  Install into an explicit directory.
  --force            Replace an existing ActionTape.app after making a backup.
  -h, --help         Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --system)
      DESTINATION_DIR="/Applications"
      shift
      ;;
    --destination)
      if (($# < 2)); then
        echo "--destination requires a directory" >&2
        exit 2
      fi
      DESTINATION_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${DESTINATION_DIR}" || "${DESTINATION_DIR}" == "/" ]]; then
  echo "Refusing unsafe destination directory: '${DESTINATION_DIR}'" >&2
  exit 2
fi

mkdir -p -- "${DESTINATION_DIR}"
DESTINATION_DIR="$(cd -- "${DESTINATION_DIR}" && pwd)"
INSTALLED_APP="${DESTINATION_DIR}/ActionTape.app"

if [[ "${DESTINATION_DIR}" == "${PROJECT_DIR}/.build/artifacts" ]]; then
  echo "The installation destination cannot also be the packaging output directory." >&2
  exit 2
fi

if [[ -e "${INSTALLED_APP}" || -L "${INSTALLED_APP}" ]]; then
  if [[ "${FORCE}" -ne 1 ]]; then
    echo "${INSTALLED_APP} already exists. Re-run with --force to replace it." >&2
    exit 1
  fi
fi

"${SCRIPT_DIR}/package-app.sh"
SOURCE_APP="${PROJECT_DIR}/.build/artifacts/ActionTape.app"

if [[ -e "${INSTALLED_APP}" || -L "${INSTALLED_APP}" ]]; then
  BACKUP_ROOT="$(mktemp -d "${DESTINATION_DIR}/ActionTape-backup.XXXXXX")"
  BACKUP_APP="${BACKUP_ROOT}/ActionTape.app"
  mv -- "${INSTALLED_APP}" "${BACKUP_APP}"
  echo "Backed up the previous app to ${BACKUP_APP}"
fi

/usr/bin/ditto "${SOURCE_APP}" "${INSTALLED_APP}"
echo "Installed ${INSTALLED_APP}"
echo "Open System Settings > Privacy & Security > Accessibility if macOS requests permission."
echo "This local development build is not Developer ID signed or notarized."
