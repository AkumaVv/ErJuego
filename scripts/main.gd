extends Node3D

const DEFAULT_PORT := 9417
const SERVER_ADDRESSES := ["127.0.0.1", "188.77.174.150"]
const SETTINGS_PATH := "user://multiplayer_settings.cfg"
const MAX_PLAYERS := 4
const SPAWN_POINTS := [
	Vector3(-2.4, 1.05, 9.0), Vector3(-0.8, 1.05, 9.0),
	Vector3(0.8, 1.05, 9.0), Vector3(2.4, 1.05, 9.0)
]
const CHARACTER_NAMES := ["Knight", "Rogue", "Mage", "Barbarian"]
const CHARACTER_COLORS := [Color("#b94747"), Color("#3e70bd"), Color("#3f985c"), Color("#c19235")]

@onready var player_template: CharacterBody3D = $Player
@onready var menu: Control = $MultiplayerMenu/MenuPanel
@onready var interface: CanvasLayer = $Interface
@onready var address_select: OptionButton = $MultiplayerMenu/MenuPanel/VBox/Address
@onready var character_select: OptionButton = $MultiplayerMenu/MenuPanel/VBox/Character
@onready var name_input: LineEdit = $MultiplayerMenu/MenuPanel/VBox/PlayerName
@onready var port_input: SpinBox = $MultiplayerMenu/MenuPanel/VBox/Port
@onready var status_label: Label = $MultiplayerMenu/MenuPanel/VBox/Status
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var inventory_window: CanvasLayer = $InventoryWindow
@onready var equipment_area: Control = $InventoryWindow/Panel/VBox/EquipmentArea
@onready var inventory_grid: GridContainer = $InventoryWindow/Panel/VBox/BackpackScroll/Center/Grid
@onready var character_window: CanvasLayer = $CharacterWindow
@onready var character_details: Label = $CharacterWindow/Panel/VBox/Details

var players: Dictionary = {}
var player_names: Dictionary = {}
var selected_character := 0
var pause_open := false

func _ready() -> void:
	for character_name in CHARACTER_NAMES:
		character_select.add_item(character_name)
	address_select.add_item("Local / this PC — 127.0.0.1")
	address_select.add_item("Server — 188.77.174.150")
	port_input.value = DEFAULT_PORT
	_load_settings()
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
	_setup_inventory_slots()
	_setup_equipment_slots()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and interface.visible:
		if event.keycode == KEY_I:
			_toggle_game_window("inventory")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_C:
			_toggle_game_window("character")
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6 and interface.visible:
		for skeleton_enemy in get_tree().get_nodes_in_group("counterattack_targets"):
			if skeleton_enemy.has_method("cycle_combat_mode"):
				skeleton_enemy.cycle_combat_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and (inventory_window.visible or character_window.visible):
		_close_game_windows()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and (interface.visible or pause_open):
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()

func _setup_inventory_slots() -> void:
	for index in range(60):
		var slot := PanelContainer.new()
		# The project viewport is enlarged when running fullscreen, so these become
		# roughly 50 px cells at 1080p while still fitting ten columns.
		slot.custom_minimum_size = Vector2(30.0, 30.0)
		slot.add_theme_stylebox_override("panel", _inventory_slot_style())
		inventory_grid.add_child(slot)

func _inventory_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.04, 0.025, 0.98)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.38, 0.25, 0.09, 1.0)
	style.shadow_color = Color(0, 0, 0, 0.72)
	style.shadow_size = 4
	return style

func _setup_equipment_slots() -> void:
	var slots := [
		["Helm", "helm", Vector2(0.39, 0.02), Vector2(0.61, 0.19)],
		["Main Hand", "sword", Vector2(0.03, 0.22), Vector2(0.23, 0.71)],
		["Body Armour", "armour", Vector2(0.38, 0.23), Vector2(0.62, 0.71)],
		["Amulet", "amulet", Vector2(0.66, 0.23), Vector2(0.78, 0.37)],
		["Second Hand", "shield", Vector2(0.77, 0.22), Vector2(0.97, 0.71)],
		["Ring 1", "ring", Vector2(0.25, 0.56), Vector2(0.37, 0.69)],
		["Ring 2", "ring", Vector2(0.63, 0.56), Vector2(0.75, 0.69)],
		["Gloves", "gloves", Vector2(0.07, 0.77), Vector2(0.29, 0.96)],
		["Belt", "belt", Vector2(0.38, 0.80), Vector2(0.62, 0.94)],
		["Boots", "boots", Vector2(0.71, 0.77), Vector2(0.93, 0.96)]
	]
	for slot_data in slots:
		var slot := PanelContainer.new()
		slot.tooltip_text = slot_data[0]
		slot.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		slot.anchor_left = slot_data[2].x
		slot.anchor_top = slot_data[2].y
		slot.anchor_right = slot_data[3].x
		slot.anchor_bottom = slot_data[3].y
		slot.offset_left = 0.0
		slot.offset_top = 0.0
		slot.offset_right = 0.0
		slot.offset_bottom = 0.0
		slot.add_theme_stylebox_override("panel", _inventory_slot_style())
		var placeholder := TextureRect.new()
		placeholder.texture = _equipment_placeholder_texture(slot_data[1])
		placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		placeholder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(placeholder)
		equipment_area.add_child(slot)

func _equipment_placeholder_texture(kind: String) -> ImageTexture:
	var shapes := {
		"helm": '<path d="M22 70V45C22 18 78 18 78 45V70H61V53H48V82H30V70Z"/>',
		"sword": '<path d="M46 12H54L57 64L70 72L57 78L54 91H46L43 78L30 72L43 64Z"/>',
		"armour": '<path d="M22 28L39 18H61L78 28L69 48L65 88H35L31 48Z"/>',
		"amulet": '<path d="M28 20Q50 65 72 20M50 58L63 72L50 88L37 72Z" fill="none" stroke-width="8"/>',
		"shield": '<path d="M50 12L82 25V55Q78 78 50 90Q22 78 18 55V25Z"/>',
		"ring": '<circle cx="50" cy="55" r="27" fill="none" stroke-width="13"/><path d="M38 25L50 12L62 25Z"/>',
		"gloves": '<path d="M28 82L20 50L25 28L34 55L33 20L41 53L45 17L49 53L56 23L58 60L72 48L66 78L52 89Z"/>',
		"belt": '<path d="M10 38H90V64H10Z"/><path d="M40 31H65V71H40Z" fill="none" stroke-width="7"/>',
		"boots": '<path d="M22 15H48V61L61 76V88H12V72L25 59ZM62 15H82V66L92 76V88H58V72L65 59Z"/>'
	}
	var shape: String = shapes.get(kind, shapes["armour"])
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><g fill="#49351f" stroke="#a17b3f" stroke-width="4" stroke-linejoin="round">%s</g></svg>' % shape
	var image := Image.new()
	image.load_svg_from_string(svg, 2.0)
	return ImageTexture.create_from_image(image)

func _toggle_game_window(window_name: String) -> void:
	if window_name == "inventory":
		inventory_window.visible = not inventory_window.visible
	elif window_name == "character":
		character_window.visible = not character_window.visible
	if character_window.visible:
		_update_character_window()
	_set_local_controls(not inventory_window.visible and not character_window.visible)

func _close_game_windows() -> void:
	inventory_window.visible = false
	character_window.visible = false
	_set_local_controls(true)

func _set_local_controls(enabled: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE
	var local_player := get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if local_player and local_player.has_method("set_controls_enabled"):
		local_player.set_controls_enabled(enabled)

func _update_character_window() -> void:
	var peer_id := multiplayer.get_unique_id()
	var local_player := get_node_or_null("Player_%d" % peer_id)
	if not local_player:
		return
	var class_index: int = clampi(local_player.character_class, 0, CHARACTER_NAMES.size() - 1)
	character_details.text = "Name: %s\nClass: %s\nHealth: %d / %d\nBase damage: 5\n\n◆ ATTRIBUTES ◆\n\nStrength: %d\nDexterity: %d\nIntelligence: %d\n\nSecondary: %s" % [
		player_names.get(peer_id, "Player"),
		CHARACTER_NAMES[class_index],
		local_player.health,
		local_player.max_health,
		local_player.strength,
		local_player.dexterity,
		local_player.intelligence,
		["Block", "Double Bolt", "Chain", "Triple Whirlwind"][class_index]
	]

func _toggle_pause_menu() -> void:
	pause_open = not pause_open
	pause_menu.visible = pause_open
	interface.visible = not pause_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_open else Input.MOUSE_MODE_CAPTURED
	var local_player := get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if local_player and local_player.has_method("set_controls_enabled"):
		local_player.set_controls_enabled(not pause_open)

func _on_login_pressed() -> void:
	pause_open = false
	pause_menu.visible = false
	inventory_window.visible = false
	character_window.visible = false
	multiplayer.multiplayer_peer = null
	players.clear()
	player_names.clear()
	for child in get_children():
		if child.name.begins_with("Player_"):
			child.queue_free()
	menu.visible = true
	interface.visible = false
	status_label.text = "Disconnected. You can host or join another game."
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_host_pressed() -> void:
	selected_character = character_select.selected
	_save_settings()
	var port := int(port_input.value)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		status_label.text = "Could not host the game: %s" % error_string(error)
		return
	multiplayer.multiplayer_peer = peer
	players[1] = selected_character
	player_names[1] = _clean_name(name_input.text, 1)
	_spawn_player(1, selected_character, player_names[1])
	status_label.text = "Game hosted on port %d" % port
	_show_game()

func _on_join_pressed() -> void:
	selected_character = character_select.selected
	_save_settings()
	var address: String = SERVER_ADDRESSES[address_select.selected]
	var port := int(port_input.value)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		status_label.text = "Could not start the connection: %s" % error_string(error)
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting to %s:%d…" % [address, port]

func _on_connected_to_server() -> void:
	status_label.text = "Connected. Preparing character…"
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
	return cleaned if not cleaned.is_empty() else "Player %d" % peer_id

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", name_input.text.strip_edges())
	config.set_value("player", "character", character_select.selected)
	config.set_value("connection", "server", address_select.selected)
	config.set_value("connection", "port", int(port_input.value))
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save settings: " + error_string(error))

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	name_input.text = str(config.get_value("player", "name", ""))
	character_select.select(clampi(int(config.get_value("player", "character", 0)), 0, CHARACTER_NAMES.size() - 1))
	address_select.select(clampi(int(config.get_value("connection", "server", 0)), 0, SERVER_ADDRESSES.size() - 1))
	port_input.value = clampi(int(config.get_value("connection", "port", DEFAULT_PORT)), 1024, 65535)

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
	pause_menu.visible = false
	pause_open = false
	inventory_window.visible = false
	character_window.visible = false
	interface.visible = true

func _on_connection_failed() -> void:
	status_label.text = "Could not connect to the host."
	multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	status_label.text = "The host closed the game."
	menu.visible = true
	interface.visible = false
	pause_menu.visible = false
	pause_open = false
	inventory_window.visible = false
	character_window.visible = false
	players.clear()
	player_names.clear()
	for child in get_children():
		if child.name.begins_with("Player_"):
			child.queue_free()
