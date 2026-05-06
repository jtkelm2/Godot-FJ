## Wire form of one card-template catalog entry, per protocol §3.1.1.
## NL `CardTemplate` is built from this plus loaded image assets by Catalog.

class_name WireCatalogEntry extends RefCounted

var template_name: String = ""
var display_name: String = ""
var description: String = ""

## `level` is wire-nullable; `has_level` distinguishes "level is zero" from
## "level is absent."
var level: int = 0
var has_level: bool = false

var types: Array[NLEnums.CardType] = []
var is_elusive: bool = false
var is_first: bool = false
