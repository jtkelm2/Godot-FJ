## SL language: typed state snapshot. NL — wire-agnostic.
## Deserialization happens in wire/ (Phase 2).
##
## Symmetric in player perspective: `role` and `hp` are dicts keyed by PID,
## not single-side fields. The wire (per protocol §3.2) only carries the
## receiving player's role and HP, but the NL type is symmetric so consumers
## written against State don't need to know which perspective they're in.
## Game outcome is conveyed by the trailing DL.GameEnded event, not by State.

class_name State extends RefCounted


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
## Hidden slots are absent from the wire entirely; here `UnknownContents`
## makes that state explicit and uniform.
@abstract
class SlotContents extends RefCounted:
	pass


class UnknownContents extends SlotContents:
	pass


class CountContents extends SlotContents:
	var n: int
	func _init(count: int = 0) -> void:
		n = count


class FullContents extends SlotContents:
	var cards: Array[CardInstance]
	func _init(c: Array[CardInstance] = []) -> void:
		cards = c


var role: Dictionary    ## Dict[NLEnums.PID, Role]
var hp: Dictionary      ## Dict[NLEnums.PID, HP]
var phase: NLEnums.Phase = NLEnums.Phase.NONE
var priority: NLEnums.PID = NLEnums.PID.RED
var slots: Dictionary   ## Dict[SlotID, SlotContents]
