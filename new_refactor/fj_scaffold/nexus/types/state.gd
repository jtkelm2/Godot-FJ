## SL language: typed state snapshot. NL — wire-agnostic.
## Deserialization happens in wire/ (Phase 2).
##
## Symmetric in player perspective: `role` and `hp` are dicts keyed by PID,
## not single-side fields. The wire (per protocol §3.2) only carries the
## receiving player's role and HP, but the NL type is symmetric so consumers
## written against State don't need to know which perspective they're in.
## Game outcome is conveyed by the trailing DL.GameEnded event, not by State.

class_name State extends NL


class Role extends RefCounted:
	var alignment: NLEnums.Alignment
	var role_name: String
	func _init(a: NLEnums.Alignment = NLEnums.Alignment.GOOD, n: String = "") -> void:
		alignment = a
		role_name = n


class HP extends RefCounted:
	var val: int
	var cap: int
	var floor: int
	func _init(v: int = 0, c: int = 0, f: int = 0) -> void:
		val = v
		cap = c
		floor = f


## Tagged union: visible card list, fog-of-war count, or fully hidden.
## Hidden slots are absent from the wire entirely; the UNKNOWN tag makes
## that state explicit and uniform. Construct via the PascalCase factories.
class SlotContents extends RefCounted:
	enum Type { UNKNOWN, COUNT, FULL }

	var type: Type
	var n: int = 0                              ## Used when type == COUNT.
	var cards: Array[CardInstance] = []         ## Used when type == FULL.

	static func Unknown() -> SlotContents:
		var s := SlotContents.new()
		s.type = Type.UNKNOWN
		return s

	static func Count(p_n: int) -> SlotContents:
		var s := SlotContents.new()
		s.type = Type.COUNT
		s.n = p_n
		return s

	static func Full(p_cards: Array[CardInstance]) -> SlotContents:
		var s := SlotContents.new()
		s.type = Type.FULL
		s.cards = p_cards
		return s


var role: Dictionary    ## Dict[NLEnums.PID, Role]
var hp: Dictionary      ## Dict[NLEnums.PID, HP]
var phase: NLEnums.Phase = NLEnums.Phase.NONE
var priority: NLEnums.PID = NLEnums.PID.RED
var slots: Dictionary   ## Dict[SlotID, SlotContents]
