#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/kimi-code"
WORKFLOW="smartbox-native-release.yml"

fail() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

confirm() {
  local answer
  read -r -p "$1 [j/N] " answer
  case "${answer,,}" in
    j | ja | y | yes) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  printf 'Verwendung: %s [VERSION]\n' "${0##*/}"
  printf 'Ohne VERSION wird die Version aus apps/kimi-code/package.json verwendet.\n'
  exit 0
fi

for command in git node npm gh curl; do
  command -v "$command" >/dev/null 2>&1 || fail "Das Kommando '$command' wurde nicht gefunden."
done

gh auth status >/dev/null 2>&1 || fail "GitHub CLI ist nicht angemeldet. Zuerst 'gh auth login' ausführen."
git -C "$ROOT_DIR" diff --quiet || fail "Es gibt nicht committed Änderungen."
git -C "$ROOT_DIR" diff --cached --quiet || fail "Es gibt nicht committed Staging-Änderungen."
[[ -z "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard)" ]] ||
  fail "Es gibt unversionierte Dateien. Bitte vor dem Release committen oder entfernen."

BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"
[[ -n "$BRANCH" ]] || fail "Detached HEAD wird für Releases nicht unterstützt."
ORIGIN_URL="$(git -C "$ROOT_DIR" remote get-url origin)"
case "$ORIGIN_URL" in
  https://github.com/*) REPO="${ORIGIN_URL#https://github.com/}" ;;
  git@github.com:*) REPO="${ORIGIN_URL#git@github.com:}" ;;
  ssh://git@github.com/*) REPO="${ORIGIN_URL#ssh://git@github.com/}" ;;
  *) fail "origin muss auf ein GitHub-Repository zeigen, aktuell: $ORIGIN_URL" ;;
esac
REPO="${REPO%/}"
REPO="${REPO%.git}"
[[ "$REPO" == */* ]] || fail "Das Repository konnte nicht aus origin ermittelt werden: $ORIGIN_URL"

CURRENT_VERSION="$(node --input-type=module -e "import fs from 'node:fs'; console.log(JSON.parse(fs.readFileSync(process.argv[1], 'utf8')).version)" "$PACKAGE_DIR/package.json")"
VERSION="${1:-$CURRENT_VERSION}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] ||
  fail "Ungültige Version: $VERSION"
TAG="smartbox-v$VERSION"

if git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  fail "Der lokale Tag $TAG existiert bereits."
fi
if [[ -n "$(git -C "$ROOT_DIR" ls-remote --tags origin "refs/tags/$TAG")" ]]; then
  fail "Der Remote-Tag $TAG existiert bereits. Für einen neuen Build eine neue VERSION verwenden."
fi

printf '\nSmartbox-AI-Release\n'
printf '  Repository: %s\n' "$REPO"
printf '  Branch:     %s\n' "$BRANCH"
printf '  Version:    %s\n' "$VERSION"
printf '  Tag:        %s\n' "$TAG"

confirm 'Version veröffentlichen, Branch/Tag pushen und Native-Builds starten?' || {
  printf 'Release abgebrochen.\n'
  exit 0
}

if [[ "$VERSION" != "$CURRENT_VERSION" ]]; then
  npm --prefix "$PACKAGE_DIR" pkg set version="$VERSION"
  git -C "$ROOT_DIR" add -- apps/kimi-code/package.json
  git -C "$ROOT_DIR" commit -m "release: Smartbox AI $VERSION"
fi

COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
git -C "$ROOT_DIR" tag -a "$TAG" -m "Smartbox AI $VERSION" "$COMMIT"
git -C "$ROOT_DIR" push origin "$BRANCH"
git -C "$ROOT_DIR" push origin "refs/tags/$TAG"

printf '\n==> Workflow %s wird gestartet\n' "$WORKFLOW"
gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref "$BRANCH" \
  -f tag="$TAG" \
  -f version="$VERSION" \
  -f sha="$COMMIT"

RUN_ID=""
for _ in {1..15}; do
  RUN_ID="$(gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --branch "$BRANCH" \
    --event workflow_dispatch \
    --limit 20 \
    --json databaseId,headSha \
    --jq ".[] | select(.headSha == \"$COMMIT\") | .databaseId" | head -n 1)"
  [[ -n "$RUN_ID" ]] && break
  sleep 2
done
[[ -n "$RUN_ID" ]] || fail "Der gestartete Workflow wurde nicht gefunden. Prüfe die Actions-Seite von $REPO."

printf '==> Workflow-Lauf: %s\n' "https://github.com/$REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" --repo "$REPO" --exit-status

printf '\n==> Release veröffentlicht\n'
gh release view "$TAG" --repo "$REPO" --json url --jq '.url'
printf '\nLinux-Installation:\n'
printf '  curl -fsSL https://raw.githubusercontent.com/%s/main/scripts/install.sh | bash\n' "$REPO"
printf '\nWindows-Installation (PowerShell):\n'
printf '  irm https://raw.githubusercontent.com/%s/main/scripts/install.ps1 | iex\n' "$REPO"
