## OptionAdapter: native scene-input → typed `Option` candidates.
##
## The composer wires each SlotView / WeaponSlotView / info_panel input
## signal to one of the `on_*` push methods, binding the relevant SlotID /
## TextOption alongside the index payload. The adapter wraps the data in
## the appropriate NL `Option` constructor and emits `option_candidate`,
## which the OptionValidator considers against the pending Prompt.
##
## Candidates are emitted as `Array[Option]` to model both single-select
## (length 1) and multi-select (length must_select) uniformly. The wire
## boundary mirrors this — `Serializer.serialize_response` projects length-1
## to the singular shape and length>=2 to the plural shape per protocol §5.1.
##
## Strictly NL-aware: the adapter takes typed identities (SlotID, TextOption)
## not wire-name strings. Identity resolution is the composer's job — it
## binds each scene signal with the matching SlotID looked up from the
## Catalog.

class_name OptionAdapter extends RefCounted


signal option_candidate(options: Array[Option])


func on_card_clicked(slot: SlotID, idx: int) -> void:
	option_candidate.emit([Option.Loc(Loc.Slot(slot, idx))] as Array[Option])


func on_slot_clicked(slot: SlotID) -> void:
	option_candidate.emit([Option.Slot(slot)] as Array[Option])


func on_weapon_slot_clicked(slot: SlotID) -> void:
	# The weapon_slots catalog and the regular slots catalog are disjoint;
	# the same Option.Slot variant carries either via the SlotID it wraps.
	# (The Serializer disambiguates at the wire boundary by checking which
	# Catalog table holds the SlotID.)
	option_candidate.emit([Option.Slot(slot)] as Array[Option])


func on_text_option(option: Option) -> void:
	option_candidate.emit([option] as Array[Option])


## Multi-select entry point. Caller resolves CardPresenter indices into the
## corresponding pending-prompt Options and hands the array here.
func on_revealed_cards_chosen(options: Array[Option]) -> void:
	option_candidate.emit(options)
