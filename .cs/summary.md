# Session Summary: Snip

**Date:** 2026-07-09 to 2026-07-14 (multiple sittings)
**Duration:** ~5 days of intermittent work; 82 commits on `design/snip-brainstorm`

## Objective

Design and build **Snip**, a menu-bar macOS app that stores text snippets and inserts a chosen one at the cursor of the frontmost app through a radial (pie) menu: trigger the ring under the cursor, drag to a wedge, release to insert. It is meant as a paid product distributed outside the Mac App Store, with CleanShot X as the aesthetic reference.

By the final stretch (this conversation) the app was feature complete, so Alex shifted the goal from building features to unifying and polishing the visual language, then backing the work up off the machine.

## Environment

A macOS 14+ native app. The deployment target is macOS 14.0 even though it builds against the 26.5 SDK, a distinction that matters (see Key Discoveries). Logic lives in a `SnipKit` SwiftPM package (models, radial geometry, token resolver, JSON store, coordinate math) with 25 green unit tests; the app target is a thin AppKit shell (`LSUIElement` agent, `CGEventTap`, borderless `NSPanel` overlay) hosting SwiftUI. The project is generated with XcodeGen. It requires the Accessibility permission.

## Key Discoveries

- **The signal should follow the macOS system accent.** Earlier work had committed to a fixed "instrument azure" so Snip would read identically on every Mac. Alex reversed that: the one accent color now resolves to `NSColor.controlAccentColor`. This is a two-token change, because the hot core of the lit selection was a hardcoded light blue that would clash on any non-blue accent. The fix derives the core from the accent (lifted 65% toward white) so it always keeps the accent's hue. Verified on a pink-accent Mac, where no blue remains.
- **The settings "black bar" was stock-macOS chrome clashing with the custom window.** The Trigger and Exceptions panes used a grouped SwiftUI `Form`, whose opaque system-gray background respects the titlebar safe area. Inside the custom full-size-content HUD window (transparent titlebar, gradient background) that left a darker strip above the lighter form: the "bar." The Snippets tab, a bespoke view, never had it. Rebuilding the panes as custom views removed the bar and finished the visual language in one move.
- **The deployment floor blocks macOS 15 APIs.** `Color.mix(with:by:)` is macOS 15+, so it failed to compile at the 14.0 target despite being present in the 26.5 SDK. AppKit's `NSColor.blended(withFraction:of:)` and hand-drawn `Canvas` are the fallbacks. (Saved as durable memory.)
- **DRY has a limit at different render sizes.** Reusing the 18px menu-bar dial image as a large hub watermark made its strokes scale up thick, which read as "too obvious." A vector `Canvas` engraving keeps 1px hairlines at any footprint. There are now two deliberate dial drawings, one per context, and they should not be re-merged.
- **SourceKit reports phantom errors for this project.** Every build showed `No such module 'SnipKit'` and `Cannot find 'HUD'` errors because the local package is not resolved in the index; `xcodebuild` succeeded every time. (Saved as durable memory.)

## Changes Made

The visual-language pass, all on top of the shipped v1:

- **System accent signal** (`HUDTheme.swift`): `HUD.signal` points at the system accent; `HUD.signalCore` is derived from it toward white.
- **Detent settings restyle** (`SettingsView.swift`, `MainWindowView.swift`): replaced the grouped `Form`s with custom HUD views (chamber plates, hairline dividers, a machined-key segmented control, machined-key buttons). Promoted the section label and button treatment into shared components (`FieldLabel`, `MachinedKeyButtonStyle`) so `LibraryView` and the settings share one definition.
- **Menu-bar identity** (`AppDelegate.swift`): swapped the generic `text.insert` symbol for a purpose-drawn monochrome dial template that tints for light and dark bars.
- **Hub maker's mark** (`RingEditorView.swift`): iterated from a corner logo, to the hub center, to a large whisper-thin `Canvas` engraving on the hub boss, per Alex's feedback.
- **Menu cleanup** (`AppDelegate.swift`): "Grant Accessibility" and its divider now hide once the app is trusted, re-checked on each menu open.
- **Overlay legibility**: raised the overlay's lit-selection wash from 0.12 to 0.20 so it reads over arbitrary content.
- **Claude Design sync**: updated the claude.ai "Snip" design system to match. Rewrote five cards from the fixed azure to a `--signal` token equal to the system accent, with a multi-accent demonstration (a four-accent bearing strip in the palette card, four mini-dials in the dial card), and pushed them via DesignSync.
- **Backup**: the repo had no git remote, so I created a private GitHub repo `hex/Snip` and pushed both branches.

## Key Files & Outputs

- `Snip/UI/HUDTheme.swift`: the Detent tokens; `signal`/`signalCore` now accent-derived; added `FieldLabel` and `MachinedKeyButtonStyle`.
- `Snip/UI/SettingsView.swift`: Trigger and Exceptions panes rebuilt as custom HUD views (no `Form`).
- `Snip/UI/RingEditorView.swift`: the hub maker's mark (a faint `Canvas` dial).
- `Snip/AppDelegate.swift`: the dial menu-bar icon and the conditional "Grant Accessibility" item.
- `Snip/UI/MainWindowView.swift`, `Snip/UI/LibraryView.swift`: shared `FieldLabel`, sidebar accent, dropped redundant padding.
- Claude Design "Snip" project: `palette`, `dial`, `sidebar`, `editor`, `controls` cards updated.
- New durable memory: `project_snip-build-gotchas.md`, `reference_snip-repo.md`.

## Outcome

Snip is feature complete and now speaks one visual language (the Detent machined-instrument dark HUD) across every surface: the overlay, the ring editor, the settings, the sidebar, the menu-bar icon, and the maker's mark. The whole app follows the user's system accent. I verified everything live on a pink-accent Mac, and both branches are backed up at **https://github.com/hex/Snip** (private). I added 10 commits this conversation; the session totals 82.

## Notes for Future Reference

- Keep working on and pushing `design/snip-brainstorm`, not `main` (a 1-commit base). See `reference_snip-repo.md`.
- The deployment target is macOS 14.0; do not reach for 15.0+ APIs without raising the floor. See `project_snip-build-gotchas.md`.
- The signal is the system accent by design. Do not reintroduce a fixed brand color.
- Two dial drawings exist on purpose (the 18px AppKit menu-bar template and the hub `Canvas` hairline engraving). They render in different contexts and should stay separate.
- The status menu and any `NSMenu` cannot be styled to Detent; that is a platform limit.
- Deferred features by spec: a v1.5 search palette, v2 per-app rings, and notarization/Sparkle/licensing.
