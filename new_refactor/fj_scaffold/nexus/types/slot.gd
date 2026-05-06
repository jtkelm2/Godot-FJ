## NL slot identity. Wire-agnostic — no wire names, no Catalog references.
##
## Tagged-union flattening: one concrete class with a `Type` enum tag plus
## the union of fields each former-constructor needed. PascalCase static
## factories (`SlotID.Hand(side)` etc.) are the construction surface;
## `make(type, side, num)` is the dynamic-dispatch helper for callers that
## hold the type as data (Catalog wire-role parsing).
##
## Structural identity is exposed via `equals(other)`. SlotID instances are
## NOT interned — consumers that need dict-by-SlotID lookups write their
## own private linear-search helpers using `equals`.
##
## Base name is `SlotID` (not `Slot`) because the UI widget `fj/ui/slot.gd`
## already registers `class_name Slot` globally.

class_name SlotID extends RefCounted


## Discrete slot kinds — one value per former constructor.
enum Type {
	GUARD_DECK,
	HAND,
	DECK,
	REFRESH,
	DISCARD,
	EQUIPMENT,
	SIDEBAR,
	ACTION_FIELD_TOP_DISTANT,
	ACTION_FIELD_TOP_HIDDEN,
	ACTION_FIELD_BOTTOM_DISTANT,
	ACTION_FIELD_BOTTOM_HIDDEN,
	WS,             ## the weapon slot itself (formerly WeaponZone). Used by Catalog.
	WS_WEAPON,      ## the weapon-card holster (formerly Holster).
	WS_KILLSTACK,   ## the kill stack (formerly Killstack).
}


var type: Type
var side: NLEnums.PID    ## Ignored by GuardDeck.
var num: int             ## Used only by WS / WS_WEAPON / WS_KILLSTACK.


# --- Construction ---

## Dynamic-dispatch factory for callers that hold the type as data.
static func make(t: Type, p_side: NLEnums.PID, p_num: int) -> SlotID:
	var s := SlotID.new()
	s.type = t
	s.side = p_side
	s.num = p_num
	return s


# --- PascalCase factories, one per former constructor ---

static func GuardDeck() -> SlotID:
	return make(Type.GUARD_DECK, NLEnums.PID.RED, 0)


static func Hand(p_side: NLEnums.PID) -> SlotID:
	return make(Type.HAND, p_side, 0)


static func Deck(p_side: NLEnums.PID) -> SlotID:
	return make(Type.DECK, p_side, 0)


static func Refresh(p_side: NLEnums.PID) -> SlotID:
	return make(Type.REFRESH, p_side, 0)


static func Discard(p_side: NLEnums.PID) -> SlotID:
	return make(Type.DISCARD, p_side, 0)


static func Equipment(p_side: NLEnums.PID) -> SlotID:
	return make(Type.EQUIPMENT, p_side, 0)


static func Sidebar(p_side: NLEnums.PID) -> SlotID:
	return make(Type.SIDEBAR, p_side, 0)


static func ActionTopDistant(p_side: NLEnums.PID) -> SlotID:
	return make(Type.ACTION_FIELD_TOP_DISTANT, p_side, 0)


static func ActionTopHidden(p_side: NLEnums.PID) -> SlotID:
	return make(Type.ACTION_FIELD_TOP_HIDDEN, p_side, 0)


static func ActionBottomDistant(p_side: NLEnums.PID) -> SlotID:
	return make(Type.ACTION_FIELD_BOTTOM_DISTANT, p_side, 0)


static func ActionBottomHidden(p_side: NLEnums.PID) -> SlotID:
	return make(Type.ACTION_FIELD_BOTTOM_HIDDEN, p_side, 0)


static func WeaponZone(p_side: NLEnums.PID, p_num: int) -> SlotID:
	return make(Type.WS, p_side, p_num)


static func Holster(p_side: NLEnums.PID, p_num: int) -> SlotID:
	return make(Type.WS_WEAPON, p_side, p_num)


static func Killstack(p_side: NLEnums.PID, p_num: int) -> SlotID:
	return make(Type.WS_KILLSTACK, p_side, p_num)


# --- Equality ---

func equals(other: SlotID) -> bool:
	return other != null and other.type == type and other.side == side and other.num == num
