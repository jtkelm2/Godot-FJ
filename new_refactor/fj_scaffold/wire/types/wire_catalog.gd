## Wire form of the catalog message envelope, per protocol §3.1.
##
## `WireSlotEntry` is the wire-shape of one entry in the `slots` /
## `weapon_slots` dicts (just owner + role). It has no NL counterpart —
## the NL form of slot identity is the typed `SlotID` ADT, which Catalog
## constructs from these wire entries.

class_name WireCatalog extends RefCounted


class WireSlotEntry extends RefCounted:
	var owner: String = ""  ## "self" / "opponent" / "shared"
	var role: String = ""
	func _init(o: String = "", r: String = "") -> void:
		owner = o
		role = r


var cards: Dictionary           ## Dict[String, WireCatalogEntry] — keyed by card name
var slots: Dictionary           ## Dict[String, WireSlotEntry]    — keyed by slot wire name
var weapon_slots: Dictionary    ## Dict[String, WireSlotEntry]    — keyed by weapon slot wire name
