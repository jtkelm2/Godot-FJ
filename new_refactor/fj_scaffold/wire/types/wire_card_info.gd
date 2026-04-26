## Wire form of card info: name (catalog reference) + counters.
## Per protocol §3.2.1, each card object in a slot's card list.

class_name WireCardInfo extends RefCounted

var name: String = ""
var counters: int = 0

func _init(n: String = "", c: int = 0) -> void:
	name = n
	counters = c
