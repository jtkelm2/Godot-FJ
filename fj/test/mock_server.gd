extends Control

## A simple TCP mock server that replays canned protocol messages
## for testing the Fool's Journey client without the real game server.

const DEFAULT_PORT := 9001

@onready var port_input: LineEdit = $VBoxContainer/PortRow/PortInput
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var step_button: Button = $VBoxContainer/StepButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var log_text: TextEdit = $VBoxContainer/LogText

var tcp_server: TCPServer
var client_peer: StreamPeerTCP
var _step_index: int = 0
var _sequence: Array[Dictionary] = []


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	step_button.pressed.connect(_on_step_pressed)
	step_button.disabled = true
	_build_test_sequence()


func _build_test_sequence() -> void:
	# A minimal but realistic protocol sequence for testing
	_sequence = [
		# Step 0: catalog
		{
			"type": "catalog",
			"cards": {
				"enemy_3": {"name": "enemy_3", "display_name": "Enemy (3)", "text": "If you kill this with a weapon: Discard this and your kill pile.", "level": 3, "types": ["ENEMY"], "is_elusive": false, "is_first": false},
				"enemy_5": {"name": "enemy_5", "display_name": "Enemy (5)", "text": "", "level": 5, "types": ["ENEMY"], "is_elusive": false, "is_first": false},
				"food_5": {"name": "food_5", "display_name": "Food (5)", "text": "", "level": 5, "types": ["FOOD"], "is_elusive": false, "is_first": false},
				"weapon_4": {"name": "weapon_4", "display_name": "Weapon (4)", "text": "", "level": 4, "types": ["WEAPON"], "is_elusive": false, "is_first": false},
				"weapon_2": {"name": "weapon_2", "display_name": "Weapon (2)", "text": "", "level": 2, "types": ["WEAPON"], "is_elusive": false, "is_first": false},
				"major_1": {"name": "major_1", "display_name": "The Magician", "text": "On resolve: Look at the top 3 cards of the deck, and resolve one of them.", "level": null, "types": ["EVENT"], "is_elusive": false, "is_first": false},
				"good_role_1": {"name": "good_role_1", "display_name": "Human", "text": "Good role. While equipped: Call the Guards.", "level": null, "types": ["EQUIPMENT"], "is_elusive": false, "is_first": false},
			},
			"slots": {
				"red_hand":                        {"owner": "self",     "role": "hand"},
				"red_deck":                        {"owner": "self",     "role": "deck"},
				"red_refresh":                     {"owner": "self",     "role": "refresh"},
				"red_discard":                     {"owner": "self",     "role": "discard"},
				"red_sidebar":                     {"owner": "self",     "role": "sidebar"},
				"red_equipment":                   {"owner": "self",     "role": "equipment"},
				"red_action_field_top_distant":     {"owner": "self",     "role": "action_field_top_distant"},
				"red_action_field_top_hidden":      {"owner": "self",     "role": "action_field_top_hidden"},
				"red_action_field_bottom_hidden":   {"owner": "self",     "role": "action_field_bottom_hidden"},
				"red_action_field_bottom_distant":  {"owner": "self",     "role": "action_field_bottom_distant"},
				"red_ws_0_weapon":                 {"owner": "self",     "role": "ws_0_weapon"},
				"red_ws_0_killstack":              {"owner": "self",     "role": "ws_0_killstack"},
				"blue_deck":                       {"owner": "opponent", "role": "deck"},
				"blue_action_field_top_distant":    {"owner": "opponent", "role": "action_field_top_distant"},
				"blue_action_field_bottom_distant": {"owner": "opponent", "role": "action_field_bottom_distant"},
				"guard_deck":                      {"owner": "shared",   "role": "guard_deck"},
			},
			"weapon_slots": {
				"red_ws_0":  {"owner": "self",     "role": "ws_0"},
				"blue_ws_0": {"owner": "opponent", "role": "ws_0"},
			}
		},

		# Step 1: initial state (identity revealed via view.role/alignment;
		# hidden opponent slots absent)
		{
			"type": "state",
			"view": {
				"role": "Human",
				"alignment": "GOOD",
				"hp": 20,
				"slots": {
					"red_hand": [{"name": "food_5", "counters": 0}, {"name": "enemy_3", "counters": 0}, {"name": "weapon_2", "counters": 0}],
					"red_deck": 25,
					"red_refresh": 0,
					"red_discard": 0,
					"red_equipment": [{"name": "good_role_1", "counters": 0}],
					"red_action_field_top_distant": [{"name": "enemy_5", "counters": 0}],
					"red_action_field_top_hidden": [{"name": "major_1", "counters": 0}],
					"red_action_field_bottom_hidden": [{"name": "weapon_4", "counters": 0}],
					"red_action_field_bottom_distant": [{"name": "enemy_3", "counters": 0}],
					"red_ws_0_weapon": [],
					"red_ws_0_killstack": [],
					"blue_deck": 24,
					"blue_action_field_top_distant": [{"name": "enemy_3", "counters": 0}],
					"blue_action_field_bottom_distant": [{"name": "food_5", "counters": 0}],
					"guard_deck": 4,
				},
				"current_phase": "ACTION",
				"priority": "RED",
				"game_result": null
			}
		},

		# Step 2: prompt (choose an action slot to resolve)
		{
			"type": "prompt",
			"text": "Choose an action slot to resolve:",
			"options": [
				{"type": "card", "slot": "red_action_field_top_distant", "index": 0},
				{"type": "card", "slot": "red_action_field_top_hidden", "index": 0},
				{"type": "card", "slot": "red_action_field_bottom_hidden", "index": 0},
				{"type": "card", "slot": "red_action_field_bottom_distant", "index": 0},
				{"type": "text", "text": "Pass"}
			]
		},

		# Step 3: close
		{"type": "close"},
	]


func _on_start_pressed() -> void:
	var port := port_input.text.to_int() if port_input.text.is_valid_int() else DEFAULT_PORT
	tcp_server = TCPServer.new()
	var err := tcp_server.listen(port)
	if err != OK:
		status_label.text = "Failed to listen on port %d: %s" % [port, error_string(err)]
		return

	status_label.text = "Listening on port %d... waiting for client" % port
	start_button.disabled = true
	_log("Server started on port %d" % port)


func _process(_delta: float) -> void:
	if tcp_server and tcp_server.is_listening():
		if tcp_server.is_connection_available():
			client_peer = tcp_server.take_connection()
			client_peer.set_no_delay(true)
			status_label.text = "Client connected!"
			step_button.disabled = false
			_step_index = 0
			_log("Client connected")

	if client_peer:
		client_peer.poll()
		if client_peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_read_client()
		elif client_peer.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			_log("Client disconnected")
			client_peer = null
			step_button.disabled = true


func _read_client() -> void:
	var available := client_peer.get_available_bytes()
	if available <= 0:
		return
	var result := client_peer.get_data(available)
	if result[0] == OK:
		var text := (result[1] as PackedByteArray).get_string_from_utf8()
		for line in text.split("\n", false):
			_log("<<< %s" % line.strip_edges())


func _on_step_pressed() -> void:
	if client_peer == null:
		status_label.text = "No client connected"
		return

	if _step_index >= _sequence.size():
		status_label.text = "Sequence complete"
		step_button.disabled = true
		return

	var msg: Dictionary = _sequence[_step_index]
	_send_to_client(msg)
	_step_index += 1

	if _step_index >= _sequence.size():
		status_label.text = "All messages sent"
		step_button.disabled = true


func _send_to_client(msg: Dictionary) -> void:
	var json_str := JSON.stringify(msg) + "\n"
	var data := json_str.to_utf8_buffer()
	client_peer.put_data(data)
	_log(">>> [%s] (%d bytes)" % [msg.get("type", "?"), data.size()])


func _log(text: String) -> void:
	log_text.text += text + "\n"
	log_text.scroll_vertical = log_text.get_line_count()
