## NL location ADT — where a card is, in NL terms.
## Wire-agnostic.

@abstract
class_name Loc extends RefCounted


## Card has no known location (e.g., spawned, drawn from concealment).
class UnknownLoc extends Loc:
	pass


## Card is at index `idx` in slot `slot`. Index convention is the protocol's:
## 0 is the top of the pile.
class SlotLoc extends Loc:
	var slot: SlotID
	var idx: int
	func _init(s: SlotID, i: int) -> void:
		slot = s
		idx = i
