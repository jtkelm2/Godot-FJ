## RL language: typed options a client may emit in response to a prompt.
## NL — wire-agnostic. Serialization/deserialization happens in wire/.
##
## Wire `card` collapses into `Option.Loc(loc)` carrying a `Loc.Slot(slot,
## idx)`; wire `weapon_slot` collapses into `Option.Slot(slotid)` where the
## SlotID has `Type.WS`. Wire `revealed_card` keeps its own variant
## (`Option.RevealedCard`) since it identifies by card-template name rather
## than slot location. The wire/NL boundary (Catalog + Serializer/Deserializer)
## handles the projection.
##
## Tagged-union flattening: one concrete class with a `Type` enum tag plus
## the union of fields each former-constructor needed. Construct via the
## PascalCase factories (`Option.Text`, `Option.Loc`, `Option.Slot`,
## `Option.RevealedCard`).

class_name Option extends NL


enum Type { TEXT, LOC, SLOT, REVEALED_CARD }


var type: Type
var text: String = ""        ## Used when type == TEXT.
var loc: Loc = null          ## Used when type == LOC.
var slot: SlotID = null      ## Used when type == SLOT.
var card: CardTemplate = null   ## Used when type == REVEALED_CARD; wire card-template name.

# --- PascalCase factories ---

static func Text(p_text: String) -> Option:
	var o := Option.new()
	o.type = Type.TEXT
	o.text = p_text
	return o


static func Loc(p_loc: Loc) -> Option:
	var o := Option.new()
	o.type = Type.LOC
	o.loc = p_loc
	return o


static func Slot(p_slot: SlotID) -> Option:
	var o := Option.new()
	o.type = Type.SLOT
	o.slot = p_slot
	return o


static func RevealedCard(p_card:CardTemplate) -> Option:
	var o := Option.new()
	o.type = Type.REVEALED_CARD
	o.card = p_card
	return o


# --- Equality ---

## Used by OptionValidator to match candidate options against pending prompt
## options by structural equality. Reference equality via `==` would only work
## if both came from the same Catalog-vended canonical instance — which client
## candidates never are (built scene-side from local SlotIDs).
func equals(other: Option) -> bool:
	if other == null or other.type != type:
		return false
	match type:
		Type.TEXT: return text == other.text
		Type.LOC:  return loc.equals(other.loc)
		Type.SLOT: return slot.equals(other.slot)
		Type.REVEALED_CARD: return card.template_name == other.card.template_name
	return false
