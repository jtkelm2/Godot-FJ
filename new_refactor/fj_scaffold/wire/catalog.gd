## Catalog: bijective WL ↔ NL translator for slot/card identities, plus
## eager texture loading. Immutable after _init.
##
## **Player-symmetric.** Per protocol §1.3 / §3.1, the catalog is identical
## for both clients. SlotIDs are constructed with absolute PIDs read straight
## from each slot's `owner` field. The receiving client's own PID is
## delivered separately via the `pid_assignment` notify and lives outside
## Catalog.
##
## Catalog vends *canonical* SlotID and CardTemplate instances (one per
## identity) so downstream code can use them as Dictionary keys with
## reference equality. Two lookup directions are offered:
##
##   wire_name → SlotID         via `slot_for(wire_name)` / `weapon_slot_for(...)`
##   (kind, side, num) → SlotID via `slot_id_for(side, kind, num)` /
##                                `weapon_slot_id_for(side, num)`
##
## Both return the same canonical instance; the second is what the composer
## uses at scene-init time to map each `SlotView`'s identity exports to
## Catalog's slot.

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


# (kind, side, num) → canonical SlotID, populated alongside the wire-name
# tables. Lets `slot_id_for` be a single dict lookup.
var _canonical_by_identity: Dictionary = {}            ## Dict[Array, SlotID]
var _canonical_by_weapon_identity: Dictionary = {}     ## Dict[Array, SlotID.WeaponZone]


# Card backs by absolute PID + a neutral back for unowned slots.
var _back_by_pid: Dictionary = {}    ## Dict[NLEnums.PID, Texture2D]
var _neutral_back: Texture2D = null


func _init(catalog_msg: Dictionary) -> void:
	_build_slot_tables(catalog_msg.get("slots", {}))
	_build_weapon_slot_tables(catalog_msg.get("weapon_slots", {}))
	_load_back_textures()
	var name_to_image := _load_card_image_map()
	_build_card_templates(catalog_msg.get("cards", {}), name_to_image)


# --- Public API: regular slots ---

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


## Single-direction resolver from (kind, side, num) → canonical SlotID.
## `num` is consulted only for ws-interior kinds. Composer calls this once
## per `SlotView` at scene-init time.
func slot_id_for(p_side: NLEnums.PID, p_kind: NLEnums.SlotKind, p_num: int = 0) -> SlotID:
	var key := _identity_key(p_side, p_kind, p_num)
	return _canonical_by_identity.get(key)


# --- Public API: weapon slots ---

func weapon_slot_for(wire_name: String) -> SlotID:
	assert(_weapon_slot_by_name.has(wire_name), "Catalog: unknown weapon slot wire: %s" % wire_name)
	return _weapon_slot_by_name[wire_name]


func wire_for_weapon_slot(slot: SlotID) -> String:
	return _name_by_weapon_slot.get(slot, "")


func has_weapon_slot(wire_name: String) -> bool:
	return _weapon_slot_by_name.has(wire_name)


func weapon_slot_id_for(p_side: NLEnums.PID, p_num: int) -> SlotID:
	var key := _identity_key(p_side, NLEnums.SlotKind.WS, p_num)
	return _canonical_by_weapon_identity.get(key)


# --- Public API: cards + backs ---

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
		var resolved := _parse_wire_role(role)
		if resolved.kind < 0:
			push_warning("Catalog: unrecognized slot role '%s' (wire=%s)" % [role, wire])
			continue
		var side: NLEnums.PID
		if resolved.kind == NLEnums.SlotKind.GUARD_DECK:
			side = NLEnums.PID.RED  # ignored by GuardDeck constructor
		elif owner_v == null:
			push_warning("Catalog: non-shared slot with null owner (wire=%s)" % wire)
			continue
		else:
			side = _parse_pid(str(owner_v))
		var slot := SlotID.make(resolved.kind, side, resolved.num)
		_slot_by_name[str(wire)] = slot
		_name_by_slot[slot] = str(wire)
		_canonical_by_identity[_identity_key(side, resolved.kind, resolved.num)] = slot


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
		var slot := SlotID.make(NLEnums.SlotKind.WS, pid, num)
		_weapon_slot_by_name[str(wire)] = slot
		_name_by_weapon_slot[slot] = str(wire)
		_canonical_by_weapon_identity[_identity_key(pid, NLEnums.SlotKind.WS, num)] = slot


# --- Wire role string → SlotKind ---

class _WireRole extends RefCounted:
	var kind: int = -1     ## NLEnums.SlotKind value, or -1 if unparseable.
	var num: int = 0
	func _init(k: int = -1, n: int = 0) -> void:
		kind = k
		num = n


## Parses a slot's wire `role` string into a `(kind, num)` pair. Internal
## to Catalog — wire role strings live here, not in NL types.
static func _parse_wire_role(role: String) -> _WireRole:
	match role:
		"guard_deck":                  return _WireRole.new(NLEnums.SlotKind.GUARD_DECK)
		"hand":                        return _WireRole.new(NLEnums.SlotKind.HAND)
		"deck":                        return _WireRole.new(NLEnums.SlotKind.DECK)
		"refresh":                     return _WireRole.new(NLEnums.SlotKind.REFRESH)
		"discard":                     return _WireRole.new(NLEnums.SlotKind.DISCARD)
		"equipment":                   return _WireRole.new(NLEnums.SlotKind.EQUIPMENT)
		"sidebar":                     return _WireRole.new(NLEnums.SlotKind.SIDEBAR)
		"action_field_top_distant":    return _WireRole.new(NLEnums.SlotKind.ACTION_FIELD_TOP_DISTANT)
		"action_field_top_hidden":     return _WireRole.new(NLEnums.SlotKind.ACTION_FIELD_TOP_HIDDEN)
		"action_field_bottom_distant": return _WireRole.new(NLEnums.SlotKind.ACTION_FIELD_BOTTOM_DISTANT)
		"action_field_bottom_hidden":  return _WireRole.new(NLEnums.SlotKind.ACTION_FIELD_BOTTOM_HIDDEN)
	if role.begins_with("ws_"):
		var num := _parse_ws_interior(role, "weapon")
		if num >= 0:
			return _WireRole.new(NLEnums.SlotKind.WS_WEAPON, num)
		num = _parse_ws_interior(role, "killstack")
		if num >= 0:
			return _WireRole.new(NLEnums.SlotKind.WS_KILLSTACK, num)
	return _WireRole.new()


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


## Composite key for `_canonical_by_identity` and `_canonical_by_weapon_identity`.
static func _identity_key(side: NLEnums.PID, kind: NLEnums.SlotKind, num: int) -> Array:
	return [int(kind), int(side), num]


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
	if not image_file.is_empty():
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
