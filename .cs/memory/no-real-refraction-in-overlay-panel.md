---
name: no-real-refraction-in-overlay-panel
description: "Snip's overlay cannot really refract the pixels behind it; CABackdropLayer renders nothing in a borderless non-activating NSPanel. Do not retry."
metadata: 
  node_type: memory
  type: project
  originSessionId: 059b1701-d450-4e8b-b39e-ce4457595325
---

Snip's radial overlay hub is a **painted** lens (inner shadow on the top inside edge, specular on
the bottom, crisp rim). It does not actually magnify or distort the pixels behind the window, and
it cannot be made to.

**Why, established empirically on macOS 26:**

1. `CALayer.backgroundFilters` filters content beneath the layer **within its own window's backing
   store**. Snip's window is transparent and the hub is a hole, so there are zero in-window pixels
   to bend. It never reached other apps' pixels.
2. `CABackdropLayer` (private, the layer `NSVisualEffectView` uses) **renders nothing** in Snip's
   panel, whether added as a sublayer or installed via `makeBackingLayer()`, with
   `windowServerAware` and `allowsInPlaceFiltering` set. A `CIColorInvert` diagnostic did not even
   change colour, which rules out both "filters are dropped" and "zoom has odd units". There is no
   backdrop content at all. The WindowServer only feeds it to `NSVisualEffectView` through a
   private host relationship. Suspected cause: the panel is borderless, non-activating,
   `.screenSaver` level, transparent, `ignoresMouseEvents`.
3. Probed facts about `CABackdropLayer` on macOS 26, if it is ever revisited: `zoom` defaults to
   `0` (not 1), `scale`, `windowServerAware`, `captureOnly`, `allowsInPlaceFiltering`, `groupName`
   and `backdropRect` are real properties; `disableBlur` and `blurRadius` do not exist. `CALayer`
   stores unknown keys instead of raising, so probing cannot crash.

**The only remaining route** is ScreenCaptureKit, which needs the **Screen Recording** permission.
Rejected: a text-snippet app that already asks for Accessibility has no business also asking to
record the screen, for a decorative effect.

**How to apply:** if refraction, magnification, or a real magnifier effect comes up again for the
overlay, do not spend rounds on it. State this finding and move on. See
[[narrative.alex-geana-erepubliklabs-com]] for the full trail, including two retractions where I
claimed the lens worked based on reading screenshots rather than measuring.
