---
name: snip-build-gotchas
description: "Snip's deployment target is macOS 14.0 (built against the 26.5 SDK), so 15.0+ APIs fail to compile; and SourceKit shows phantom SnipKit/HUD errors while xcodebuild succeeds."
metadata: 
  node_type: memory
  type: project
  originSessionId: 059b1701-d450-4e8b-b39e-ce4457595325
---

Two things about building Snip that look like errors but are not:

**Deployment target is macOS 14.0, not 26.** The build compiles against MacOSX26.5.sdk but
targets `arm64-apple-macos14.0`, so an API gated `@available(macOS 15.0, *)` is IN the SDK yet
fails to compile at the 14.0 floor. This bit `Color.mix(with:by:)` (macOS 15+): it looked fine
but the compiler rejected it with "only available in macOS 15.0 or newer". Reach for an AppKit or
Canvas alternative (e.g. `NSColor.blended(withFraction:of:)`, or draw in `Canvas`) instead of a
15.0+ SwiftUI API, unless the floor is deliberately raised.

**SourceKit phantom errors.** Every build this session the language server flagged
`No such module 'SnipKit'` and cascading `Cannot find 'HUD' / 'AppModel' / 'MainTab' in scope`.
The local SwiftPM package (SnipKit) is not resolved in the index, so these are noise; every
`xcodebuild ... build` returned `** BUILD SUCCEEDED **`. Trust the build, not the inline
SourceKit diagnostics.
