# board/scenes/

The `Board` scene — a passive Renderer scene. The script's only job is to expose its widgets and overlay; the composition root (`app/session.gd`) does all wiring.

## Files

| File | Responsibility |
|---|---|
| `board.gd` | `class_name Board extends Control`. Accessor-only. `find_slot_views()`, `find_weapon_slot_views()`, plus `info_panel` and `overlay` as `@onready` exposed members. |
| `board.tscn` | Scene hierarchy ported from `fj/ui/board.tscn`, paths rebound to the new View classes. SlotView / WeaponSlotView instances carry `side` (PID) / `role` / `num` exports. |
| `info_panel.gd` | NL-aware port of `fj/ui/info_panel.gd`. Holds `my_pid` permanently (set once via `set_my_pid` at session start). `bind_state(state)`, `bind_prompt(prompt)`, `flash_hp(target, old, new)`, `set_phase`, `mark_player_died`, `set_game_result`, `show_notify`, `preview_card`. Emits `text_option_selected` and `animation_started` / `animation_finished` (so the composer can gate the queue on info-panel-side animations). |
| `info_panel.tscn` | Panel layout, ported. |

## What `board.gd` does NOT do

- No reference to `Conductor`, `InputHandler`, `NexusRouter`, or `Catalog`.
- No signal wiring.
- No NL handling.

That's all `app/session.gd`'s job. The Board scene is identity-free at the renderer layer; identity resolution (mapping each `SlotView`'s `(side, role, num)` exports to a Catalog-vended `SlotID`) happens in Session.

## Renderer API the Conductor consumes

The Conductor (set up by Session) is given:

- `slot_for: Dict[SlotID, SlotView]` — built by Session by walking the Board.
- `weapon_slot_for: Dict[SlotID.WeaponZone, WeaponSlotView]` — same.
- `overlay: Control` — `board.overlay`, the parent for in-flight cards.
- `card_factory: Callable` — a closure that instantiates a fresh CardView.
- `back_for_slot: Callable` — a closure mapping SlotID → Texture2D back.

None of the above is exposed by Board; Session builds them.

## Identity exports on widgets

Each SlotView in `board.tscn` carries `side` (PID enum), `role` (matches the protocol slot role string — `"hand"`, `"deck"`, `"action_field_top_distant"`, …), and `num` (used only for `ws_weapon` / `ws_killstack` interior roles). WeaponSlotView carries `side` and `num` directly and propagates them plus the fixed roles to its holster/killstack children at `_ready`.

## Migration vs `fj/ui/board.gd`

Old `board.gd` was ~330 lines doing six roles. The new `board.gd` is ~30 lines doing one. Everything else moved:

| Old role | New home |
|---|---|
| Tree-walk slot binding | `Board.find_slot_views()` + Session._build_slot_dicts |
| `_change_pass`, animation queue, busy guard | Conductor.Scheduler + ReadinessTracker |
| `_run_events`, divergence check | Conductor.DivergenceMonitor |
| `_full_rebuild`, slot-contents reconciliation | Dispatcher._full_rebuild + SlotWrangler |
| Highlight application | Dispatcher._apply_prompt |
| Click handlers (`_on_slot_card_clicked`, etc.) | OptionAdapter, with SlotID bound by Session |
| `_respond_matching`, `_dict_content_equal` | OptionValidator |
| Info-panel updates (`_update_info_panel`) | Conductor's per-event signals → InfoPanel methods (wired by Session) |
| `GameSession.respond` | `nexus.send_response`, fed by `input.option_accepted` (wired by Session) |
