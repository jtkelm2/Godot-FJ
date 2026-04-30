## NL enum namespace. Wire-agnostic. Access as `NLEnums.PID.RED`, etc.

@abstract
class_name NLEnums extends RefCounted


enum PID { RED, BLUE }


## NONE represents wire-null (between phases). Always carry a value; consumers
## that care about the transition match against NONE explicitly.
enum Phase { NONE, SETUP, REFRESH, MANIPULATION, ACTION }


enum Alignment { GOOD, EVIL }


enum CardType { WEAPON, EQUIPMENT, ENEMY, FOOD, EVENT }


## Game outcomes per protocol §3.2.2.
enum Outcome {
	MUTUAL_GOOD_WIN,
	GOOD_KILLED_EVIL,
	EVIL_KILLED_GOOD,
	GOOD_KILLED_GOOD,
	EXHAUSTION,
	GOOD_GOOD_MUTUAL_DEATH,
	GOOD_EVIL_MUTUAL_DEATH,
	GOOD_THWARTED,
	EVIL_THWARTED,
}


## Discrete slot kinds — one value per `SlotID` constructor. Used as the
## type-safe identity export on `SlotView` and as the dispatch key for
## `SlotID.make(kind, side, num)`.
enum SlotKind {
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
	WS,             ## the weapon slot itself (WeaponZone). Used by Catalog internally.
	WS_WEAPON,      ## the weapon-card holster (Holster).
	WS_KILLSTACK,   ## the kill stack (Killstack).
}
