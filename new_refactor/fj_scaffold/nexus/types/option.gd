## RL language: typed options a client may emit in response to a prompt.
## NL — wire-agnostic. Serialization/deserialization happens in wire/.
##
## Per the Python sketch this is 3 variants, not 4: the wire's `card` collapses
## into `LocOption(SlotLoc(slot, idx))`, and the wire's `weapon_slot` collapses
## into `SlotOption(SlotID.WeaponZone(side, num))`. The wire/NL boundary
## (Catalog + Serializer/Deserializer in Phase 2) handles the projection.

@abstract
class_name Option extends NL


## Used by OptionValidator to match candidate options against pending prompt
## options by structural equality. Reference equality via `==` would only work
## if both came from the same Catalog-vended canonical instance.
@abstract func equals(other: Option) -> bool


class TextOption extends Option:
	var text: String
	func _init(t: String) -> void:
		text = t
	func equals(other: Option) -> bool:
		return other is TextOption and (other as TextOption).text == text


class LocOption extends Option:
	var loc: Loc
	func _init(l: Loc) -> void:
		loc = l
	func equals(other: Option) -> bool:
		if not (other is LocOption):
			return false
		return _loc_equals(loc, (other as LocOption).loc)

	## Structural equality for Loc. Phase 2 may move this onto Loc itself
	## once Catalog vends canonical SlotID instances and reference equality
	## becomes reliable.
	static func _loc_equals(a: Loc, b: Loc) -> bool:
		if a is Loc.UnknownLoc:
			return b is Loc.UnknownLoc
		if a is Loc.SlotLoc and b is Loc.SlotLoc:
			var sa := a as Loc.SlotLoc
			var sb := b as Loc.SlotLoc
			return sa.slot == sb.slot and sa.idx == sb.idx
		return false


class SlotOption extends Option:
	var slot: SlotID
	func _init(s: SlotID) -> void:
		slot = s
	func equals(other: Option) -> bool:
		return other is SlotOption and (other as SlotOption).slot == slot
