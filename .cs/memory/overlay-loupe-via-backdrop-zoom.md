---
name: overlay-loupe-via-backdrop-zoom
description: How to render a live MAGNIFIED loupe of content behind a transparent overlay window on macOS (private CABackdropLayer capture group with negative zoom); CAPortalLayer does NOT magnify.
metadata:
  type: reference
---

Live magnification of the content BEHIND a borderless non-activating `NSPanel` (a loupe) IS
possible on macOS 26, no Screen Recording, all private API. Measured and verified by Fable
(agentId a24f64b9edf61cfe9) with a probe reproducing Snip's panel: 1.500x exactly, sharp.
Implemented in `Snip/Overlay/BackdropLoupeView.swift`.

**The working recipe: a private CABackdropLayer capture group.**
- Provider layer: `CABackdropLayer`, `captureOnly = true`, `windowServerAware = true`,
  `groupName = <unique>`, `scale = backingScaleFactor`, frame = the loupe bounds.
- Consumer layer: `CABackdropLayer`, `windowServerAware = true`, same `groupName`, frame = bounds,
  and a NEGATIVE `zoom`.
- Add both as sublayers of the loupe view's layer; clip to a circle with `masksToBounds` +
  `cornerRadius`.
- Magnification law (measured, exact fit): `contentScale = 1 / (1 + scale*zoom)`, remapped around
  the consumer's centre. So `zoom = (1/m - 1)/scale` gives magnification `m`. For m=1.5 at
  scale=2: zoom = -1/6. Keep m >= ~0.4; `zoom` must stay > -1/scale (the formula's pole).
- Sharp (no filters), tracks the panel automatically, no portal, no NSVisualEffectView, no leaks
  across reuse. Independent of any other backdrop group (does not touch a sibling frost).

**Dead ends (do not retry):**
- `CAPortalLayer` mirroring a backdrop + transform: does NOT magnify. A windowServerAware backdrop
  is procedural, re-evaluated at composite time and sampled 1:1 for its on-screen footprint,
  ignoring portal/ancestor transforms. (An earlier "verified" claim for this was wrong; the
  screenshots were 1:1 under blur.)
- Bumping the SHARED window capture provider `scale` to sharpen: harmful, it sharpens every
  consumer (e.g. a ring frost) and forces per-frame gaussian-radius compensation. The capture
  group above uses its OWN provider, so it needs no shared-state mutation.
- `CALayer.backgroundFilters`, hand-rolled backdrop joining the window group, and Core Image
  filters on the backdrop: all dead (the window is server-side hosted; CIFilters never run there).
- Native `CABackdropLayer.zoom` on the WINDOW's own backdrop only zooms OUT; you need your own
  capture group with a negative zoom to zoom IN.

**Edge / barrel distortion (physical-lens rim):** a native **`displacementMap` `CAFilter`** on
the consumer. CAFilter responds to `-inputKeys` (use it; never setValue a key not listed, the
NSException is uncatchable in Swift). Keys: `inputMaskImage` (RGBA CGImage: R,G = signed radial
vector, 0.5 neutral, growing r^2 outward, B=255 A=255), `inputAmount` (ABSOLUTE POINTS, scale with
radius), `inputOffset` = `NSValue(point:(0.5,0.5))` set explicitly. Requires a CAPTURE MARGIN:
size provider+consumer ~0.4*radius larger than the visible circle and clip with a CAShapeLayer
aperture, else the rim samples transparency. Filters stack. glassBackground/Foreground need a
private height-field sublayer (`inputSourceSublayerName`) and make the disc vanish otherwise;
chromatic aberration reads as a global glitch. `CAFilter.filterTypes` is the 43 real native types;
CIFilters never run server-side.

Gate on `isSupported` (CABackdropLayer present) and a separate distortion gate (CAFilter
displacementMap + expected inputKeys); painted lens is the fallback. `zoom`/displacement semantics
are private and were measured on a 2x display; sanity-check 1x displays if supported.

See [[narrative.alex-geana-erepubliklabs-com]] for the trail, including two retracted lens claims.
