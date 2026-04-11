extends Control

@onready var host_input: LineEdit = $CenterContainer/VBoxContainer/HostRow/HostInput
@onready var port_input: LineEdit = $CenterContainer/VBoxContainer/PortRow/PortInput
@onready var transport_selector: OptionButton = $CenterContainer/VBoxContainer/TransportRow/TransportSelector
@onready var connect_button: Button = $CenterContainer/VBoxContainer/ConnectButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	transport_selector.add_item("TCP", 0)
	transport_selector.add_item("WebSocket", 1)

	connect_button.pressed.connect(_on_connect_pressed)
	NetworkTransport.connected.connect(_on_connected)
	NetworkTransport.connection_error.connect(_on_connection_error)
	NetworkTransport.disconnected.connect(_on_disconnected)


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
	var transport: NetworkTransport.TransportType
	match transport_selector.selected:
		0:
			transport = NetworkTransport.TransportType.TCP
		1:
			transport = NetworkTransport.TransportType.WEBSOCKET
		_:
			transport = NetworkTransport.TransportType.TCP

	status_label.text = "Connecting to %s:%d..." % [host, port]
	connect_button.disabled = true
	NetworkTransport.connect_to_server(host, port, transport)


func _on_connected() -> void:
	status_label.text = "Connected!"
	get_tree().change_scene_to_file("res://fj/main.tscn")


func _on_connection_error(err: String) -> void:
	status_label.text = "Error: %s" % err
	connect_button.disabled = false


func _on_disconnected() -> void:
	status_label.text = "Disconnected."
	connect_button.disabled = false
