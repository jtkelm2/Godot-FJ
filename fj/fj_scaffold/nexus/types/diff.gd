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


# --- Description ---

## One-line human-readable summary of this event. Variant-specific: only the
## fields relevant to the current `type` are read. Used by the Logger; safe
## to call on any DL.
func describe() -> String:
	match type:
		Type.CARD_MOVED:
			return "CardMoved %s → %s" % [_loc_str(orig), _loc_str(dest)]
		Type.SLOT_TRANSFERRED:
			return "SlotTransferred %s → %s (×%d)" % [_slot_str(orig_slot), _slot_str(dest_slot), count]
		Type.HP_CHANGED:
			return "HPChanged %s: %d → %d" % [NLEnums.PID.keys()[target], old_hp, new_hp]
		Type.SLOT_SHUFFLED:
			return "SlotShuffled %s" % _slot_str(slot)
		Type.PLAYER_DIED:
			return "PlayerDied %s" % NLEnums.PID.keys()[target]
		Type.PHASE_CHANGED:
			return "PhaseChanged %s" % NLEnums.Phase.keys()[phase]
		Type.GAME_ENDED:
			return "GameEnded %s won=%s" % [NLEnums.Outcome.keys()[outcome], won]
	return "<unknown DL>"


## SlotID / Loc don't yet carry their own `describe`; these are private
## stopgaps for DL's own formatter. Lift them onto SlotID / Loc if other
## consumers want the same string form.
static func _slot_str(s: SlotID) -> String:
	if s == null:
		return "null"
	var t: String = SlotID.Type.keys()[s.type]
	if s.type == SlotID.Type.GUARD_DECK:
		return t
	if s.type == SlotID.Type.WS or s.type == SlotID.Type.WS_WEAPON or s.type == SlotID.Type.WS_KILLSTACK:
		return "%s/%s/%d" % [NLEnums.PID.keys()[s.side], t, s.num]
	return "%s/%s" % [NLEnums.PID.keys()[s.side], t]


static func _loc_str(loc: Loc) -> String:
	if loc == null:
		return "null"
	if loc.type == Loc.Type.UNKNOWN:
		return "?"
	return "%s[%d]" % [_slot_str(loc.slot), loc.idx]
