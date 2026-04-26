# board/scenes/

The `Board` scene — a thin orchestrator. This is where the old `fj/ui/board.gd` god-scene gets dismantled.

## Files

| File | Responsibility |
|---|---|
| `board.gd` | Orchestrator. See below. |
| `board.tscn` | Scene hierarchy (copied from `fj/ui/board.tscn`, script reference updated). |
| `info_panel.gd` | Side panel. Mostly unchanged from old client — it was already well-scoped. |
| `info_panel.tscn` | Panel layout. Copy from old. |

## The new `board.gd`

The old `board.gd` was ~330 lines doing six roles. The new one does exactly one: **compose**. Specifically:

1. Accept a `NexusRouter` via `configure(router)`.
2. Instantiate `Conductor` (passing router + self-as-RendererAccess).
3. Instantiate `InputHandler` (passing router).
4. Walk the scene tree to register every `Slot` and `WeaponSlot`, resolving wire names via `Catalog` (available on the router's session).
5. Connect every scene-input signal (card_clicked, slot_clicked, weapon_slot_clicked, info_panel.text_option_selected) to `InputHandler.adapter`'s methods.
6. Implement the `RendererAccess` protocol: `slot_for`, `weapon_slot_for`, `overlay`, `completion_signal`.

That's it. No change pipelines, no animation code, no highlight logic, no option matching. All moved.

## The RendererAccess protocol

`Conductor` needs a small interface onto the scene. Instead of passing `Board` directly (which would couple `Conductor` to the scene's full API), we pass an object satisfying:

```gdscript
slot_for(wire: String) -> Slot
weapon_slot_for(ws_wire: String) -> WeaponSlot
overlay() -> Control
completion_signal() -> Signal    # fires when any animation completes
```

`Board` implements all four. A test harness can implement them with mocks.

## Why NodePath-free signal wiring

The old `board.gd` walked the tree with `_find_slots` / `_find_weapon_slots` and bound wire names via `.bind(wire)` on signal connects. The new version should keep that pattern — it works well — but the bound data becomes typed:

```gdscript
# old
slot.card_clicked.connect(_on_slot_card_clicked.bind(wire))
func _on_slot_card_clicked(_slot: Slot, index: int, wire: String) -> void:
    _respond_matching({"type": "card", "slot": wire, "index": index})

# new
slot.card_clicked.connect(_input.adapter.on_card_clicked.bind(wire))
# Slot.card_clicked emits (slot: Slot, shadow_index: int). After .bind(wire),
# the signal delivers (slot, shadow_index, wire). OptionAdapter.on_card_clicked
# expects (slot_wire: String, shadow_index: int), so swap the bind order:
slot.card_clicked.connect(
    func(_s, idx): _input.adapter.on_card_clicked(wire, idx)
)
```

## Migration checklist for `board.gd`

Order matters here — the old file's methods migrate to different places:

| Old method | New home |
|---|---|
| `_ready` | `board.gd::configure` (receives router); `_ready` becomes trivial |
| `_bind_slots`, `_bind_weapon_slots`, `_find_slots`, `_find_weapon_slots` | Stay in `board.gd` |
| `_wire_for` | Delete — use `Catalog.slot_wire_for` |
| `_on_changed`, `_change_pass` | **Delete.** Scheduler + router subscriptions replace this. |
| `_run_events` | **Delete.** DivergenceMonitor + Dispatcher.play_batch replace this. |
| `_full_rebuild` | **Delete.** Dispatcher.full_rebuild replaces this. |
| `_rebuild_slot_contents` | **Delete.** Inside Dispatcher.full_rebuild. |
| `_apply_prompt_highlights`, `_decorate_option` | **Delete.** Dispatcher.play_prompt_decorations replaces. |
| `_update_info_panel` | Stay — but triggered by router.state_received and router.prompt_received, not _on_changed. |
| `_on_slot_card_clicked` etc. | **Delete.** OptionAdapter methods. |
| `_respond_matching`, `_dict_content_equal`, `_respond` | **Delete.** OptionValidator. |
| `_on_slot_card_hovered`, `_on_slot_card_unhovered` | Stay — hover preview is a scene-local concern (info_panel.preview_card). |
| `_place_info_panel_for_side` | Stay. |

Net: the new `board.gd` should be ~80-120 lines, mostly tree-walking and signal wiring.

## Autoload references to remove

The old `board.gd` had ~15 references to `GameSession.*` and implicit use of `NetworkTransport`. Under the new scheme, `Board` has exactly one reference to an injected dependency: the `NexusRouter`. Everything else flows from there.

Replace:
- `GameSession.my_side` → `router.session.catalog.my_color` (or, better, inject my_color directly at configure time).
- `GameSession.my_role`, `GameSession.my_alignment` → read from the latest `StateSnapshot` in the info panel update.
- `GameSession.catalog` → `router.session.catalog`.
- `GameSession.log` → pass a logger in at configure time if needed, or drop (logging is a session-level concern, not a board concern).
- `GameSession.respond(opt)` → `router.send_response(opt)`, hidden behind the InputHandler pipeline.
