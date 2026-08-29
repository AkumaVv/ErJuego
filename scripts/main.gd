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
const PROCEDURAL_DUNGEON_SCRIPT := preload("res://scripts/procedural_dungeon.gd")
const TRAINING_DUMMY_SCRIPT := preload("res://scripts/training_dummy.gd")
const LOBBY_ENEMY_NAMES := ["SKELETON MINION", "SKELETON WARRIOR", "SKELETON ROGUE", "SKELETON MAGE"]
const LOBBY_ENEMY_BODY_RADII := [0.44, 0.48, 0.43, 0.45]
const LOBBY_ENEMY_BODY_HEIGHTS := [1.38, 1.72, 1.55, 1.62]
const LOBBY_ENEMY_HEAD_RADII := [0.40, 0.38, 0.34, 0.38]
const LOBBY_ENEMY_HEAD_HEIGHTS := [1.34, 1.67, 1.51, 1.70]
const LOBBY_ENEMY_SHOULDER_WIDTHS := [1.18, 1.28, 1.20, 1.18]
const LOBBY_ENEMY_SHOULDER_RADII := [0.24, 0.27, 0.24, 0.25]
const LOBBY_ENEMY_SHOULDER_HEIGHTS := [1.08, 1.27, 1.16, 1.20]
const LOBBY_ENEMY_SILHOUETTE_SIZES := [
	Vector3(1.512, 1.690, 0.712),
	Vector3(1.515, 2.021, 1.138),
	Vector3(1.515, 1.800, 0.900),
	Vector3(1.512, 2.052, 1.354)
]
const LOBBY_ENEMY_SILHOUETTE_Z_CENTERS := [-0.002, -0.023, -0.004, 0.015]
const EQUIPMENT_TYPES := ["helmet", "body_armour", "gloves", "boots", "ring", "amulet", "belt"]
const SKILL_TREE_SCRIPT := preload("res://scripts/skill_tree.gd")
const EQUIPMENT_NAMES := {
	"helmet": ["Helmet", "Helmet", "Helmet", "Helmet"],
	"body_armour": ["Body Armour", "Body Armour", "Body Armour", "Body Armour"],
	"gloves": ["Gloves", "Gloves", "Gloves", "Gloves"],
	"boots": ["Boots", "Boots", "Boots", "Boots"],
	"ring": ["Ring", "Ring", "Ring", "Ring"],
	"amulet": ["Amulet", "Amulet", "Amulet", "Amulet"],
	"belt": ["Belt", "Belt", "Belt", "Belt"]
}

@onready var player_template: CharacterBody3D = $Player
@onready var menu: Control = $MultiplayerMenu/MenuPanel
@onready var interface: CanvasLayer = $Interface
@onready var address_select: OptionButton = $MultiplayerMenu/MenuPanel/VBox/Address
@onready var character_select: OptionButton = $MultiplayerMenu/MenuPanel/VBox/Character
@onready var name_input: LineEdit = $MultiplayerMenu/MenuPanel/VBox/PlayerName
@onready var port_input: SpinBox = $MultiplayerMenu/MenuPanel/VBox/Port
@onready var status_label: Label = $MultiplayerMenu/MenuPanel/VBox/Status
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var death_menu: CanvasLayer = $DeathMenu
@onready var inventory_window: CanvasLayer = $InventoryWindow
@onready var equipment_area: Control = $InventoryWindow/Panel/VBox/EquipmentArea
@onready var inventory_grid: GridContainer = $InventoryWindow/Panel/VBox/BackpackScroll/Center/Grid
@onready var character_window: CanvasLayer = $CharacterWindow
@onready var character_details: Label = $CharacterWindow/Panel/VBox/DetailsMargin/Details
var dungeon_entrance_sign: StaticBody3D
var lobby_stash_object: StaticBody3D
var stash_window: CanvasLayer
var stash_grid: GridContainer
var stash_items: Array = []
var stash_slots: Array[PanelContainer] = []
var stash_initialized := false
var focused_stash_object: StaticBody3D
var held_item: Dictionary = {}
var held_origin_container := ""
var held_origin_index := -1
var held_item_layer: CanvasLayer
var held_item_icon: TextureRect
var skill_tree_window: CanvasLayer
var skill_tree_view: Control

var players: Dictionary = {}
var player_names: Dictionary = {}
var selected_character := 0
var pause_open := false
var in_dungeon := false
var dungeon_seed := 0
var inside_lobby_unlocked := false
var death_return_pending := false
var local_inventory: Array = []
var local_equipment := {
	"main_hand": {}, "helm": {}, "armour": {}, "gloves": {}, "boots": {},
	"ring_1": {}, "ring_2": {}, "amulet": {}, "belt": {}
}
var inventory_slots: Array[PanelContainer] = []
var equipment_slots: Dictionary = {}
var local_items_initialized := false
var equipped_items_by_peer: Dictionary = {}
var item_icon_textures: Dictionary = {}

func _physics_process(_delta: float) -> void:
	if not in_dungeon or inside_lobby_unlocked or not multiplayer.is_server():
		return
	var generated := get_node_or_null("ProceduralDungeon")
	if not generated or not generated.has_method("is_player_inside_lobby"):
		return
	for peer_id in players:
		var player := get_node_or_null("Player_%d" % peer_id)
		if player and not generated.is_player_inside_lobby(player.global_position):
			_unlock_inside_lobby.rpc()
			return

func _process(_delta: float) -> void:
	if held_item_icon and held_item_icon.visible:
		held_item_icon.position = get_viewport().get_mouse_position() - held_item_icon.size * 0.5

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
	_setup_stash_window()
	_setup_skill_tree_window()
	_initialize_test_stash()
	_setup_lobby_dungeon_sign()
	lobby_stash_object = _create_stash_world_object(self, Vector3(3.9, 0.0, -10.15), "LobbyStash")
	lobby_stash_object.rotation.y = 0.0
	_setup_lobby_enemy_dummies()

func _setup_lobby_enemy_dummies() -> void:
	var z_positions := [-6.0, -2.0, 2.0, 6.0]
	for type in range(4):
		var dummy := StaticBody3D.new()
		dummy.name = "LobbyEnemyDummy_%d" % type
		dummy.position = Vector3(-10.35, 0.05, z_positions[type])
		dummy.rotation_degrees.y = 90.0
		dummy.set_script(TRAINING_DUMMY_SCRIPT)
		dummy.skeleton_type = type
		dummy.target_title = LOBBY_ENEMY_NAMES[type]
		dummy.combat_mode = 1
		dummy.fixed_passive_dummy = true
		dummy.add_to_group("lobby_enemy_dummies")
		var body_collision := CollisionShape3D.new()
		body_collision.name = "CollisionShape3D"
		var capsule := CapsuleShape3D.new()
		capsule.radius = LOBBY_ENEMY_BODY_RADII[type]
		capsule.height = LOBBY_ENEMY_BODY_HEIGHTS[type]
		body_collision.shape = capsule
		body_collision.position.y = capsule.height * 0.5
		dummy.add_child(body_collision)
		var head_collision := CollisionShape3D.new()
		head_collision.name = "HeadCollisionShape3D"
		var sphere := SphereShape3D.new()
		sphere.radius = LOBBY_ENEMY_HEAD_RADII[type]
		head_collision.shape = sphere
		head_collision.position.y = LOBBY_ENEMY_HEAD_HEIGHTS[type]
		dummy.add_child(head_collision)
		var shoulder_collision := CollisionShape3D.new()
		shoulder_collision.name = "ShoulderCollisionShape3D"
		var shoulder_capsule := CapsuleShape3D.new()
		shoulder_capsule.radius = LOBBY_ENEMY_SHOULDER_RADII[type]
		shoulder_capsule.height = LOBBY_ENEMY_SHOULDER_WIDTHS[type]
		shoulder_collision.shape = shoulder_capsule
		shoulder_collision.position.y = LOBBY_ENEMY_SHOULDER_HEIGHTS[type]
		shoulder_collision.rotation_degrees.z = 90.0
		dummy.add_child(shoulder_collision)
		var silhouette_collision := CollisionShape3D.new()
		silhouette_collision.name = "SilhouetteCollisionShape3D"
		var silhouette_box := BoxShape3D.new()
		silhouette_box.size = LOBBY_ENEMY_SILHOUETTE_SIZES[type]
		silhouette_collision.shape = silhouette_box
		silhouette_collision.position.y = silhouette_box.size.y * 0.5
		silhouette_collision.position.z = LOBBY_ENEMY_SILHOUETTE_Z_CENTERS[type]
		dummy.add_child(silhouette_collision)
		var label := Label3D.new()
		label.name = "Counter"
		label.position = Vector3(0.0, 2.75, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 30
		label.outline_size = 7
		label.modulate = Color(0.92, 0.94, 1.0)
		dummy.add_child(label)
		add_child(dummy)

func _input(event: InputEvent) -> void:
	if death_menu.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P and interface.visible:
		_toggle_skill_tree()
		get_viewport().set_input_as_handled()
		return
	if interface.visible and _is_dungeon_sign_activation(event) and (not stash_window or not stash_window.visible):
		if _is_looking_at_stash():
			_open_stash()
			get_viewport().set_input_as_handled()
			return
	if interface.visible and not in_dungeon and _is_dungeon_sign_activation(event):
		if _is_looking_at_dungeon_sign():
			_on_join_dungeon_pressed()
			get_viewport().set_input_as_handled()
			return
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
	if event.is_action_pressed("ui_cancel") and (inventory_window.visible or character_window.visible or (stash_window and stash_window.visible) or (skill_tree_window and skill_tree_window.visible)):
		_close_game_windows()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and (interface.visible or pause_open):
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()

func _setup_inventory_slots() -> void:
	local_inventory.resize(60)
	for index in range(60):
		var slot := PanelContainer.new()
		# The project viewport is enlarged when running fullscreen, so these become
		# roughly 50 px cells at 1080p while still fitting ten columns.
		slot.custom_minimum_size = Vector2(30.0, 30.0)
		slot.clip_contents = true
		slot.add_theme_stylebox_override("panel", _inventory_slot_style())
		slot.gui_input.connect(_on_inventory_slot_input.bind(index))
		inventory_slots.append(slot)
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

func _setup_stash_window() -> void:
	stash_window = CanvasLayer.new()
	stash_window.name = "StashWindow"
	stash_window.layer = 12
	stash_window.visible = false
	add_child(stash_window)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.anchor_left = 0.02
	panel.anchor_top = 0.04
	panel.anchor_right = 0.36
	panel.anchor_bottom = 0.96
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.032, 0.0175, 0.0125, 0.99)
	panel_style.border_width_left = 6
	panel_style.border_width_top = 6
	panel_style.border_width_right = 6
	panel_style.border_width_bottom = 6
	panel_style.border_color = Color(0.43, 0.29, 0.105, 1.0)
	panel_style.shadow_color = Color(0, 0, 0, 0.85)
	panel_style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", panel_style)
	stash_window.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "◆  STASH  ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#d9a83e"))
	column.add_child(title)
	var hint := Label.new()
	hint.text = "Left click: move · Ctrl+click: quick transfer"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("#aa8a57"))
	column.add_child(hint)
	var separator := HSeparator.new()
	column.add_child(separator)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	stash_grid = GridContainer.new()
	stash_grid.columns = 9
	stash_grid.add_theme_constant_override("h_separation", 4)
	stash_grid.add_theme_constant_override("v_separation", 4)
	center.add_child(stash_grid)
	stash_items.resize(81)
	for index in range(81):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(30.0, 30.0)
		slot.clip_contents = true
		slot.add_theme_stylebox_override("panel", _inventory_slot_style())
		slot.gui_input.connect(_on_stash_slot_input.bind(index))
		stash_slots.append(slot)
		stash_grid.add_child(slot)
	_setup_held_item_cursor()

func _setup_skill_tree_window() -> void:
	skill_tree_window = CanvasLayer.new()
	skill_tree_window.name = "SkillTreeWindow"
	skill_tree_window.layer = 24
	skill_tree_window.visible = false
	add_child(skill_tree_window)
	skill_tree_view = Control.new()
	skill_tree_view.name = "SkillTree"
	skill_tree_view.set_script(SKILL_TREE_SCRIPT)
	skill_tree_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skill_tree_window.add_child(skill_tree_view)

func _toggle_skill_tree() -> void:
	if skill_tree_window.visible:
		skill_tree_view.snap_rotations()
		skill_tree_window.visible = false
		_set_local_controls(true)
	else:
		_return_held_item()
		inventory_window.visible = false
		character_window.visible = false
		if stash_window:
			stash_window.visible = false
		_close_all_stashes()
		skill_tree_window.visible = true
		_set_local_controls(false)

func _setup_held_item_cursor() -> void:
	held_item_layer = CanvasLayer.new()
	held_item_layer.name = "HeldItemCursor"
	held_item_layer.layer = 40
	add_child(held_item_layer)
	held_item_icon = TextureRect.new()
	held_item_icon.name = "Icon"
	held_item_icon.size = Vector2(44.0, 44.0)
	held_item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	held_item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	held_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held_item_icon.visible = false
	held_item_layer.add_child(held_item_icon)

func _initialize_test_stash() -> void:
	if stash_initialized:
		return
	stash_initialized = true
	var write_index := 0
	for variant in range(4):
		stash_items[write_index] = _create_wand_item_for_variant(variant)
		write_index += 1
		for item_type in EQUIPMENT_TYPES:
			stash_items[write_index] = _create_equipment_item_for_variant(item_type, variant)
			write_index += 1
	_refresh_stash_ui()

func _refresh_stash_ui() -> void:
	for index in range(stash_slots.size()):
		_set_item_slot_display(stash_slots[index], stash_items[index])

func _on_stash_slot_input(event: InputEvent, index: int) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if event.ctrl_pressed and held_item.is_empty():
		_quick_transfer_stash_to_inventory(index)
	else:
		_pick_or_place_item("stash", index)

func _setup_equipment_slots() -> void:
	var slots := [
		["Helm", "helm", Vector2(0.39, 0.02), Vector2(0.61, 0.19)],
		["Main Hand", "sword", Vector2(0.03, 0.22), Vector2(0.23, 0.71)],
		["Body Armour", "armour", Vector2(0.38, 0.23), Vector2(0.62, 0.71)],
		["Amulet", "amulet", Vector2(0.63, 0.23), Vector2(0.75, 0.37)],
		["Second Hand", "shield", Vector2(0.77, 0.22), Vector2(0.97, 0.71)],
		["Ring 1", "ring", Vector2(0.25, 0.56), Vector2(0.37, 0.69)],
		["Ring 2", "ring", Vector2(0.63, 0.56), Vector2(0.75, 0.69)],
		["Gloves", "gloves", Vector2(0.07, 0.77), Vector2(0.29, 0.96)],
		["Belt", "belt", Vector2(0.38, 0.80), Vector2(0.62, 0.94)],
		["Boots", "boots", Vector2(0.71, 0.77), Vector2(0.93, 0.96)]
	]
	for slot_data in slots:
		var slot := PanelContainer.new()
		slot.clip_contents = true
		slot.tooltip_text = slot_data[0]
		slot.set_meta("slot_name", slot_data[0])
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
		placeholder.name = "Placeholder"
		placeholder.texture = _equipment_placeholder_texture(slot_data[1])
		placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		placeholder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(placeholder)
		var item_display := Label.new()
		item_display.name = "ItemDisplay"
		item_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_display.add_theme_color_override("font_color", Color.WHITE)
		item_display.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
		item_display.add_theme_constant_override("outline_size", 4)
		slot.add_child(item_display)
		var slot_key := str(slot_data[1])
		if slot_data[0] == "Main Hand":
			slot_key = "main_hand"
		elif slot_data[0] == "Ring 1":
			slot_key = "ring_1"
		elif slot_data[0] == "Ring 2":
			slot_key = "ring_2"
		equipment_slots[slot_key] = slot
		if slot_key in local_equipment:
			slot.gui_input.connect(_on_equipment_slot_input.bind(slot_key))
		equipment_area.add_child(slot)
	_refresh_inventory_ui()

func _create_wand_item() -> Dictionary:
	return _create_wand_item_for_variant(randi_range(0, 3))

func _create_wand_item_for_variant(variant: int) -> Dictionary:
	var peer_id := multiplayer.get_unique_id()
	variant = clampi(variant, 0, 3)
	return {
		"instance_id": "%d-%d-%d" % [peer_id, Time.get_ticks_usec(), randi()],
		"type": "wand",
		"name": "Starter Wand",
		"rarity": "normal",
		"model_variant": variant,
		"base_color": ["grey", "red", "yellow", "blue"][variant],
		"physical_min": 4,
		"physical_max": 6
	}

func _create_equipment_item(item_type: String) -> Dictionary:
	return _create_equipment_item_for_variant(item_type, randi_range(0, 3))

func _create_equipment_item_for_variant(item_type: String, variant: int) -> Dictionary:
	var safe_type := item_type if item_type in EQUIPMENT_TYPES else "helmet"
	variant = clampi(variant, 0, 3)
	var names: Array = EQUIPMENT_NAMES[safe_type]
	var defensive := safe_type in ["helmet", "body_armour", "gloves", "boots", "belt"]
	var color_names := ["red", "green", "blue", "tricolor"] if defensive else ["grey", "red", "yellow", "blue"]
	return {
		"instance_id": "%d-%d-%d" % [multiplayer.get_unique_id(), Time.get_ticks_usec(), randi()],
		"type": safe_type,
		"name": names[variant],
		"rarity": "normal",
		"model_variant": variant,
		"base_color": color_names[variant]
	}

func _initialize_local_items(character: int) -> void:
	if local_items_initialized:
		return
	local_items_initialized = true
	_initialize_test_stash()
	if character == 2:
		local_equipment["main_hand"] = _create_wand_item()
	_submit_equipped_items()
	_refresh_inventory_ui()

func _on_inventory_slot_input(event: InputEvent, index: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if held_item.is_empty():
			_equip_inventory_item(index)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.ctrl_pressed and held_item.is_empty() and stash_window and stash_window.visible:
		_quick_transfer_inventory_to_stash(index)
	else:
		_pick_or_place_item("inventory", index)

func _equip_inventory_item(index: int) -> void:
	var item = local_inventory[index]
	if not item is Dictionary or item.is_empty():
		return
	var destination := _equipment_slot_for_item(item)
	if destination.is_empty():
		return
	var previous = local_equipment.get(destination, {})
	local_equipment[destination] = item
	local_inventory[index] = previous if previous is Dictionary and not previous.is_empty() else null
	_submit_equipped_items()
	_refresh_inventory_ui()

func _equipment_slot_for_item(item: Dictionary) -> String:
	var item_type := str(item.get("type", ""))
	if item_type == "wand":
		var local_player := get_node_or_null("Player_%d" % multiplayer.get_unique_id())
		return "main_hand" if local_player and local_player.character_class == 2 else ""
	var slot_map := {"helmet": "helm", "body_armour": "armour", "gloves": "gloves", "boots": "boots", "amulet": "amulet", "belt": "belt"}
	if item_type == "ring":
		return "ring_1" if (local_equipment.get("ring_1", {}) as Dictionary).is_empty() else "ring_2"
	return str(slot_map.get(item_type, ""))

func _on_equipment_slot_input(event: InputEvent, slot_key: String) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if held_item.is_empty() or not _item_fits_equipment_slot(held_item, slot_key):
			return
		var previous = local_equipment.get(slot_key, {})
		local_equipment[slot_key] = held_item
		if previous is Dictionary and not previous.is_empty():
			held_item = previous
		else:
			_clear_held_item()
		_submit_equipped_items()
		_refresh_held_item_cursor()
		_refresh_inventory_ui()
		return
	if event.button_index != MOUSE_BUTTON_RIGHT or not held_item.is_empty():
		return
	var item = local_equipment.get(slot_key, {})
	if not item is Dictionary or item.is_empty():
		return
	var free_slot := local_inventory.find(null)
	if free_slot < 0:
		return
	local_inventory[free_slot] = item
	local_equipment[slot_key] = {}
	_submit_equipped_items()
	_refresh_inventory_ui()

func _item_fits_equipment_slot(item: Dictionary, slot_key: String) -> bool:
	var item_type := str(item.get("type", ""))
	if slot_key == "main_hand":
		if item_type != "wand":
			return false
		var local_player := get_node_or_null("Player_%d" % multiplayer.get_unique_id())
		return local_player != null and local_player.character_class == 2
	if slot_key == "ring_1" or slot_key == "ring_2":
		return item_type == "ring"
	var slot_types := {
		"helm": "helmet", "armour": "body_armour", "gloves": "gloves",
		"boots": "boots", "amulet": "amulet", "belt": "belt"
	}
	return str(slot_types.get(slot_key, "")) == item_type

func _quick_transfer_inventory_to_stash(index: int) -> void:
	var item = local_inventory[index]
	if not item is Dictionary or item.is_empty():
		return
	var destination := stash_items.find(null)
	if destination < 0:
		return
	stash_items[destination] = item
	local_inventory[index] = null
	_refresh_inventory_ui()
	_refresh_stash_ui()

func _quick_transfer_stash_to_inventory(index: int) -> void:
	var item = stash_items[index]
	if not item is Dictionary or item.is_empty():
		return
	var destination := local_inventory.find(null)
	if destination < 0:
		return
	local_inventory[destination] = item
	stash_items[index] = null
	_refresh_inventory_ui()
	_refresh_stash_ui()

func _pick_or_place_item(container_name: String, index: int) -> void:
	var target = local_inventory[index] if container_name == "inventory" else stash_items[index]
	if held_item.is_empty():
		if not target is Dictionary or target.is_empty():
			return
		held_item = target
		held_origin_container = container_name
		held_origin_index = index
		_set_container_item(container_name, index, null)
	else:
		_set_container_item(container_name, index, held_item)
		if target is Dictionary and not target.is_empty():
			held_item = target
		else:
			_clear_held_item()
	_refresh_held_item_cursor()
	_refresh_inventory_ui()
	_refresh_stash_ui()

func _set_container_item(container_name: String, index: int, item) -> void:
	if container_name == "inventory":
		local_inventory[index] = item
	else:
		stash_items[index] = item

func _refresh_held_item_cursor() -> void:
	if not held_item_icon:
		return
	held_item_icon.visible = not held_item.is_empty()
	held_item_icon.texture = _item_icon_texture(str(held_item.get("type", "")), int(held_item.get("model_variant", 0))) if not held_item.is_empty() else null

func _clear_held_item() -> void:
	held_item = {}
	held_origin_container = ""
	held_origin_index = -1
	_refresh_held_item_cursor()

func _return_held_item() -> void:
	if held_item.is_empty():
		return
	var returned := false
	if held_origin_index >= 0:
		var origin = local_inventory[held_origin_index] if held_origin_container == "inventory" else stash_items[held_origin_index]
		if origin == null:
			_set_container_item(held_origin_container, held_origin_index, held_item)
			returned = true
	if not returned:
		var preferred := local_inventory if held_origin_container == "inventory" else stash_items
		var free_slot := preferred.find(null)
		if free_slot >= 0:
			_set_container_item(held_origin_container, free_slot, held_item)
			returned = true
	if not returned:
		var fallback_name := "stash" if held_origin_container == "inventory" else "inventory"
		var fallback := stash_items if fallback_name == "stash" else local_inventory
		var fallback_slot := fallback.find(null)
		if fallback_slot >= 0:
			_set_container_item(fallback_name, fallback_slot, held_item)
			returned = true
	if returned:
		_clear_held_item()
		_refresh_inventory_ui()
		_refresh_stash_ui()

func _refresh_inventory_ui() -> void:
	for index in range(inventory_slots.size()):
		var slot := inventory_slots[index]
		var item = local_inventory[index] if index < local_inventory.size() else null
		_set_item_slot_display(slot, item)
	for slot_key in equipment_slots:
		var equipment_slot := equipment_slots[slot_key] as PanelContainer
		_set_item_slot_display(equipment_slot, local_equipment.get(slot_key, {}))
	refresh_character_panel()

func _set_item_slot_display(slot: PanelContainer, item) -> void:
	var label := slot.get_node_or_null("ItemDisplay") as Label
	var placeholder := slot.get_node_or_null("Placeholder") as TextureRect
	var item_icon := slot.get_node_or_null("ItemIcon") as TextureRect
	if not label:
		# Backpack cells are created without their display until first refresh.
		label = Label.new()
		label.name = "ItemDisplay"
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.01))
		label.add_theme_constant_override("outline_size", 3)
		slot.add_child(label)
	label.visible = false
	if not item_icon:
		item_icon = TextureRect.new()
		item_icon.name = "ItemIcon"
		item_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item_icon.offset_left = 4.0
		item_icon.offset_top = 4.0
		item_icon.offset_right = -4.0
		item_icon.offset_bottom = -4.0
		item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(item_icon)
	if item is Dictionary and not item.is_empty():
		item_icon.texture = _item_icon_texture(str(item.get("type", "")), int(item.get("model_variant", 0)))
		item_icon.visible = true
		if placeholder:
			placeholder.visible = false
		if str(item.get("type", "")) == "wand":
			slot.tooltip_text = "%s\nPhysical Damage: %d–%d" % [item.name, item.physical_min, item.physical_max]
		else:
			slot.tooltip_text = str(item.get("name", "Item"))
	else:
		item_icon.texture = null
		item_icon.visible = false
		if placeholder:
			placeholder.visible = true
		slot.tooltip_text = str(slot.get_meta("slot_name", ""))

func _item_icon_texture(item_type: String, variant: int) -> ImageTexture:
	variant = clampi(variant, 0, 3)
	var cache_key := "%s_%d" % [item_type, variant]
	if item_icon_textures.has(cache_key):
		return item_icon_textures[cache_key]
	var wand_designs := [
		'<path d="M18 91Q34 72 48 59Q59 49 68 35" fill="none" stroke="#5a3828" stroke-width="10" stroke-linecap="round"/><path d="M21 87Q43 62 64 39" fill="none" stroke="#d7ad72" stroke-width="3" stroke-linecap="round"/><path d="M67 39C53 31 57 15 70 11C83 7 92 19 87 31C83 42 73 48 67 39Z"/><circle cx="73" cy="25" r="6" fill="#f7f9ff" opacity=".75"/>',
		'<path d="M17 91C28 77 33 65 45 59C58 52 59 39 68 31" fill="none" stroke="#573826" stroke-width="11" stroke-linecap="round"/><path d="M23 84C40 65 51 59 63 37" fill="none" stroke="#e0b57a" stroke-width="3"/><path d="M66 36C53 31 54 17 65 12C76 7 88 15 88 27C88 39 76 45 66 36Z"/><path d="M66 15Q53 7 47 20Q57 22 65 27" fill="none" stroke="#d9dee8" stroke-width="4"/>',
		'<path d="M18 91L65 40" fill="none" stroke="#43352d" stroke-width="11" stroke-linecap="round"/><path d="M23 84L61 43" fill="none" stroke="#e5cda7" stroke-width="3"/><path d="M63 43C51 35 55 20 68 15L77 7L80 19C91 25 91 39 80 46C74 50 68 49 63 43Z"/><path d="M70 22L82 35M82 22L70 35" stroke="#f7f3e9" stroke-width="3"/>',
		'<path d="M17 91Q42 65 66 37" fill="none" stroke="#252d39" stroke-width="11" stroke-linecap="round"/><path d="M23 85Q44 62 63 40" fill="none" stroke="#cbd4df" stroke-width="3"/><path d="M65 42C54 34 56 20 68 14C80 8 92 18 90 31C88 44 75 50 65 42Z"/><path d="M67 14L76 4L82 16M59 23L47 19L55 32" fill="none" stroke="#e7edf6" stroke-width="4"/>'
	]
	var equipment_designs := {
		"helmet": [
			'<path d="M18 72V43Q20 16 50 14Q80 16 82 43V72H65V48H35V72Z"/><path d="M35 35H65"/>',
			'<path d="M16 70V39Q22 17 50 17Q78 17 84 39V70L67 82V48H33V82Z"/><path d="M50 17V70"/>',
			'<path d="M20 76V40Q24 20 50 20Q76 20 80 40V76H62V49H38V76Z"/><path d="M28 24L16 7L40 23M72 24L84 7L60 23"/>',
			'<path d="M18 75V39Q23 18 50 18Q77 18 82 39V75H64V49H36V75Z"/><path d="M25 21L32 6L43 20L50 3L57 20L68 6L75 21Z"/>'
		],
		"body_armour": [
			'<path d="M22 24L39 14H61L78 24L68 48L65 90H35L32 48Z"/><path d="M39 14L50 34L61 14M37 48H63"/>',
			'<path d="M18 27L38 14H62L82 27L70 48L66 90H34L30 48Z"/><path d="M33 38H67M32 52H68M34 66H66"/>',
			'<path d="M19 25L37 12H63L81 25L70 47L66 90H34L30 47Z"/><path d="M31 31L50 45L69 31M50 45V88"/>',
			'<path d="M20 25L38 13H62L80 25L69 48L65 90H35L31 48Z"/><path d="M50 28L60 43L50 58L40 43Z"/><path d="M37 68H63"/>'
		],
		"gloves": [
			'<path d="M25 88L18 53L25 27L34 57L34 18L43 55L49 15L52 56L62 25L61 63L76 48L69 80L52 91Z"/>',
			'<path d="M24 87L18 52L26 24L34 57L36 17L44 56L50 14L54 57L64 24L62 64L77 48L69 80L51 91Z"/><path d="M25 65H68M28 76H65"/>',
			'<path d="M23 87L18 52L27 25L34 57L37 17L45 56L51 14L55 57L65 25L63 64L78 48L69 81L51 92Z"/><path d="M25 66L35 58L45 66L55 57L67 66"/>',
			'<path d="M24 88L18 52L27 25L35 58L37 17L45 56L51 14L55 57L65 25L63 64L78 48L69 81L51 92Z"/><path d="M37 68L50 57L63 68L50 84Z"/>'
		],
		"boots": [
			'<path d="M20 12H47V55C47 68 56 72 68 77C76 81 78 91 68 93H13C9 77 14 64 24 55Z"/><path d="M22 31H46M18 61Q36 69 54 70" fill="none"/>',
			'<path d="M20 10H48V54C48 67 58 71 72 77C82 82 80 94 69 94H12C8 78 13 64 24 54Z"/><path d="M18 27H48M17 42H47M16 62Q35 70 57 71" fill="none"/>',
			'<path d="M18 11H50V54C50 67 60 71 74 77C84 82 82 94 70 94H11C8 78 13 63 23 53Z"/><path d="M19 22L49 34L19 46L48 57M17 65Q38 73 61 72" fill="none"/>',
			'<path d="M19 10H49V54C49 67 59 71 73 77C83 82 81 94 70 94H11C8 78 13 64 24 53Z"/><path d="M33 18L43 33L33 48L23 33ZM18 63Q37 71 60 72" fill="none"/>'
		],
		"ring": [
			'<circle cx="50" cy="58" r="27" fill="none" stroke-width="13"/><path d="M38 27L50 12L62 27Z"/>',
			'<circle cx="50" cy="58" r="27" fill="none" stroke-width="12"/><rect x="36" y="10" width="28" height="25" rx="5"/>',
			'<circle cx="50" cy="59" r="26" fill="none" stroke-width="11"/><path d="M50 7L67 24L50 40L33 24Z"/>',
			'<circle cx="50" cy="58" r="27" fill="none" stroke-width="12"/><path d="M35 28L40 13H60L65 28L50 40Z"/><path d="M40 13L50 28L60 13" fill="none"/>'
		],
		"amulet": [
			'<path d="M22 14Q50 63 78 14" fill="none"/><path d="M50 54L65 72L50 91L35 72Z"/>',
			'<path d="M20 15Q50 61 80 15" fill="none"/><path d="M61 54Q42 57 39 74Q42 91 63 87Q50 78 61 54Z"/>',
			'<path d="M20 14Q50 61 80 14" fill="none"/><path d="M50 49L68 68L50 92L32 68Z"/><path d="M50 55V84"/>',
			'<path d="M20 15Q50 61 80 15" fill="none"/><circle cx="50" cy="72" r="17"/><path d="M50 47V57M50 87V97M25 72H35M65 72H75"/>'
		],
		"belt": [
			'<path d="M7 35H93V67H7Z"/><rect x="39" y="28" width="27" height="46" fill="none"/>',
			'<path d="M6 34H94V68H6Z"/><circle cx="22" cy="51" r="4"/><circle cx="78" cy="51" r="4"/><rect x="39" y="29" width="24" height="44" fill="none"/>',
			'<path d="M7 37H93V65H7Z"/><path d="M12 37L25 65L38 37L51 65L64 37L77 65L90 37" fill="none"/><rect x="40" y="30" width="22" height="42"/>',
			'<path d="M6 34H94V68H6Z"/><path d="M50 29L66 51L50 73L34 51Z"/><path d="M12 44H32M68 44H88M12 58H32M68 58H88"/>'
		]
	}
	var design := ""
	if item_type == "wand":
		design = wand_designs[variant]
	elif equipment_designs.has(item_type):
		design = equipment_designs[item_type][variant]
	else:
		return null
	var defensive_types := ["helmet", "body_armour", "gloves", "boots", "belt"]
	var magical_colors := ["#aeb6c2", "#cc3945", "#e5b92f", "#3987db"]
	var defensive_colors := ["#c73b43", "#3e9a59", "#397fd0", "url(#tricolor)"]
	var fill_color: String = defensive_colors[variant] if item_type in defensive_types else magical_colors[variant]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="tricolor" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#d63d48"/><stop offset=".5" stop-color="#3ba05b"/><stop offset="1" stop-color="#397fd8"/></linearGradient></defs><g fill="%s" stroke="#25222a" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round">%s</g><path d="M27 25Q43 13 61 20" fill="none" stroke="#ffffff" stroke-width="3" opacity=".28" stroke-linecap="round"/></svg>' % [fill_color, design]
	var image := Image.new()
	image.load_svg_from_string(svg, 2.0)
	var texture := ImageTexture.create_from_image(image)
	item_icon_textures[cache_key] = texture
	return texture

func _add_item_to_local_inventory(item: Dictionary) -> bool:
	var free_slot := local_inventory.find(null)
	if free_slot < 0:
		return false
	local_inventory[free_slot] = item.duplicate(true)
	_refresh_inventory_ui()
	return true

func _submit_equipped_items() -> void:
	var loadout := local_equipment.duplicate(true)
	if multiplayer.is_server():
		_set_equipped_item_for_peer(multiplayer.get_unique_id(), loadout)
	else:
		_request_set_equipped_item.rpc_id(1, loadout)

@rpc("any_peer", "call_remote", "reliable")
func _request_set_equipped_item(loadout: Dictionary) -> void:
	if multiplayer.is_server():
		_set_equipped_item_for_peer(multiplayer.get_remote_sender_id(), loadout)

func _set_equipped_item_for_peer(peer_id: int, loadout: Dictionary) -> void:
	equipped_items_by_peer[peer_id] = loadout.duplicate(true)
	if multiplayer.has_multiplayer_peer():
		_sync_equipped_item.rpc(peer_id, loadout)
	else:
		_sync_equipped_item(peer_id, loadout)

@rpc("authority", "call_local", "reliable")
func _sync_equipped_item(peer_id: int, loadout: Dictionary) -> void:
	equipped_items_by_peer[peer_id] = loadout.duplicate(true)
	var player := get_node_or_null("Player_%d" % peer_id)
	if player and player.has_method("apply_equipped_items"):
		player.apply_equipped_items(loadout)

func roll_personal_wand_drops() -> void:
	if not multiplayer.is_server():
		return
	for peer_id in players:
		if randf() > 0.10:
			continue
		# Each personal drop independently rolls one of the currently implemented
		# equipment families, then one of its four visual variants.
		var drop_types := ["wand"] + EQUIPMENT_TYPES
		var drop_type: String = drop_types.pick_random()
		var item := _create_wand_item() if drop_type == "wand" else _create_equipment_item(drop_type)
		item["instance_id"] = "%d-%d-%d" % [peer_id, Time.get_ticks_usec(), randi()]
		if peer_id == multiplayer.get_unique_id():
			_receive_personal_drop(item)
		else:
			_receive_personal_drop.rpc_id(peer_id, item)

@rpc("authority", "call_remote", "reliable")
func _receive_personal_drop(item: Dictionary) -> void:
	_add_item_to_local_inventory(item)

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
		if inventory_window.visible and (not stash_window or not stash_window.visible):
			_return_held_item()
		inventory_window.visible = not inventory_window.visible
	elif window_name == "character":
		character_window.visible = not character_window.visible
	if character_window.visible:
		_update_character_window()
	_set_local_controls(not inventory_window.visible and not character_window.visible and (not stash_window or not stash_window.visible))

func _close_game_windows() -> void:
	_return_held_item()
	inventory_window.visible = false
	character_window.visible = false
	if stash_window:
		stash_window.visible = false
	if skill_tree_window:
		if skill_tree_window.visible:
			skill_tree_view.snap_rotations()
		skill_tree_window.visible = false
	_close_all_stashes()
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
	var damage_text := "%d–%d" % [local_player.weapon_damage_min, local_player.weapon_damage_max] if local_player.has_method("_has_equipped_weapon") and local_player._has_equipped_weapon() else "No weapon equipped"
	character_details.text = "Name: %s\nClass: %s\nHealth: %d / %d\nWeapon damage: %s\n\n◆ ATTRIBUTES ◆\n\nStrength: %d\nDexterity: %d\nIntelligence: %d\n\nSecondary: %s" % [
		player_names.get(peer_id, "Player"),
		CHARACTER_NAMES[class_index],
		local_player.health,
		local_player.max_health,
		damage_text,
		local_player.strength,
		local_player.dexterity,
		local_player.intelligence,
		["Block", "Double Bolt", "Chain", "Triple Whirlwind"][class_index]
	]

func refresh_character_panel() -> void:
	if character_window and character_window.visible:
		_update_character_window()

func _toggle_pause_menu() -> void:
	pause_open = not pause_open
	pause_menu.visible = pause_open
	interface.visible = not pause_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_open else Input.MOUSE_MODE_CAPTURED
	var local_player := get_node_or_null("Player_%d" % multiplayer.get_unique_id())
	if local_player and local_player.has_method("set_controls_enabled"):
		local_player.set_controls_enabled(not pause_open)

func _on_login_pressed() -> void:
	_return_held_item()
	_close_all_stashes()
	pause_open = false
	pause_menu.visible = false
	death_menu.visible = false
	inventory_window.visible = false
	character_window.visible = false
	if stash_window:
		stash_window.visible = false
	multiplayer.multiplayer_peer = null
	players.clear()
	player_names.clear()
	equipped_items_by_peer.clear()
	_reset_local_items()
	_reset_lobby_world()
	for child in get_children():
		if child.name.begins_with("Player_"):
			child.queue_free()
	menu.visible = true
	interface.visible = false
	status_label.text = "Disconnected. You can host or join another game."
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_return_to_lobby_pressed() -> void:
	if not in_dungeon:
		_close_pause_in_lobby()
		return
	if multiplayer.is_server():
		_return_party_to_lobby.rpc()
	else:
		_request_return_to_lobby.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_return_to_lobby() -> void:
	if multiplayer.is_server() and in_dungeon:
		_return_party_to_lobby.rpc()

@rpc("authority", "call_local", "reliable")
func _return_party_to_lobby() -> void:
	_reset_lobby_world()
	death_return_pending = false
	death_menu.visible = false
	var player_index := 0
	for peer_id in players:
		var player := get_node_or_null("Player_%d" % peer_id)
		if player:
			if player.has_method("revive_full"):
				player.revive_full()
			player.global_position = SPAWN_POINTS[player_index % SPAWN_POINTS.size()]
			player.velocity = Vector3.ZERO
		player_index += 1
	_close_pause_in_lobby()

func handle_player_death(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_show_death_menu()

func _show_death_menu() -> void:
	_return_held_item()
	_close_all_stashes()
	pause_open = false
	pause_menu.visible = false
	inventory_window.visible = false
	character_window.visible = false
	if stash_window:
		stash_window.visible = false
	death_menu.visible = true
	interface.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_local_controls(false)

func _on_death_return_inside_pressed() -> void:
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_respawn_player_inside.rpc(peer_id)
	else:
		_request_respawn_inside.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_respawn_inside() -> void:
	if multiplayer.is_server() and in_dungeon:
		_respawn_player_inside.rpc(multiplayer.get_remote_sender_id())

@rpc("authority", "call_local", "reliable")
func _respawn_player_inside(peer_id: int) -> void:
	if not in_dungeon:
		return
	var generated := get_node_or_null("ProceduralDungeon")
	var player := get_node_or_null("Player_%d" % peer_id)
	if not generated or not player or not generated.has_method("get_spawn_position"):
		return
	var peer_list := players.keys()
	var spawn_index := maxi(0, peer_list.find(peer_id))
	if generated.has_method("reset_player_inside_lobby_access"):
		generated.reset_player_inside_lobby_access(peer_id)
	player.global_position = generated.get_spawn_position(spawn_index)
	player.velocity = Vector3.ZERO
	if player.has_method("revive_full"):
		player.revive_full()
	if peer_id == multiplayer.get_unique_id():
		death_menu.visible = false
		interface.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_set_local_controls(true)

func _on_death_exit_pressed() -> void:
	if multiplayer.is_server():
		_return_party_to_lobby.rpc()
	else:
		_request_return_to_lobby.rpc_id(1)

func _close_pause_in_lobby() -> void:
	pause_open = false
	pause_menu.visible = false
	interface.visible = true
	_set_local_controls(true)

func _setup_lobby_dungeon_sign() -> void:
	dungeon_entrance_sign = StaticBody3D.new()
	dungeon_entrance_sign.name = "DungeonEntranceSign"
	dungeon_entrance_sign.position = Vector3(0, 2.15, -10.9)
	dungeon_entrance_sign.add_to_group("dungeon_entrance")
	var board_mesh := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(4.2, 1.7, 0.18)
	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = Color("#25150a")
	board_material.roughness = 0.82
	board.material = board_material
	board_mesh.mesh = board
	dungeon_entrance_sign.add_child(board_mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = board.size
	collision.shape = shape
	dungeon_entrance_sign.add_child(collision)
	var label := Label3D.new()
	label.position = Vector3(0, 0, 0.12)
	label.text = "JOIN THE DUNGEON\nCLICK OR PRESS E"
	label.font_size = 34
	label.modulate = Color("#e0ad4c")
	label.outline_size = 10
	label.outline_modulate = Color("#160b04")
	dungeon_entrance_sign.add_child(label)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.25, 1.0)
	light.light_color = Color("#ff9b45")
	light.light_energy = 1.6
	light.omni_range = 5.0
	dungeon_entrance_sign.add_child(light)
	add_child(dungeon_entrance_sign)

func _create_stash_world_object(parent: Node, position_: Vector3, object_name: String) -> StaticBody3D:
	var stash := StaticBody3D.new()
	stash.name = object_name
	stash.position = position_
	stash.collision_layer = 1
	stash.collision_mask = 1
	stash.add_to_group("stash_interactable")
	parent.add_child(stash)
	var base_mesh := load("res://addons/kaykit_dungeon_remastered/Assets/obj/chest.obj") as Mesh
	var lid_mesh := load("res://addons/kaykit_dungeon_remastered/Assets/obj/chest_lid.obj") as Mesh
	var base_model := MeshInstance3D.new()
	base_model.name = "Base"
	base_model.mesh = base_mesh
	base_model.scale = Vector3.ONE * 1.2
	stash.add_child(base_model)
	var lid_pivot := Node3D.new()
	lid_pivot.name = "LidPivot"
	lid_pivot.position = Vector3(0, 0.6, -0.7) * 1.2
	stash.add_child(lid_pivot)
	var lid_model := MeshInstance3D.new()
	lid_model.name = "Lid"
	lid_model.mesh = lid_mesh
	lid_model.scale = Vector3.ONE * 1.2
	lid_model.position = Vector3(0, -0.6, 0.7) * 1.2
	lid_pivot.add_child(lid_model)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.25, 1.35)
	collision.shape = shape
	collision.position.y = 0.62
	stash.add_child(collision)
	var label := Label3D.new()
	label.text = "STASH\nCLICK OR PRESS E"
	label.position = Vector3(0, 1.65, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 26
	label.outline_size = 7
	label.modulate = Color("#e0ad4c")
	stash.add_child(label)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.15, 0)
	light.light_color = Color("#ffad59")
	light.light_energy = 1.0
	light.omni_range = 3.2
	stash.add_child(light)
	return stash

func _is_looking_at_stash() -> bool:
	focused_stash_object = null
	var player := get_node_or_null("Player_%d" % multiplayer.get_unique_id()) as CharacterBody3D
	if not player:
		return false
	var camera := player.get_node_or_null("Head/Camera3D") as Camera3D
	if not camera:
		return false
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + -camera.global_basis.z * 2.0)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not (hit.collider as Node).is_in_group("stash_interactable"):
		return false
	focused_stash_object = hit.collider as StaticBody3D
	return true

func _open_stash() -> void:
	_animate_stash(focused_stash_object, true)
	stash_window.visible = true
	inventory_window.visible = true
	character_window.visible = false
	_refresh_stash_ui()
	_refresh_inventory_ui()
	_set_local_controls(false)

func _animate_stash(stash: StaticBody3D, opening: bool) -> void:
	if not is_instance_valid(stash):
		return
	var lid := stash.get_node_or_null("LidPivot") as Node3D
	if not lid:
		return
	var tween := lid.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(lid, "rotation_degrees:x", -72.0 if opening else 0.0, 0.42)

func _close_all_stashes() -> void:
	for stash in get_tree().get_nodes_in_group("stash_interactable"):
		_animate_stash(stash as StaticBody3D, false)

func _is_dungeon_sign_activation(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventKey:
		return event.pressed and not event.echo and event.keycode == KEY_E
	return false

func _is_looking_at_dungeon_sign() -> bool:
	var player := get_node_or_null("Player_%d" % multiplayer.get_unique_id()) as CharacterBody3D
	if not player:
		return false
	var camera := player.get_node_or_null("Head/Camera3D") as Camera3D
	if not camera:
		return false
	var from := camera.global_position
	var to := from + -camera.global_basis.z * 3.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit.collider as Node).is_in_group("dungeon_entrance")

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

func _on_join_dungeon_pressed() -> void:
	if in_dungeon:
		return
	if multiplayer.is_server():
		_start_dungeon()
	else:
		_request_dungeon.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_dungeon() -> void:
	if multiplayer.is_server() and not in_dungeon:
		_start_dungeon()

func _start_dungeon() -> void:
	dungeon_seed = randi()
	inside_lobby_unlocked = false
	_enter_dungeon.rpc(dungeon_seed, false)

@rpc("authority", "call_local", "reliable")
func _enter_dungeon(seed_value: int, safe_zone_unlocked := false) -> void:
	if in_dungeon:
		return
	in_dungeon = true
	dungeon_seed = seed_value
	inside_lobby_unlocked = safe_zone_unlocked
	if dungeon_entrance_sign:
		dungeon_entrance_sign.visible = false
		dungeon_entrance_sign.process_mode = Node.PROCESS_MODE_DISABLED
	if lobby_stash_object:
		lobby_stash_object.visible = false
		lobby_stash_object.process_mode = Node.PROCESS_MODE_DISABLED
	var lobby := get_node_or_null("Dungeon")
	if lobby:
		lobby.visible = false
		lobby.process_mode = Node.PROCESS_MODE_DISABLED
	for target_name in ["TrainingDummy", "TrainingEnemy2", "TrainingAlly"]:
		var target := get_node_or_null(target_name)
		if target:
			target.position.y = -100.0
			target.process_mode = Node.PROCESS_MODE_DISABLED
	for dummy in get_tree().get_nodes_in_group("lobby_enemy_dummies"):
		dummy.visible = false
		dummy.process_mode = Node.PROCESS_MODE_DISABLED
	var generated := Node3D.new()
	generated.name = "ProceduralDungeon"
	generated.set_script(PROCEDURAL_DUNGEON_SCRIPT)
	add_child(generated)
	generated.generate(seed_value)
	var back_direction := Vector3(generated.inside_lobby_direction.x, 0.0, generated.inside_lobby_direction.y)
	# Leave enough room behind the lid so neither the closed chest nor its opening
	# animation intersects the decorative wall geometry.
	var inside_stash := _create_stash_world_object(generated, generated.inside_lobby_center + back_direction * 4.25, "InsideLobbyStash")
	var stash_front := -back_direction
	inside_stash.rotation.y = atan2(stash_front.x, stash_front.z)
	if inside_lobby_unlocked:
		generated.unlock_inside_lobby()
	var player_index := 0
	for peer_id in players:
		var player := get_node_or_null("Player_%d" % peer_id)
		if player:
			player.global_position = generated.get_spawn_position(player_index)
			player.rotation.y = generated.get_spawn_facing_yaw()
			player.velocity = Vector3.ZERO
		player_index += 1
	_set_local_controls(true)

@rpc("authority", "call_local", "reliable")
func _unlock_inside_lobby() -> void:
	inside_lobby_unlocked = true
	var generated := get_node_or_null("ProceduralDungeon")
	if generated and generated.has_method("unlock_inside_lobby"):
		generated.unlock_inside_lobby()

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
			if equipped_items_by_peer.has(existing_id):
				_sync_equipped_item.rpc_id(peer_id, existing_id, equipped_items_by_peer[existing_id])
	if in_dungeon:
		_enter_dungeon.rpc_id(peer_id, dungeon_seed, inside_lobby_unlocked)

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
	if equipped_items_by_peer.has(peer_id):
		player.apply_equipped_items(equipped_items_by_peer[peer_id])
	if peer_id == multiplayer.get_unique_id():
		_initialize_local_items(character)
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
	equipped_items_by_peer.erase(peer_id)
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
	_return_held_item()
	_close_all_stashes()
	menu.visible = false
	pause_menu.visible = false
	death_menu.visible = false
	pause_open = false
	inventory_window.visible = false
	character_window.visible = false
	if stash_window:
		stash_window.visible = false
	interface.visible = true
	if not in_dungeon:
		_set_local_controls(true)

func _reset_lobby_world() -> void:
	in_dungeon = false
	dungeon_seed = 0
	inside_lobby_unlocked = false
	var generated := get_node_or_null("ProceduralDungeon")
	if generated:
		generated.queue_free()
	var lobby := get_node_or_null("Dungeon")
	if lobby:
		lobby.visible = true
		lobby.process_mode = Node.PROCESS_MODE_INHERIT
	if dungeon_entrance_sign:
		dungeon_entrance_sign.visible = true
		dungeon_entrance_sign.process_mode = Node.PROCESS_MODE_INHERIT
	if lobby_stash_object:
		lobby_stash_object.visible = true
		lobby_stash_object.process_mode = Node.PROCESS_MODE_INHERIT
	var target_positions := {
		"TrainingDummy": Vector3(0, 0.05, 3),
		"TrainingEnemy2": Vector3(2, 0.05, 4.2),
		"TrainingAlly": Vector3(-2, 0.05, 4.2)
	}
	for target_name in target_positions:
		var target := get_node_or_null(target_name)
		if target:
			target.position = target_positions[target_name]
			target.process_mode = Node.PROCESS_MODE_INHERIT
	for dummy in get_tree().get_nodes_in_group("lobby_enemy_dummies"):
		dummy.visible = true
		dummy.process_mode = Node.PROCESS_MODE_INHERIT

func _on_connection_failed() -> void:
	status_label.text = "Could not connect to the host."
	multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	_return_held_item()
	_close_all_stashes()
	status_label.text = "The host closed the game."
	menu.visible = true
	interface.visible = false
	pause_menu.visible = false
	death_menu.visible = false
	pause_open = false
	inventory_window.visible = false
	character_window.visible = false
	if stash_window:
		stash_window.visible = false
	players.clear()
	player_names.clear()
	equipped_items_by_peer.clear()
	_reset_local_items()
	_reset_lobby_world()
	for child in get_children():
		if child.name.begins_with("Player_"):
			child.queue_free()

func _reset_local_items() -> void:
	_clear_held_item()
	local_items_initialized = false
	for slot_key in local_equipment:
		local_equipment[slot_key] = {}
	local_inventory.clear()
	local_inventory.resize(60)
	stash_initialized = false
	stash_items.clear()
	stash_items.resize(81)
	if not stash_slots.is_empty():
		_refresh_stash_ui()
	_refresh_inventory_ui()
