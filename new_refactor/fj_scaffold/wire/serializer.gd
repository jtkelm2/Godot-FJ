## Serializer: NL values → WL Variant dicts.
##
## Inverse of Deserializer for outbound traffic (RL responses + OOB messages).
## Per protocol §4.4, response options must echo the original byte-identically;
## these methods produce the dicts in the exact wire shape the server sent.

@abstract
class_name Serializer extends RefCounted


## NL Option → wire option dict.
static func serialize_option(opt: Option, catalog: Catalog) -> Dictionary:
	if opt is Option.TextOption:
		return {"type": "text", "text": (opt as Option.TextOption).text}
	if opt is Option.LocOption:
		var loc := (opt as Option.LocOption).loc
		if loc is Loc.SlotLoc:
			var sl := loc as Loc.SlotLoc
			return {
				"type": "card",
				"slot": catalog.wire_for_slot(sl.slot),
				"index": sl.idx,
			}
		push_error("Serializer.serialize_option: LocOption with non-SlotLoc cannot be echoed")
		return {}
	if opt is Option.SlotOption:
		var s := (opt as Option.SlotOption).slot
		# A SlotOption can carry either a regular slot or a weapon slot — the
		# wire form differs ("slot" vs "weapon_slot"). Distinguish by which
		# Catalog table the SlotID is registered in.
		var ws_wire := catalog.wire_for_weapon_slot(s)
		if not ws_wire.is_empty():
			return {"type": "weapon_slot", "name": ws_wire}
		return {"type": "slot", "name": catalog.wire_for_slot(s)}
	push_error("Serializer.serialize_option: unknown Option subtype: %s" % opt)
	return {}


## NL Option → `response` envelope (per protocol §5.1).
static func serialize_response(opt: Option, catalog: Catalog) -> Dictionary:
	return {"type": "response", "option": serialize_option(opt, catalog)}


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
