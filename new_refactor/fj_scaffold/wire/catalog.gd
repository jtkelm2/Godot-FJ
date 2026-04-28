## Catalog: bijective WL ↔ NL translator for slot/card identities, plus
## eager texture loading. Immutable after _init.
##
## **Player-symmetric.** Per protocol §1.3 / §3.1, the catalog is identical
## for both clients — it does not encode the receiving player's identity.
## SlotIDs are constructed with absolute PIDs read straight from each slot's
## `owner` field. The receiving client's own PID is delivered separately via
## the `pid_assignment` notify (§3.4.2) and lives outside Catalog.
##
## Catalog vends *canonical* SlotID and CardTemplate instances — one per
## identity — so downstream code can use them as Dictionary keys with
## reference equality.

class_name Catalog extends RefCounted


const CARD_INFO_DIR := "res://fj/assets/card_info/"
const CARD_ASSET_DIR := "res://fj/assets/images/cards/"


# Bijective name ↔ NL maps. Object identity is reliable as a Dictionary key
# because every SlotID / CardTemplate instance is constructed exactly once
# below and reused thereafter.
var _slot_by_name: Dictionary = {}            ## Dict[String, SlotID]
var _name_by_slot: Dictionary = {}            ## Dict[SlotID, String]
var _weapon_slot_by_name: Dictionary = {}     ## Dict[String, SlotID.WeaponZone]
var _name_by_weapon_slot: Dictionary = {}     ## Dict[SlotID.WeaponZone, String]
var _card_by_name: Dictionary = {}            ## Dict[String, CardTemplate]
var _name_by_card: Dictionary = {}            ## Dict[CardTemplate, String]


# Card backs by absolute PID + a neutral back for unowned slots.
var _back_by_pid: Dictionary = {}    ## Dict[NLEnums.PID, Texture2D]
var _neutral_back: Texture2D = null


func _init(catalog_msg: Dictionary) -> void:
	_build_slot_tables(catalog_msg.get("slots", {}))
	_build_weapon_slot_tables(catalog_msg.get("weapon_slots", {}))
	_load_back_textures()
	var name_to_image := _load_card_image_map()
	_build_card_templates(catalog_msg.get("cards", {}), name_to_image)


# --- Public API ---

func slot_for(wire_name: String) -> SlotID:
	assert(_slot_by_name.has(wire_name), "Catalog: unknown slot wire: %s" % wire_name)
	return _slot_by_name[wire_name]


func wire_for_slot(slot: SlotID) -> String:
	return _name_by_slot.get(slot, "")


func has_slot(wire_name: String) -> bool:
	return _slot_by_name.has(wire_name)


## All known regular SlotIDs (excludes WeaponZone — those live under weapon_slots).
func all_slots() -> Array[SlotID]:
	var out: Array[SlotID] = []
	for s in _slot_by_name.values():
		out.append(s)
	return out


func weapon_slot_for(wire_name: String) -> SlotID:
	assert(_weapon_slot_by_name.has(wire_name), "Catalog: unknown weapon slot wire: %s" % wire_name)
	return _weapon_slot_by_name[wire_name]


func wire_for_weapon_slot(slot: SlotID) -> String:
	return _name_by_weapon_slot.get(slot, "")


func has_weapon_slot(wire_name: String) -> bool:
	return _weapon_slot_by_name.has(wire_name)


func card_for(wire_name: String) -> CardTemplate:
	assert(_card_by_name.has(wire_name), "Catalog: unknown card name: %s" % wire_name)
	return _card_by_name[wire_name]


func wire_for_card(template: CardTemplate) -> String:
	return _name_by_card.get(template, "")


func has_card(wire_name: String) -> bool:
	return _card_by_name.has(wire_name)


func back_for_pid(pid: NLEnums.PID) -> Texture2D:
	return _back_by_pid.get(pid)


func neutral_back() -> Texture2D:
	return _neutral_back


# --- Slot construction ---

func _build_slot_tables(slots_dict: Dictionary) -> void:
	for wire in slots_dict:
		var info: Dictionary = slots_dict[wire]
		var owner_v: Variant = info.get("owner")
		var role := str(info.get("role", ""))
		var slot := _make_slot(role, owner_v)
		if slot != null:
			_slot_by_name[str(wire)] = slot
			_name_by_slot[slot] = str(wire)
		else:
			push_warning("Catalog: unrecognized slot role '%s' (owner=%s, wire=%s)" % [role, owner_v, wire])


func _build_weapon_slot_tables(weapon_slots_dict: Dictionary) -> void:
	for wire in weapon_slots_dict:
		var info: Dictionary = weapon_slots_dict[wire]
		var owner_v: Variant = info.get("owner")
		var role := str(info.get("role", ""))
		var num := _parse_ws_num(role)
		if num < 0:
			push_warning("Catalog: unparseable weapon slot role '%s' (wire=%s)" % [role, wire])
			continue
		if owner_v == null:
			push_warning("Catalog: weapon slot with null owner (wire=%s); skipping" % wire)
			continue
		var pid := _parse_pid(str(owner_v))
		var slot := SlotID.WeaponZone.new(pid, num)
		_weapon_slot_by_name[str(wire)] = slot
		_name_by_weapon_slot[slot] = str(wire)


func _make_slot(role: String, owner_v: Variant) -> SlotID:
	# Unowned (null owner) — only GuardDeck reachable.
	if owner_v == null:
		if role == "guard_deck":
			return SlotID.GuardDeck.new()
		return null

	var pid := _parse_pid(str(owner_v))

	# Per-side simple roles.
	match role:
		"hand":                          return SlotID.Hand.new(pid)
		"deck":                          return SlotID.Deck.new(pid)
		"refresh":                       return SlotID.Refresh.new(pid)
		"discard":                       return SlotID.Discard.new(pid)
		"equipment":                     return SlotID.Equipment.new(pid)
		"sidebar":                       return SlotID.Sidebar.new(pid)
		"action_field_top_distant":      return SlotID.ActionTopDistant.new(pid)
		"action_field_top_hidden":       return SlotID.ActionTopHidden.new(pid)
		"action_field_bottom_distant":   return SlotID.ActionBottomDistant.new(pid)
		"action_field_bottom_hidden":    return SlotID.ActionBottomHidden.new(pid)

	# Per-side per-num interiors: ws_<N>_weapon, ws_<N>_killstack.
	if role.begins_with("ws_"):
		var num := _parse_ws_interior(role, "weapon")
		if num >= 0:
			return SlotID.Holster.new(pid, num)
		num = _parse_ws_interior(role, "killstack")
		if num >= 0:
			return SlotID.Killstack.new(pid, num)

	return null


static func _parse_pid(s: String) -> NLEnums.PID:
	match s:
		"RED":  return NLEnums.PID.RED
		"BLUE": return NLEnums.PID.BLUE
		_:
			push_error("Catalog: unknown PID owner '%s'" % s)
			return NLEnums.PID.RED


## Parses "ws_<N>" → N, else -1.
static func _parse_ws_num(role: String) -> int:
	if not role.begins_with("ws_"):
		return -1
	var rest := role.substr(3)
	return rest.to_int() if rest.is_valid_int() else -1


## Parses "ws_<N>_<suffix>" → N, else -1.
static func _parse_ws_interior(role: String, suffix: String) -> int:
	var pattern := "_" + suffix
	if not role.begins_with("ws_") or not role.ends_with(pattern):
		return -1
	var middle := role.substr(3, role.length() - 3 - pattern.length())
	return middle.to_int() if middle.is_valid_int() else -1


# --- Card construction + asset loading ---

func _load_back_textures() -> void:
	_back_by_pid[NLEnums.PID.RED] = load(CARD_ASSET_DIR + "back_red.png") as Texture2D
	_back_by_pid[NLEnums.PID.BLUE] = load(CARD_ASSET_DIR + "back_blue.png") as Texture2D
	_neutral_back = load(CARD_ASSET_DIR + "back1.png") as Texture2D


## Reads every JSON in `card_info/`, building a card_name → front_image
## filename map. The card_info JSONs are local-only (not on the wire); they
## supply the asset filenames that the wire catalog references by name.
func _load_card_image_map() -> Dictionary:
	var map: Dictionary = {}
	var dir := DirAccess.open(CARD_INFO_DIR)
	if dir == null:
		push_error("Catalog: failed to open card info directory: %s" % CARD_INFO_DIR)
		return map
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var json_path := CARD_INFO_DIR + file_name
			var file := FileAccess.open(json_path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data: Dictionary = json.data
					if data.has("name") and data.has("front_image"):
						map[str(data["name"])] = str(data["front_image"])
				file.close()
		file_name = dir.get_next()
	return map


func _build_card_templates(cards_dict: Dictionary, name_to_image: Dictionary) -> void:
	for wire_name in cards_dict:
		var entry: Dictionary = cards_dict[wire_name]
		var t := _make_card_template(str(wire_name), entry, name_to_image)
		_card_by_name[str(wire_name)] = t
		_name_by_card[t] = str(wire_name)


func _make_card_template(wire_name: String, entry: Dictionary, name_to_image: Dictionary) -> CardTemplate:
	var t := CardTemplate.new()
	t.template_name = wire_name
	t.display_name = str(entry.get("display_name", ""))
	t.description = str(entry.get("text", ""))
	var lvl = entry.get("level")
	if lvl == null:
		t.has_level = false
		t.level = 0
	else:
		t.has_level = true
		t.level = int(lvl)

	var types: Array[NLEnums.CardType] = []
	for type_str in (entry.get("types", []) as Array):
		var ct := _parse_card_type(str(type_str))
		if ct >= 0:
			types.append(ct as NLEnums.CardType)
	t.types = types

	t.is_elusive = bool(entry.get("is_elusive", false))
	t.is_first = bool(entry.get("is_first", false))

	var image_file: String = name_to_image.get(wire_name, "")
	if image_file.is_empty(): push_warning("Catalog: failed to load image for wire_name: %s" % wire_name)
	else:
		var path := CARD_ASSET_DIR + image_file
		var tex := load(path) as Texture2D
		if tex != null:
			t.front = tex
		else:
			push_warning("Catalog: failed to load front for card %s at %s" % [wire_name, path])

	return t


static func _parse_card_type(s: String) -> int:
	match s.to_upper():
		"WEAPON":    return NLEnums.CardType.WEAPON
		"EQUIPMENT": return NLEnums.CardType.EQUIPMENT
		"ENEMY":     return NLEnums.CardType.ENEMY
		"FOOD":      return NLEnums.CardType.FOOD
		"EVENT":     return NLEnums.CardType.EVENT
		_:           return -1
