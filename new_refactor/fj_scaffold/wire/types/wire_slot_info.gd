## Wire form of slot contents. Three variants per protocol §3.2.1:
##   - UNKNOWN: hidden slot (omitted from wire dict; lifted to explicit here).
##   - COUNT:   count-only fog of war.
##   - FULL:    visible card list.
##
## Tagged-union flattening: one concrete class with a `Type` enum tag plus
## the union of fields each variant needs. Construct via the PascalCase
## factories. Wire-only — Deserializer lifts these into State.SlotContents.

class_name WireSlotInfo extends RefCounted


enum Type { UNKNOWN, COUNT, FULL }


var type: Type
var n: int = 0                              ## Used when type == COUNT.
var cards: Array[WireCardInfo] = []         ## Used when type == FULL.


# --- PascalCase factories ---

static func Unknown() -> WireSlotInfo:
	var w := WireSlotInfo.new()
	w.type = Type.UNKNOWN
	return w


static func Count(p_n: int) -> WireSlotInfo:
	var w := WireSlotInfo.new()
	w.type = Type.COUNT
	w.n = p_n
	return w


static func Full(p_cards: Array[WireCardInfo]) -> WireSlotInfo:
	var w := WireSlotInfo.new()
	w.type = Type.FULL
	w.cards = p_cards
	return w
