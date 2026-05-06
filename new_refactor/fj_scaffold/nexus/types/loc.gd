## NL location — where a card is, in NL terms. Wire-agnostic.
##
## Tagged-union flattening: one concrete class with a `Type` enum tag plus
## the union of fields each former-constructor needed. Use the PascalCase
## static factories (`Loc.Unknown()`, `Loc.Slot(slot, idx)`) for construction.
##
## Index convention follows the protocol's: 0 is the top of the pile.

class_name Loc extends RefCounted


enum Type { UNKNOWN, SLOT }


var type: Type
var slot: SlotID = null     ## Used when type == SLOT.
var idx: int = 0            ## Used when type == SLOT.


# --- PascalCase factories ---

static func Unknown() -> Loc:
	var l := Loc.new()
	l.type = Type.UNKNOWN
	return l


static func Slot(p_slot: SlotID, p_idx: int) -> Loc:
	var l := Loc.new()
	l.type = Type.SLOT
	l.slot = p_slot
	l.idx = p_idx
	return l


# --- Equality ---

func equals(other: Loc) -> bool:
	if other == null or other.type != type:
		return false
	match type:
		Type.UNKNOWN:
			return true
		Type.SLOT:
			return slot.equals(other.slot) and idx == other.idx
	return false
