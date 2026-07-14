# Snip Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Snip to full distribution parity with Stash — public MIT repo, Sparkle auto-updates, notarized Developer ID releases, a `/release` command, a Homebrew cask, and a snip.hexul.com page — ending with the first public release, v2026.7.0.

**Architecture:** All app changes are `project.yml`-driven (XcodeGen generates Info.plist and the xcodeproj; never edit those directly). Sparkle is wired through a small `UpdaterController` owned by `AppDelegate` and passed down to the settings view. Release mechanics live in a `.claude/commands/release.md` command ported from Stash. The website lives in the separate `hexul.com` repo (Cloudflare Pages, subdomain-to-subdirectory worker).

**Tech Stack:** Swift 5.9 / SwiftUI + AppKit, XcodeGen, SwiftPM (SnipKit local package, Sparkle 2.6+), `notarytool` + `stapler`, GitHub Releases, Homebrew tap, Cloudflare Pages.

**Spec:** `docs/superpowers/specs/2026-07-14-snip-distribution-design.md`

## Global Constraints

- Deployment floor is **macOS 14.0** — no 15.0+ APIs (`project_snip-build-gotchas.md`). Appcast `minimumSystemVersion` is `14.0`; cask is `>= :sonoma`.
- `SWIFT_VERSION: "5.9"`, team `7G4UQW35EL`, bundle ID `ai.symbiotica.Snip` — all unchanged.
- Version for this release: display `2026.7.0`, build `2026071400` (`YYYYMMDDNN`, must increase every release; Sparkle compares the build number).
- **`project.yml` is the single source of truth.** After every `project.yml` change run `xcodegen generate`. `Snip/Info.plist` and `Snip.xcodeproj/` are generated and gitignored.
- Build: `xcodegen generate && xcodebuild -project Snip.xcodeproj -scheme Snip -configuration Debug -derivedDataPath ./DerivedData build`. SourceKit shows phantom `No such module 'SnipKit'` errors — ignore them; **xcodebuild is the truth**.
- Tests: `swift test --package-path SnipKit` (25 green today; must stay green).
- Tasks 1–5 commit to `design/snip-brainstorm`; Task 6 merges to `main`; everything after happens on `main`.
- **Do not commit `.cs/` changes from here on** (Task 6 untracks the directory; keep session notes uncommitted so no further session content enters soon-public history).
- New Swift files start with the two `// ABOUTME:` comment lines, matching the codebase.
- **Testing approach:** this is infrastructure work — SnipKit logic is untouched, and Sparkle's internals must not be mocked. Each task's gate is an executable check (build success, `codesign --verify`, notarization Accepted, `curl` assertions, `brew install`) instead of unit tests. The existing 25 SnipKit tests must stay green throughout.
- Two user gates, both via AskUserQuestion: release-notes approval (inside `/release`) and the repo-public flip (Task 6). Nothing is pushed to a public surface before its gate passes.

---

### Task 1: Sparkle plumbing (package, EdDSA key, feed keys, appcast skeleton, UpdaterController)

**Files:**
- Modify: `project.yml` (packages, target dependencies, info properties)
- Create: `Snip/UpdaterController.swift`
- Create: `appcast.xml`

**Interfaces:**
- Produces: `UpdaterController` — `@MainActor @Observable final class`; `init()`, `func checkForUpdates()`, `var automaticallyChecksForUpdates: Bool`. Task 2 consumes exactly these.

- [ ] **Step 1: Add the Sparkle package and dependency to `project.yml`**

In the `packages:` block add Sparkle below `SnipKit`, and add the dependency to the `Snip` target:

```yaml
packages:
  SnipKit:
    path: SnipKit
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
```

```yaml
    dependencies:
      - package: SnipKit
      - package: Sparkle
```

- [ ] **Step 2: Resolve packages to obtain Sparkle's key tools**

```bash
xcodegen generate
xcodebuild -project Snip.xcodeproj -resolvePackageDependencies -derivedDataPath ./DerivedData
ls DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/
```

Expected: `generate_keys`, `sign_update`, `generate_appcast` listed.

- [ ] **Step 3: Generate the Snip-specific EdDSA keypair**

```bash
KEYS=DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
"$KEYS" --account Snip
```

Expected: prints a base64 public key and stores the private key in the login Keychain under account `Snip`. Confirm retrievability: `"$KEYS" --account Snip -p` prints the same public key. (If this Sparkle build lacks `--account`, stop and raise with Alex — do NOT overwrite the default-account key, which is Stash's.)

- [ ] **Step 4: Add feed + key + version properties to `project.yml` `info.properties`**

```yaml
    info:
      path: Snip/Info.plist
      properties:
        LSUIElement: true
        CFBundleName: Snip
        CFBundleDisplayName: Snip
        CFBundleIconName: AppIcon
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        NSHumanReadableCopyright: ""
        SUFeedURL: https://raw.githubusercontent.com/hex/Snip/main/appcast.xml
        SUPublicEDKey: <the public key printed in Step 3>
```

(`SUPublicEDKey` is the runtime output of Step 3 — paste the printed base64 string.)

- [ ] **Step 5: Create the appcast skeleton at the repo root**

`appcast.xml`:

```xml
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
    <channel>
        <title>Snip</title>
        <link>https://raw.githubusercontent.com/hex/Snip/main/appcast.xml</link>
        <description>Snip radial snippet menu updates</description>
        <language>en</language>
    </channel>
</rss>
```

(The first `<item>` is inserted by the first `/release` run — Task 7.)

- [ ] **Step 6: Create `Snip/UpdaterController.swift`**

```swift
// ABOUTME: Wraps Sparkle's SPUStandardUpdaterController for menu-triggered and automatic update checks.
// ABOUTME: Exposes the auto-check flag as observable state for the settings toggle.
import Foundation
import Observation
@preconcurrency import Sparkle

@MainActor
@Observable
final class UpdaterController {
    @ObservationIgnored private let controller: SPUStandardUpdaterController

    /// Mirrors Sparkle's setting so SwiftUI observes changes; Sparkle persists the value itself.
    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
```

- [ ] **Step 7: Build and verify the generated plist**

```bash
xcodegen generate
xcodebuild -project Snip.xcodeproj -scheme Snip -configuration Debug -derivedDataPath ./DerivedData build
plutil -extract SUFeedURL raw Snip/Info.plist
plutil -extract SUPublicEDKey raw Snip/Info.plist
swift test --package-path SnipKit
```

Expected: build **succeeds**, both keys print, 25 tests pass.

- [ ] **Step 8: Commit**

```bash
git add project.yml Snip/UpdaterController.swift appcast.xml
git commit -m "feat: Sparkle plumbing — package, Snip EdDSA feed keys, appcast skeleton, UpdaterController"
git status --short   # verify nothing intended was left behind
```

---

### Task 2: Update UI hooks (menu item + settings toggle)

**Files:**
- Modify: `Snip/AppDelegate.swift` (property, menu construction ~lines 63–74, new selector, `MainWindowView(...)` call ~line 129)
- Modify: `Snip/UI/MainWindowView.swift` (new `updater` property, pass-through at line ~70)
- Modify: `Snip/UI/SettingsView.swift` (`TriggerSettingsView`: new property + Updates group)

**Interfaces:**
- Consumes: `UpdaterController` from Task 1 (`checkForUpdates()`, `automaticallyChecksForUpdates`).
- Produces: nothing consumed later; UI endpoints.

- [ ] **Step 1: Own and start the updater in `AppDelegate`**

Add the property alongside the other controllers (near line 48):

```swift
    private var updater: UpdaterController!
```

First line inside `applicationDidFinishLaunching` additions (before the menu is built):

```swift
        updater = UpdaterController()
```

- [ ] **Step 2: Add the menu item before Quit**

Between `menu.addItem(grantDivider)` and the Quit item:

```swift
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
```

And the selector with the other `@objc` actions:

```swift
    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }
```

- [ ] **Step 3: Thread the updater to the settings pane**

In `AppDelegate` where the window content is built (~line 129), add the argument:

```swift
            window.contentView = NSHostingView(rootView: MainWindowView(
                model: model,
                updater: updater,
                ...existing closures unchanged...
```

In `MainWindowView` (after `@Bindable var model: AppModel`):

```swift
    var updater: UpdaterController
```

and at the `TriggerSettingsView` construction (line ~70):

```swift
            TriggerSettingsView(model: model, updater: updater, onConfigChanged: onConfigChanged, onRecordingChange: onRecordingChange)
```

- [ ] **Step 4: Add the Updates group to `TriggerSettingsView`**

New property after `@Bindable var model: AppModel`:

```swift
    @Bindable var updater: UpdaterController
```

In `body`, after the `Text(footerText)...` block and before `Spacer(minLength: 0)`:

```swift
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("UPDATES")
                plateRow("Automatically check for updates") {
                    Toggle("", isOn: $updater.automaticallyChecksForUpdates)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .tint(HUD.signal)
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(HUD.chamber))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUD.hairline, lineWidth: 1))
            }
```

- [ ] **Step 5: Build, run, verify live**

```bash
xcodegen generate
xcodebuild -project Snip.xcodeproj -scheme Snip -configuration Debug -derivedDataPath ./DerivedData build
open DerivedData/Build/Products/Debug/Snip.app
```

Verify in the running app: (a) status menu shows "Check for Updates…"; clicking it produces a Sparkle dialog — **an "update feed" error is the expected outcome right now** (the raw URL is still private/404) and proves the wiring; (b) Settings → Trigger shows the UPDATES plate and the toggle flips and persists across relaunch.

- [ ] **Step 6: Commit**

```bash
git add Snip/AppDelegate.swift Snip/UI/MainWindowView.swift Snip/UI/SettingsView.swift
git commit -m "feat: Check for Updates menu item and auto-check settings toggle"
git status --short
```

---

### Task 3: Manual Developer ID signing + CalVer versions

**Files:**
- Modify: `project.yml` (target `settings.base`)

- [ ] **Step 1: Switch signing and versions in `project.yml`**

```yaml
        MARKETING_VERSION: "2026.7.0"
        CURRENT_PROJECT_VERSION: "2026071400"
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "Developer ID Application"
```

(replacing `MARKETING_VERSION: "0.1.0"`, `CURRENT_PROJECT_VERSION: "1"`, `CODE_SIGN_STYLE: Automatic`; `DEVELOPMENT_TEAM` and `ENABLE_HARDENED_RUNTIME` stay).

- [ ] **Step 2: Verify identity is present, then build**

```bash
security find-identity -p codesigning -v | grep "Developer ID Application"
xcodegen generate
xcodebuild -project Snip.xcodeproj -scheme Snip -configuration Debug -derivedDataPath ./DerivedData build
codesign -dv DerivedData/Build/Products/Debug/Snip.app 2>&1 | grep -E "Authority|flags"
plutil -extract CFBundleShortVersionString raw Snip/Info.plist
```

Expected: identity found; build succeeds; `Authority=Developer ID Application: Alexandru Geana (7G4UQW35EL)` and `runtime` flag; version prints `2026.7.0`.

- [ ] **Step 3: Commit**

```bash
git add project.yml
git commit -m "feat: Developer ID manual signing and CalVer 2026.7.0"
git status --short
```

---

### Task 4: LICENSE + README

**Files:**
- Create: `LICENSE`
- Create: `README.md`

- [ ] **Step 1: Create `LICENSE`** — standard MIT text, header lines:

```
MIT License

Copyright (c) 2026 hexul
```

(the remaining paragraphs are the canonical MIT text, byte-identical to `~/.claude-sessions/Stash/LICENSE` — copy that file and keep the same copyright line).

- [ ] **Step 2: Create `README.md`**

```markdown
<p align="center">
  <img src="snip-icon.png" width="128" alt="Snip icon">
</p>

<h1 align="center">Snip</h1>

<p align="center">
  A radial snippet menu for your Mac's menu bar.<br>
  Hold a trigger, drag to a wedge, release — the snippet lands at your cursor.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

---

## Features

- **Radial menu at the cursor** -- hold the trigger and a frosted ring blooms under the pointer; drag to a wedge and release to insert
- **Three trigger gestures** -- hold the middle button, hold a side/thumb button or keyboard shortcut, or double-click-and-hold a mouse button
- **Inserts into any app** -- paste-and-restore into the frontmost app, with your clipboard put back afterwards
- **Caret placement** -- put `$|` in a snippet and the cursor lands exactly there after insertion
- **Live tokens** -- `{date}`, `{time}`, and `{clipboard}` expand at insert time
- **Magnifying hub** -- the ring's center is a live loupe that magnifies whatever is behind the overlay
- **Works over fullscreen apps** -- the ring floats above native-fullscreen windows
- **Ring editor** -- arrange snippets on a visual dial in the library; drag positions to swap them
- **Per-app exceptions** -- suppress the trigger in apps that need the button (e.g. Blender's orbit)
- **Follows your accent** -- the entire UI keys off the system accent color
- **Auto-update** -- checks for updates via Sparkle, with one-click install from GitHub Releases

## Install

```sh
brew install --cask hex/tap/snip
```

Or [download the latest release](https://github.com/hex/Snip/releases/latest) from GitHub Releases. The app is Developer ID signed and notarized.

### Build from Source

**Prerequisites:**

| Requirement | Minimum |
|---|---|
| macOS | 14.0 (Sonoma) |
| Xcode | 16.0 |
| XcodeGen | 2.38 |

```sh
brew install xcodegen     # if not installed
xcodegen generate
open Snip.xcodeproj       # build and run with Cmd+R
```

Or from the command line:

```sh
xcodegen generate
xcodebuild -project Snip.xcodeproj -scheme Snip -configuration Debug build
```

## Usage

Snip lives in the menu bar. Set a trigger in Settings (default: hold the middle mouse button). Hold it anywhere, in any app: the ring opens under your cursor. Drag toward a wedge to light it up, release to insert that snippet at the cursor. Release in the middle to cancel.

Open **Snippets** from the menu bar icon to manage your library: edit text, assign snippets to ring positions on the dial, and drag positions to rearrange. **Settings** holds the trigger gesture, per-app exceptions, and update preferences.

## Permissions

Snip needs the **Accessibility** permission (System Settings → Privacy & Security → Accessibility) for two things:

- observing the trigger (a `CGEventTap` watches for your held button or shortcut)
- inserting text (a synthesized paste into the frontmost app)

Everything stays on your Mac: snippets are stored locally as JSON in `~/Library/Application Support/Snip/`, and the app sends no telemetry. The only network request Snip makes is the Sparkle update check against this repository.

## Architecture

```
CGEventTap (trigger gesture)
    |
EventTapEngine -- arm, detect hold/double-click, suppress per-app
    |
OverlayPanelController -- borderless non-activating panel, radial ring + loupe hub
    |
RadialGeometry (SnipKit) -- wedge hit-testing from drag vector
    |
PasteEngine -- token resolution, paste-and-restore, caret placement
```

Pure logic lives in the **SnipKit** SwiftPM package (models, radial geometry, token resolver, JSON store, coordinate math) with its own test suite. The app target is a thin AppKit shell (`LSUIElement` agent) hosting SwiftUI.

## Project Structure

```
Snip/
├── project.yml             # XcodeGen configuration (source of truth)
├── SnipKit/                # Pure-logic SwiftPM package + unit tests
├── Snip/
│   ├── AppDelegate.swift       # Status item, event tap, windows
│   ├── AppModel.swift          # Observable app state + persistence
│   ├── UpdaterController.swift # Sparkle auto-update integration
│   └── UI/                     # Ring overlay, library, settings (SwiftUI)
└── docs/                   # Design specs and plans
```

## Testing

```sh
swift test --package-path SnipKit
```

## Versioning

Snip uses calendar versioning: **YYYY.M.PATCH** (`2026.7.0` = first release of July 2026). The build number (`CFBundleVersion`) is date-encoded and monotonic; Sparkle compares it to decide when to offer updates.

## License

MIT
```

- [ ] **Step 3: Verify README file references**

```bash
ls snip-icon.png && rg -c "hex/Snip" README.md
```

Expected: icon exists at root (README references it), at least one repo link.

- [ ] **Step 4: Commit**

```bash
git add LICENSE README.md
git commit -m "docs: MIT license and README"
git status --short
```

---

### Task 5: `/release` command

**Files:**
- Create: `.claude/commands/release.md`

Port of Stash's command (`~/.claude-sessions/Stash/.claude/commands/release.md`) with the Snip deltas: version bump in `project.yml` (+ `xcodegen generate`), repo-root paths, tests preflight, min-OS 14.0/`:sonoma`, `sign_update --account Snip`, `Casks/snip.rb`.

- [ ] **Step 1: Create `.claude/commands/release.md` with exactly this content**

````markdown
---
allowed_tools:
  - Read
  - Edit
  - Grep
  - Glob
  - Bash
  - Task
  - AskUserQuestion
  - Skill
---

Release a new version of Snip (signed, notarized, with appcast + Homebrew tap update).

## Version Format

`YYYY.M.BUILD` where:
- `YYYY` = current year (4 digits)
- `M` = current month (1-2 digits, NO leading zero)
- `BUILD` = incrementing counter, resets each month

Source of truth: `project.yml` → `MARKETING_VERSION` (display) and `CURRENT_PROJECT_VERSION` (Sparkle's comparison number). `Snip/Info.plist` is GENERATED by XcodeGen — never edit it directly; run `xcodegen generate` after bumping. The `appcast.xml` and Homebrew cask are kept in sync from `project.yml`.

## Release Steps

### 1. Bump Version

Read `project.yml`. Calculate the new version:

```bash
YEAR=$(date +%Y)
MONTH=$(date +%-m)  # No leading zero
```

- If current `YYYY.M` matches today's `YYYY.M`: increment `BUILD` by 1.
- If current `YYYY.M` is older: reset to `YYYY.M.0`.

Update `MARKETING_VERSION` in `project.yml`.

Also set `CURRENT_PROJECT_VERSION` to a date-encoded monotonic build number: `YYYYMMDD` plus a 2-digit same-day counter (e.g. `2026071400`, increment the suffix for a second build the same day). This MUST increase on every release. Sparkle decides whether an update is available by comparing `CFBundleVersion` (carried in the appcast as `sparkle:version`); the display version is cosmetic. Then:

```bash
xcodegen generate
```

### 2. Pre-flight checks

Run these BEFORE any expensive work (build, notarize).

**(a) Clean working tree:**

```bash
git status
```

Stop if there are uncommitted changes that aren't part of the release. (`.cs/` session files are untracked and don't count.) If code changes ARE the release, commit them as feature commits first; the release commit should only contain `project.yml` + `appcast.xml`.

**(b) Tests + Release build:**

```bash
swift test --package-path SnipKit
```

All tests must pass. The Release build in step 4 doubles as the build check — but run it once here without signing if you want an early failure signal.

**(c) Pre-commit hook viability:**

```bash
ls .git/hooks/ | grep -v '\.sample$'
for hook in .git/hooks/pre-commit .git/hooks/post-merge .git/hooks/commit-msg; do
    [ -x "$hook" ] || continue
    bash "$hook" </dev/null >/dev/null 2>&1 && echo "ok: $hook" || echo "BROKEN: $hook (will block your commit)"
done
```

If a hook is broken AND not load-bearing, remove it; if load-bearing, fix it first.

**(d) Min-OS triplet alignment:**

```bash
PROJECT_TARGET=$(grep -A1 'deploymentTarget:' project.yml | grep -oE '[0-9]+\.[0-9]+')
echo "project.yml deployment target: $PROJECT_TARGET"

APPCAST_MIN=$(grep -m1 'sparkle:minimumSystemVersion' appcast.xml | grep -oE '[0-9]+\.[0-9]+')
echo "appcast latest item minimumSystemVersion: $APPCAST_MIN"

CASK_MIN_CODENAME=$(curl -s https://raw.githubusercontent.com/hex/homebrew-tap/master/Casks/snip.rb | grep -oE 'depends_on macos: ">= :[a-z]+"' | grep -oE ':[a-z]+' | tr -d ':')
echo "cask depends_on macos: :$CASK_MIN_CODENAME"
```

Codename map: `:sonoma` = 14, `:sequoia` = 15, `:tahoe` = 16. All three must map to the same major version (14 today). On the FIRST release the appcast has no items yet and the cask may not exist — skip the missing ones.

### 3. Run /simplify on uncommitted code

If the release includes code changes (not just a version bump), invoke the `/simplify` skill. Skip if version-only.

### 4. Build, Sign, Notarize, Staple

```bash
xcodegen generate

xcodebuild -project Snip.xcodeproj \
    -scheme Snip \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath DerivedData \
    build

APP_PATH="DerivedData/Build/Products/Release/Snip.app"

# Re-sign nested binaries (Sparkle's XPC services) with hardened runtime + secure timestamp
codesign --deep --force --options runtime --timestamp \
    --sign "Developer ID Application: Alexandru Geana (7G4UQW35EL)" \
    "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "/tmp/Snip-notarize.zip"
xcrun notarytool submit "/tmp/Snip-notarize.zip" \
    --key ~/.appstoreconnect/AuthKey_<NOTARY_KEY_ID>.p8 \
    --key-id <NOTARY_KEY_ID> \
    --issuer <NOTARY_ISSUER_ID> \
    --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
```

Stop on any failure. If rejected, `xcrun notarytool log <SUBMISSION_ID> --key ...` shows why.

### 5. Package the release zip

```bash
VERSION=$(grep -oE 'MARKETING_VERSION: "[0-9.]+"' project.yml | grep -oE '[0-9.]+')
ZIP_NAME="Snip-${VERSION}.zip"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_NAME"

unzip -l "$ZIP_NAME" | head
ZIP_SIZE=$(stat -f%z "$ZIP_NAME")
ZIP_SHA256=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')
echo "size=$ZIP_SIZE sha256=$ZIP_SHA256"
```

### 6. Sign the zip with Sparkle EdDSA

```bash
SIGN_TOOL=DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
ED_SIGNATURE=$("$SIGN_TOOL" --account Snip "$ZIP_NAME" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
echo "ed_signature=$ED_SIGNATURE"
```

The private EdDSA key lives in the macOS Keychain under account `Snip` (NOT the default `ed25519` account — that one is Stash's).

### 7. Update appcast.xml

Insert a new `<item>` at the top of `<channel>` in `appcast.xml`:

```xml
<item>
    <title>Version VERSION</title>
    <pubDate>RFC822_NOW</pubDate>
    <sparkle:version>BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>VERSION</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <enclosure url="https://github.com/hex/Snip/releases/download/vVERSION/Snip-VERSION.zip"
               length="ZIP_SIZE"
               type="application/octet-stream"
               sparkle:edSignature="ED_SIGNATURE" />
</item>
```

Substitutions:
- `VERSION` = the bumped `MARKETING_VERSION`
- `BUILD_NUMBER` = `CURRENT_PROJECT_VERSION` from `project.yml` (must match the built app and exceed the previous release's)
- `RFC822_NOW` = `date -u "+%a, %d %b %Y %H:%M:%S +0000"`
- `ZIP_SIZE` = from step 5
- `ED_SIGNATURE` = from step 6

`sparkle:minimumSystemVersion` matches the deployment target in `project.yml`.

### 8. Generate release notes and get approval

```bash
git fetch --tags origin 2>/dev/null
PREV_TAG=$(git tag --list 'v*' --sort=-version:refname | head -1)
git log "$PREV_TAG"..HEAD --oneline --no-merges
git diff --stat "$PREV_TAG"..HEAD
```

(First release: no previous tag — describe the product instead of a diff.) Group into **Features / Fixes / Performance & Polish / Other**. Draft markdown notes with `## What's Changed` and a `**Full Changelog**` link `https://github.com/hex/Snip/compare/vPREV...vNEW`.

Show via **AskUserQuestion**: **Approve** / **Edit**. DO NOT proceed past this gate without approval.

### 9. Commit + push

```bash
git add project.yml appcast.xml
git commit -m "Release v$VERSION"
git push
```

### 10. Create GitHub release

```bash
gh release create "v$VERSION" \
    --title "v$VERSION" \
    --notes "$(cat <<'EOF'
<approved release notes>
EOF
)" \
    "$ZIP_NAME"
```

### 11. Update Homebrew tap

The cask repo is `hex/homebrew-tap`, branch `master`:

```bash
TAP_DIR=$(mktemp -d)
gh repo clone hex/homebrew-tap "$TAP_DIR" -- --depth=1
cd "$TAP_DIR"

sed -i '' "s/version \"[^\"]*\"/version \"$VERSION\"/" Casks/snip.rb
sed -i '' "s/sha256 \"[^\"]*\"/sha256 \"$ZIP_SHA256\"/" Casks/snip.rb

grep -E 'version|sha256' Casks/snip.rb

git add Casks/snip.rb
git commit -m "snip: $VERSION"
git push
cd -
rm -rf "$TAP_DIR"
```

(First release: the cask file won't exist yet — create it per the distribution plan instead of sed-ing.)

### 12. Verify the release

```bash
curl -s https://raw.githubusercontent.com/hex/Snip/main/appcast.xml | head
curl -sI "https://github.com/hex/Snip/releases/download/v$VERSION/Snip-$VERSION.zip" | head
curl -s "https://raw.githubusercontent.com/hex/homebrew-tap/master/Casks/snip.rb" | head
```

## Important

- Notarization can take 30s–10min. Wait for it. Don't skip.
- The Developer ID cert is in the login keychain — `security find-identity -p codesigning -v` to confirm.
- The Sparkle EdDSA key is in the Keychain under account `Snip`. If lost, installed apps can no longer verify updates.
- `sparkle:minimumSystemVersion` must match the `project.yml` deployment target (14.0). Bumping the target requires updating appcast items AND the cask's `depends_on`.
- Do NOT commit or push until release notes are approved.
- The website (`hexul.com/snip/index.html`) does NOT need a per-release update — its version pill is the minimum supported macOS, not the app version.
- The release is reversible up to step 9. After step 10, it's public.
````

- [ ] **Step 2: Do NOT commit — local-only, like Stash**

The command embeds App Store Connect account identifiers (notary key-id, issuer UUID) and the Developer ID cert name. Stash's public-visibility prep gitignored all of `.claude/` so its `/release` lives on disk, never in the public repo. Match that: the file stays on disk (created via Write, fully functional), and Task 6 gitignores `.claude/` wholesale. Nothing to commit here.

---

### Task 6: Public-visibility prep, merge to main, flip public (GATED)

**Files:**
- Modify: `.gitignore`
- Untrack (files stay on disk): all of `.cs/` (11 files), `CLAUDE.md`

- [ ] **Step 1: Rewrite the session/secrets section of `.gitignore`**

Replace the current narrow entries (`.cs/local/`, `.cs/archives/`, `.cs/.narrative-reminder-cooldown`, `.claude/settings.local.json`) with:

```
# Development session artifacts
.cs/
.claude/
CLAUDE.md
AGENTS.md

# Secrets and credentials
*.key
*.pem
*.p12
*.p8
*.cer
.env

# Release artifacts
Snip-*.zip
```

(keep every other existing section: transient files, build artifacts, generated `Snip/Info.plist` + `Snip/Snip.entitlements` + `Snip.xcodeproj/`, OS files, editor config. `.claude/` is ignored wholesale — matching Stash, so the `/release` command and its embedded ASC account identifiers stay on disk, out of the public repo.)

- [ ] **Step 2: Untrack session files**

```bash
git rm -r --cached .cs CLAUDE.md
git add .gitignore
git commit -m "Prepare repo for public visibility"
git status --short   # expect: .cs/ and CLAUDE.md now untracked-but-present, tree otherwise clean
```

- [ ] **Step 3: Merge to main and push**

```bash
git checkout main
git merge design/snip-brainstorm
git push origin main design/snip-brainstorm
git log --oneline -3
```

Expected: merge succeeds (fast-forward or clean merge; the design branch grew from main's single commit). `main` now carries everything.

- [ ] **Step 4: GATE — confirm the public flip with Alex**

AskUserQuestion: "hex/Snip is prepped (MIT, session files untracked). Flip it public now? This is the irreversible step." Options: **Flip public** / **Hold**. Do not proceed on Hold.

- [ ] **Step 5: Flip visibility and set homepage**

```bash
gh repo edit hex/Snip --visibility public --accept-visibility-change-consequences
gh repo edit hex/Snip --homepage "https://snip.hexul.com"
gh repo view hex/Snip --json visibility -q '.visibility'
curl -s https://raw.githubusercontent.com/hex/Snip/main/appcast.xml | head -5
```

Expected: `PUBLIC`; the appcast skeleton is now publicly fetchable (this also makes the in-app "Check for Updates" report "up to date" instead of a feed error).

---

### Task 7: First release — v2026.7.0

Execute `.claude/commands/release.md` (Task 5) from `main`, top to bottom. First-release specifics:

- [ ] **Step 1: Version** — `project.yml` already says `2026.7.0` / `2026071400` (Task 3). If today's date differs from 2026-07-14, re-encode `CURRENT_PROJECT_VERSION` accordingly.
- [ ] **Step 2: Pre-flights** — tests green; tree clean; hooks ok; triplet check will find no appcast item and no cask yet (expected on first release).
- [ ] **Step 3: Build → sign → notarize → staple** per command step 4. Expected: `codesign --verify` clean; notarytool status **Accepted**; `stapler validate` ok. Also run `spctl -a -t exec -vv DerivedData/Build/Products/Release/Snip.app` — expect `accepted`, `source=Notarized Developer ID`.
- [ ] **Step 4: Zip + EdDSA sign** per command steps 5–6 (record `ZIP_SIZE`, `ZIP_SHA256`, `ED_SIGNATURE`).
- [ ] **Step 5: Appcast item** per command step 7 (first `<item>` in the channel).
- [ ] **Step 6: Release notes gate.** Draft for v2026.7.0 (initial release — describe the product):

```markdown
## What's Changed

Initial public release.

- Radial snippet menu: hold your trigger, drag to a wedge, release to insert at the cursor
- Three trigger gestures: hold middle button, hold a key/side button, or double-click-and-hold
- Live loupe hub that magnifies content behind the ring; works over fullscreen apps
- Snippet library with a visual ring editor; `$|` caret marker and `{date}`/`{time}`/`{clipboard}` tokens
- Per-app exceptions, system-accent UI, Sparkle auto-updates

**Full Changelog**: https://github.com/hex/Snip/commits/v2026.7.0
```

Present via AskUserQuestion (Approve / Edit) before any push.
- [ ] **Step 7: Commit `project.yml` + `appcast.xml` as `Release v2026.7.0`, push, `gh release create v2026.7.0` with the zip** (command steps 9–10).
- [ ] **Step 8: Verify** — command step 12 curls: appcast shows the item; the zip URL returns `HTTP/2 302` (GitHub asset redirect).

---

### Task 8: Homebrew cask + brew end-to-end

**Files:**
- Create: `Casks/snip.rb` in `hex/homebrew-tap` (branch `master`)

- [ ] **Step 1: Create the cask** (via depth-1 clone into a temp dir, as in the command's step 11):

```ruby
cask "snip" do
  version "2026.7.0"
  sha256 "<ZIP_SHA256 recorded in Task 7 Step 4>"

  url "https://github.com/hex/Snip/releases/download/v#{version}/Snip-#{version}.zip"
  name "Snip"
  desc "Radial snippet menu for the macOS menu bar"
  homepage "https://snip.hexul.com"

  depends_on macos: ">= :sonoma"

  app "Snip.app"

  zap trash: [
    "~/Library/Application Support/Snip",
    "~/Library/Preferences/ai.symbiotica.Snip.plist",
  ]
end
```

Commit message: `snip: add cask (2026.7.0)`; push to `master`.

- [ ] **Step 2: End-to-end install on this machine**

```bash
# quit the dev build first so two instances don't double the event tap
osascript -e 'tell application "Snip" to quit' 2>/dev/null || true
brew update
brew install --cask hex/tap/snip
spctl -a -t exec -vv /Applications/Snip.app
open /Applications/Snip.app
```

Expected: install succeeds; `accepted` + `source=Notarized Developer ID`; app launches with no Gatekeeper dialog; menu-bar dial appears; "Check for Updates…" reports **"You're up to date!"** (this proves feed fetch + EdDSA chain end-to-end).

---

### Task 9: Website — snip.hexul.com

**Files (all in `~/.claude-sessions/hexul.com`, a separate clean git repo):**
- Create: `snip/index.html`, `snip/icon.png`, `snip/privacy/index.html`
- Modify: `_worker.js` (SUBDOMAIN_MAP), `index.html` (product card), `sitemap.xml`

At execution, invoke the **frontend-design** skill for the page's visual pass. Constraints: single-file page like `stash/index.html` (inline CSS, no build step); Snip's Detent aesthetic (near-black machined dark, hairline strokes, `#0a84ff`-family accent used sparingly as a lit edge, monospace-flavored labels); an inline-SVG ring mockup (8 wedge ring, one lit wedge, hub circle) instead of Stash's clipboard mockup rows. **Do NOT copy Stash's "Ad-hoc signed / right-click to Open" note — Snip is notarized.**

- [ ] **Step 1: Copy the icon** — `cp ~/.claude-sessions/Snip/snip-icon.png snip/icon.png` (plus favicon reuse of site defaults).

- [ ] **Step 2: Build `snip/index.html`** with these sections and copy (structure mirrors `stash/index.html`: layered background, `main.page`, intro, mockup, desc, install, features grid, footer):
  - Intro: `<h1>Snip</h1>`, badge `macOS 14+`, tagline "A radial snippet menu for your menu bar."
  - Mockup: inline SVG dial — outer ring, 8 wedge separators, one wedge filled with the accent at low opacity + lit edge, hub circle with a faint engraving stroke.
  - Desc: "Snip waits in your menu bar. Hold your trigger — middle mouse, a thumb button, or a shortcut — and a ring of snippets blooms under the cursor. Drag to a wedge, release, and the text lands at your cursor in whatever app you're in. Tokens like `{date}` and `{clipboard}` fill in as they land."
  - Install: `$ brew install --cask hex/tap/snip` + "Or download directly from GitHub Releases." linking `https://github.com/hex/Snip/releases/latest` + note "Developer ID signed and notarized."
  - Features grid (6): Radial insert · Three trigger gestures · Live loupe hub · Ring editor · Caret + tokens · Per-app exceptions.
  - Footer: links to GitHub repo, privacy page, hexul.com.

- [ ] **Step 3: Build `snip/privacy/index.html`** — same visual family, one screen of copy: snippets stored locally as JSON in `~/Library/Application Support/Snip/`; no telemetry, no analytics, no accounts; the only network call is the Sparkle update check against `raw.githubusercontent.com/hex/Snip`; Accessibility permission is used solely to observe the trigger gesture and synthesize the paste.

- [ ] **Step 4: Wire routing + listings**

`_worker.js` — add to `SUBDOMAIN_MAP`:

```js
  'snip': '/snip',
```

`index.html` — add a product card in the products grid (before or after Stash, matching sibling markup):

```html
            <a href="https://snip.hexul.com" class="product">
                <span class="icon-glass"><img src="snip/icon.png" alt="Snip" class="product-icon" width="44" height="44"></span>
                <div class="product-info">
                    <span class="product-name">Snip</span>
                    <span class="product-desc">Radial snippet menu</span>
                </div>
                <span class="product-platform"><svg viewBox="0 0 640 512" aria-label="macOS" style="width:16px;height:13px"><path d="M128 32C92.7 32 64 60.7 64 96v256c0 35.3 28.7 64 64 64h144v32H192c-17.7 0-32 14.3-32 32s14.3 32 32 32h256c17.7 0 32-14.3 32-32s-14.3-32-32-32H368v-32h144c35.3 0 64-28.7 64-64V96c0-35.3-28.7-64-64-64H128zm0 64h384v256H128V96z"/></svg></span>
            </a>
```

`sitemap.xml` — add `<url>` entries for `https://snip.hexul.com` and `https://snip.hexul.com/privacy/` matching the Stash entries' shape.

- [ ] **Step 5: Commit + push + verify deploy**

```bash
cd ~/.claude-sessions/hexul.com
git add snip _worker.js index.html sitemap.xml
git commit -m "Add Snip product page at snip.hexul.com"
git push
# after the Pages deploy settles (~1-2 min):
curl -sI https://snip.hexul.com | head -3
curl -s https://snip.hexul.com | rg -c "Snip"
```

Expected: `HTTP/2 200`. **If DNS/SSL fails:** `snip.hexul.com` needs a custom-domain entry in the Cloudflare Pages project — no API token in this env, so hand Alex the exact dashboard step (Pages project → Custom domains → add `snip.hexul.com`) and re-verify after.

---

### Task 10: Wrap-up (docs, memory, session notes)

- [ ] **Step 1: Update durable memory** — `.cs/memory/reference_snip-repo.md` currently says work lives on `design/snip-brainstorm`, not `main`; now false. Rewrite: repo is public, `main` is the release branch, releases via `/release`, Sparkle key in Keychain account `Snip`, cask `hex/tap/snip`, site `snip.hexul.com`. Update `MEMORY.md` hook line to match.
- [ ] **Step 2: Session docs** — update `.cs/README.md` outcome + append the release record to the narrative (uncommitted — `.cs/` is untracked now).
- [ ] **Step 3: Final checklist** — confirm each: repo PUBLIC with LICENSE + README rendering; release v2026.7.0 with zip asset; appcast serving one item; `brew install --cask hex/tap/snip` works; snip.hexul.com live; in-app "Check for Updates" says up-to-date; SnipKit tests green.
- [ ] **Step 4: Offer /wrap** to Alex (session wrap-up cue: "released" is a strong signal).
