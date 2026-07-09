# Snip — Design Spec

- **Status:** Approved (brainstorm complete) — ready for implementation planning
- **Date:** 2026-07-09
- **Author:** Alex + Claude (Opus 4.8), with divergent ideation and an architecture review by Fable (claude-fable-5)
- **Platform:** macOS 14 (Sonoma) and later, Apple Silicon + Intel

---

## 1. Summary

**Snip** is a menu-bar macOS app for inserting saved text snippets into any app. The
signature interaction is a **radial (pie) menu**: the user holds the middle mouse button
(or a configurable keyboard hotkey), a frosted menu blooms under the cursor, they drag
toward a wedge and release, and the chosen snippet's text is inserted at the text cursor
of whatever app is frontmost.

The distinctive value versus existing snippet tools (Raycast, Alfred, TextExpander,
Espanso — all list/search based) is **spatial muscle memory**: because ring positions are
fixed, the hand learns "snippet 3 is up-left" and stops reading, making insertion faster
than any search box.

**Aesthetic north star:** CleanShot X — translucent `NSVisualEffectView` vibrancy panels,
generous rounded corners, soft ambient shadows, SF Pro, a restrained accent color, buttery
spring micro-animations, menu-bar-first, near-zero chrome; the overlay always feels like it
floats *above* the work.

---

## 2. Scope & Distribution

- **A real, eventually-paid product**, distributed **outside the Mac App Store**. The core
  feature depends on a global `CGEventTap`, the Accessibility permission, and synthetic
  input — all of which are forbidden in the App Store sandbox. The App Store is therefore
  permanently off the table for the core feature; this is a deliberate, accepted constraint.
- **Build order:** ship a working *personal-grade* v1 first (the hard technical core is
  identical regardless of distribution), then layer product concerns without a rewrite:
  Developer ID signing + notarization, Sparkle auto-update, licensing/payments, a website.
- **Proposed bundle identifier:** `ai.symbiotica.Snip` (revisable).

---

## 3. Core Interaction

### Trigger (two, converging on one selection path)
- **Primary — hold the middle mouse button.** The hero gesture; mouse users only.
- **Fallback — hold a configurable keyboard hotkey.** Trackpad-only users (a large share of
  the paying market) have no middle button, so a keyboard trigger is required for reach.
  Prefer a key-plus-modifier chord over a bare modifier hold (cleaner to consume; avoids the
  synthetic-modifier contamination problem — see §12).
- Both triggers are configurable in Settings.

### Gesture (the pie menu)
- **Press** (and hold) → the ring **blooms** under the cursor (target: sub-300 ms perceived).
- **Drag** toward a wedge → that wedge highlights (with boundary hysteresis so it doesn't
  flicker along a seam).
- **Release** over a wedge → **fire** (insert). **Release inside the center dead-zone**
  (~24 pt radius) → **cancel**. **Escape** → cancel.
- The gesture is one continuous motion (release-to-select), which is what builds muscle memory.
- Perceptual ceiling: ~8 wedges before slices get too thin to aim reliably (Fitts's Law).

---

## 4. UX Direction & Roadmap

Chosen strategy: **"The Eight" + escape hatch** — fixed ring positions are sacred; the long
tail lives behind a deliberate door. This was chosen over (a) *geometry-carries-scale*
(nested/concentric rings) and (b) *intelligence-carries-scale* (frecency/predicted re-ranking).
Re-ranking the ring was explicitly **rejected** because it destroys the muscle memory that
justifies a radial menu over a search box in the first place.

| Milestone | Feature | Rationale |
|---|---|---|
| **v1** | **The Eight** — up to 8 hand-pinned fixed slots in one ring; empty slots render as ghosted affordances (also covers the 0/1-snippet and onboarding cases). | Cheapest credible build; sacred muscle memory; cleanest CleanShot look. |
| **v1.5** | **The Well** — dwell on the ring's center → the ring exhales into a small frosted search palette for the full library. Same gesture, no second hotkey. | Long-tail door that preserves the fixed ring. Signature inhale/exhale motion. |
| **v2** | **Chameleon** — "your Eight, *per app*": the ring's contents swap based on the frontmost app. | Deterministic (only changes when *you* change apps), not algorithmic re-ranking. Paid-tier differentiator; frontmost-app detection is near-free, the cost is onboarding. |

**Parked wildcard:** *Inkstroke* — blind marking-menu compound-stroke selection (~3× faster
for experts, 30 years of HCI evidence). A future throwaway prototype; unmatched demo if the
recognizer can be made trustworthy. Not in any committed milestone.

---

## 5. Snippet Model

A snippet is a **template** resolved at fire time, not a static string.

- **Base:** plain text.
- **Dynamic tokens** (resolved at the moment of release):
  - `{date}` — current date. v1 default: system-locale medium style (`DateFormatter`
    `.medium`, e.g. "Jul 9, 2026"). Custom format strings are deferred.
  - `{time}` — current time. v1 default: system-locale short style (`DateFormatter`
    `.short`, e.g. "11:14 AM").
  - `{clipboard}` — the user's clipboard contents *as captured before insertion begins*
    (see §6 — we read the clipboard first, precisely so this token is meaningful).
- **Caret marker `$|`** — marks where the text cursor should land after insertion
  (e.g. `"Hi $|,\n\nThanks,\nAlex"` drops the caret right after `"Hi "`). Offset is measured
  in **grapheme clusters** (Swift `String.count`), because Cocoa arrow-key movement is one
  grapheme per press.
- **Explicitly deferred:** rich text / formatting; interactive fill-in fields; per-snippet
  insertion-mode overrides. The `SnippetStore` schema carries a version field so these extend
  without a migration crisis.

Each snippet has: an id, a user-written short **label** (shown on the wedge, e.g. `SLA`),
optional secondary caption, the template body, and a **slot assignment** (which of the 8
ring positions it's pinned to, if any). Unpinned snippets exist in the library for the
future search palette (v1.5) but do not appear on the ring.

---

## 6. Insertion Mechanism — Paste-and-Restore

Chosen over synthetic keystroke injection and Accessibility-API insertion because it is the
most reliable across the huge variety of macOS text fields and is instant regardless of
length. (Keystroke injection is slower on long text and dropped by some apps;
AX-insertion is too flaky in Electron/browsers/terminals to be the primary path — but see the
seam in §8/§12.)

**Fire-time sequence:**
1. **Snapshot** the current pasteboard — *all* items and *all* their types (string, RTF,
   image, file URLs), not just the string. Skip items marked `org.nspasteboard.ConcealedType`
   (password managers) from any logging.
2. **Resolve** the template via `TokenResolver`, using the snapshot for `{clipboard}` and
   extracting the `$|` grapheme offset.
3. **Write** the resolved text to the pasteboard, marked `org.nspasteboard.TransientType` +
   `AutoGeneratedType` so clipboard managers (Maccy, Paste) don't archive snippet firings.
4. **Wait for clean modifier state** (hotkey mode only) — poll
   `CGEventSource.flagsState(.combinedSessionState)` until the user's physically-held
   modifiers are released, with a ~500 ms timeout (prevents ⌥⌘V = *Move Item* in Finder).
5. **Synthesize ⌘V** — v-down/v-up (keycode 9) with `flags = [.maskCommand]` set explicitly on
   both, posted to `.cghidEventTap`. Stamp our synthetic events (`eventSourceUserData`) so our
   own tap ignores them.
6. **Reposition the caret** — after a ~75–100 ms delay (so the paste lands before the arrows),
   send Left-arrow key events equal to the grapheme count from `$|` to end.
7. **Restore** the original pasteboard after a generous fixed delay (~250–300 ms) — but
   **only if `NSPasteboard.changeCount` still equals our write** (if it moved, the user copied
   something; don't clobber it).

**Known, documented limitations** (best-effort, not solved in v1): editors with vim emulation,
auto-indent-on-newline, and terminals may misplace the `$|` caret; Electron / remote-desktop
apps that read the pasteboard lazily may occasionally paste the *restored* old clipboard. This
imperfect fixed-delay restore is the industry-standard behavior (TextExpander, Alfred, Raycast
all live with it). Paste has one silver lining over typing: it bypasses smart-quotes/autocorrect.

---

## 7. Architecture — AppKit shell + SwiftUI content (Option B)

Native Swift is effectively mandatory: the three load-bearing subsystems — global event
interception (`CGEventTap`), a transient vibrancy overlay (`NSPanel` + `NSVisualEffectView`),
and synthetic input (`CGEvent`) — have no viable cross-platform wrapper. Electron/Tauri was
considered and **rejected**.

### The non-negotiable invariant: the overlay is display-only
Because the event tap **consumes** the middle-mouse events (returns `nil` so the underlying app
never sees them), those events are routed to *no* window — including ours. Therefore SwiftUI
gestures inside the panel would receive nothing. **All input comes from the tap; the panel
(`ignoresMouseEvents = true`) only renders state.** This is forced by event consumption, not a
style choice, and it must be preserved (documented as an invariant on the panel class). Its
happy consequence: the selection logic becomes a pure, testable function.

### Per-surface decisions
| Surface | Decision |
|---|---|
| Overlay shell | AppKit `NSPanel` subclass, `styleMask = [.borderless, .nonactivatingPanel]`, `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `isOpaque = false`, `backgroundColor = .clear`, shown via `orderFrontRegardless()`, ring-sized (not screen-sized). |
| Radial content | SwiftUI in `NSHostingView` (`sizingOptions = []`, explicit frame), **render-only, zero gesture handling**; pre-created at launch to avoid a first-open hitch. |
| Vibrancy | `NSVisualEffectView` (`.hudWindow` material) with a ring-shaped `maskImage`, wrapped in `NSViewRepresentable`. |
| Library / Settings | Pure SwiftUI windows. |
| Menu-bar lifecycle | `NSStatusItem` + `NSApplicationDelegate` (not SwiftUI `MenuBarExtra` — need precise activation-policy + tap-lifecycle control). `LSUIElement` agent (no Dock icon). |
| Persistence | `Codable` JSON, atomic writes, in Application Support. |

### The `keyboardMode` seam (built in v1, used in v1.5)
The v1.5 search palette needs live keyboard text entry while the overlay is up. A
`.nonactivatingPanel` **can become key without activating the app** (the Spotlight/LaunchBar
pattern), so keystrokes route to it while the target app stays frontmost and paste still
lands. The panel subclass therefore carries a `keyboardMode` flag from day one
(`canBecomeKey` returns it; `ignoresMouseEvents` flips with it; dismissal resigns key before
paste fires). This is the one behavior in the design resting on underdocumented (though
well-precedented) AppKit behavior, so it is **spiked early** (see §13).

---

## 8. Module Breakdown

1. **EventTapEngine** — owns both `CGEventTap`s on a dedicated run-loop thread; the trigger
   state machine; `kCGEventTapDisabledByTimeout` re-enable + state resync; ignores our own
   synthetic events. Emits semantic events: `bloom(at:)`, `pointer(vector:)`, `commit`, `cancel`.
   - **Two taps** (masks are fixed at creation): a lean **always-on trigger tap**
     (`otherMouseDown/Up/Dragged` + `keyDown/keyUp/flagsChanged`), and an **on-demand session
     tap** created on bloom / destroyed on dismiss (`mouseMoved` for hotkey-hold mode + `keyDown`
     for Escape and, later, the palette). A permanently-enabled `mouseMoved` tap would fire a
     callback on every system-wide pointer move — avoided.
2. **RadialSession** — *pure* interaction logic: pointer-vector → `atan2` → wedge index,
   center dead-zone, boundary hysteresis, fire/cancel decision. No AppKit import. Fully
   unit-tested.
3. **OverlayPanelController** — owns the prewarmed `OverlayPanel` + `NSHostingView`; target-screen
   selection, Quartz↔Cocoa coordinate conversion, `visibleFrame` clamping (notch/menu bar);
   show/hide; `keyboardMode` flipping.
4. **RadialMenuView** (SwiftUI) — draws ring, wedges, highlight, and bloom/dismiss springs from
   an `@Observable` view model. Zero input handling, ever. (`Canvas` is the escape hatch if
   drag-update rendering ever janks; CALayer is not needed.)
5. **SnippetStore** — `Codable` JSON in Application Support, atomic writes, slot model, a
   `schemaVersion` field for migrations.
6. **TokenResolver** — *pure*: expands `{date}/{time}/{clipboard}`; extracts the grapheme-aware
   `$|` offset. Unit-tested.
7. **PasteEngine** — pasteboard snapshot/restore with `changeCount` guard and `org.nspasteboard`
   markers; modifier-clean wait; synthetic ⌘V + arrow burst. Contains the **seam** for future
   AX-based insertion (`kAXSelectedTextAttribute` / `kAXSelectedTextRange`), which is where mature
   snippet tools end up (AX-first, paste-fallback) — not built in v1.
8. **PermissionsCoordinator + AppShell** — `AXIsProcessTrustedWithOptions` onboarding, trust
   polling, tap (re)creation orchestration; `NSStatusItem`; SwiftUI settings/library windows.

---

## 9. Data Flow — the fire path

```
hold trigger
  → EventTapEngine consumes middle-down → emits bloom(at: cursor)
  → OverlayPanelController positions the prewarmed panel under the cursor (coord-converted,
    clamped to visibleFrame) → orderFrontRegardless()
drag
  → tap streams pointer vectors → RadialSession computes the highlighted wedge (dead-zone +
    hysteresis) → updates the @Observable model → RadialMenuView redraws the highlight
release
  → RadialSession decides fire(slot) or cancel
  → TokenResolver resolves the snippet (clipboard snapshot read FIRST, $| offset extracted)
  → PasteEngine: snapshot pasteboard → write resolved text → wait for clean modifiers
              → synth ⌘V → (delay) arrow-keys to $| caret → changeCount-guarded restore
  → OverlayPanelController orders the panel out
```

---

## 10. Persistence

- `Codable` JSON at `~/Library/Application Support/Snip/snippets.json`, written atomically.
- A handful-to-hundreds of snippets does not warrant SwiftData/SQLite; JSON is trivial to back
  up, diff, and later sync. A `schemaVersion` field is present from v1 so a move to SwiftData
  or iCloud sync (if the library ever gets huge) is a migration, not a rewrite.

---

## 11. Permissions & Onboarding

- **Accessibility** (`AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`) is the
  gate. Without trust: `CGEvent.tapCreate(.defaultTap)` returns **nil** (a reliable runtime
  signal), and `CGEvent.post` **silently no-ops**. All features gate on the `tapCreate` result,
  never on an assumption.
- **Grant-while-running:** after the user flips the toggle in System Settings, poll
  `AXIsProcessTrusted()` (~1 s) while onboarding is up, retry `tapCreate` on flip, and offer a
  "Restart Snip" button as the fallback (TCC caching sometimes needs a relaunch).
- Onboarding is a first-run SwiftUI window explaining the permission and its purpose, with live
  status and the restart fallback.

---

## 12. Risks & Mitigations (ranked by likelihood of biting)

1. **TCC + unstable dev signing** — DerivedData rebuilds churn the app identity → Accessibility
   silently revokes → hours lost blaming tap code. **Sign dev builds with a stable Developer ID,
   run from a stable path**; `tccutil reset Accessibility <bundle-id>` to test onboarding.
2. **Display-only invariant erosion** — a later "simplification" into SwiftUI gestures breaks the
   product (consumed events never reach the panel). Encoded as an architectural invariant + code
   comment on the panel class.
3. **Quartz↔Cocoa Y-flip on multi-display** — ring blooms on the wrong screen or mirrored. One
   tested coordinate-conversion helper used everywhere.
4. **Tap timeout mid-hold → missed mouseUp → stuck-open ring** — dedicated tap thread; on
   re-enable, resync from `CGEventSource.buttonState(.combinedSessionState)` / `keyState`; plus a
   watchdog that dismisses the ring after a few event-less seconds while open.
5. **Held hotkey modifiers contaminating synthetic ⌘V** (⌥⌘V = *Move* in Finder) — wait for clean
   modifier state before posting (§6 step 4). Middle-button mode is immune; hotkey mode is not.
6. **Clipboard restore race / manager pollution** — no read-completion signal exists;
   `changeCount`-guarded restore + `org.nspasteboard.TransientType` markers. Electron/remote apps
   will occasionally lose — documented, industry-standard.
7. **Secure Event Input** (password fields, Terminal secure entry) makes keyboard events invisible
   to taps → the **hotkey** trigger silently dies while active. Detect via
   `IsSecureEventInputEnabled()` and surface a hint; middle-mouse keeps working (a resilience
   argument for shipping both triggers).
8. **NSHostingView cold-start hitch** — pre-create panel + hosting view at launch; one offscreen
   warm-up order-front/out.
9. **Full-screen spaces / notch** — `.fullScreenAuxiliary` + `.canJoinAllSpaces`; clamp ring center
   to `screen.visibleFrame`. (Exclusive-Metal-fullscreen games will still win; accepted.)
10. **Middle-button ecosystem conflicts** (Blender, CAD, BetterTouchTool/Mos remaps) — Snip owns
    button 2 globally in v1; the hotkey is the escape valve. A **per-app exclusion list** is
    deferred to v2 (predicted #1 feature request).
11. **Arrow-key caret repositioning** wrong across newlines/vim-mode/terminals — documented best-effort.
12. **Autorepeat keyDowns in hotkey-hold** — consume the hotkey's keyDown, *all* autorepeats, and
    keyUp, or the target app receives stray characters.

---

## 13. v1 Scope

**In:**
- Menu-bar agent (`LSUIElement`, `NSStatusItem`), Accessibility onboarding.
- Up to 8 fixed hand-pinned slots ("The Eight"); ghosted empty slots.
- Both triggers (middle-hold + configurable hotkey), drag+release fire, center/Escape cancel.
- Display-only SwiftUI radial overlay with CleanShot vibrancy + bloom/dismiss springs.
- Snippet templates: plain text + `{date}/{time}/{clipboard}` + `$|` caret marker.
- Paste-and-restore insertion with `changeCount`-guarded restore and caret repositioning.
- SwiftUI library window (create/edit/delete snippets, write labels, pin to slots) and Settings
  (trigger configuration).
- `Codable` JSON persistence with `schemaVersion`.
- The `keyboardMode` seam on the panel class (built, unused in v1).

**Early de-risking milestone (walking skeleton, Gall's Law):** menu-bar agent + a tap that just
logs + a prewarmed empty panel + **the key-nonactivating-panel spike** (~50-line proof: make a
non-activating panel key over TextEdit, type into it, dismiss, synthesize ⌘V — verified on the
target macOS versions) *before* betting v1.5 on it.

**Deferred:** the v1.5 search palette ("The Well"); v2 per-app rings ("Chameleon"); AX-based
insertion; rich text; interactive fill-in fields; per-snippet insertion-mode overrides; per-app
exclusion list; Developer-ID/notarization/Sparkle/licensing (added after the core works).

---

## 14. Testing Strategy (TDD-forward)

The architecture isolates pure *logic* from OS-fighting *effects* precisely so most of it is
unit-testable.
- **Unit-tested first, real RED→GREEN (no mocks):** `RadialSession` (angle→wedge, dead-zone,
  hysteresis) and `TokenResolver` (token expansion, grapheme-aware `$|` offset).
- **Integration-tested against real APIs:** `SnippetStore` (JSON round-trip + migration),
  `PasteEngine`'s pasteboard snapshot/restore + `changeCount` guard (real `NSPasteboard`).
- **Manually verified end-to-end** against real target apps (TextEdit, Mail, VS Code, a
  browser): synthetic input cannot be honestly unit-tested, so we drive the real flow and
  observe it (per project rule: verify behavior, not just types/tests).
- Test output must be pristine; intentionally-triggered error paths capture and assert their output.

---

## 15. Open questions to verify during implementation

These are explicit verification tasks (not undecided design), to confirm on the minimum target
macOS at build time:
1. Whether keyboard-event taps additionally require the **Input Monitoring** TCC category on the
   target macOS versions (Accessibility has historically sufficed for active taps).
2. Exact behavior of a previously-*denied* process after a mid-run grant (does the tap work on
   retry, or is a relaunch required?) — determines how hard we lean on the "Restart Snip" fallback.
3. The precise clean-modifier wait timing and paste→arrow delay that feel instant yet correct
   across slow apps (tunable debug pref during development).
4. Whether users need custom `{date}`/`{time}` format strings in v1 (defaults are decided —
   §5 — so this is a product/scope call, not a blocker).

---

## 16. Aesthetic reference

CleanShot X, as above. Interactive mockup comparing the three strategy directions (the chosen
"The Eight", plus the rejected Bloom and the v2-bound Chameleon), CleanShot-flavored:
- Artifact: https://claude.ai/code/artifact/5b5af153-cc7a-4aca-9dc1-5490c3db43c4
- Source: `scratchpad/snip-radial-mockups.html`
