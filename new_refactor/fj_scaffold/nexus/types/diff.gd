## DL language: typed game-state events. NL — wire-agnostic.
## Deserialization happens in wire/.
##
## Tagged-union flattening: one concrete class with a `Type` enum tag plus
## the union of all fields each former-constructor needed. Construct via the
## PascalCase factories (`DL.CardMoved(orig, dest)` etc.); the factories set
## only the fields relevant to that variant.

class_name DL extends NL


enum Type {
	CARD_MOVED,
	SLOT_TRANSFERRED,
	HP_CHANGED,
	SLOT_SHUFFLED,
	PLAYER_DIED,
	PHASE_CHANGED,
	GAME_ENDED,
}


var type: Type
var orig: Loc = null                 ## CARD_MOVED. Loc.Unknown() if no prior slot.
var dest: Loc = null                 ## CARD_MOVED.
var slot: SlotID = null              ## SLOT_SHUFFLED.
var orig_slot: SlotID = null         ## SLOT_TRANSFERRED.
var dest_slot: SlotID = null         ## SLOT_TRANSFERRED.
var count: int = 0                   ## SLOT_TRANSFERRED.
## `target` is included for symmetry — fog-of-war filters this so only the
## receiving client's own HP changes are emitted, but the field is part of
## the wire schema (§3.2.3).
var target: NLEnums.PID = NLEnums.PID.RED  ## HP_CHANGED, PLAYER_DIED.
## `new` is a reserved identifier in GDScript, so HP val fields are *_hp.
var old_hp: int = 0                  ## HP_CHANGED.
var new_hp: int = 0                  ## HP_CHANGED.
## NLEnums.Phase.NONE represents wire-null (between phases).
var phase: NLEnums.Phase = NLEnums.Phase.NONE  ## PHASE_CHANGED.
var outcome: NLEnums.Outcome = NLEnums.Outcome.EXHAUSTION  ## GAME_ENDED.
var won: Dictionary[NLEnums.PID, bool] = {}     ## GAME_ENDED.


# --- PascalCase factories ---

static func CardMoved(p_orig: Loc, p_dest: Loc) -> DL:
	var d := DL.new()
	d.type = Type.CARD_MOVED
	d.orig = p_orig
	d.dest = p_dest
	return d


static func SlotTransferred(p_orig: SlotID, p_dest: SlotID, p_count: int) -> DL:
	var d := DL.new()
	d.type = Type.SLOT_TRANSFERRED
	d.orig_slot = p_orig
	d.dest_slot = p_dest
	d.count = p_count
	return d


static func HPChanged(p_target: NLEnums.PID, p_old: int, p_new: int) -> DL:
	var d := DL.new()
	d.type = Type.HP_CHANGED
	d.target = p_target
	d.old_hp = p_old
	d.new_hp = p_new
	return d


static func SlotShuffled(p_slot: SlotID) -> DL:
	var d := DL.new()
	d.type = Type.SLOT_SHUFFLED
	d.slot = p_slot
	return d


static func PlayerDied(p_target: NLEnums.PID) -> DL:
	var d := DL.new()
	d.type = Type.PLAYER_DIED
	d.target = p_target
	return d


static func PhaseChanged(p_phase: NLEnums.Phase) -> DL:
	var d := DL.new()
	d.type = Type.PHASE_CHANGED
	d.phase = p_phase
	return d


static func GameEnded(p_outcome: NLEnums.Outcome, p_won: Dictionary[NLEnums.PID, bool]) -> DL:
	var d := DL.new()
	d.type = Type.GAME_ENDED
	d.outcome = p_outcome
	d.won = p_won
	return d
