## NL card template — fully resolved card metadata + assets.
##
## In Phase 1 the asset fields (front/back textures) are placeholders.
## Catalog will populate them in Phase 2+ from the wire catalog entry plus
## image files loaded from disk via the existing fj/assets/image_resolver.gd
## conventions.

class_name CardTemplate extends RefCounted


var template_name: String = ""    ## canonical identifier (also Catalog key)
var display_name: String = ""
var description: String = ""

## `level` is wire-nullable; `has_level` distinguishes "level is zero" from
## "level is absent." Most consumers should check `has_level` before reading.
var level: int = 0
var has_level: bool = false

var types: Array[NLEnums.CardType] = []
var is_elusive: bool = false
var is_first: bool = false

# TODO Phase 2+: deserialized assets the Renderer needs to draw the card.
# var front: Texture2D
# var back: Texture2D
