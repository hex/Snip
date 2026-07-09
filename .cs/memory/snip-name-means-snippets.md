---
name: ""
metadata: 
  node_type: memory
  originSessionId: 059b1701-d450-4e8b-b39e-ce4457595325
---

The macOS app **Snip** takes its name from **Snippets**, not from "snipping" or cutting.
Its only verb is *inserting* saved text at the cursor; it never cuts, clips, or trims anything.

**Why:** the obvious-but-wrong reflex is a scissors icon (`scissors` SF Symbol, ✂ emoji), which
promises destructive cut/clip behavior — the opposite of what the app does. Alex corrected this
after the first build shipped a scissors menu-bar icon.

**How to apply:** use insertion/text imagery — the menu-bar icon is the `text.insert` SF Symbol.
Avoid `cut`, `clip`, `trim`, `scissors` in symbol names, type names, variable names, UI copy,
and marketing. Prefer snippet/insert/paste vocabulary.

See [[narrative.alex-geana-erepubliklabs-com]] for the build log.
