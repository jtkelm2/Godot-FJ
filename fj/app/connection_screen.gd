## ConnectionScreen: host/port + transport-type input. Talks only to the
## App autoload; no other component is reachable.

extends Control


@onready var host_input: LineEdit = $CenterContainer/VBoxContainer/HostRow/HostInput
@onready var port_input: LineEdit = $CenterContainer/VBoxContainer/PortRow/PortInput
@onready var transport_selector: OptionButton = $CenterContainer/VBoxContainer/TransportRow/TransportSelector
@onready var connect_button: Button = $CenterContainer/VBoxContainer/ConnectButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	transport_selector.add_item("TCP", Transport.Type.TCP)
	transport_selector.add_item("WebSocket", Transport.Type.WEBSOCKET)

	connect_button.pressed.connect(_on_connect_pressed)
	App.connected.connect(_on_connected)
	App.connection_error.connect(_on_connection_error)
	App.disconnected.connect(_on_disconnected)
	App.session_started.connect(_on_session_started)


func _on_connect_pressed() -> void:
	var host := host_input.text.strip_edges()
	var port_text := port_input.text.strip_edges()

	if host.is_empty():
		status_label.text = "Please enter a host."
		return
	if not port_text.is_valid_int():
		status_label.text = "Please enter a valid port number."
		return

	var port := port_text.to_int()
	var transport: Transport.Type
	match transport_selector.selected:
		Transport.Type.TCP:       transport = Transport.Type.TCP
		Transport.Type.WEBSOCKET: transport = Transport.Type.WEBSOCKET
		_:                        transport = Transport.Type.TCP

	status_label.text = "Connecting to %s:%d..." % [host, port]
	connect_button.disabled = true
	App.connect_to(host, port, transport)


func _on_connected() -> void:
	status_label.text = "Connected. Waiting for server..."


func _on_session_started(my_pid: NLEnums.PID) -> void:
	# App swaps the scene as part of session_started; this status is mostly
	# for the brief moment between "session started" and the new scene
	# replacing this one.
	status_label.text = "Joining game as %s..." % _pid_name(my_pid)


func _on_connection_error(err: String) -> void:
	status_label.text = "Error: %s" % err
	connect_button.disabled = false


func _on_disconnected() -> void:
	status_label.text = "Disconnected."
	connect_button.disabled = false


static func _pid_name(pid: NLEnums.PID) -> String:
	match pid:
		NLEnums.PID.RED:  return "RED"
		NLEnums.PID.BLUE: return "BLUE"
	return ""
