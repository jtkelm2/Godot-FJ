## DL language: typed game-state events. NL — wire-agnostic.
## Deserialization happens in wire/ (Phase 2).

@abstract
class_name DL extends NL


class CardMoved extends DL:
	var orig: Loc  ## Loc.UnknownLoc if the card had no prior slot.
	var dest: Loc
	func _init(o: Loc, d: Loc) -> void:
		orig = o
		dest = d


class SlotTransferred extends DL:
	var orig: SlotID
	var dest: SlotID
	var count: int
	func _init(o: SlotID, d: SlotID, c: int) -> void:
		orig = o
		dest = d
		count = c


class HPChanged extends DL:
	## `new` is a reserved identifier in GDScript, so val fields are *_hp.
	## `target` is included for symmetry — fog-of-war filters this so only the
	## receiving client's own HP changes are emitted, but the field is part of
	## the wire schema (§3.2.3).
	var target: NLEnums.PID
	var old_hp: int
	var new_hp: int
	func _init(t: NLEnums.PID, o: int, n: int) -> void:
		target = t
		old_hp = o
		new_hp = n


class SlotShuffled extends DL:
	var slot: SlotID
	func _init(s: SlotID) -> void:
		slot = s


class PlayerDied extends DL:
	var target: NLEnums.PID
	func _init(t: NLEnums.PID) -> void:
		target = t


class PhaseChanged extends DL:
	## Always carries a value. NLEnums.Phase.NONE represents wire-null
	## (between phases).
	var phase: NLEnums.Phase
	func _init(p: NLEnums.Phase) -> void:
		phase = p


class GameEnded extends DL:
	var outcome: NLEnums.Outcome
	var won: Dictionary  ## Dict[NLEnums.PID, bool]
	func _init(o: NLEnums.Outcome, w: Dictionary) -> void:
		outcome = o
		won = w
