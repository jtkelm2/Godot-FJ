# board/renderer/

The `Renderer`: animation primitives + scene-tree widgets. Identity-free — Renderer widgets don't know which NL `SlotID` they represent. The composition root maintains the `Dict[SlotID, SlotView]` mapping externally.

See `architecture.md §Renderer`.

## Authoritative order vs. display order

`SlotView._cards` is the authoritative card list — server-driven, mutated only by `insert` / `remove` / `clear` calls. User drag-reorder in the hand (when implemented) rearranges the scene-tree child order of `CardView` nodes for display purposes only; `_cards` is untouched. Click dispatch returns indices into `_cards` — RL options reference authoritative positions, not the scene-tree position the user sees.

`SimpleSlotView` keeps `card[0]` (protocol's top-of-pile) as the LAST sibling in the scene tree, so Godot's input routing makes it both the visual top AND the first to receive mouse events.

## Files

| File | Defines | Old-client analogue |
|---|---|---|
| `highlight.gd` | `class_name HighlightLevel` with `enum Level { LOWLIGHT, CONTEXT, HIGHLIGHT }`. | `fj/ui/highlight.gd` |
| `card_view.gd` | `class_name CardView extends Control`. Front/back/highlight. `clicked` signal. | `fj/ui/card.gd` |
| `slot_view.gd` | `@abstract class_name SlotView extends Control`. ABC with click/hover signal choreography. Abstract: `insert`, `remove`, `clear`, `count`, `get_card`. | `fj/ui/slot.gd` |
| `simple_slot.gd` | `class_name SimpleSlotView extends SlotView`. Pile/hand layout with configurable offset. | `fj/ui/simple_slot.gd` |
| `slot_field.gd` | `class_name SlotFieldView extends SlotView`. Composite over child SlotViews (equipment, sidebar). Re-emits child signals with globally-numbered indices. | `fj/ui/slot_field.gd` |
| `weapon_slot_view.gd` | `class_name WeaponSlotView extends Node`. Composite over holster + killstack SlotViews; emits `weapon_slot_clicked` on holster empty-area click. | `fj/ui/weapon_slot.gd` |

`SlotWrangler` (NL `SlotContents` → CardView population) is **not** in the Renderer — it bridges NL into Renderer primitive calls and belongs in the Conductor (Phase 4).

## Naming convention

The Renderer widget classes carry a `View` suffix (`SlotView`, `CardView`, `SimpleSlotView`, …) to avoid colliding with the existing `fj/ui/` global `class_name`s (`Slot`, `Card`, etc.) that remain in use until Phase 6 deletes the old tree.

## Renderer API contract (Phase 4 — Conductor's view)

Conductor consumes the following from the Renderer side. There is no monolithic "Renderer" class; the composition root provides:

- `slot_for: Dict[SlotID, SlotView]` — the registered SlotID → widget mapping.
- `weapon_slot_for: Dict[SlotID.WeaponZone, WeaponSlotView]` — same for weapon slots.
- `overlay: Control` — a Control under which in-flight cards are reparented during animations.
- `completion_signal: Signal` — fires whenever an animation finishes. `ReadinessTracker` subscribes here.
- `highlight(target, level)` — set a `HighlightLevel.Level` on a `SlotView` / `CardView` / `WeaponSlotView`.

No method on the Renderer takes a DL term or a State snapshot. The Conductor translates those into primitive calls.

## Migration notes from `fj/ui/`

Behaviorally close ports of the old widgets, with these adjustments:

1. `_cards` is kept as-is — authoritative, server-driven. No shadow/display split, no permutation array.
2. Click dispatch returns `_index_of(card)` — an index into `_cards`. That index is the exact value an `OptionAdapter.on_card_clicked` consumer wants.
3. `owner_side` and `role` exports are **removed** from `SlotView` and `WeaponSlotView`. Wire-name resolution is the wire layer's job; the Renderer is identity-free.
4. `WeaponSlotView` no longer reaches into the Catalog to derive its wire identifiers (`ws_wire`, `holster_wire`, `killstack_wire`).
5. The tree-reordering pattern in `SimpleSlotView` (card[0] = last sibling) is preserved.

## Scene files

`.tscn` files for each widget are NOT included in Phase 3. They will be ported (with script references rebound to the new `View` classes) when the Board scene is assembled in Phase 5.
