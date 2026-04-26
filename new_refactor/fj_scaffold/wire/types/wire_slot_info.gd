## Wire form of slot contents. Three variants per protocol §3.2.1:
##   - WireUnknownInfo: hidden slot (omitted from wire dict; lifted to explicit here).
##   - WireCountInfo:   count-only fog of war.
##   - WireFullInfo:    visible card list.

@abstract
class_name WireSlotInfo extends RefCounted


class WireUnknownInfo extends WireSlotInfo:
	pass


class WireCountInfo extends WireSlotInfo:
	var n: int
	func _init(count: int = 0) -> void:
		n = count


class WireFullInfo extends WireSlotInfo:
	var cards: Array[WireCardInfo]
	func _init(c: Array[WireCardInfo] = []) -> void:
		cards = c
