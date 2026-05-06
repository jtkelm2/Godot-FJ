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
##
## Outbound:
##   option_accepted(option: Option) — fires when the validator matches a
##                                     candidate against the pending prompt.
##                                     Composer wires this to
##                                     `nexus.send_response`.

class_name InputHandler extends Node


signal option_accepted(option: Option)


var _adapter: OptionAdapter
var _validator: OptionValidator


func _ready() -> void:
	_adapter = OptionAdapter.new()
	_validator = OptionValidator.new()
	_adapter.option_candidate.connect(_validator.consider)
	_validator.option_accepted.connect(option_accepted.emit)


# --- Inbound PL channel ---

func set_pending_prompt(prompt: Prompt) -> void:
	_validator.set_pending(prompt)


func clear_pending() -> void:
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
