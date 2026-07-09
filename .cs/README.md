---
status: active
created: 2026-07-09
tags: []
aliases: ["Snip"]
---
# Session: Snip

**Started:** 2026-07-09 11:01:50
**Location:** erp-alexgeana-mac:/Users/alex.geana/.claude-sessions/claude-sessions

## Objective

Design and build **Snip**, a menu-bar macOS app that stores text snippets and inserts a
chosen snippet at the cursor of the frontmost app via a **radial (pie) menu** triggered by
holding the middle mouse button (or a keyboard hotkey): press → ring blooms under the cursor
→ drag to a wedge → release to insert. Aesthetic north star: CleanShot X. Intended as a real,
eventually-paid product (distributed outside the Mac App Store).

Current phase: **v1 feature complete**. Spec: `docs/superpowers/specs/2026-07-09-snip-design.md`.
Plan: `docs/superpowers/plans/2026-07-09-snip-v1.md` (all 14 tasks done). Branch:
`design/snip-brainstorm`. Build: `xcodegen generate && xcodebuild -project Snip.xcodeproj -scheme
Snip -configuration Debug -derivedDataPath ./DerivedData build`. Tests: `swift test --package-path
SnipKit` (25 green).

## Environment

macOS 14+ native app. Swift, AppKit shell (`LSUIElement` menu-bar agent + `CGEventTap` +
borderless `NSPanel` overlay) hosting SwiftUI content; `Codable` JSON persistence. Requires the
Accessibility permission. Greenfield repo, no app code yet at design time.

## Outcome

[To be filled when session is complete - summarize what was accomplished]
