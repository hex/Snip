---
name: session-narrative-alex-geana-erepubliklabs-com
description: Session lab-notebook and work-in-progress narrative for alex-geana-erepubliklabs-com. Looser bar than durable memory. Read all narrative.*.md on resume.
metadata: 
  node_type: memory
  type: narrative
  originSessionId: 059b1701-d450-4e8b-b39e-ce4457595325
---

# Session narrative (alex-geana-erepubliklabs-com)

## 2026-07-09 — Brainstorming "Snip": macOS radial snippet inserter

**Product:** macOS app. Store text snippets; hold middle-mouse (or a hotkey) → a
radial pie menu blooms under the cursor → drag toward a wedge → release inserts the
snippet's text at the cursor of whatever app is frontmost. Aesthetic north star:
**CleanShot X** (frosted vibrancy panels, rounded, SF Pro, restrained accent, spring motion).

**Decisions locked (with the "why"):**
- **Scope:** real, eventually-paid product distributed OUTSIDE the Mac App Store
  (core feature needs Accessibility + global CGEventTap + synthetic input, all
  App-Store-forbidden). Still build a working personal-grade v1 first; layer
  Developer-ID signing + notarization + Sparkle auto-update + licensing after.
- **Trigger:** hold middle-mouse = hero interaction, PLUS a configurable keyboard
  hotkey fallback (trackpads have no middle button → don't cap the market). Both
  converge on one selection path: drag + release to fire; release at center = cancel.
- **Core UX direction — "The Eight + escape hatch" (Strategy C):** resolves the
  central tension (muscle memory needs FIXED positions vs. capacity needs many).
  Ring positions are sacred; the long tail lives behind a deliberate door.
  - v1: **The Eight** — up to 8 hand-pinned fixed slots; empty slots ghosted (also
    covers the 0/1-snippet + onboarding cases). Cheapest credible build.
  - v1.5: **The Well** — dwell on center → ring exhales into a small frosted search
    palette for the long tail. Same gesture, no second hotkey.
  - v2: **Chameleon** — "your Eight, per app" (frontmost-app detection ~free; spend
    is onboarding). The paid-tier differentiator. Deterministic, not re-ranked.
- **Rejected:** re-ranking rings (Orbit frecency / Sixth Sense prediction) — they
  sabotage the muscle memory that justifies a radial over a searchable list.
  Wildcard parked: **Inkstroke** (blind marking-menu compound strokes) — future
  throwaway prototype, unmatched demo if the recognizer can be trusted.

**Process notes:**
- "using Fable" = user wants the claude-fable-5 model involved. Chose HYBRID: I (Opus)
  drive the interactive brainstorm; dispatch Fable subagents for divergent idea bursts.
  Fable generated the 12 radial concepts (agentId ad2813401fb8b8742).
- Visual mockup artifact (CleanShot-flavored, 3 strategies side by side):
  https://claude.ai/code/artifact/5b5af153-cc7a-4aca-9dc1-5490c3db43c4
  source: scratchpad/snip-radial-mockups.html

**Resolved before spec:** content model = plain text + `{date}/{time}/{clipboard}` + `$|`
caret; insertion = paste-and-restore (changeCount-guarded); stack = AppKit shell + display-only
SwiftUI overlay (Option B, Fable-reviewed); persistence = Codable JSON.

**Artifacts committed (branch `design/snip-brainstorm`):**
- Spec: `docs/superpowers/specs/2026-07-09-snip-design.md`
- Plan: `docs/superpowers/plans/2026-07-09-snip-v1.md` (14 TDD tasks; SnipKit package + app target)

## 2026-07-09 (cont.) — Executing plan: SnipKit slice DONE

Chose to build the pure-logic package first (fully autonomous, no Team ID / Accessibility
needed). Structure: `SnipKit/` SwiftPM package (Foundation-only) tested via `swift test`.

**Done — plan Tasks 1,3–7, strict RED→GREEN, one commit each, 21 tests green:**
- `Snippet` / `SnippetLibrary` (Codable, schemaVersion)
- `SnippetStore` (atomic JSON, empty-when-missing, migrate hook)
- `TokenResolver` (tokens + grapheme-aware `$|`; `{time}` asserted by components to dodge
  ICU U+202F narrow-no-break-space before AM/PM)
- `RadialSession` (pointer→wedge, dead-zone, hysteresis)
- `ScreenGeometry` (Quartz↔Cocoa Y-flip + ring clamping)
- Toolchain: Swift 6.3.2 / macOS 26.5.1; `Package.swift` pinned to tools-version 5.9 (avoid
  strict-concurrency noise on injected closures). Run tests: `swift test --package-path SnipKit`.

**Remaining — plan Tasks 2, 8–14 (app target).** BLOCKED ON ALEX'S MACHINE:
needs `DEVELOPMENT_TEAM` id in project.yml, `brew install xcodegen`, granting Accessibility,
and manual end-to-end verification (watch snippets paste into TextEdit/Mail/VS Code). Not
autonomously completable. Order: XcodeGen project + menu-bar agent → AX smoke test →
overlay panel → EventTapEngine → PasteEngine → library/settings/onboarding.

