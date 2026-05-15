## NL card template — fully resolved card metadata + assets.
##
## Catalog populates the asset fields (front texture) from the wire catalog
## entry plus image files loaded from disk via the per-card-name JSONs in
## `assets/card_info/`.

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
## mapping (`assets/card_info/<name>.json` → `front_image` filename).
## Card backs are per-side, not per-card; the Dispatcher loads them itself
## from `assets/images/cards/back_*.png`.
var front: Texture2D = null
