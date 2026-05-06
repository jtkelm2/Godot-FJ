# board/input/

The `InputHandler`: PL in, RL out.

See `architecture.md §InputHandler`.

## Composition

```
InputHandler = OptionAdapter + OptionValidator
```

`InputHandler` is a thin Node holding both as internal RefCounteds and exposing their combined surface. The composer (Phase 6 App / Board) wires:

- `nexus.pl_in` → `input_handler.set_pending_prompt`
- each SlotView's / WeaponSlotView's input signals → `input_handler.on_*` (with the SlotID bound)
- `info_panel.text_option_selected` → `input_handler.on_text_option`
- `input_handler.option_accepted` → `nexus.send_response`

## Files

| File | Responsibility | Old-client analogue |
|---|---|---|
| `input_handler.gd` | `class_name InputHandler extends Node`. Public surface (`set_pending_prompt`, `clear_pending`, `on_card_clicked`, `on_slot_clicked`, `on_weapon_slot_clicked`, `on_text_option`, `option_accepted` signal). | Parts of `fj/ui/board.gd`. |
| `option_adapter.gd` | `class_name OptionAdapter extends RefCounted`. Native input (with SlotID already resolved by the composer's bind) → typed `Option` candidates. | `fj/ui/board.gd` click handlers. |
| `option_validator.gd` | `class_name OptionValidator extends RefCounted`. PL pending-prompt tracking + content-equality matching via `Option.equals`. Forwards the *matched* option (not the candidate) for byte-identical echo per protocol §4.4. | `fj/ui/board.gd::_respond_matching` and `_dict_content_equal`. |

## NL-only surface

OptionAdapter takes typed identities (`SlotID`, `Option.TextOption`) — never wire-name strings. Identity resolution is the composer's job: each scene-input signal is bound with the matching Catalog-vended `SlotID` at scene-init time, so the SlotID instance equals the one DL events arrive carrying (reference equality holds).

## Why not fold the validator into the adapter

Keeping them separate means:

1. `OptionValidator` is scene-tree-free and unit-testable.
2. Alternative adapters (AI, scripted test harness) can reuse the validator unchanged.
3. The validator's invariants (P2 in protocol.md: one response per prompt) are visible in one small file.
