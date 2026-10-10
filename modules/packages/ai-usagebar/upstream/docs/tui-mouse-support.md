# TUI mouse support: how it works and how to extend it

How mouse interaction is implemented in `ai-usagebar-tui` (ratatui + crossterm),
and what to do when a UI change adds or moves an interactive element.

ratatui does not route clicks: crossterm delivers raw `MouseEvent`s and the app
maps them to targets itself. This document describes that mapping so a UI
change keeps mouse behavior correct without rediscovering the rules.

## Architecture

```
crossterm Event::Mouse ──► reader thread ──filter──► channel ──► event loop
                                                                 │
   ┌─────────────────────────────────────────────────────────────┘
   │ handle_mouse(app, event)
   │   1. ignore non-left-click events
   │   2. if an overlay (Settings / picker / context) owns the screen,
   │      it consumes the click
   │   3. otherwise hit-test against the rects the LAST draw recorded
   ▼
rects recorded during draw():  app.hit.{nav_entries, footer_actions, settings_rows}
```

- `src/bin/ai-usagebar-tui.rs` — reader thread (event filtering), the event
  loop, `handle_mouse` (hit-testing + dispatch), `apply_settings_action`.
- `src/tui/view.rs` — `draw()`: clears every hit list at frame start, renders
  header/body/footer, records `nav_entries` (sidebar) and `footer_actions`
  (footer), then renders the Settings overlay on top.
- `src/tui/settings.rs` — the overlay: `render()` records `settings_rows`,
  `handle_key()` owns keyboard behavior.
- `src/tui/app.rs` — the `HitTargets` registry (a `RefCell` on `App`).

## Rules that keep mouse behavior correct

1. **Clear every hit list at frame start** (`draw()` in `view.rs`). Rects from
   a view that is no longer rendered must die with the frame, or clicks in
   that area trigger ghost actions.
2. **Record rects at the rendered position.** In a scrolled pane the on-screen
   row of body line `L` is `top + L - scroll`. Recording the unscrolled
   position makes clicks select the control `scroll` rows away from what the
   user sees. `settings::render` computes the scroll offset before recording
   and its `row_at` helper applies it.
3. **Never record rects for clipped rows.** If a row's y falls outside the
   pane's visible bounds, push no rect — a click there must not hit an
   invisible control. See `row_at` in `settings.rs`.
4. **Overlays consume clicks.** While Settings, the vendor picker, or the
   context view is open, `handle_mouse` returns early (or closes the popup on
   outside clicks) — clicks must never leak through to background tabs or the
   footer. Keyboard dispatch has the same rule; keep both in sync.
5. **Filter events in the reader thread.** Only left-button downs are
   forwarded to the loop; motion/scroll/release events would otherwise cause
   full-frame redraws and channel backlog.
6. **Prefer the narrowest matching rect.** When two targets share a row (label
   + switch cell), push the more specific rect first — the hit-test keeps the
   first match.

## Adding a new interactive element

### In the sidebar or footer (`view.rs`)

Push `(NavTarget, Rect)` / `(FooterAction, Rect)` into the matching list while
drawing (`draw_sidebar` / `draw_footer`). The footer computes each segment's
width the same way `Help` renders it (`key + 1 space + description`, `•`
separator = 3 cells), so the rect covers exactly the rendered label.

### In the Settings overlay (`settings.rs`)

Pick the `SettingsRow` variant that matches the interaction:

| Variant | Use for | Click behavior |
|---|---|---|
| `Focus(Focus)` | any focusable field/row | focuses the row |
| `Switch(Focus, KeyCode, KeyModifiers)` | value cell that acts | focuses the row, then sends the synthetic key (space toggles a switch; `←`/`→` step the primary radio) |
| `OpenPicker` | the primary vendor's name cell | opens the vendor picker popup |
| `Pick(usize)` | a choice row in the open picker | selects that vendor |
| `HintKey(KeyCode, KeyModifiers)` | hint-footer "link" | sends the key through `handle_key` (save/close/toggle/reveal) |

Record during `render()` through the scroll-aware `row_at` helper; for a
two-target row (label + value cell), push the value cell first. Row geometry
is computed from the same layout the renderer draws: `padded_label` /
`switch_cell` mirror `provider_row` / `notify_enabled_line` (a 5-cell focus
prefix, the label padded to at least 11 columns — longer names push the value
right — then the value segment), and `primary_name_pad` pins the primary
radio's arrow columns. If you change one of those renderers, update the
helpers in the same commit.

Key detail for value cells: the click focuses the row and then sends the
key **through `handle_key`** rather than mutating state directly, so mouse and
keyboard behavior stay defined in one place.

### Tests every interactive element needs

The existing suites show the three patterns to copy:

1. **Geometry** — the element records a rect at the right place:
   `render_records_switch_cells_right_of_the_labels` (settings.rs).
2. **Behavior** — a `TestBackend` draw + `handle_mouse` click at the rendered
   position produces the expected state/action:
   `clicking_a_provider_switch_cell_toggles_it_without_losing_the_click`,
   `clicking_the_primary_arrows_steps_the_vendor_radio` (ai-usagebar-tui.rs).
3. **Clamping** — on a terminal too short to show the element, no rect is
   recorded: `settings_draw_clamps_hit_rects_on_short_terminals` (view.rs).

Run `cargo test` — the mouse suites fail loudly when rendering and hit
targets drift apart; keep them in sync with any layout change.

## When to consider a framework instead

The manual pattern is idiomatic ratatui and stays cheap while interactive
surfaces are few and the helpers above cover them. Revisit before it grows:

- **cursive** — retained views; the framework does hit-testing and focus.
- **paradox-ui / a3s-tui / omp-tui** (2026) — retained trees over/modern
  stacks with built-in hit regions.
- **tui-realm** — component events over ratatui, but per-item clicks inside
  scrolled lists remain a known gap (issue #172).

Triggers to re-evaluate: many scrollable click-per-item surfaces, drag and
drop, hover states, or accessibility requirements. A survey of these options
lives in the separate research repository (`Pesquisas/Rust`,
"Rust GUI & TUI Ecosystem Survey (2026)").
