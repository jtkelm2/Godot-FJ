## NL slot identity ADT. Wire-agnostic — no wire names, no Catalog references.
##
## Catalog is responsible for vending canonical instances (one per identity)
## so dict lookups via reference equality work. Phase 2 wires this up.
##
## Base name is `SlotID` (not `Slot`) because the UI widget `fj/ui/slot.gd`
## already registers `class_name Slot` globally. Same reason `WeaponZone` is
## the constructor name for the protocol's "weapon slot" — `WeaponSlot` is
## taken globally too.

@abstract
class_name SlotID extends RefCounted


# Shared zones (no per-side variant).

class GuardDeck extends SlotID:
	pass


# Per-side zones (parameterized by side).

class Hand extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


class Deck extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


class Refresh extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


class Discard extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


class Equipment extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


class Sidebar extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


class ActionTopDistant extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


class ActionTopHidden extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


class ActionBottomDistant extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


class ActionBottomHidden extends SlotID:
	var side: NLEnums.PID
	func _init(s: NLEnums.PID) -> void:
		side = s


# Per-side per-num zones (parameterized by side and weapon-slot index).

## The protocol's `ws_N` weapon slot identity (renamed from "WeaponSlot"
## to avoid colliding with the global `class_name WeaponSlot` in fj/ui/).
class WeaponZone extends SlotID:
	var side: NLEnums.PID
	var num: int
	func _init(s: NLEnums.PID, n: int) -> void:
		side = s
		num = n


## The protocol's `ws_N_weapon` interior — the slot holding the weapon card.
class Holster extends SlotID:
	var side: NLEnums.PID
	var num: int
	func _init(s: NLEnums.PID, n: int) -> void:
		side = s
		num = n


## The protocol's `ws_N_killstack` interior — the kill stack.
class Killstack extends SlotID:
	var side: NLEnums.PID
	var num: int
	func _init(s: NLEnums.PID, n: int) -> void:
		side = s
		num = n
