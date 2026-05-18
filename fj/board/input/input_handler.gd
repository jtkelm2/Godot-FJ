## InputHandler: the small assembly that holds an OptionAdapter and an
## OptionValidator and exposes their combined surface to the composer.
##
## Inbound (composer wires to these):
##   set_pending_prompt(prompt)    — from `nexus.pl_in`.
##   clear_pending()               — when an answered prompt should also
##                                   clear if the engine ever cancels one.
##   on_card_clicked(slot, idx)    — bound from each SlotView's
##                                   `card_clicked` with the SlotID.
##   on_slot_clicked(slot)         — bound from each SlotView's
##                                   `slot_clicked` with the SlotID.
##   on_weapon_slot_clicked(slot)  — bound from each WeaponSlotView's
##                                   `weapon_slot_clicked` with the SlotID.
##   on_text_option(option)        — from info_panel.text_option_selected.
##   on_revealed_cards_chosen(idx) — from CardPresenter.selection_made;
##                                   indices into the pending prompt's
##                                   options array. InputHandler resolves
##                                   them against its own pending-prompt
##                                   stash before forwarding to the adapter.
##
## Outbound:
##   option_accepted(opts: Array[Option]) — fires when the validator matches
##                                          a candidate set against the
##                                          pending prompt. Composer wires
##                                          this to `nexus.send_response`.
##                                          Length-1 = single-select;
##                                          length>=2 = multi-select.

class_name InputHandler extends Node


signal option_accepted(options: Array[Option])


var _adapter: OptionAdapter
var _validator: OptionValidator
## Cached for indices→options resolution in `on_revealed_cards_chosen`. The
## validator holds its own pending; we keep a parallel copy so the adapter
## remains prompt-agnostic.
var _pending: Prompt = null


func _ready() -> void:
	_adapter = OptionAdapter.new()
	_validator = OptionValidator.new()
	_adapter.option_candidate.connect(_validator.consider)
	_validator.option_accepted.connect(option_accepted.emit)


# --- Inbound PL channel ---

func set_pending_prompt(prompt: Prompt) -> void:
	_pending = prompt
	_validator.set_pending(prompt)


func clear_pending() -> void:
	_pending = null
	_validator.clear_pending()


# --- Inbound input channel (composer wires scene signals here) ---

func on_card_clicked(slot: SlotID, idx: int) -> void:
	_adapter.on_card_clicked(slot, idx)


func on_slot_clicked(slot: SlotID) -> void:
	_adapter.on_slot_clicked(slot)


func on_weapon_slot_clicked(slot: SlotID) -> void:
	_adapter.on_weapon_slot_clicked(slot)


func on_text_option(option: Option) -> void:
	_adapter.on_text_option(option)


## CardPresenter emits positional indices; resolve against the pending
## prompt's options and hand the array to the adapter. No-op if no prompt
## is pending or any index is out of range (the modal shouldn't fire under
## those conditions, but defend against late signals).
func on_revealed_cards_chosen(indices: Array[int]) -> void:
	if _pending == null:
		return
	var opts: Array[Option] = []
	for i in indices:
		if i < 0 or i >= _pending.options.size():
			return
		opts.append(_pending.options[i])
	_adapter.on_revealed_cards_chosen(opts)
