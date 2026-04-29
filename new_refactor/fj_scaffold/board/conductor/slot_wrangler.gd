## SlotWrangler: builds CardViews from NL CardInstance / count placeholders
## and stocks SlotViews with them. The Conductor uses this for full rebuilds
## and to materialize stand-in cards for facedown moves.
##
## Both inputs are Callables provided by the composer:
##   - `card_factory()` returns a fresh, unparented CardView.
##   - `back_for_slot(slot_id: SlotID)` returns the appropriate Texture2D
##     back for that slot's owner (Catalog provides the per-PID lookup).
##
## Wire-agnostic. NL-only on the input side.

class_name SlotWrangler extends RefCounted


var card_factory: Callable     ## () -> CardView
var back_for_slot: Callable    ## (slot_id: SlotID) -> Texture2D


## Replace `slot`'s contents with what `contents` describes.
func populate(slot: SlotView, slot_id: SlotID, contents: State.SlotContents) -> void:
	slot.clear()
	if contents is State.UnknownContents:
		return
	var back: Texture2D = back_for_slot.call(slot_id)
	if contents is State.FullContents:
		var cards := (contents as State.FullContents).cards
		for i in cards.size():
			slot.insert(i, create_card(cards[i].template.front, back, true))
	elif contents is State.CountContents:
		var n := (contents as State.CountContents).n
		for i in n:
			slot.insert(i, create_card(null, back, false))


## Build a free-standing CardView with the given textures and face.
func create_card(front: Texture2D, back: Texture2D, faceup: bool) -> CardView:
	var c: CardView = card_factory.call()
	c.front_texture = front
	c.back_texture = back
	c.is_faceup = faceup
	return c
