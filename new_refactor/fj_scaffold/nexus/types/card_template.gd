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

## Front face texture, loaded eagerly by Catalog from the local image-info
## mapping (`fj/assets/card_info/<name>.json` → `front_image` filename).
## Card backs are per-side, not per-card; ask `Catalog.back_for(slot)` instead.
var front: Texture2D = null
