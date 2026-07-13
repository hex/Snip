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

Shipped a working, polished macOS app on branch `design/snip-brainstorm`, from a one-sentence
idea to a verified product.

**Core (all verified in-app):** menu-bar agent; hold middle mouse (or a hotkey, seam built) to
bloom a CleanShot-style frosted radial menu; drag+release inserts the snippet at the cursor of the
frontmost app via paste-and-restore with a `$|` caret marker and `{date}/{time}/{clipboard}` tokens.
Library window, per-app suppress list (running-apps picker), tabbed Settings, first-run
Accessibility onboarding.

**Architecture:** `SnipKit` SwiftPM package holds pure logic (models, radial geometry, token
resolver, JSON store, coordinate math), 25 unit tests green. Thin AppKit/SwiftUI app target
(`CGEventTap` on its own run loop, display-only non-activating overlay, `PasteEngine`).

**Signature UI:** a live **magnifying-glass loupe** in the ring's hub, real WindowServer
magnification via a private `CABackdropLayer` capture group (negative `zoom`) plus a
`displacementMap` `CAFilter` for barrel/edge distortion, with an elastic iris entry tuned against
the 12 animation principles. The ring floats over native-fullscreen apps.

**Notable debugging:** the loupe took several Fable-measured breakthroughs (CIFilters don't run on
a server-hosted backdrop; CAPortalLayer can't magnify a backdrop; the zoom law
`1/(1+scale·zoom)`); the fullscreen bug was `isFloatingPanel=true` silently resetting the window
level below the fullscreen app. Two lens claims were retracted after being made on misread
screenshots, the durable memories capture what actually works.

Design spec + implementation plan under `docs/superpowers/`. Deferred (spec, not bugs): v1.5
search palette, v2 per-app rings, notarization/Sparkle/licensing.
