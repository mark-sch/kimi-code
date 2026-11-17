#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/apps/kimi-code"
PACKAGE_JSON="$APP_DIR/package.json"

confirm() {
  local prompt="$1"
  local answer
  read -r -p "$prompt [j/N] " answer
  case "${answer,,}" in
    j | ja | y | yes) return 0 ;;
    *) return 1 ;;
  esac
}

fail() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

for command in node pnpm npm; do
  command -v "$command" >/dev/null 2>&1 ||
    fail "Das Kommando '$command' wurde nicht gefunden."
done

[[ -f "$PACKAGE_JSON" ]] ||
  fail "Keine Kimi-Code-App unter $APP_DIR gefunden."

VERSION="$(
  node --input-type=module -e \
    "import { readFileSync } from 'node:fs'; console.log(JSON.parse(readFileSync(process.argv[1], 'utf8')).version)" \
    "$PACKAGE_JSON"
)"

PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kimi-code-deploy.XXXXXX")"
trap 'rm -rf -- "$PACKAGE_DIR"' EXIT

PACKAGE_PATH="$PACKAGE_DIR/moonshot-ai-kimi-code-$VERSION.tgz"
CURRENT_KIMI="$(command -v kimi || true)"

printf '\nKimi-Code-Deployment\n'
printf '  Projekt:          %s\n' "$ROOT_DIR"
printf '  Neue Version:     %s\n' "$VERSION"
printf '  Aktueller Aufruf: %s\n' "${CURRENT_KIMI:-nicht installiert}"

if [[ -n "$CURRENT_KIMI" ]]; then
  printf '  Aktueller Pfad:   %s\n' "$(readlink -f "$CURRENT_KIMI")"
  printf '  Aktuelle Version: %s\n' "$("$CURRENT_KIMI" --version 2>/dev/null || printf 'unbekannt')"
fi

printf '\nLaufende Kimi-Web-Instanzen vorher mit Strg+C beenden.\n'

confirm 'Build erzeugen und global installieren?' || {
  printf 'Deployment abgebrochen.\n'
  exit 0
}

printf '\n==> Abhängigkeiten prüfen\n'
pnpm --dir "$ROOT_DIR" install --frozen-lockfile

printf '\n==> Projekt bauen\n'
pnpm --dir "$ROOT_DIR" build

printf '\n==> Smoke-Test ausführen\n'
pnpm -C "$APP_DIR" smoke

printf '\n==> Installationspaket erzeugen\n'
pnpm -C "$APP_DIR" pack --pack-destination "$PACKAGE_DIR"
[[ -f "$PACKAGE_PATH" ]] ||
  fail "Das erwartete Paket $PACKAGE_PATH wurde nicht erzeugt."

if command -v uv >/dev/null 2>&1 &&
  uv tool list 2>/dev/null | grep -Eq '^kimi-cli([[:space:]]|$)'; then
  if confirm 'Die alte Python-Installation über uv wurde erkannt. Deinstallieren?'; then
    uv tool uninstall kimi-cli
  else
    fail 'Die alte Installation muss zuerst entfernt werden.'
  fi
elif command -v pipx >/dev/null 2>&1 &&
  pipx list --short 2>/dev/null | grep -Eq '^kimi-cli([[:space:]]|$)'; then
  if confirm 'Die alte Python-Installation über pipx wurde erkannt. Deinstallieren?'; then
    pipx uninstall kimi-cli
  else
    fail 'Die alte Installation muss zuerst entfernt werden.'
  fi
fi

if npm ls --global --depth=0 @moonshot-ai/kimi-code >/dev/null 2>&1; then
  if confirm 'Die vorhandene globale npm-Installation vor dem Update entfernen?'; then
    npm uninstall --global @moonshot-ai/kimi-code
  else
    fail 'Deployment vor dem Ersetzen der globalen Installation abgebrochen.'
  fi
fi

printf '\n==> Version %s global installieren\n' "$VERSION"
npm install --global "$PACKAGE_PATH"

INSTALLED_KIMI="$(command -v kimi || true)"
[[ -n "$INSTALLED_KIMI" ]] ||
  fail 'Nach der Installation wurde kein globales Kommando kimi gefunden.'

printf '\n==> Installation prüfen\n'
printf '  Kommando: %s\n' "$INSTALLED_KIMI"
printf '  Pfad:     %s\n' "$(readlink -f "$INSTALLED_KIMI")"
printf '  Version:  %s\n' "$("$INSTALLED_KIMI" --version)"

"$INSTALLED_KIMI" --version 2>&1 | grep -Fq "$VERSION" ||
  fail "Die aktive Installation meldet nicht die erwartete Version $VERSION."

"$INSTALLED_KIMI" web --help 2>&1 | grep -Fq 'Smartbox AI' ||
  fail 'Der aktive Build enthält nicht den erwarteten Smartbox-AI-Standardtitel.'

if [[ -d "$HOME/.kimi" ]]; then
  if confirm 'Daten einer alten Python-Installation jetzt mit kimi migrate übernehmen?'; then
    "$INSTALLED_KIMI" migrate
  fi
fi

printf '\nDeployment erfolgreich abgeschlossen.\n'
printf 'Falls die Shell noch den alten Pfad verwendet: hash -r\n'
printf 'Kimi Web starten:\n'
printf '  kimi web --port 58627 --no-open --host\n'

