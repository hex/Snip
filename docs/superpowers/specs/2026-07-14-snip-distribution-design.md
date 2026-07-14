# Snip Distribution — Design

**Date:** 2026-07-14
**Status:** Approved by Alex (direction, scope, and design confirmed in session)
**Reference implementation:** Stash (`hex/Stash`, `~/.claude-sessions/Stash`)

## Goal

Bring Snip to full distribution parity with Stash: a public, MIT-licensed GitHub
repo with Sparkle auto-updates, Developer ID signed + notarized releases, a
`/release` slash command, a Homebrew cask, a README, and a page on hexul.com.
The pass ends with Snip's first public release, **v2026.7.0**, installable via
`brew install --cask hex/tap/snip`.

## Decisions (with rationale)

| Decision | Choice | Why |
|---|---|---|
| Distribution model | Public + free, MIT | Alex's call; supersedes the v1 spec's "paid product" plan. Licensing/trial work is **dropped, not deferred**. |
| Release branch | `main` (merge `design/snip-brainstorm` in) | Matches Stash; appcast raw URL points at `main`. |
| Git history | No rewrite; untrack session files going forward | Same trade-off Stash accepted publicly. Only session notes/timeline are tracked; `.cs/local/` (command log) never was. |
| Sparkle key | New EdDSA keypair, Keychain account `Snip` (`generate_keys --account Snip`) | Key isolation: losing or leaking one app's key must not break the other's update chain. |
| Version scheme | CalVer `YYYY.M.PATCH` display + date-encoded `CFBundleVersion` (`YYYYMMDDNN`) | Stash parity. Sparkle compares `CFBundleVersion`; the display string is cosmetic. |
| Version source of truth | `project.yml` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`) | Snip's Info.plist is XcodeGen-generated (unlike Stash's hand-maintained one). The `/release` command edits `project.yml`, never Info.plist. |
| Deployment floor | Stays macOS 14.0 | Existing constraint (`project_snip-build-gotchas.md`). Appcast `minimumSystemVersion` 14.0, cask `>= :sonoma`. |
| Bundle ID | Stays `ai.symbiotica.Snip` | No reason to churn; cask `zap` paths use it. |
| `docs/superpowers/` | Stays public | Good engineering docs; nothing sensitive. |

## Non-goals

- No history rewrite / filter-repo scrub.
- No change to deployment target, bundle ID, Swift version, or app features
  beyond the Sparkle UI hooks.
- No paid licensing, trials, or storefront.
- No CI; releases run locally via `/release`, as with Stash.

## Workstreams

### 1. Repo promotion + public prep (`hex/Snip`)

1. Merge `design/snip-brainstorm` into `main` (plain `git merge`;
   fast-forward is fine since `main` is an ancestor); `main` is the release
   branch from here on.
2. "Prepare repo for public visibility" commit, mirroring Stash `688512b`:
   - `git rm --cached` the tracked `.cs/` files (11), `.claude/`, `CLAUDE.md`
     (files remain on disk).
   - Extend `.gitignore`: `.cs/`, `.claude/`, `CLAUDE.md`, `AGENTS.md`,
     secrets (`*.key`, `*.pem`, `*.p12`, `*.p8`, `*.cer`, `.env`), and
     `Snip-*.zip`.
3. Flip visibility: `gh repo edit hex/Snip --visibility public` — **only after
   an explicit in-the-moment confirmation from Alex**. This is the single
   irreversible step; everything before it is local.

### 2. LICENSE + README

- `LICENSE`: MIT, same text as Stash's (copyright Alexandru Geana).
- `README.md`, Stash-shaped: centered `snip-icon.png`, one-line description,
  badges (macOS 14+, Swift 5.9, MIT), Features, Install (brew cask first,
  build-from-source with XcodeGen), Usage (trigger gestures, ring, library,
  settings), **Permissions** section explaining why Accessibility is required
  (event tap + paste; Snip's analog of Stash's Privacy section — all data
  local, no telemetry), Architecture (SnipKit package + thin AppKit shell,
  ASCII flow diagram), Project Structure, Testing
  (`swift test --package-path SnipKit`), Versioning (CalVer), License.

### 3. Sparkle integration (app)

- `project.yml`:
  - Add package `Sparkle: { url: https://github.com/sparkle-project/Sparkle, from: "2.6.0" }`
    and the dependency on the `Snip` target.
  - `info.properties` additions:
    - `SUFeedURL: https://raw.githubusercontent.com/hex/Snip/main/appcast.xml`
    - `SUPublicEDKey: <public key from the new Snip keypair>`
- New EdDSA keypair via Sparkle's `generate_keys --account Snip`; private key
  lives in the macOS Keychain under account `Snip`. If the bundled
  `generate_keys` lacks `--account`, fall back to exporting/importing a
  dedicated key file kept out of the repo — but 2.6+ supports accounts.
- `UpdaterController` wrapper in the app target: same minimal shape as
  Stash's (`SPUStandardUpdaterController`, `checkForUpdates()`,
  `automaticallyChecksForUpdates`).
- UI hooks:
  - "Check for Updates…" item in the status-bar menu (`AppDelegate`),
    above Settings/Quit.
  - "Automatically check for updates" toggle: a new **Updates** field group at
    the bottom of the Trigger settings pane, using the existing Detent
    components (`FieldLabel`, chamber plate, hairline dividers).
- `appcast.xml` at the repo root: created as an empty channel (title, link to
  its own raw URL, description) during integration; the first `/release` run
  inserts the v2026.7.0 `<item>` with `sparkle:minimumSystemVersion` **14.0**.

### 4. Signing + versioning (`project.yml`)

- `CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "Developer ID Application"`
  (team `7G4UQW35EL`, cert already in the login keychain). Hardened runtime is
  already enabled; the app already runs under it, so no new runtime surprises.
- `MARKETING_VERSION: "2026.7.0"`, `CURRENT_PROJECT_VERSION: "2026071400"`
  (date-encoded + 2-digit same-day counter; MUST increase every release).

### 5. `/release` command (`.claude/commands/release.md`)

Port Stash's 12-step pipeline with these adaptations:

| Aspect | Stash | Snip |
|---|---|---|
| Version bump target | `Stash/Stash/Info.plist` | `project.yml` (`MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`), then `xcodegen generate` |
| Project location | nested `Stash/` dir | repo root |
| Min-OS triplet | 15.0 / `:sequoia` | 14.0 / `:sonoma` |
| Sparkle signing | default keychain key | `sign_update --account Snip` |
| Cask | `Casks/stash.rb` | `Casks/snip.rb` |
| Tests preflight | none (gap in Stash's command) | **added:** `swift test --package-path SnipKit` + Release build before any signing/notarization |

Unchanged: pre-flight checks (clean tree, hook viability, min-OS triplet),
notarization via `notarytool` with the ASC key at
`~/.appstoreconnect/AuthKey_<NOTARY_KEY_ID>.p8`, stapling, `ditto` zip, appcast
insertion, release-notes **approval gate before any push**, GitHub release,
tap update, post-release curl verification.

### 6. First release: v2026.7.0

Run the new `/release` flow end-to-end after the repo is public. Release notes:
initial public release + feature list. Order matters: public flip **before**
the GitHub release, so enclosure/appcast URLs resolve.

### 7. Homebrew cask (`hex/homebrew-tap`)

`Casks/snip.rb`, modeled on `stash.rb`: `version`, `sha256`, GitHub download
URL, `name "Snip"`, `desc "Radial snippet menu for the macOS menu bar"`,
`homepage "https://snip.hexul.com"`,
`depends_on macos: ">= :sonoma"`, `app "Snip.app"`, `zap trash` with Snip's
real data paths (verify at implementation time where the JSON store and
preferences live under `ai.symbiotica.Snip`).

### 8. Website (`hexul.com` repo)

- `snip/index.html`: single-file page modeled on `stash/index.html`'s
  structure but in Snip's Detent machined-dark aesthetic (system-accent
  signal, hairlines, machined keys). Download button → latest GitHub release
  zip; brew one-liner; feature grid; icon.
- `snip/icon.png` (from the repo's `snip-icon.png`).
- `snip/privacy/index.html`: all-local, no telemetry, why Accessibility.
- `_worker.js`: add `'snip': '/snip'` to `SUBDOMAIN_MAP`.
- Main `index.html`: Snip product card in the products grid; `sitemap.xml`
  entries for `snip.hexul.com` and its privacy page.
- **Open item:** `snip.hexul.com` may need a custom-domain entry in Cloudflare
  Pages if no wildcard exists. No Cloudflare API token in this environment —
  if required, Alex adds it in the dashboard (verify with `curl` after deploy).

## Verification

- `swift test --package-path SnipKit` green (25 tests).
- Release build succeeds with Manual Developer ID signing.
- `codesign --verify --deep --strict --verbose=2` passes.
- Notarization status **Accepted**; `stapler validate` passes;
  `spctl -a -vv` says accepted / Notarized Developer ID.
- `curl` checks: appcast raw URL, release zip download URL, cask raw URL.
- End-to-end: `brew install --cask hex/tap/snip` on this machine, launch, then
  Sparkle "Check for Updates" reports up-to-date — this exercises feed fetch,
  parse, and the EdDSA trust chain. The *upgrade* path proves itself at the
  second release (first release has no prior version to update from).

## Risks

- **Public flip is irreversible.** Gated on explicit confirmation.
- **Old session notes stay in history.** Accepted (Stash precedent). If Alex
  ever changes his mind, a filter-repo scrub + force-push is possible while
  the audience is still zero.
- **Sparkle key custody.** If the Keychain `Snip` EdDSA key is lost, shipped
  apps can no longer verify updates. Same custody rule as Stash's key.
- **Notarization rejections** surface via `xcrun notarytool log`; usual causes
  are unsigned nested binaries (Sparkle's XPC services — `--deep` re-sign
  handles them, as in Stash's flow) or hardened-runtime violations.
- **Cloudflare subdomain** may need manual dashboard work (no API token here).
