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
	POST_MANIPULATE,
	PLAYER_DIED,
	PHASE_CHANGED,
	GAME_ENDED,
	ROLE_ASSIGNED
}

enum CardState {
	FACEUP,
	FACEDOWN,
	DISCARD,
}

var type: Type
var orig: Loc = null                 ## CARD_MOVED. Loc.Unknown() if no prior slot.
var dest: Loc = null                 ## CARD_MOVED.
## CARD_MOVED. Carries the moved card's identity when the server has it
## visible to this player (either endpoint card-visible). `null` means the
## protocol omitted it (both endpoints count-only or hidden) and the client
## must fall back to source-side extraction or treat the move as opaque.
var card: CardInstance = null
var card_endstate: CardState = CardState.FACEUP
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
## NLEnums.Phase.NONE represents wire-null (between phases / phase ended
## without a new one starting — protocol §3.2.3 omits the key in that case).
var phase: NLEnums.Phase = NLEnums.Phase.NONE  ## PHASE_CHANGED.
var outcome: NLEnums.Outcome = NLEnums.Outcome.EXHAUSTION  ## GAME_ENDED.
var won: Dictionary[NLEnums.PID, bool] = {}     ## GAME_ENDED.
## POST_MANIPULATE. Which player manipulated.
var manipulator: NLEnums.PID = NLEnums.PID.RED
## POST_MANIPULATE. Index (0 or 1) of the sidebar card the manipulator
## forced; -1 means the field was absent (no force, or the receiving player
## isn't the manipulator). See protocol §3.2.3.
var into_hidden_zone: bool = false
var forced: int = -1
var role: State.Role = null


# --- PascalCase factories ---

## `p_card` is optional — pass `null` when the protocol omits the `card`
## field (both endpoints hidden or count-only).
static func CardMoved(p_orig: Loc, p_dest: Loc, p_card_endstate: CardState, p_card: CardInstance = null) -> DL:
	var d := DL.new()
	d.type = Type.CARD_MOVED
	d.orig = p_orig
	d.dest = p_dest
	d.card = p_card
	d.card_endstate = p_card_endstate
	return d


static func SlotTransferred(p_orig: SlotID, p_dest: SlotID, p_card_endstate: CardState, p_count: int) -> DL:
	var d := DL.new()
	d.type = Type.SLOT_TRANSFERRED
	d.orig_slot = p_orig
	d.dest_slot = p_dest
	d.count = p_count
	d.card_endstate = p_card_endstate
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


## `p_forced` of -1 means the field was absent on the wire.
static func PostManipulate(p_manipulator: NLEnums.PID, p_forced: int = -1, p_into_hidden_zone:bool = false) -> DL:
	var d := DL.new()
	d.type = Type.POST_MANIPULATE
	d.manipulator = p_manipulator
	d.forced = p_forced
	d.into_hidden_zone = p_into_hidden_zone
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

static func RoleAssigned(p_player: NLEnums.PID, p_card: CardInstance, p_role:State.Role):
	var d = DL.new()
	d.type = Type.ROLE_ASSIGNED
	d.target = p_player
	d.card = p_card
	d.role = p_role
	return d

# --- Description ---

## One-line human-readable summary of this event. Variant-specific: only the
## fields relevant to the current `type` are read. Used by the Logger; safe
## to call on any DL.
func describe() -> String:
	match type:
		Type.CARD_MOVED:
			var card_str := " [%s]" % card.describe() if card != null else ""
			return "CardMoved %s → %s%s (%s)" % [orig.describe(), dest.describe(), card_str, CardState.find_key(card_endstate)]
		Type.SLOT_TRANSFERRED:
			return "SlotTransferred %s → %s (×%d) (%s)" % [orig_slot.describe(), dest_slot.describe(), count, CardState.find_key(card_endstate)]
		Type.HP_CHANGED:
			return "HPChanged %s: %d → %d" % [NLEnums.PID.keys()[target], old_hp, new_hp]
		Type.SLOT_SHUFFLED:
			return "SlotShuffled %s" % slot.describe()
		Type.POST_MANIPULATE:
			var force_str := " forced=%d" % forced if forced >= 0 else ""
			return "PostManipulate %s%s" % [NLEnums.PID.keys()[manipulator], force_str]
		Type.PLAYER_DIED:
			return "PlayerDied %s" % NLEnums.PID.keys()[target]
		Type.PHASE_CHANGED:
			return "PhaseChanged %s" % NLEnums.Phase.keys()[phase]
		Type.GAME_ENDED:
			return "GameEnded %s won=%s" % [NLEnums.Outcome.keys()[outcome], won]
	return "<unknown DL>"
