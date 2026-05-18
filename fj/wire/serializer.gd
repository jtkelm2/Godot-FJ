## Serializer: NL values → WL Variant dicts.
##
## Inverse of Deserializer for outbound traffic (RL responses + OOB messages).
## Per protocol §4.4, response options must echo the original byte-identically;
## these methods produce the dicts in the exact wire shape the server sent.

@abstract
class_name Serializer extends RefCounted


## NL Option → wire option dict.
static func serialize_option(opt: Option, catalog: Catalog) -> Dictionary:
	match opt.type:
		Option.Type.TEXT:
			return {"type": "text", "text": opt.text}
		Option.Type.LOC:
			if opt.loc.type == Loc.Type.SLOT:
				return {
					"type": "card",
					"slot": catalog.wire_for_slot(opt.loc.slot),
					"index": opt.loc.idx,
				}
			push_error("Serializer.serialize_option: Option.Loc with non-Slot Loc cannot be echoed")
			return {}
		Option.Type.SLOT:
			# An Option.Slot can carry either a regular slot or a weapon slot —
			# the wire form differs ("slot" vs "weapon_slot"). Distinguish by
			# which Catalog table the SlotID is registered in.
			var ws_wire := catalog.wire_for_weapon_slot(opt.slot)
			if not ws_wire.is_empty():
				return {"type": "weapon_slot", "name": ws_wire}
			return {"type": "slot", "name": catalog.wire_for_slot(opt.slot)}
		Option.Type.REVEALED_CARD:
			return {"type": "revealed_card", "name": opt.card_name}
	push_error("Serializer.serialize_option: unknown Option type: %s" % opt.type)
	return {}


## NL Options → `response` envelope (per protocol §5.1).
## Single-element arrays emit the singular `{"option": ...}` shape; arrays of
## length >= 2 emit the multi-select `{"options": [...]}` shape.
static func serialize_response(opts: Array[Option], catalog: Catalog) -> Dictionary:
	if opts.size() == 1:
		return {"type": "response", "option": serialize_option(opts[0], catalog)}
	var out: Array[Dictionary] = []
	for o in opts:
		out.append(serialize_option(o, catalog))
	return {"type": "response", "options": out}


# --- Out-of-band messages (per protocol §6) ---

static func serialize_resign() -> Dictionary:
	return {"type": "resign"}


static func serialize_draw_offer() -> Dictionary:
	return {"type": "draw_offer"}


static func serialize_draw_accept() -> Dictionary:
	return {"type": "draw_accept"}


# --- Primitives (mostly for testing / future symmetry) ---

static func serialize_pid(pid: NLEnums.PID) -> String:
	match pid:
		NLEnums.PID.RED:  return "RED"
		NLEnums.PID.BLUE: return "BLUE"
		_: return ""


static func serialize_phase(phase: NLEnums.Phase) -> Variant:
	match phase:
		NLEnums.Phase.NONE:         return null
		NLEnums.Phase.SETUP:        return "SETUP"
		NLEnums.Phase.REFRESH:      return "REFRESH"
		NLEnums.Phase.MANIPULATION: return "MANIPULATION"
		NLEnums.Phase.ACTION:       return "ACTION"
		_: return null
