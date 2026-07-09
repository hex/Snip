---
name: overlay-loupe-via-caportallayer
description: "How to render a live MAGNIFIED view of other apps' pixels behind a transparent overlay panel on macOS (CAPortalLayer mirroring an NSVisualEffectView backdrop), and which approaches are dead ends."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 059b1701-d450-4e8b-b39e-ce4457595325
---

Real, live magnification of the apps BEHIND a borderless non-activating `NSPanel` (a loupe) IS
possible on macOS 26, with no Screen Recording permission, all private API. Fable verified the
mechanism with a probe reproducing Snip's exact panel and screenshots (agentId a171a6479c5f92621).
Implemented in `Snip/Overlay/BackdropLoupeView.swift`.

**Why the obvious things fail:** the overlay window is rendered SERVER-SIDE
(`CABackdropLayer.groupNamespace == "hostingNamespacedContext"`). Consequences:
- **Core Image filters never run on the backdrop.** So a `CIColorInvert` "does it render" test is
  invalid, it can never show anything, regardless of wiring. Only native **`CAFilter`** types
  execute server-side (gaussianBlur, colorInvert, displacementMap, glassBackground/Foreground,
  lanczosResize, chromaticAberration, vibrantDark/Light, ...).
- A **hand-rolled `CABackdropLayer`** (even with `windowServerAware`, `allowsInPlaceFiltering`,
  copied `groupName`/`groupNamespace`) receives NO backdrop. Only AppKit's window-level
  registration (`_registerBackdropView:`) wires one. Do not hand-roll; commandeer a real
  `NSVisualEffectView`'s.
- `CABackdropLayer.zoom` only zooms OUT (>=1 samples a bigger region; <1 = solid gray; 0 = off);
  layer `transform` is ignored for backdrop sampling. So there is no magnify-IN on the backdrop.

**The working recipe (magnify-in loupe):**
1. Put a small hidden `NSVisualEffectView` (`.hudWindow`, `.behindWindow`, `.active`) at the loupe
   spot. AppKit registers it and the WindowServer wires its consumer `CABackdropLayer`.
2. Recurse the effect view's layer tree to find that `CABackdropLayer` (match by class name).
3. Strip its `filters` (sharp live feed) and set its fill/tone/tint sibling layers `opacity = 0`.
   Re-strip in the effect view's `updateLayer` (AppKit reapplies the material recipe).
4. Add a private **`CAPortalLayer`**: `sourceLayer` = that backdrop, `hidesSourceLayer = true`,
   `allowsBackdropGroups = true`, `transform = CATransform3DMakeScale(mag, mag, 1)`. A portal
   mirrors another layer's content through its OWN transform, so scaling magnifies. This is the
   crux, and the one thing the backdrop layer cannot do.
5. For sharpness, raise the window-root capture provider (`captureOnly == true`) `scale` from
   0.125 to `backingScaleFactor`, and multiply every consumer's `gaussianBlur.inputRadius` by the
   same ratio so other frost (e.g. Snip's ring) is unchanged.

Gate everything on `isSupported` (CAPortalLayer + CABackdropLayer present); fall back to a painted
lens. All private API, acceptable because Snip is not App-Store. ScreenCaptureKit is the public
alternative but needs Screen Recording, rejected for a snippet app.

See [[narrative.alex-geana-erepubliklabs-com]] for the full trail, including two retractions where
I claimed a lens worked by reading screenshots instead of measuring.
