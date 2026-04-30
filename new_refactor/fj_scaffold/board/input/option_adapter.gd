## OptionAdapter: native scene-input → typed `Option` candidates.
##
## The composer wires each SlotView / WeaponSlotView / info_panel input
## signal to one of the `on_*` push methods, binding the relevant SlotID /
## TextOption alongside the index payload. The adapter wraps the data in
## the appropriate NL `Option` constructor and emits `option_candidate`,
## which the OptionValidator considers against the pending Prompt.
##
## Strictly NL-aware: the adapter takes typed identities (SlotID, TextOption)
## not wire-name strings. Identity resolution is the composer's job — it
## binds each scene signal with the matching SlotID looked up from the
## Catalog.

class_name OptionAdapter extends RefCounted


signal option_candidate(option: Option)


func on_card_clicked(slot: SlotID, idx: int) -> void:
	option_candidate.emit(Option.LocOption.new(Loc.SlotLoc.new(slot, idx)))


func on_slot_clicked(slot: SlotID) -> void:
	option_candidate.emit(Option.SlotOption.new(slot))


func on_weapon_slot_clicked(slot: SlotID) -> void:
	# The weapon_slots catalog and the regular slots catalog are disjoint;
	# the same Option.SlotOption variant carries either via the SlotID it
	# wraps. (The Serializer disambiguates at the wire boundary by checking
	# which Catalog table holds the SlotID.)
	option_candidate.emit(Option.SlotOption.new(slot))


func on_text_option(option: Option.TextOption) -> void:
	option_candidate.emit(option)
