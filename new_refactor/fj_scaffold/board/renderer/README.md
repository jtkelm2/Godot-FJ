# board/renderer/

The `Renderer`: animation primitives and completion signals. Knows nothing of NL.

See `architecture.md §Renderer`.

## Authoritative order vs. display order

`Slot._cards` is the authoritative card list — server-driven, mutated only by NL events. User drag-reorder in the hand (when implemented) rearranges the scene-tree child order of `Card` nodes for display purposes only; `_cards` is untouched. Click dispatch returns indices into `_cards` — RL options reference authoritative positions, not the scene-tree position the user sees.

The old `fj/ui/simple_slot.gd` already keeps `card[0]` as the input-receiving sibling via scene-tree reordering; that pattern stays. The scene tree is the display-order carrier, `_cards` is the authoritative carrier, and neither needs a permutation table to connect them.

## Files

| File | Responsibility | Old-client analogue |
|---|---|---|
| `slot.gd` | `class_name Slot` ABC. Shadow + σ. Click/hover signal choreography. | `fj/ui/slot.gd` |
| `simple_slot.gd` | Pile/hand layout. Resolves through σ for rendering. | `fj/ui/simple_slot.gd` |
| `slot_field.gd` | Aggregate slot over child slots (for equipment, sidebar). | `fj/ui/slot_field.gd` |
| `weapon_slot.gd` | Composite over holster + killstack. | `fj/ui/weapon_slot.gd` |
| `card.gd` | Leaf widget: front/back/highlight. | `fj/ui/card.gd` |
| `highlight.gd` | `class_name Highlight`. The decoration level enum. | `fj/ui/highlight.gd` |
| `slot_wrangler.gd` | Bridge between wire names (CardInstance) and UI widgets (Card). | `fj/ui/slot_wrangler.gd` |

## Renderer API contract

The `Renderer` exposes to the `Conductor`:

- `slot_for(wire_name: String) -> Slot` — lookup a slot widget by wire name.
- `weapon_slot_for(ws_wire: String) -> WeaponSlot` — same for weapon slots.
- `overlay() -> Control` — the Control for in-flight cards.
- `highlight(target, level)` — set a highlight on a Slot/Card/WeaponSlot.
- `completion_signal()` — a signal that fires every time an animation finishes. `ReadinessTracker` subscribes here.

No method on the Renderer takes a DL term or a StateSnapshot. The Conductor translates those into primitive calls.

## Migration notes

Old `fj/ui/slot.gd` already has the right shape (abstract base + concrete subclasses). The main changes:

1. Keep `_cards` as-is — it's the authoritative list. No shadow/display split, no permutation array.

2. Click dispatch already returns `_index_of(card)` (an index into `_cards`). That's exactly what `OptionAdapter.on_card_clicked` wants — no translation needed.

3. Remove the `owner_side`/`role` fields from Slot — those were load-bearing for the old board.gd's wire-name resolution, but now resolution happens via `SlotWrangler`/`Catalog` and the Slot is identity-free until bound by the scene.

4. Preserve the tree-reordering logic in `simple_slot.gd` that makes `card[0]` the input-receiving sibling.
