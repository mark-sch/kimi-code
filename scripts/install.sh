#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${SMARTBOX_REPOSITORY:-mark-sch/kimi-code}"
VERSION="${KIMI_VERSION:-}"
INSTALL_DIR="${KIMI_INSTALL_DIR:-$HOME/.kimi-code}"
NO_MODIFY_PATH="${KIMI_NO_MODIFY_PATH:-}"

fail() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    fail "sha256sum oder shasum wird für die Prüfsummenprüfung benötigt."
  fi
}

manifest_checksum() {
  local target="$1" compact
  compact="$(tr -d '\n\r\t' < "$TMP_DIR/manifest.json" | sed 's/ \+/ /g')"
  if [[ $compact =~ \"$target\"[[:space:]]*:[[:space:]]*\{[^{}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    fail "Die Release-Metadaten enthalten keine Prüfsumme für $target."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || fail "--version benötigt eine Version."
      VERSION="$2"
      shift 2
      ;;
    --version=*)
      VERSION="${1#*=}"
      shift
      ;;
    -h | --help)
      printf 'Verwendung: curl -fsSL https://raw.githubusercontent.com/%s/main/scripts/install.sh | bash\n' "$REPO"
      printf 'Optionale Umgebung: KIMI_VERSION, KIMI_INSTALL_DIR, KIMI_NO_MODIFY_PATH\n'
      exit 0
      ;;
    *) fail "Unbekannte Option: $1" ;;
  esac
done

for command in curl uname tar awk sed tr; do
  command -v "$command" >/dev/null 2>&1 || fail "Das Kommando '$command' wird benötigt."
done

case "$(uname -s)" in
  Linux) OS="linux" ;;
  Darwin) OS="darwin" ;;
  *) fail "Dieses Betriebssystem wird von install.sh nicht unterstützt: $(uname -s)" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) ARCH="x64" ;;
  arm64 | aarch64) ARCH="arm64" ;;
  *) fail "Diese Architektur wird nicht unterstützt: $(uname -m)" ;;
esac
TARGET="$OS-$ARCH"

if [[ "$OS" == "linux" ]] && command -v ldd >/dev/null 2>&1 && ldd /bin/sh 2>&1 | grep -q musl; then
  fail "Alpine/musl wird vom nativen Paket nicht unterstützt. Verwende stattdessen die npm-Installation."
fi

if [[ -n "$VERSION" ]]; then
  if [[ "$VERSION" == smartbox-v* ]]; then TAG="$VERSION"; else TAG="smartbox-v$VERSION"; fi
else
  printf '==> Neuestes Release wird ermittelt\n'
  LATEST_URL="$(curl -fsSL --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")"
  TAG="${LATEST_URL##*/}"
  [[ "$TAG" == smartbox-v* ]] || fail "Das neueste Release konnte nicht ermittelt werden."
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smartbox-install.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT
DOWNLOAD_BASE="https://github.com/$REPO/releases/download/$TAG"
ARCHIVE="kimi-code-$TARGET.tar.gz"
curl -fsSL --retry 3 -o "$TMP_DIR/manifest.json" "$DOWNLOAD_BASE/manifest.json"
CHECKSUM="$(manifest_checksum "$TARGET")"
[[ "$CHECKSUM" =~ ^[a-f0-9]{64}$ ]] || fail "Ungültige SHA-256-Prüfsumme in manifest.json."

printf '==> Lade %s aus %s\n' "$ARCHIVE" "$TAG"
curl -fSL --retry 3 -o "$TMP_DIR/$ARCHIVE" "$DOWNLOAD_BASE/$ARCHIVE"
curl -fsSL --retry 3 -o "$TMP_DIR/$ARCHIVE.sha256" "$DOWNLOAD_BASE/$ARCHIVE.sha256"
EXPECTED_ARCHIVE="$(awk '{print $1}' "$TMP_DIR/$ARCHIVE.sha256")"
ACTUAL_ARCHIVE="$(sha256_file "$TMP_DIR/$ARCHIVE")"
[[ "$ACTUAL_ARCHIVE" == "$EXPECTED_ARCHIVE" ]] || fail "Die Prüfsumme des Downloads stimmt nicht überein."

mkdir "$TMP_DIR/extract"
tar -xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR/extract"
BINARY="$TMP_DIR/extract/kimi"
[[ -f "$BINARY" ]] || fail "Das Paket enthält keine kimi-Executable."
ACTUAL_BINARY="$(sha256_file "$BINARY")"
[[ "$ACTUAL_BINARY" == "$CHECKSUM" ]] || fail "Die Prüfsumme der Executable stimmt nicht mit manifest.json überein."

BIN_DIR="$INSTALL_DIR/bin"
mkdir -p "$BIN_DIR"
install -m 0755 "$BINARY" "$BIN_DIR/kimi"
printf '==> Installiert: %s\n' "$BIN_DIR/kimi"

VERSION_OUTPUT="$("$BIN_DIR/kimi" --version 2>&1)"
printf '%s\n' "$VERSION_OUTPUT"
[[ "$VERSION_OUTPUT" == *"${TAG#smartbox-v}"* ]] || fail "Die installierte Version entspricht nicht dem Release $TAG."

if [[ -z "$NO_MODIFY_PATH" ]]; then
  SHELL_NAME="${SHELL##*/}"
  case "$SHELL_NAME" in
    fish)
      RC_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
      PATH_LINE="fish_add_path -g \"$BIN_DIR\""
      ;;
    zsh)
      RC_FILE="${ZDOTDIR:-$HOME}/.zshrc"
      PATH_LINE="export PATH=\"$BIN_DIR:\$PATH\""
      ;;
    *)
      RC_FILE="$HOME/.bashrc"
      PATH_LINE="export PATH=\"$BIN_DIR:\$PATH\""
      ;;
  esac
  mkdir -p "$(dirname "$RC_FILE")"
  touch "$RC_FILE"
  if ! grep -qsF "$BIN_DIR" "$RC_FILE"; then
    printf '\n%s\n' "$PATH_LINE" >> "$RC_FILE"
    printf '==> PATH in %s ergänzt; öffne anschließend ein neues Terminal.\n' "$RC_FILE"
  fi
fi

printf '\nSmartbox AI wurde erfolgreich installiert. Starte Kimi Web mit:\n'
printf '  kimi web --no-open\n'
