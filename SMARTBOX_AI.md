# Smartbox-AI-Anpassungen

Dieses Repository enthält lokale Smartbox-AI-Anpassungen des Kimi-Code-Projekts. Die Web-UI-Quelle ist nicht Bestandteil dieses Repositorys. Ihre vorgebauten Dateien unter `apps/kimi-code/dist-web/` können durch ein `sync:web` aus code-app vollständig ersetzt werden.

Der ursprüngliche Stand der lokalen Anpassungen ist im Commit `7bdd32d3a` enthalten und kann mit `git show 7bdd32d3a` eingesehen werden.

## Dauerhafte Anpassungen außerhalb des Web-Bundles

Diese Änderungen liegen in den CLI-Quellen und werden durch `sync:web` nicht überschrieben:

- `apps/kimi-code/src/cli/sub/web/shared.ts`: Standardwert `webTitle: opts.webTitle ?? 'Smartbox AI'`
- `apps/kimi-code/src/cli/sub/web/run.ts`: Hilfetext für `--web-title`
- `apps/kimi-code/src/tui/components/chrome/welcome.ts`: `Welcome to Smartbox AI!`
- `apps/kimi-code/src/tui/easter-eggs/dance.ts`: animierte Variante des Begrüßungstextes
- `apps/kimi-code/test/cli/web/web.test.ts`: Tests für den Standard-Browsertitel
- `deploy.sh`: Build-, Paketierungs- und Installationsablauf

Nach einem upstream Merge müssen diese Stellen nur dann erneut angepasst werden, wenn dadurch ein Konflikt entstanden ist oder upstream die entsprechende Codestruktur geändert hat.

## Von `sync:web` betroffene Anpassungen

Nach jedem `sync:web` sind folgende beiden Bereiche zu prüfen.

### 1. Statischer HTML-Titel

In `apps/kimi-code/dist-web/index.html` muss lauten:

```html
<title>Smartbox AI</title>
```

### 2. Sichtbarer Sidebar-Text

Die Sidebar besitzt derzeit zwei Varianten. Beide müssen `Smartbox AI` anzeigen:

```js
w("span",{class:"ch-name"},"Smartbox AI",-1)
w("span",{class:"fup-ch-name"},"Smartbox AI",-1)
```

Der Dateiname und der Hash des JS-Bundles können sich bei jedem Sync ändern. Deshalb nicht nach dem bisherigen Dateinamen `index-Br2mYqjr.js` suchen, sondern nach den stabilen CSS-Klassen:

```bash
rg -n 'class:"(?:ch-name|fup-ch-name)"' apps/kimi-code/dist-web/assets/
```

Falls der Minifier oder die Web-UI die Darstellung verändert hat, müssen die Texte anhand der CSS-Klassen und der umgebenden Sidebar-Komponente zugeordnet werden. Nicht pauschal alle Vorkommen von `Kimi Code` ersetzen: Davon können auch Login-, Fehler-, OAuth- oder sonstige Produkttexte betroffen sein.

## Ablauf nach einem Sync oder upstream Merge

```bash
# Upstream-Änderungen holen und bei Bedarf mergen
git fetch upstream
git pull --no-rebase upstream main

# Optional: Web-Bundle aus einem passenden code-app-Checkout übernehmen
cd /pfad/zu/code-app
KIMI_CODE_REPO=/home/mark/git/kimi-code pnpm run sync:web
cd /home/mark/git/kimi-code

# Geänderte Dateien und Branding-Stellen prüfen
git status --short
rg -n 'Kimi Code|Smartbox AI' apps/kimi-code/dist-web/index.html
rg -n 'class:"(?:ch-name|fup-ch-name)"' apps/kimi-code/dist-web/assets/
```

Nach dem Nachpflegen der beiden Bereiche des Web-Bundles:

```bash
pnpm install --frozen-lockfile
pnpm build
pnpm -C apps/kimi-code smoke
pnpm -C apps/kimi-code exec vitest run test/cli/web/web.test.ts
pnpm -C apps/kimi-code exec vitest run test/tui/components/chrome/welcome.test.ts
git diff --check
```

Anschließend Kimi Web beziehungsweise die CLI neu starten. Falls sich der Dateiname des JS-Bundles nicht geändert hat, kann der Browser wegen des langen Asset-Cache weiterhin die alte Version anzeigen; dann einmal hart neu laden oder den Browser-Cache für die Seite leeren.

Vor dem Commit die Änderungen vollständig prüfen:

```bash
git status --short
git diff --stat
git diff -- apps/kimi-code/dist-web/index.html
git diff -- apps/kimi-code/dist-web/assets/
```

Keine generierten Deklarationsdateien unter `packages/agent-core-v2/src/` oder `test/` hinzufügen. Diese Build-Artefakte sind durch `.gitignore` ausgeschlossen.

## Native Releases und Remote-Installation

`release.sh` startet den Workflow `.github/workflows/smartbox-native-release.yml` im eigenen GitHub-Fork. Der Workflow baut native Pakete für Linux x64/ARM64 und Windows x64/ARM64 und veröffentlicht sie als GitHub Release. Die Binaries werden nicht in Git committed; im Repository liegen nur der Release-Ablauf und die Installer.

Voraussetzungen auf dem ausführenden Rechner:

- Git, Node.js, npm und curl,
- GitHub CLI (`gh`) mit erfolgreichem `gh auth login`,
- Schreibzugriff auf den Fork,
- ein sauberer Arbeitsbaum ohne unversionierte oder nicht committed Dateien.

Ein Release mit der aktuell in `apps/kimi-code/package.json` eingetragenen Version erzeugen:

```bash
./release.sh
```

Vorher die Version erhöhen und diese Versionsänderung automatisch committen:

```bash
./release.sh 2.6.3
```

Das Skript erzeugt den Tag `smartbox-v<VERSION>`, pusht Branch und Tag zu `origin`, startet den Workflow und wartet auf dessen Abschluss. Ein bereits vorhandener Tag wird abgelehnt, damit ein Release nicht versehentlich ersetzt wird. Auf Manjaro wird die GitHub CLI bei Bedarf mit `sudo pacman -S github-cli` installiert.

Nach erfolgreichem Release installieren Linux-Benutzer die neueste Version mit:

```bash
curl -fsSL https://raw.githubusercontent.com/mark-sch/kimi-code/main/scripts/install.sh | bash
```

Eine bestimmte Version installieren:

```bash
curl -fsSL https://raw.githubusercontent.com/mark-sch/kimi-code/main/scripts/install.sh | KIMI_VERSION=2.6.3 bash
```

Unter Windows in PowerShell:

```powershell
irm https://raw.githubusercontent.com/mark-sch/kimi-code/main/scripts/install.ps1 | iex
```

Eine bestimmte Windows-Version:

```powershell
$env:KIMI_VERSION = '2.6.3'
irm https://raw.githubusercontent.com/mark-sch/kimi-code/main/scripts/install.ps1 | iex
```

Beide Installer verwenden standardmäßig `~/.kimi-code/bin` beziehungsweise `%USERPROFILE%\.kimi-code\bin`, prüfen die SHA-256-Prüfsummen und ergänzen den Benutzer-PATH. `KIMI_INSTALL_DIR` ändert das Installationsverzeichnis; `KIMI_NO_MODIFY_PATH=1` verhindert die PATH-Änderung. Auf dem Zielrechner sind weder Node.js noch pnpm erforderlich.

Die Windows-Binaries werden ohne Authenticode-Signatur erzeugt; Windows SmartScreen kann deshalb eine Warnung anzeigen. Native Linux-Pakete setzen glibc voraus. Für Alpine/musl bleibt die npm-basierte Installation erforderlich.

Die One-Liner lesen ihre Skripte aus dem `main`-Branch. Deshalb müssen neue Installer- oder Release-Änderungen vor ihrer Verwendung committed und nach GitHub gepusht werden. Für eine reproduzierbare Installation des Installers selbst kann `main` in der URL durch einen Commit-SHA ersetzt werden.
