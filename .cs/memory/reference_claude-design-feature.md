---
name: ""
metadata: 
  node_type: memory
  originSessionId: 059b1701-d450-4e8b-b39e-ce4457595325
---

"Claude Design" = the user's **design-system projects on claude.ai/design**, edited
through the deferred **`DesignSync`** tool. It is a specific product, NOT a euphemism
for "do some design work". When Alex says "use claude design", reach for this, do not
improvise HTML mockups + a design panel and call it "claude design".

**Gate:** access is off until the user runs `/design consent` (undo with `/design revoke`).
The `/design` command itself only does `consent`/`revoke`; the real work is the DesignSync tool.

**Tool flow (DesignSync `method`):** `list_projects` -> (`create_project {name}` if none) ->
build local preview cards -> `finalize_plan {projectId, localDir, writes[], deletes[]}` (deletes
is REQUIRED even if `[]`; this prompts the user) -> `write_files {planId, files:[{path, localPath}]}`
(reads localPath from disk, contents never enter model context) -> `list_files` to confirm.
Ordering is enforced: list/read -> finalize_plan -> write/delete.

**Cards:** each is a self-contained preview HTML whose FIRST line is
`<!-- @dsCard group="..." title="..." -->`; the app compiles those markers into the
Design System pane. `register_assets` is a legacy fallback for files without the marker.

Applied here: created project "Snip" and pushed the [[snip-name-means-snippets]] Detent
design system (palette, type, dial with lit bearing, sidebar). See
[[session-narrative-alex-geana-erepubliklabs-com]] for the full push.
