# board/input/

The `InputHandler`: PL in, RL out.

See `architecture.md §InputHandler`.

## Composition

```
InputHandler = OptionAdapter + OptionValidator
```

## Files

| File | Responsibility | Old-client analogue |
|---|---|---|
| `input_handler.gd` | Wrapper that holds the validator and exposes the RL-emit point. | Parts of `fj/ui/board.gd`. |
| `option_adapter.gd` | Scene-input (clicks, text button presses) → Option values. | `fj/ui/board.gd` click handlers + `info_panel.text_option_selected`. |
| `option_validator.gd` | PL pending-prompt tracking + echo matching. | `fj/ui/board.gd::_respond_matching` and `_dict_content_equal`. |

## API surface

### InputHandler

```gdscript
class_name InputHandler
extends RefCounted

func _init(router: NexusRouter)

# router.prompt_received → validator.set_pending
# validator.option_accepted → router.send_response
```

### OptionAdapter

Native → Option translation. The scene's click/hover signals wire in here.

```gdscript
class_name OptionAdapter
extends RefCounted

signal option_candidate(option: Option)

func on_card_clicked(slot_wire: String, shadow_index: int) -> void
    # emit CardOption(slot_wire, shadow_index)

func on_slot_clicked(slot_wire: String) -> void
    # emit SlotOption(slot_wire)

func on_weapon_slot_clicked(ws_wire: String) -> void
    # emit WeaponSlotOption(ws_wire)

func on_text_option_selected(option: Option.TextOption) -> void
    # emit TextOption as-is (already typed — the info panel constructs it)
```

### OptionValidator

Tracks the current prompt and matches incoming Option candidates against it.

```gdscript
class_name OptionValidator
extends RefCounted

signal option_accepted(option: Option)
    # emitted when a candidate structurally matches a pending option;
    # the matched option is forwarded (ensuring byte-identical echo).

func set_pending(prompt: Prompt) -> void
    # called on router.prompt_received. Replaces any previous pending.

func set_pending_none() -> void
    # called when the prompt has been answered; blocks further
    # candidates from being forwarded.

func consider(candidate: Option) -> void
    # called on OptionAdapter.option_candidate. Walks pending.options,
    # uses Option.equals for content comparison, emits option_accepted
    # on match (forwarding the MATCHED option, not the candidate, so
    # echo is byte-identical).
```

## Why not fold the validator into the adapter

Keeping them separate means:

1. `OptionValidator` is scene-tree-free and unit-testable.
2. Alternative adapters (AI, scripted test harness) can reuse the validator unchanged.
3. The validator's invariants (P2 in protocol.md: one response per prompt) are visible in one small file.

## Migration notes

The old `board.gd` had `_on_slot_card_clicked` / `_on_slot_slot_clicked` / `_on_weapon_slot_clicked` / `_on_text_option_selected` all calling a local `_respond_matching`. The adapter absorbs the click handlers; the validator absorbs `_respond_matching` and `_dict_content_equal`.

Under the new architecture, the validator uses `Option.equals` (content comparison via the typed ADT), not `_dict_content_equal` on raw Dictionaries. The matched option is forwarded to the router, not the candidate — this preserves byte-identical echo for `protocol.md §4.4`.
