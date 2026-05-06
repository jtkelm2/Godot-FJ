## NL slot identity ADT. Wire-agnostic — no wire names, no Catalog references.
##
## Identity is structural: each constructor's `key()` returns
## `[kind: int, side: int, num: int]`, suitable as a Dictionary key for
## reference-free lookup. Conductor uses this to map SlotID values arriving
## via DL events to the SlotView widgets in the scene.
##
## Base name is `SlotID` (not `Slot`) because the UI widget `fj/ui/slot.gd`
## already registers `class_name Slot` globally. Same reason `WeaponZone` is
## the constructor name for the protocol's "weapon slot" — `WeaponSlot` is
## taken globally too.

@abstract
class_name SlotID extends RefCounted


## Resolver between `SlotKind` (+ side, num) and `SlotID`. Builds a fresh
## instance — there is no canonical-instance contract; structural equality
## via `key()` is what consumers compare.
static func make(kind: NLEnums.SlotKind, side: NLEnums.PID, num: int) -> SlotID:
	match kind:
		NLEnums.SlotKind.GUARD_DECK:                  return GuardDeck.new()
		NLEnums.SlotKind.HAND:                        return Hand.new(side)
		NLEnums.SlotKind.DECK:                        return Deck.new(side)
		NLEnums.SlotKind.REFRESH:                     return Refresh.new(side)
		NLEnums.SlotKind.DISCARD:                     return Discard.new(side)
		NLEnums.SlotKind.EQUIPMENT:                   return Equipment.new(side)
		NLEnums.SlotKind.SIDEBAR:                     return Sidebar.new(side)
		NLEnums.SlotKind.ACTION_FIELD_TOP_DISTANT:    return ActionTopDistant.new(side)
		NLEnums.SlotKind.ACTION_FIELD_TOP_HIDDEN:     return ActionTopHidden.new(side)
		NLEnums.SlotKind.ACTION_FIELD_BOTTOM_DISTANT: return ActionBottomDistant.new(side)
		NLEnums.SlotKind.ACTION_FIELD_BOTTOM_HIDDEN:  return ActionBottomHidden.new(side)
		NLEnums.SlotKind.WS:                          return WeaponZone.new(side, num)
		NLEnums.SlotKind.WS_WEAPON:                   return Holster.new(side, num)
		NLEnums.SlotKind.WS_KILLSTACK:                return Killstack.new(side, num)
	push_error("SlotID.make: unknown kind %d" % kind)
	return null


## Structural identity key — the dispatch handle for slot lookup. Three ints:
## `[kind, side, num]`. Side defaults to 0 for shared (`GuardDeck`); num
## defaults to 0 for non-ws kinds.
@abstract func key() -> Array


# Shared zones (no per-side variant).

class GuardDeck extends SlotID:
	func key() -> Array:
		return [NLEnums.SlotKind.GUARD_DECK, 0, 0]


# Per-side zones (parameterized by side).

class Hand extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.HAND, side, 0]


class Deck extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.DECK, side, 0]


class Refresh extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.REFRESH, side, 0]


class Discard extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.DISCARD, side, 0]


class Equipment extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.EQUIPMENT, side, 0]


class Sidebar extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.SIDEBAR, side, 0]


class ActionTopDistant extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.ACTION_FIELD_TOP_DISTANT, side, 0]


class ActionTopHidden extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.ACTION_FIELD_TOP_HIDDEN, side, 0]


class ActionBottomDistant extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.ACTION_FIELD_BOTTOM_DISTANT, side, 0]


class ActionBottomHidden extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s
	func key() -> Array:
		return [NLEnums.SlotKind.ACTION_FIELD_BOTTOM_HIDDEN, side, 0]


# Per-side per-num zones (parameterized by side and weapon-slot index).

## The protocol's `ws_N` weapon slot identity (renamed from "WeaponSlot"
## to avoid colliding with the global `class_name WeaponSlot` in fj/ui/).
class WeaponZone extends SlotID:
	var side: NLEnums.PID
	var num: int
	func _init(s: NLEnums.PID, n: int) -> void:
		side = s
		num = n
	func key() -> Array:
		return [NLEnums.SlotKind.WS, side, num]


## The protocol's `ws_N_weapon` interior — the slot holding the weapon card.
class Holster extends SlotID:
	var side: NLEnums.PID
	var num: int
	func _init(s: NLEnums.PID, n: int) -> void:
		side = s
		num = n
	func key() -> Array:
		return [NLEnums.SlotKind.WS_WEAPON, side, num]


## The protocol's `ws_N_killstack` interior — the kill stack.
class Killstack extends SlotID:
	var side: NLEnums.PID
	var num: int
	func _init(s: NLEnums.PID, n: int) -> void:
		side = s
		num = n
	func key() -> Array:
		return [NLEnums.SlotKind.WS_KILLSTACK, side, num]
