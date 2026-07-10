---
name: verify-git-status-after-scoped-add
description: "After a scoped `git add <paths>` + commit, run `git status`; a scoped add can strand a related change and leave the committed tree non-compiling."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 059b1701-d450-4e8b-b39e-ce4457595325
---

When committing with an explicit path list (`git add Snip/ .cs/`) rather than `git add -A`, a
change in a sibling directory that the same feature touched can be silently left out. The working
tree still builds (it has the change), so nothing looks wrong locally; the committed tree is
inconsistent and a clean checkout fails.

**Why:** in the Snip session the cursor-centering fix renamed `ScreenGeometry.clampedOrigin` →
`centeredOrigin` (in `SnipKit/`) and updated `OverlayPanelController` (in `Snip/`) to call it, but
the commit's `git add` only listed `Snip/`. For ~15 commits, committed `OverlayPanelController`
referenced a function absent from committed `ScreenGeometry`. Caught only when a later `git status`
surfaced the stranded `SnipKit/` diff.

**How to apply:** after any scoped `git add` + commit, run `git status` and confirm no related
files are still modified/untracked. Alex's rule already forbids blind `git add -A`; the complement
is: scoped adds must be reconciled against `git status`. For a change that spans directories
(a package + its app consumer), stage every touched path or verify the tree is clean afterward.
Consider a quick `swift build`/checkout-from-HEAD sanity check for cross-module renames.
