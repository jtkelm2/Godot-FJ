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


## NOTE: `WireCatalog` is currently unused — Catalog parses raw JSON directly
## in `wire/catalog.gd` rather than going through this typed envelope. The
## dict values were originally meant to be `WireCatalogEntry` / `WireSlotEntry`
## but those typed shapes never materialized; they're left as untyped raw JSON
## here. Kept for protocol-document parity per `WireLang = … | WireCatalog`.
var cards: Dictionary[String, Variant] = {}           ## Keyed by card name.
var slots: Dictionary[String, Variant] = {}           ## Keyed by slot wire name.
var weapon_slots: Dictionary[String, Variant] = {}    ## Keyed by weapon slot wire name.
