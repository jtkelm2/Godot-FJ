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
