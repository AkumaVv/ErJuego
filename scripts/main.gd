extends Node3D

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const SPAWN_POINTS := [
	Vector3(-2.4, 1.05, 9.0), Vector3(-0.8, 1.05, 9.0),
	Vector3(0.8, 1.05, 9.0), Vector3(2.4, 1.05, 9.0)
]
const CHARACTER_NAMES := ["Caballero rojo", "Guardián azul", "Explorador verde", "Mercenario dorado"]
const CHARACTER_COLORS := [Color("#b94747"), Color("#3e70bd"), Color("#3f985c"), Color("#c19235")]

@onready var player_template: CharacterBody3D = $Player
@onready var menu: Control = $MultiplayerMenu/MenuPanel
@onready var interface: CanvasLayer = $Interface
@onready var address_input: LineEdit = $MultiplayerMenu/MenuPanel/VBox/Address
@onready var character_select: OptionButton = $MultiplayerMenu/MenuPanel/VBox/Character
@onready var name_input: LineEdit = $MultiplayerMenu/MenuPanel/VBox/PlayerName
@onready var port_input: SpinBox = $MultiplayerMenu/MenuPanel/VBox/Port
@onready var status_label: Label = $MultiplayerMenu/MenuPanel/VBox/Status

var players: Dictionary = {}
var player_names: Dictionary = {}
var selected_character := 0

func _ready() -> void:
	for character_name in CHARACTER_NAMES:
		character_select.add_item(character_name)
	player_template.process_mode = Node.PROCESS_MODE_DISABLED
	player_template.visible = false
	player_template.position = Vector3(0.0, -100.0, 0.0)
	player_template.get_node("CollisionShape3D").disabled = true
	interface.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_host_pressed() -> void:
	selected_character = character_select.selected
	var port := int(port_input.value)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		status_label.text = "No se pudo crear la partida: %s" % error_string(error)
		return
	multiplayer.multiplayer_peer = peer
	players[1] = selected_character
	player_names[1] = _clean_name(name_input.text, 1)
	_spawn_player(1, selected_character, player_names[1])
	status_label.text = "Partida creada en el puerto %d" % port
	_show_game()

func _on_join_pressed() -> void:
	selected_character = character_select.selected
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var port := int(port_input.value)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		status_label.text = "No se pudo iniciar la conexión: %s" % error_string(error)
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Conectando a %s:%d…" % [address, port]

func _on_connected_to_server() -> void:
	status_label.text = "Conectado. Preparando personaje…"
	_request_join.rpc_id(1, selected_character, name_input.text)

@rpc("any_peer", "call_remote", "reliable")
func _request_join(preferred_character: int, requested_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var character := _available_character(preferred_character)
	players[peer_id] = character
	player_names[peer_id] = _clean_name(requested_name, peer_id)
	_spawn_player(peer_id, character, player_names[peer_id])
	_spawn_player_remote.rpc(peer_id, character, player_names[peer_id])
	for existing_id in players:
		if existing_id != peer_id:
			_spawn_player_remote.rpc_id(peer_id, existing_id, players[existing_id], player_names[existing_id])

@rpc("authority", "call_remote", "reliable")
func _spawn_player_remote(peer_id: int, character: int, display_name: String) -> void:
	players[peer_id] = character
	player_names[peer_id] = display_name
	_spawn_player(peer_id, character, display_name)

func _spawn_player(peer_id: int, character: int, display_name: String) -> void:
	var node_name := "Player_%d" % peer_id
	if has_node(node_name):
		return
	var player := player_template.duplicate() as CharacterBody3D
	player.name = node_name
	player.position = SPAWN_POINTS[maxi(0, players.size() - 1) % SPAWN_POINTS.size()]
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.get_node("CollisionShape3D").disabled = false
	add_child(player)
	player.configure_network_player(peer_id, character, CHARACTER_COLORS[character], display_name)
	if peer_id == multiplayer.get_unique_id():
		_show_game()

func _available_character(preferred: int) -> int:
	preferred = clampi(preferred, 0, CHARACTER_COLORS.size() - 1)
	if not players.values().has(preferred):
		return preferred
	for character in range(CHARACTER_COLORS.size()):
		if not players.values().has(character):
			return character
	return preferred

func _clean_name(requested_name: String, peer_id: int) -> String:
	var cleaned := requested_name.strip_edges().replace("\n", " ").replace("\r", " ")
	cleaned = cleaned.left(18)
	return cleaned if not cleaned.is_empty() else "Jugador %d" % peer_id

func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	player_names.erase(peer_id)
	_remove_player(peer_id)
	if multiplayer.is_server():
		_remove_player_remote.rpc(peer_id)

@rpc("authority", "call_remote", "reliable")
func _remove_player_remote(peer_id: int) -> void:
	players.erase(peer_id)
	player_names.erase(peer_id)
	_remove_player(peer_id)

func _remove_player(peer_id: int) -> void:
	var player := get_node_or_null("Player_%d" % peer_id)
	if player:
		player.queue_free()

func _show_game() -> void:
	menu.visible = false
	interface.visible = true

func _on_connection_failed() -> void:
	status_label.text = "No se pudo conectar con el anfitrión."
	multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	status_label.text = "El anfitrión cerró la partida."
	menu.visible = true
	interface.visible = false
	players.clear()
	player_names.clear()
	for child in get_children():
		if child.name.begins_with("Player_"):
			child.queue_free()
