#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "Uso: $0 nali-linux-x64.tar.gz" >&2
  exit 2
fi

APP_HOME="${HOME}/.local/share/nali"
BIN_HOME="${HOME}/.local/bin"
DESKTOP_HOME="${HOME}/.local/share/applications"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$ARCHIVE" -C "$TMP_DIR"
if [[ ! -x "$TMP_DIR/bundle/nali" ]]; then
  echo "El archivo no contiene bundle/nali. Descarga el artefacto Linux oficial de Nali." >&2
  exit 3
fi

mkdir -p "$APP_HOME" "$BIN_HOME" "$DESKTOP_HOME"
rm -rf "$APP_HOME"/*
cp -a "$TMP_DIR/bundle/." "$APP_HOME/"
ln -sfn "$APP_HOME/nali" "$BIN_HOME/nali"

cat > "$DESKTOP_HOME/nali.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Nali
Comment=Reproductor de música Nali
Exec=$APP_HOME/nali
Icon=multimedia-player
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupNotify=true
DESKTOP
chmod +x "$DESKTOP_HOME/nali.desktop"

if ! command -v nali >/dev/null 2>&1; then
  case ":$PATH:" in
    *":$BIN_HOME:"*) ;;
    *) echo "Añade $BIN_HOME a PATH para ejecutar 'nali' desde la terminal." ;;
  esac
fi

echo "Nali se instaló en: $APP_HOME"
echo "Puedes abrirlo desde el menú de aplicaciones o ejecutar: $BIN_HOME/nali"
echo "Si faltan bibliotecas GTK, instala libgtk-3-0 y liblzma5 con el gestor de paquetes de tu distribución."
