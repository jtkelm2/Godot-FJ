@tool
class_name WeaponSlot
extends PassiveContainer

## A first-class weapon slot: a composite that owns a `holster` slot (the
## equipped weapon card) and a `killstack` slot (defeated enemies). Dealt
## with as a peer to Slot — never as "a slot with extra fields."
##
## Packaged as a scene (`weapon_slot.tscn`): instance it into a board layout,
## override `owner_side` and `ws_role` in the instance, done. The holster
## and killstack child Slots are wired via `@export` in the packed scene
## — no role-suffix introspection anywhere in this script.
##
## Public surface (all operations on a weapon slot go through these — never
## by reaching into `holster` / `killstack` from outside the Wrangler):
##
##   set_sharpness(int)
##   set_highlight(on)                             ← composite-level prompt
##   set_card_highlight(interior_wire, idx, on)    ← per-card highlight
##   clear_highlights()
##   ws_wire / holster_wire / killstack_wire / interior_wires()
##
## Signals (re-emitted symmetrically from BOTH holster and killstack, so
## future prompts can interrogate killstack contents if cards become faceup):
##
##   weapon_slot_clicked(ws)                ← composite-level click
##   card_clicked(interior_wire, index)     ← either holster or killstack
##   card_hovered(interior_wire, index)
##   card_unhovered()

signal weapon_slot_clicked(weapon_slot: WeaponSlot)
signal card_clicked(interior_wire: String, index: int)
signal card_hovered(interior_wire: String, index: int)
signal card_unhovered

@export var owner_side: String = ""  # "RED" | "BLUE" | "SHARED"
@export var ws_role: String = "ws_0"

## Wire these in the packed scene's inspector (drag the child Slot nodes
## into the NodePath fields). The Wrangler will reach in here to populate
## them via `apply_to` — the one sanctioned reach-in.
@export var holster_path: NodePath
@export var killstack_path: NodePath

var holster: Slot = null
var killstack: Slot = null

# Wires resolved at init from GameSession.catalog. Empty for opp-side
# composites whose weapon slots aren't in the catalog (typical).
var ws_wire: String = ""
var holster_wire: String = ""
var killstack_wire: String = ""

@onready var _sharpness_label: Label = get_node_or_null("Sharpness") as Label


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	holster = get_node_or_null(holster_path) as Slot
	killstack = get_node_or_null(killstack_path) as Slot
	if holster == null or killstack == null:
		push_error("WeaponSlot at %s: holster_path/killstack_path must point to child Slot nodes" % get_path())
		return
	# Interior slots share our owner_side so Wrangler's back-texture lookup
	# picks the correct perspective. This is the only property we propagate.
	holster.owner_side = owner_side
	killstack.owner_side = owner_side

	_resolve_wires()
	_wire_interior_signals(holster, func(): return holster_wire)
	_wire_interior_signals(killstack, func(): return killstack_wire)
	# Composite-level click: the holster's slot_clicked is the "I selected
	# this weapon slot" gesture. Killstack's slot_clicked is intentionally
	# not promoted — holster is the canonical weapon-slot handle.
	holster.slot_clicked.connect(func(_s: Slot): weapon_slot_clicked.emit(self))


func _resolve_wires() -> void:
	var catalog = GameSession.catalog
	if catalog == null:
		return
	var ws_lookup: Dictionary
	if owner_side == GameSession.my_side:
		ws_lookup = catalog.self_weapon_slots
	else:
		ws_lookup = catalog.opponent_weapon_slots
	ws_wire = ws_lookup.get(ws_role, "")
	# Interior wires come from CatalogData's pre-built forward table — no
	# string concatenation here.
	var interiors: Dictionary = catalog.self_weapon_interiors.get(ws_wire, {})
	holster_wire = interiors.get("holster", "")
	killstack_wire = interiors.get("killstack", "")


func _wire_interior_signals(interior: Slot, wire_getter: Callable) -> void:
	# Re-emit the interior slot's per-card events at the composite level,
	# tagged with which interior wire (holster or killstack) they came from.
	# The getter indirection lets us connect during _ready before the wires
	# are resolved — though in practice _resolve_wires runs first.
	interior.card_clicked.connect(func(_s: Slot, idx: int): card_clicked.emit(wire_getter.call(), idx))
	interior.card_hovered.connect(func(_s: Slot, idx: int): card_hovered.emit(wire_getter.call(), idx))
	interior.card_unhovered.connect(func(_s: Slot): card_unhovered.emit())


# --- Public API ---

## Returns the two regular-slot wires this composite owns, for Board's
## interior-wire → composite routing (used by `card`-type prompts targeting
## a holster or killstack).
func interior_wires() -> Array:
	var out: Array = []
	if not holster_wire.is_empty():
		out.append(holster_wire)
	if not killstack_wire.is_empty():
		out.append(killstack_wire)
	return out


## Composite-level prompt highlight (for `weapon_slot` options).
func set_highlight(on: bool) -> void:
	if holster:
		holster.set_highlight(on)


## Per-card highlight inside one of the interior slots (for `card` options
## that target a holster or killstack wire).
func set_card_highlight(interior_wire: String, idx: int, on: bool) -> void:
	var interior := _interior_for(interior_wire)
	if interior and idx >= 0 and idx < interior.count():
		interior.get_card(idx).set_highlight(on)


## Clear all highlights this composite controls (composite outline + every
## inner card). Called at the start of each rebuild.
func clear_highlights() -> void:
	set_highlight(false)
	for interior in [holster, killstack]:
		if interior == null:
			continue
		for i in interior.count():
			interior.get_card(i).set_highlight(false)


func set_sharpness(value: int) -> void:
	if _sharpness_label:
		_sharpness_label.text = "♦ %d" % value
		_sharpness_label.visible = value > 0


# --- Helpers ---

func _interior_for(interior_wire: String) -> Slot:
	if interior_wire == holster_wire:
		return holster
	if interior_wire == killstack_wire:
		return killstack
	return null
