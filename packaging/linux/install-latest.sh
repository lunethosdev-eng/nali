#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="lunethosdev-eng/nali"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

command -v curl >/dev/null 2>&1 || { echo "Necesitas curl para descargar Nali." >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "Necesitas tar para instalar Nali." >&2; exit 1; }

curl -fL "https://github.com/${REPOSITORY}/releases/latest/download/nali-linux-x64.tar.gz" \
  -o "$WORK_DIR/nali-linux-x64.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/install.sh" "$WORK_DIR/nali-linux-x64.tar.gz"
