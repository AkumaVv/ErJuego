extends CharacterBody3D

const CHARACTER_BASE := "res://addons/kaykit_character_pack_adventures/Characters/gltf/"
const CHARACTER_FILES := ["Knight.glb", "Rogue_Hooded.glb", "Mage.glb", "Barbarian.glb"]
const CHARACTER_SCALES := [0.949, 1.04, 0.78, 0.975]
# Knight, Rogue, Mage and Barbarian. Each capsule follows its model instead
# of using one oversized collision volume for all four classes.
const CHARACTER_HITBOX_RADII := [0.507, 0.416, 0.442, 0.546]
# All four imported characters are normalized to roughly 2.34 m by their
# individual visual scales. Their collision tops now match those measurements.
const CHARACTER_HITBOX_HEIGHTS := [2.341, 2.341, 2.342, 2.338]
const WEAPON_BASE := "res://addons/kaykit_character_pack_adventures/Assets/gltf/"
const MAGIC_LIGHTNING_SHADER := preload("res://shaders/magic_lightning.gdshader")
const ACCESSORY_MESHES := ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield", "1H_Sword", "2H_Sword", "Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable", "Spellbook", "Spellbook_open", "1H_Wand", "2H_Staff", "1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "2H_Axe", "Mug"]
const CLASS_ACCESSORIES := [[], ["1H_Crossbow"], [], []]
const CHAIN_JUMP_DELAY := 0.09

@export var move_speed := 5.5
@export var sprint_speed := 9.0
@export var acceleration := 32.0
@export var deceleration := 55.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.0022
@export var max_health := 100

@onready var head: Node3D = $Head
@onready var health_bar: ProgressBar = get_node_or_null("../Interface/HealthBar")
@onready var health_value: Label = get_node_or_null("../Interface/HealthBar/Value")
@onready var secondary_cooldown_bar: TextureProgressBar = get_node_or_null("../Interface/SecondaryCooldown")
@onready var secondary_cooldown_value: Label = get_node_or_null("../Interface/SecondaryCooldown/Value")
@onready var secondary_cooldown_name: Label = get_node_or_null("../Interface/SecondaryCooldown/Name")
@onready var sword: Node3D = $Head/Camera3D/Sword
@onready var offhand: Node3D = $Head/Camera3D/Offhand
@onready var attack_ray: RayCast3D = $Head/Camera3D/AttackRay
@onready var first_person_camera: Camera3D = $Head/Camera3D
@onready var third_person_camera: Camera3D = $Head/ThirdPersonArm/ThirdPersonCamera

var health := max_health
var attack_in_progress := false
var sword_rest_position := Vector3.ZERO
var sword_rest_rotation := Vector3.ZERO
var offhand_rest_position := Vector3.ZERO
var offhand_rest_rotation := Vector3.ZERO
var network_ready := false
var remote_position := Vector3.ZERO
var remote_body_rotation := 0.0
var remote_head_rotation := 0.0
var remote_move_speed := 0.0
var remote_velocity := Vector3.ZERO
var character_model: Node3D
var character_animation: AnimationPlayer
var current_character_animation := ""
var third_person_enabled := false
var character_class := 0
var blocking := false
var barbarian_left_next := true
var right_hand_marker: BoneAttachment3D
var controls_enabled := true
var secondary_cooldown_duration := 0.0
var secondary_cooldown_ends_at := 0.0
var strength := 5
var dexterity := 5
var intelligence := 5
var dead := false
var equipped_weapon: Dictionary = {}
var weapon_damage_min := 0
var weapon_damage_max := 0
var equipped_weapon_variant := 0
var equipped_items: Dictionary = {}
var equipment_visual_nodes: Array[Node] = []
var first_person_weapon_nodes: Array[Node3D] = []
var third_person_weapon_nodes: Array[Node3D] = []
var first_person_wand_variants: Dictionary = {}
var third_person_wand_variants: Dictionary = {}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_health_ui()
	_setup_secondary_cooldown_ui()
	sword_rest_position = sword.position
	sword_rest_rotation = sword.rotation_degrees
	offhand_rest_position = offhand.position
	offhand_rest_rotation = offhand.rotation_degrees

func configure_network_player(peer_id: int, character_index: int, _character_color: Color, display_name: String) -> void:
	set_multiplayer_authority(peer_id)
	add_to_group("chain_allies")
	network_ready = true
	remote_position = global_position
	var local_player := is_multiplayer_authority()
	$Head/Camera3D.current = local_player
	$Head/ThirdPersonArm/ThirdPersonCamera.current = false
	$Head/Camera3D/Sword.visible = local_player
	$Head/Camera3D/Offhand.visible = local_player
	$BodyVisual.visible = not local_player
	$BodyVisual/Name.text = display_name
	character_class = character_index
	_configure_character_hitbox(character_index)
	_setup_base_stats(character_index)
	_load_character_model(character_index)
	_setup_third_person_weapons(character_index)
	if local_player:
		_setup_first_person_weapons(character_index)
		_set_camera_mode(false)
		_update_health_ui()
		_update_secondary_cooldown_ui()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_weapon_visuals()

func apply_equipped_weapon(item: Dictionary) -> void:
	equipped_weapon = item.duplicate(true)
	weapon_damage_min = int(item.get("physical_min", 0))
	weapon_damage_max = int(item.get("physical_max", 0))
	equipped_weapon_variant = clampi(int(item.get("model_variant", 0)), 0, 3)
	_update_weapon_visuals()

func apply_equipped_items(loadout: Dictionary) -> void:
	equipped_items = loadout.duplicate(true)
	apply_equipped_weapon(equipped_items.get("main_hand", {}))
	_rebuild_equipment_visuals()

func _rebuild_equipment_visuals() -> void:
	for visual_node in equipment_visual_nodes:
		if is_instance_valid(visual_node):
			visual_node.queue_free()
	equipment_visual_nodes.clear()
	# Equipment still affects the loadout and statistics, but only the equipped
	# weapon is represented on the first- and third-person character models.

func _add_equipped_visual(skeleton: Skeleton3D, slot_key: String, bone_candidates: Array[String]) -> void:
	var item = equipped_items.get(slot_key, {})
	if not item is Dictionary or item.is_empty():
		return
	var bone_name := ""
	for candidate in bone_candidates:
		if skeleton.find_bone(candidate) >= 0:
			bone_name = candidate
			break
	if bone_name.is_empty():
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "GeneratedEquipment_%s" % slot_key
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	equipment_visual_nodes.append(attachment)
	_create_equipment_model(attachment, str(item.get("type", "")), clampi(int(item.get("model_variant", 0)), 0, 3))

func _equipment_material(item_type: String, variant: int) -> Material:
	var defensive := item_type in ["helmet", "body_armour", "gloves", "boots", "belt"]
	if defensive and variant == 3:
		var shader := Shader.new()
		shader.code = "shader_type spatial; render_mode specular_schlick_ggx; void fragment(){ float stripe=fract(UV.x*3.0); vec3 red=vec3(0.78,0.08,0.11); vec3 green=vec3(0.06,0.52,0.20); vec3 blue=vec3(0.05,0.28,0.72); ALBEDO=stripe<0.333?red:(stripe<0.666?green:blue); METALLIC=0.28; ROUGHNESS=0.48; }"
		var striped := ShaderMaterial.new()
		striped.shader = shader
		return striped
	var magical_colors := [Color("#aeb6c2"), Color("#cc3945"), Color("#e5b92f"), Color("#3987db")]
	var defensive_colors := [Color("#c73b43"), Color("#3e9a59"), Color("#397fd0"), Color("#397fd0")]
	var material := StandardMaterial3D.new()
	material.albedo_color = defensive_colors[variant] if defensive else magical_colors[variant]
	material.metallic = 0.15 + variant * 0.12
	material.roughness = 0.48
	return material

func _equipment_mesh(parent: Node3D, mesh: PrimitiveMesh, position_: Vector3, scale_: Vector3, material: Material, rotation_ := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position_
	node.scale = scale_
	node.rotation_degrees = rotation_
	node.material_override = material
	parent.add_child(node)
	return node

func _create_equipment_model(parent: Node3D, item_type: String, variant: int) -> void:
	var material := _equipment_material(item_type, variant)
	if item_type == "helmet":
		var helm := CylinderMesh.new()
		helm.top_radius = 0.30 - variant * 0.015
		helm.bottom_radius = 0.34
		helm.height = 0.34 + variant * 0.025
		_equipment_mesh(parent, helm, Vector3(0, 0.13, 0), Vector3.ONE, material)
		if variant >= 1:
			var crest := BoxMesh.new()
			crest.size = Vector3(0.08 + variant * 0.025, 0.30, 0.42)
			_equipment_mesh(parent, crest, Vector3(0, 0.39, 0), Vector3.ONE, material)
	elif item_type == "body_armour":
		var chest := BoxMesh.new()
		chest.size = Vector3(0.68 + variant * 0.035, 0.62, 0.34 + variant * 0.025)
		_equipment_mesh(parent, chest, Vector3(0, -0.18, 0), Vector3.ONE, material)
		if variant >= 1:
			var shoulder := SphereMesh.new()
			for side in [-1.0, 1.0]:
				_equipment_mesh(parent, shoulder, Vector3(0.40 * side, 0.02, 0), Vector3(0.24, 0.16 + variant * 0.03, 0.22), material)
	elif item_type == "gloves":
		var glove := BoxMesh.new()
		glove.size = Vector3(0.24, 0.28 + variant * 0.025, 0.22)
		_equipment_mesh(parent, glove, Vector3.ZERO, Vector3.ONE, material, Vector3(0, variant * 12.0, 0))
	elif item_type == "boots":
		var boot := BoxMesh.new()
		boot.size = Vector3(0.26 + variant * 0.015, 0.31, 0.42 + variant * 0.025)
		_equipment_mesh(parent, boot, Vector3(0, -0.07, -0.08), Vector3.ONE, material)
		if variant >= 1:
			var cuff := CylinderMesh.new()
			cuff.top_radius = 0.17
			cuff.bottom_radius = 0.15
			cuff.height = 0.13
			_equipment_mesh(parent, cuff, Vector3(0, 0.12, 0), Vector3(1.0, 1.0, 0.82), material)
	elif item_type == "ring":
		var ring := TorusMesh.new()
		ring.inner_radius = 0.065
		ring.outer_radius = 0.095 + variant * 0.008
		_equipment_mesh(parent, ring, Vector3(0, -0.02, 0), Vector3.ONE, material, Vector3(90, 0, 0))
	elif item_type == "amulet":
		var necklace := TorusMesh.new()
		necklace.inner_radius = 0.18
		necklace.outer_radius = 0.205
		_equipment_mesh(parent, necklace, Vector3(0, -0.12, -0.20), Vector3(1.0, 1.15, 1.0), material, Vector3(90, 0, 0))
		var gem := SphereMesh.new()
		_equipment_mesh(parent, gem, Vector3(0, -0.38, -0.23), Vector3(0.10 + variant * 0.015, 0.14, 0.06), material)
	elif item_type == "belt":
		var belt := CylinderMesh.new()
		belt.top_radius = 0.39
		belt.bottom_radius = 0.39
		belt.height = 0.10 + variant * 0.018
		_equipment_mesh(parent, belt, Vector3(0, -0.36, 0), Vector3(1.0, 1.0, 0.72), material)

func _has_equipped_weapon() -> bool:
	return not equipped_weapon.is_empty() and weapon_damage_max > 0

func _roll_weapon_damage() -> int:
	if not _has_equipped_weapon():
		return 0
	return randi_range(weapon_damage_min, weapon_damage_max)

func _roll_secondary_weapon_damage() -> int:
	return ceili(float(_roll_weapon_damage()) * 1.20)

func _update_weapon_visuals() -> void:
	var active := _has_equipped_weapon()
	for weapon_node in first_person_weapon_nodes:
		if is_instance_valid(weapon_node):
			weapon_node.visible = active
	for weapon_node in third_person_weapon_nodes:
		if is_instance_valid(weapon_node):
			weapon_node.visible = active
	for variant in first_person_wand_variants:
		var fp_wand := first_person_wand_variants[variant] as Node3D
		fp_wand.visible = active and int(variant) == equipped_weapon_variant
	for variant in third_person_wand_variants:
		var tp_wand := third_person_wand_variants[variant] as Node3D
		tp_wand.visible = active and int(variant) == equipped_weapon_variant
	if is_multiplayer_authority():
		sword.visible = active and not third_person_enabled
		offhand.visible = active and not third_person_enabled and character_class in [0, 3]
	if character_model:
		_set_character_mesh_view(third_person_enabled)

func _configure_character_hitbox(class_index: int) -> void:
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not collision:
		return
	var safe_index := clampi(class_index, 0, CHARACTER_HITBOX_RADII.size() - 1)
	var capsule := CapsuleShape3D.new()
	capsule.radius = CHARACTER_HITBOX_RADII[safe_index]
	capsule.height = CHARACTER_HITBOX_HEIGHTS[safe_index]
	collision.shape = capsule
	# Keep the capsule bottom at the same Y as the model's feet (-0.90), even
	# though its centre rises when the complete character becomes 30% taller.
	collision.position.y = capsule.height * 0.5 - 0.90

func _setup_base_stats(class_index: int) -> void:
	strength = 5
	dexterity = 5
	intelligence = 5
	match class_index:
		0, 3:
			strength = 10
		1:
			dexterity = 10
		2:
			intelligence = 10

func receive_damage(amount: int, damage_type := "physical") -> void:
	if amount <= 0 or health <= 0 or dead:
		return
	var final_damage := amount
	if character_class == 0 and blocking:
		var received_ratio := 0.30 if damage_type == "magic" else 0.25
		final_damage = maxi(1, ceili(float(amount) * received_ratio))
	health = maxi(0, health - final_damage)
	_update_health_ui()
	_spawn_floating_number(final_damage, false)
	if health <= 0:
		_die()

func _die() -> void:
	if dead:
		return
	dead = true
	blocking = false
	attack_in_progress = false
	controls_enabled = false
	velocity = Vector3.ZERO
	_play_character_animation("Death_A")
	if is_multiplayer_authority():
		var game := get_parent()
		if game and game.has_method("handle_player_death"):
			game.handle_player_death(get_multiplayer_authority())

func revive_full() -> void:
	dead = false
	health = max_health
	blocking = false
	attack_in_progress = false
	velocity = Vector3.ZERO
	controls_enabled = true
	_update_health_ui()
	_play_character_animation("Idle")

@rpc("any_peer", "call_local", "reliable")
func receive_server_damage(amount: int, damage_type := "physical") -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	receive_damage(amount, damage_type)

@rpc("any_peer", "call_local", "reliable")
func receive_network_healing(amount: int) -> void:
	restore_health(amount)

func is_chain_ally() -> bool:
	return true

func receive_chain_healing(amount: int) -> void:
	var authority_id := get_multiplayer_authority()
	if authority_id == multiplayer.get_unique_id() or not multiplayer.has_multiplayer_peer():
		restore_health(amount)
	else:
		receive_network_healing.rpc_id(authority_id, amount)

func restore_health(amount: int) -> void:
	if amount <= 0 or health <= 0:
		return
	var restored := mini(amount, max_health - health)
	if restored <= 0:
		return
	health += restored
	_update_health_ui()
	_spawn_floating_number(restored, true)

func _spawn_floating_number(amount: int, healing: bool) -> void:
	var label := Label3D.new()
	label.text = ("+" if healing else "-") + str(amount)
	label.modulate = Color(0.2, 1.0, 0.3) if healing else Color(1.0, 0.12, 0.10)
	label.font_size = 42
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	get_parent().add_child(label)
	label.global_position = global_position + Vector3(0.0, 2.25, 0.0)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(0.0, 0.85, 0.0), 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9)
	tween.chain().tween_callback(label.queue_free)

func _update_health_ui() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health
	if health_value:
		health_value.text = "%d/%d" % [health, max_health]
	if is_multiplayer_authority():
		var game := get_parent()
		if game and game.has_method("refresh_character_panel"):
			game.refresh_character_panel()

func _setup_secondary_cooldown_ui() -> void:
	if not secondary_cooldown_bar:
		return
	var under_image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var progress_image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	under_image.fill(Color.TRANSPARENT)
	progress_image.fill(Color.TRANSPARENT)
	for y in range(96):
		for x in range(96):
			var distance := Vector2(x - 47.5, y - 47.5).length()
			if distance <= 45.0:
				under_image.set_pixel(x, y, Color(0.10, 0.018, 0.025, 0.94))
				progress_image.set_pixel(x, y, Color(0.78, 0.07, 0.10, 0.98))
	secondary_cooldown_bar.texture_under = ImageTexture.create_from_image(under_image)
	secondary_cooldown_bar.texture_progress = ImageTexture.create_from_image(progress_image)
	secondary_cooldown_bar.radial_initial_angle = 0.0
	secondary_cooldown_bar.radial_fill_degrees = 360.0
	secondary_cooldown_bar.radial_center_offset = Vector2.ZERO

func _process(_delta: float) -> void:
	if network_ready and is_multiplayer_authority():
		_update_secondary_cooldown_ui()

func _secondary_available(cooldown: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now < secondary_cooldown_ends_at:
		return false
	secondary_cooldown_duration = cooldown
	secondary_cooldown_ends_at = now + cooldown
	_update_secondary_cooldown_ui()
	return true

func _update_secondary_cooldown_ui() -> void:
	if not secondary_cooldown_bar:
		return
	var names := ["BLOCK", "DOUBLE BOLT", "CHAIN", "TRIPLE WHIRLWIND"]
	secondary_cooldown_name.text = names[character_class]
	if secondary_cooldown_duration <= 0.0:
		secondary_cooldown_bar.value = 100.0
		secondary_cooldown_value.text = "RMB"
		return
	var remaining := maxf(0.0, secondary_cooldown_ends_at - Time.get_ticks_msec() / 1000.0)
	secondary_cooldown_bar.value = 100.0 * (1.0 - remaining / secondary_cooldown_duration)
	secondary_cooldown_value.text = "RMB" if remaining <= 0.0 else "%.1f" % remaining

func _weapon_asset(file_name: String, parent: Node3D, position_ := Vector3.ZERO, rotation_ := Vector3.ZERO, scale_ := 1.0) -> Node3D:
	var packed := load(WEAPON_BASE + file_name) as PackedScene
	if not packed:
		push_error("Could not load weapon: " + file_name)
		return null
	var weapon := packed.instantiate() as Node3D
	weapon.position = position_
	weapon.rotation_degrees = rotation_
	weapon.scale = Vector3.ONE * scale_
	parent.add_child(weapon)
	return weapon

func _setup_first_person_weapons(class_index: int) -> void:
	first_person_weapon_nodes.clear()
	first_person_wand_variants.clear()
	for child in sword.get_children():
		child.visible = false
	sword.position = sword_rest_position
	sword.rotation_degrees = sword_rest_rotation
	offhand.position = offhand_rest_position
	offhand.rotation_degrees = offhand_rest_rotation
	match class_index:
		0:
			sword.position = Vector3(0.58, -0.74, -1.18)
			offhand.position = Vector3(-0.64, -0.60, -1.26)
			first_person_weapon_nodes.append(_weapon_asset("sword_1handed.gltf", sword, Vector3(0.0, 0.24, 0.0), Vector3.ZERO, 0.56))
			first_person_weapon_nodes.append(_weapon_asset("shield_badge.gltf", offhand, Vector3.ZERO, Vector3(0.0, 180.0, 0.0), 0.54))
		1:
			sword.position = Vector3(0.08, -0.76, -1.22)
			sword.rotation_degrees = Vector3(0.0, 180.0, 0.0)
			first_person_weapon_nodes.append(_weapon_asset("crossbow_1handed.gltf", sword, Vector3.ZERO, Vector3.ZERO, 0.52))
		2:
			sword.position = Vector3(0.60, -0.76, -1.22)
			for variant in range(4):
				var wand := _create_wand_model(sword, variant, Vector3(0.0, 0.16, 0.0), 0.68)
				first_person_weapon_nodes.append(wand)
				first_person_wand_variants[variant] = wand
		3:
			sword.position = Vector3(0.66, -0.80, -1.28)
			offhand.position = Vector3(-0.66, -0.80, -1.28)
			first_person_weapon_nodes.append(_weapon_asset("sword_1handed.gltf", sword, Vector3(0.0, 0.22, 0.0), Vector3.ZERO, 0.52))
			first_person_weapon_nodes.append(_weapon_asset("sword_1handed.gltf", offhand, Vector3(0.0, 0.22, 0.0), Vector3.ZERO, 0.52))
	sword_rest_position = sword.position
	sword_rest_rotation = sword.rotation_degrees
	offhand_rest_position = offhand.position
	offhand_rest_rotation = offhand.rotation_degrees

func _setup_third_person_weapons(class_index: int) -> void:
	third_person_weapon_nodes.clear()
	third_person_wand_variants.clear()
	if not character_model:
		return
	var skeletons := character_model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	right_hand_marker = BoneAttachment3D.new()
	right_hand_marker.bone_name = "handslot.r"
	skeleton.add_child(right_hand_marker)
	match class_index:
		0:
			third_person_weapon_nodes.append(_attach_to_hand(skeleton, "handslot.r", "sword_1handed.gltf"))
			third_person_weapon_nodes.append(_attach_to_hand(skeleton, "handslot.l", "shield_badge.gltf", Vector3.ZERO, Vector3.ZERO, 0.92))
		1:
			# La ballesta 1H integrada ya tiene el ajuste correcto para esta mano.
			pass
		2:
			var attachment := BoneAttachment3D.new()
			attachment.bone_name = "handslot.r"
			skeleton.add_child(attachment)
			for variant in range(4):
				var wand := _create_wand_model(attachment, variant, Vector3.ZERO, 1.08)
				third_person_weapon_nodes.append(wand)
				third_person_wand_variants[variant] = wand
		3:
			third_person_weapon_nodes.append(_attach_to_hand(skeleton, "handslot.r", "sword_1handed.gltf"))
			third_person_weapon_nodes.append(_attach_to_hand(skeleton, "handslot.l", "sword_1handed.gltf"))

func _attach_to_hand(skeleton: Skeleton3D, bone_name: String, file_name: String, position_ := Vector3.ZERO, rotation_ := Vector3.ZERO, scale_ := 1.0) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	return _weapon_asset(file_name, attachment, position_, rotation_, scale_)

func _wand_material(color: Color, emission_color := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_energy_multiplier = emission_energy
	return material

func _wand_cylinder(parent: Node3D, position_: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.82
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = material
	piece.mesh = mesh
	piece.position = position_
	parent.add_child(piece)
	return piece

func _wand_gem(parent: Node3D, position_: Vector3, color: Color, scale_ := Vector3(0.17, 0.28, 0.17)) -> MeshInstance3D:
	var gem := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = _wand_material(color.darkened(0.18), color, 5.0)
	gem.mesh = mesh
	gem.position = position_
	gem.scale = scale_
	gem.rotation_degrees.y = 45.0
	parent.add_child(gem)
	return gem

func _create_wand_model(parent: Node3D, variant: int, position_: Vector3, scale_: float) -> Node3D:
	var root := Node3D.new()
	root.name = "WandVariant%d" % variant
	root.position = position_
	root.scale = Vector3.ONE * scale_
	parent.add_child(root)
	var wood_dark := _wand_material(Color("#4c2d1b"))
	var bronze := _wand_material(Color("#a66a2c"))
	var pale_wood := _wand_material(Color("#8d6337"))
	var bone := _wand_material(Color("#d7c79f"))
	var leather := _wand_material(Color("#3b211a"))
	var iron := _wand_material(Color("#272c32"))
	var silver := _wand_material(Color("#aeb8c0"))
	match variant:
		0:
			_wand_cylinder(root, Vector3(0, 0.64, 0), 0.075, 1.28, wood_dark)
			for y in [0.10, 0.92, 1.18]:
				_wand_cylinder(root, Vector3(0, y, 0), 0.095, 0.09, bronze)
			_wand_gem(root, Vector3(0, 1.43, 0), Color("#aeb6c2"), Vector3(0.19, 0.34, 0.19))
		1:
			_wand_cylinder(root, Vector3(0, 0.65, 0), 0.085, 1.30, pale_wood)
			_wand_cylinder(root, Vector3(0, 0.18, 0), 0.10, 0.25, leather)
			_wand_gem(root, Vector3(0, 1.39, 0), Color("#cc3945"), Vector3(0.18, 0.28, 0.18))
			var leaf_material := _wand_material(Color("#8e2631"))
			for side in [-1.0, 1.0]:
				var leaf := _wand_gem(root, Vector3(0.13 * side, 1.15, 0), Color("#cc3945"), Vector3(0.12, 0.22, 0.04))
				leaf.material_override = leaf_material
				leaf.rotation_degrees.z = 42.0 * side
		2:
			_wand_cylinder(root, Vector3(0, 0.64, 0), 0.085, 1.28, bone)
			for y in [0.20, 0.55, 0.92]:
				_wand_cylinder(root, Vector3(0, y, 0), 0.096, 0.10, leather)
			var skull := _wand_gem(root, Vector3(0, 1.27, 0), Color("#d7c79f"), Vector3(0.25, 0.24, 0.18))
			skull.material_override = bone
			_wand_gem(root, Vector3(0, 1.52, 0), Color("#e5b92f"), Vector3(0.17, 0.29, 0.17))
		3:
			_wand_cylinder(root, Vector3(0, 0.65, 0), 0.078, 1.30, iron)
			_wand_cylinder(root, Vector3(0, 0.19, 0), 0.098, 0.30, leather)
			for y in [0.36, 0.78, 1.12]:
				_wand_cylinder(root, Vector3(0, y, 0), 0.094, 0.08, silver)
			_wand_gem(root, Vector3(0, 1.45, 0), Color("#3987db"), Vector3(0.18, 0.32, 0.18))
	return root

func _load_character_model(character_index: int) -> void:
	character_index = clampi(character_index, 0, CHARACTER_FILES.size() - 1)
	var packed := load(CHARACTER_BASE + CHARACTER_FILES[character_index]) as PackedScene
	if not packed:
		push_error("Could not load character: " + CHARACTER_FILES[character_index])
		return
	character_model = packed.instantiate() as Node3D
	character_model.name = "AdventurerModel"
	# Los modelos tienen los pies en Y=0; el fondo del controlador está en Y=-0.9.
	character_model.position = Vector3(0.0, -0.90, 0.0)
	character_model.rotation_degrees.y = 180.0
	character_model.scale = Vector3.ONE * CHARACTER_SCALES[character_index]
	$BodyVisual.add_child(character_model)
	_hide_placeholder_body()
	_filter_character_accessories(character_index)
	var animation_players := character_model.find_children("*", "AnimationPlayer", true, false)
	if not animation_players.is_empty():
		character_animation = animation_players[0] as AnimationPlayer
		_play_character_animation("1H_Ranged_Aiming" if character_index == 1 else "Idle")

func _filter_character_accessories(class_index: int) -> void:
	var allowed: Array = CLASS_ACCESSORIES[class_index]
	for mesh_node in character_model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		var mesh_name := str(mesh_instance.name)
		if mesh_name in ACCESSORY_MESHES:
			if mesh_name in allowed:
				mesh_instance.visible = true
			else:
				# Las animaciones importadas pueden restaurar tanto la visibilidad
				# como la malla. Sacar el nodo del árbol evita definitivamente que
				# reaparezcan armas que la clase no utiliza.
				mesh_instance.get_parent().remove_child(mesh_instance)
				mesh_instance.queue_free()

func _hide_placeholder_body() -> void:
	for child in $BodyVisual.get_children():
		if child is MeshInstance3D:
			var placeholder := child as MeshInstance3D
			placeholder.visible = false
			placeholder.layers = 0

func _play_character_animation(animation_name: String, speed_scale := 1.0) -> void:
	if not character_animation:
		return
	character_animation.speed_scale = speed_scale
	if current_character_animation == animation_name:
		return
	if not character_animation.has_animation(animation_name):
		return
	current_character_animation = animation_name
	character_animation.play(animation_name, 0.16)

func _input(event: InputEvent) -> void:
	if not controls_enabled or not network_ready or not is_multiplayer_authority():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_set_camera_mode(true)
			return
		if event.keycode == KEY_F1:
			_set_camera_mode(false)
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	if event is InputEventMouseButton:
		if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.pressed and _inside_lobby_combat_locked():
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if character_class == 0:
				_set_blocking(event.pressed)
			elif event.pressed:
				match character_class:
					1:
						_rogue_double_piercing()
					2:
						_mage_chain()
					3:
						_whirlwind()

func _inside_lobby_combat_locked() -> bool:
	for safe_state in get_tree().get_nodes_in_group("dungeon_safe_state"):
		if safe_state.has_method("is_player_inside_lobby") and safe_state.is_player_inside_lobby(global_position):
			return true
	return false

func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		blocking = false

func _set_camera_mode(use_third_person: bool) -> void:
	third_person_enabled = use_third_person
	first_person_camera.current = not use_third_person
	third_person_camera.current = use_third_person
	# Los modelos de aventura no tienen brazos FPS separados: la cámara queda
	# dentro de mangas, casco y escudo. En F1 usamos las armas de cámara y en F3
	# el esqueleto completo; ambas animaciones conservan la misma duración.
	sword.visible = _has_equipped_weapon() and not use_third_person
	offhand.visible = _has_equipped_weapon() and not use_third_person and character_class in [0, 3]
	$BodyVisual.visible = true
	$BodyVisual/Name.visible = use_third_person
	first_person_camera.set_cull_mask_value(2, false)
	third_person_camera.set_cull_mask_value(2, true)
	_set_character_mesh_view(use_third_person)

func _set_character_mesh_view(full_body: bool) -> void:
	if not character_model:
		return
	character_model.position = Vector3(0.0, -0.90, 0.0)
	var allowed: Array = CLASS_ACCESSORIES[character_class]
	for mesh_node in character_model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		var mesh_name := str(mesh_instance.name)
		var accessory := mesh_name in ACCESSORY_MESHES
		var arm := mesh_name.ends_with("_ArmLeft") or mesh_name.ends_with("_ArmRight")
		var attached_weapon := _has_bone_attachment_parent(mesh_instance)
		var equipment_mesh := attached_weapon or (accessory and mesh_name in allowed)
		var show_mesh := (_has_equipped_weapon() if equipment_mesh else true) and (not accessory or mesh_name in allowed or attached_weapon)
		mesh_instance.visible = show_mesh
		# La capa 2 contiene exclusivamente el cuerpo del jugador local. La cámara
		# F1 no dibuja esa capa, evitando cualquier casco o manga dentro de ella.
		mesh_instance.layers = 2 if show_mesh else 0

func _has_bone_attachment_parent(node: Node) -> bool:
	var current := node.get_parent()
	while current and current != character_model:
		if current is BoneAttachment3D:
			return true
		current = current.get_parent()
	return false

func _attack() -> void:
	if attack_in_progress or blocking or not _has_equipped_weapon():
		return
	match character_class:
		0:
			_start_melee("1H_Melee_Attack_Stab", sword, sword_rest_position, sword_rest_rotation, Vector3(-28.0, -4.0, -24.0))
		1:
			_shoot_crossbow()
		2:
			_cast_magic_ray()
		3:
			_barbarian_slash()

func _start_melee(animation_name: String, pivot: Node3D, rest_position: Vector3, rest_rotation: Vector3, attack_rotation: Vector3) -> void:
	attack_in_progress = true
	_remote_character_action.rpc(animation_name, 0.32)
	_play_timed_character_animation(animation_name, 0.32)
	_play_attack_animation(pivot, rest_position, rest_rotation, attack_rotation, true)

func _play_attack_animation(pivot: Node3D, rest_position: Vector3, rest_rotation: Vector3, attack_rotation: Vector3, apply_hit: bool) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "rotation_degrees", attack_rotation, 0.12)
	tween.parallel().tween_property(pivot, "position", rest_position + Vector3(0.0, 0.03, -0.62), 0.12)
	if apply_hit:
		tween.tween_callback(_apply_sword_hit)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(pivot, "rotation_degrees", rest_rotation, 0.20)
	tween.parallel().tween_property(pivot, "position", rest_position, 0.20)
	tween.tween_callback(_finish_attack)

@rpc("authority", "call_remote", "unreliable")
func _remote_character_action(animation_name: String, duration: float) -> void:
	if not attack_in_progress:
		attack_in_progress = true
		_play_timed_character_animation(animation_name, duration)
		_finish_remote_action(duration)

func _play_timed_character_animation(animation_name: String, duration: float) -> void:
	if not character_animation or not character_animation.has_animation(animation_name):
		return
	var animation := character_animation.get_animation(animation_name)
	var playback_speed := animation.length / maxf(duration, 0.05)
	current_character_animation = ""
	_play_character_animation(animation_name, playback_speed)

func _finish_remote_action(duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	_finish_attack()

func _barbarian_slash() -> void:
	var use_left := barbarian_left_next
	barbarian_left_next = not barbarian_left_next
	var pivot := offhand if use_left else sword
	var rest_position := offhand_rest_position if use_left else sword_rest_position
	var rest_rotation := offhand_rest_rotation if use_left else sword_rest_rotation
	var attack_rotation := Vector3(-24.0, 8.0, 58.0) if use_left else Vector3(-24.0, -8.0, -58.0)
	_start_melee("Dualwield_Melee_Attack_Slice", pivot, rest_position, rest_rotation, attack_rotation)

func _set_blocking(active: bool) -> void:
	if blocking == active or attack_in_progress:
		return
	blocking = active
	_remote_block.rpc(active)
	current_character_animation = ""
	_play_character_animation("Blocking" if active else "Idle")
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var target_position := offhand_rest_position + Vector3(0.22, 0.28, -0.30) if active else offhand_rest_position
	var target_rotation := Vector3(-6.0, 18.0, -12.0) if active else offhand_rest_rotation
	tween.tween_property(offhand, "position", target_position, 0.14)
	tween.parallel().tween_property(offhand, "rotation_degrees", target_rotation, 0.14)

@rpc("authority", "call_remote", "reliable")
func _remote_block(active: bool) -> void:
	blocking = active
	current_character_animation = ""
	_play_character_animation("Blocking" if active else "Idle")

func _shoot_crossbow() -> void:
	if attack_in_progress:
		return
	attack_in_progress = true
	var origin := _weapon_muzzle_position()
	var shot := _ranged_query(22.0, origin)
	var end: Vector3 = shot.end
	_remote_ranged_effect.rpc(0, origin, end)
	_spawn_ranged_effect(0, origin, end)
	_remote_character_action.rpc("2H_Ranged_Shoot", 0.55)
	_play_timed_character_animation("2H_Ranged_Shoot", 0.55)
	_animate_ranged_weapon(Vector3(0.0, 0.03, 0.16), 0.55)
	_deliver_projectile_hit(shot.collider, origin.distance_to(end) / 18.0)
	_finish_local_action(0.55)

func _cast_magic_ray() -> void:
	if attack_in_progress:
		return
	attack_in_progress = true
	var origin := _weapon_muzzle_position()
	var shot := _ranged_query(18.0, origin)
	var end: Vector3 = shot.end
	_remote_ranged_effect.rpc(1, origin, end)
	_spawn_ranged_effect(1, origin, end)
	_remote_character_action.rpc("Spellcast_Shoot", 0.48)
	_play_timed_character_animation("Spellcast_Shoot", 0.48)
	_animate_ranged_weapon(Vector3(-0.08, 0.18, -0.28), 0.48)
	var target: Object = shot.collider
	if target and target.has_method("receive_hit"):
		target.receive_hit(_roll_weapon_damage())
	_finish_local_action(0.48)

func _rogue_double_piercing() -> void:
	if attack_in_progress or not _has_equipped_weapon() or not _secondary_available(2.0):
		return
	attack_in_progress = true
	_remote_character_action.rpc("1H_Ranged_Shoot", 0.62)
	_play_timed_character_animation("1H_Ranged_Shoot", 0.62)
	for shot_index in range(2):
		var origin := _weapon_muzzle_position()
		var piercing := _piercing_query(22.0, 2)
		var end: Vector3 = piercing.end
		_remote_ranged_effect.rpc(0, origin, end)
		_spawn_ranged_effect(0, origin, end)
		_animate_ranged_weapon(Vector3(0.0, 0.025, 0.13), 0.20)
		for target in piercing.targets:
			if is_instance_valid(target) and target.has_method("receive_hit"):
				target.receive_hit(_roll_secondary_weapon_damage())
		if shot_index == 0:
			await get_tree().create_timer(0.28).timeout
	await get_tree().create_timer(0.34).timeout
	_finish_attack()

func _piercing_query(max_range: float, max_targets: int) -> Dictionary:
	var direction := -first_person_camera.global_transform.basis.z.normalized()
	var ray_start := first_person_camera.global_position
	var ray_end := ray_start + direction * max_range
	var exclusions: Array[RID] = [get_rid()]
	var targets: Array[Object] = []
	var final_end := ray_end
	for step in range(12):
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.exclude = exclusions
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Object = result.collider
		var hit_position: Vector3 = result.position
		final_end = hit_position
		if collider is CollisionObject3D:
			exclusions.append((collider as CollisionObject3D).get_rid())
		if collider.has_method("is_chain_ally") and collider.is_chain_ally():
			ray_start = hit_position + direction * 0.06
			continue
		if collider.has_method("receive_hit"):
			targets.append(collider)
			if targets.size() >= max_targets:
				break
			ray_start = hit_position + direction * 0.06
			continue
		break
	return {"end": final_end, "targets": targets}

func _mage_chain() -> void:
	if attack_in_progress or not _has_equipped_weapon() or not _secondary_available(3.0):
		return
	attack_in_progress = true
	var origin := _weapon_muzzle_position()
	var shot := _ranged_query(18.0, origin)
	var end: Vector3 = shot.end
	_remote_ranged_effect.rpc(1, origin, end)
	_spawn_ranged_effect(1, origin, end)
	_remote_character_action.rpc("Spellcast_Shoot", 0.72)
	_play_timed_character_animation("Spellcast_Shoot", 0.72)
	_animate_ranged_weapon(Vector3(-0.08, 0.18, -0.28), 0.72)
	var primary: Object = shot.collider
	if primary and (primary.has_method("receive_hit") or primary.has_method("is_chain_ally")):
		_apply_chain_effect(primary)
		var primary_node := primary as Node3D
		var previous_point := _target_point(primary_node)
		var visited: Array[Node3D] = [primary_node]
		var chain_elapsed := 0.0
		for _jump in range(3):
			var chained := _find_next_chain_target(previous_point, visited)
			if not chained:
				break
			visited.append(chained)
			# Let each electrical arc be read as an individual jump instead of
			# creating every segment and applying every effect in the same frame.
			await get_tree().create_timer(CHAIN_JUMP_DELAY).timeout
			chain_elapsed += CHAIN_JUMP_DELAY
			if not is_instance_valid(chained):
				continue
			var chained_point := _target_point(chained)
			_remote_ranged_effect.rpc(1, previous_point, chained_point)
			_spawn_ranged_effect(1, previous_point, chained_point)
			_apply_chain_effect(chained)
			previous_point = chained_point
		await get_tree().create_timer(maxf(0.05, 0.72 - chain_elapsed)).timeout
	else:
		await get_tree().create_timer(0.72).timeout
	_finish_attack()

func _apply_chain_effect(target: Object) -> void:
	var damage := _roll_weapon_damage()
	if damage <= 0:
		return
	if target.has_method("is_chain_ally") and target.is_chain_ally():
		var healing := maxi(1, ceili(damage * 0.05))
		if target.has_method("receive_chain_healing"):
			target.receive_chain_healing(healing)
	elif target.has_method("receive_hit"):
		target.receive_hit(damage)

func _find_next_chain_target(origin_point: Vector3, visited: Array[Node3D]) -> Node3D:
	var closest: Node3D = null
	var closest_distance_squared := 4.0 * 4.0
	var possible_targets := get_tree().get_nodes_in_group("damageable") + get_tree().get_nodes_in_group("chain_allies")
	for node in possible_targets:
		if not node is Node3D:
			continue
		var candidate := node as Node3D
		if not is_instance_valid(candidate) or visited.has(candidate):
			continue
		var distance_squared := origin_point.distance_squared_to(_target_point(candidate))
		if distance_squared <= closest_distance_squared:
			closest = candidate
			closest_distance_squared = distance_squared
	return closest

func _target_point(target: Node3D) -> Vector3:
	return target.global_position + Vector3(0.0, 1.25, 0.0)

func _weapon_muzzle_position() -> Vector3:
	if third_person_enabled and right_hand_marker:
		return right_hand_marker.global_position
	return sword.global_position - first_person_camera.global_transform.basis.z * 0.48 + first_person_camera.global_transform.basis.y * 0.10

func _ranged_query(max_range: float, origin: Vector3) -> Dictionary:
	var aim_origin := first_person_camera.global_position
	var aim_end := aim_origin - first_person_camera.global_transform.basis.z * max_range
	var aim_query := PhysicsRayQueryParameters3D.create(aim_origin, aim_end)
	aim_query.exclude = [get_rid()]
	var aim_result := get_world_3d().direct_space_state.intersect_ray(aim_query)
	var intended_end: Vector3 = aim_result.get("position", aim_end)
	# The camera ray ends exactly on the target surface. A second ray from the
	# weapon to that same boundary point can stop a fraction before entering the
	# collider because of floating-point precision, returning no target even
	# though the crosshair is centred on it. Extend it slightly through the
	# surface; nearer walls and obstacles are still detected first.
	var muzzle_direction := (intended_end - origin).normalized()
	var projectile_query_end := intended_end + muzzle_direction * 0.75
	var query := PhysicsRayQueryParameters3D.create(origin, projectile_query_end)
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return {
		"origin": origin,
		"end": result.get("position", intended_end),
		"collider": result.get("collider", null)
	}

func _animate_ranged_weapon(offset: Vector3, duration: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sword, "position", sword_rest_position + offset, duration * 0.42)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sword, "position", sword_rest_position, duration * 0.58)

func _deliver_projectile_hit(target: Object, travel_time: float) -> void:
	await get_tree().create_timer(travel_time).timeout
	if is_instance_valid(target) and target.has_method("receive_hit"):
		target.receive_hit(_roll_weapon_damage())

func _finish_local_action(duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	_finish_attack()

@rpc("authority", "call_remote", "unreliable")
func _remote_ranged_effect(effect_type: int, origin: Vector3, end: Vector3) -> void:
	_spawn_ranged_effect(effect_type, origin, end)

func _spawn_ranged_effect(effect_type: int, origin: Vector3, end: Vector3) -> void:
	if effect_type == 0:
		var packed := load(WEAPON_BASE + "arrow.gltf") as PackedScene
		if not packed:
			return
		var projectile := packed.instantiate() as Node3D
		get_parent().add_child(projectile)
		projectile.global_position = origin
		projectile.scale = Vector3.ONE * 0.32
		projectile.look_at(end, Vector3.UP)
		projectile.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90.0))
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.58, 0.2)
		glow.light_energy = 2.0
		glow.omni_range = 2.2
		glow.shadow_enabled = false
		projectile.add_child(glow)
		var duration := origin.distance_to(end) / 18.0
		var tween := projectile.create_tween()
		tween.tween_property(projectile, "global_position", end, duration)
		tween.tween_callback(projectile.queue_free)
	else:
		var distance := origin.distance_to(end)
		if distance <= 0.01:
			return
		var beam_root := Node3D.new()
		get_parent().add_child(beam_root)
		beam_root.global_position = (origin + end) * 0.5
		beam_root.quaternion = Quaternion(Vector3.UP, (end - origin).normalized())
		_add_lightning_layer(beam_root, distance, 0.055, Color(0.82, 0.96, 1.0), 14.0, 0.98, 0.045)
		_add_lightning_layer(beam_root, distance, 0.15, Color(0.12, 0.48, 1.0), 6.0, 0.34, 0.13)
		var flash := OmniLight3D.new()
		flash.light_color = Color(0.30, 0.66, 1.0)
		flash.light_energy = 3.2
		flash.omni_range = minf(6.0, maxf(2.4, distance * 0.45))
		flash.shadow_enabled = false
		beam_root.add_child(flash)
		var tween := beam_root.create_tween()
		tween.tween_interval(0.25)
		tween.tween_property(flash, "light_energy", 0.0, 0.16)
		tween.parallel().tween_property(beam_root, "scale", Vector3(0.08, 1.0, 0.08), 0.16)
		tween.tween_callback(beam_root.queue_free)
		_spawn_magic_particles(end)

func _add_lightning_layer(parent: Node3D, length: float, radius: float, color: Color, emission: float, opacity: float, jitter: float) -> void:
	var beam := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 32
	var material := ShaderMaterial.new()
	material.shader = MAGIC_LIGHTNING_SHADER
	material.set_shader_parameter("bolt_color", color)
	material.set_shader_parameter("emission_strength", emission)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("jitter_amount", jitter)
	material.set_shader_parameter("animation_speed", 30.0)
	material.set_shader_parameter("bolt_segments", 20.0)
	mesh.material = material
	beam.mesh = mesh
	parent.add_child(beam)

func _spawn_magic_particles(position_: Vector3) -> void:
	for index in range(10):
		var particle := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.055
		mesh.height = 0.11
		mesh.radial_segments = 6
		mesh.rings = 3
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.3, 0.72, 1.0, 1.0)
		material.emission_enabled = true
		material.emission = Color(0.15, 0.55, 1.0)
		material.emission_energy_multiplier = 6.0
		mesh.material = material
		particle.mesh = mesh
		get_parent().add_child(particle)
		particle.global_position = position_
		var offset := Vector3(randf_range(-0.65, 0.65), randf_range(-0.35, 0.8), randf_range(-0.65, 0.65))
		var tween := particle.create_tween().set_parallel(true)
		tween.tween_property(particle, "global_position", position_ + offset, 0.55 + index * 0.018)
		tween.tween_property(particle, "scale", Vector3.ZERO, 0.55 + index * 0.018)
		tween.chain().tween_callback(particle.queue_free)

func _whirlwind() -> void:
	if attack_in_progress or blocking or not _has_equipped_weapon() or not _secondary_available(4.0):
		return
	attack_in_progress = true
	_remote_character_action.rpc("2H_Melee_Attack_Spinning", 0.78)
	_play_timed_character_animation("2H_Melee_Attack_Spinning", 0.78)
	_run_barbarian_pulses()
	var tween := create_tween().set_trans(Tween.TRANS_LINEAR)
	# Dos medias vueltas consecutivas: las armas no regresan hacia atrás a mitad
	# del ataque, sino que completan el mismo giro continuo de 360° que el cuerpo.
	tween.tween_property(sword, "rotation_degrees", sword_rest_rotation + Vector3(0.0, 0.0, -180.0), 0.39)
	tween.parallel().tween_property(offhand, "rotation_degrees", offhand_rest_rotation + Vector3(0.0, 0.0, 180.0), 0.39)
	tween.parallel().tween_property(sword, "position", offhand_rest_position + Vector3(0.10, 0.10, -0.08), 0.39)
	tween.parallel().tween_property(offhand, "position", sword_rest_position + Vector3(-0.10, 0.10, -0.08), 0.39)
	tween.tween_property(sword, "rotation_degrees", sword_rest_rotation + Vector3(0.0, 0.0, -360.0), 0.39)
	tween.parallel().tween_property(offhand, "rotation_degrees", offhand_rest_rotation + Vector3(0.0, 0.0, 360.0), 0.39)
	tween.parallel().tween_property(sword, "position", sword_rest_position, 0.39)
	tween.parallel().tween_property(offhand, "position", offhand_rest_position, 0.39)
	tween.tween_callback(_reset_whirlwind_weapons)
	tween.tween_callback(_finish_attack)

func _reset_whirlwind_weapons() -> void:
	sword.rotation_degrees = sword_rest_rotation
	offhand.rotation_degrees = offhand_rest_rotation
	sword.position = sword_rest_position
	offhand.position = offhand_rest_position

func _apply_whirlwind_hit() -> void:
	for target in get_tree().get_nodes_in_group("damageable"):
		if target is Node3D and global_position.distance_to((target as Node3D).global_position) <= 4.0:
			if target.has_method("receive_hit"):
				target.receive_hit(_roll_secondary_weapon_damage())
			if target.has_method("receive_knockback"):
				target.receive_knockback(global_position, 0.32)

func _run_barbarian_pulses() -> void:
	for pulse in range(3):
		await get_tree().create_timer(0.13 if pulse == 0 else 0.26).timeout
		_apply_whirlwind_hit()

func _apply_sword_hit() -> void:
	attack_ray.force_raycast_update()
	if not attack_ray.is_colliding():
		return
	var target := attack_ray.get_collider()
	if target and target.has_method("receive_hit"):
		target.receive_hit(_roll_weapon_damage())

func _finish_attack() -> void:
	attack_in_progress = false
	current_character_animation = ""
	_play_character_animation("Idle")

func _physics_process(delta: float) -> void:
	if not network_ready:
		return
	if not is_multiplayer_authority():
		global_position = global_position.lerp(remote_position, minf(1.0, delta * 14.0))
		rotation.y = lerp_angle(rotation.y, remote_body_rotation, minf(1.0, delta * 14.0))
		head.rotation.x = lerp_angle(head.rotation.x, remote_head_rotation, minf(1.0, delta * 14.0))
		if not attack_in_progress and not blocking:
			_update_movement_animation(remote_move_speed)
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if controls_enabled else Vector2.ZERO
	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var is_sprinting := Input.is_key_pressed(KEY_SHIFT) and not direction.is_zero_approx()
	var current_speed := sprint_speed if is_sprinting else move_speed
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if direction.is_zero_approx():
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, deceleration * delta)
	else:
		var next_speed := move_toward(horizontal_velocity.length(), current_speed, acceleration * delta)
		horizontal_velocity = direction * next_speed
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()
	var movement_speed := Vector2(velocity.x, velocity.z).length()
	var animation_motion := -movement_speed if input_vector.y > 0.15 else movement_speed
	if not attack_in_progress and not blocking:
		_update_movement_animation(animation_motion)
	_sync_state.rpc(global_position, rotation.y, head.rotation.x, animation_motion, Vector3(velocity.x, 0.0, velocity.z))

func get_projectile_prediction_velocity() -> Vector3:
	if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		return Vector3(velocity.x, 0.0, velocity.z)
	return remote_velocity

func _update_movement_animation(movement_speed: float) -> void:
	var absolute_speed := absf(movement_speed)
	if absolute_speed < 0.12:
		_play_character_animation("1H_Ranged_Aiming" if character_class == 1 else "Idle", 1.0)
	elif movement_speed < 0.0:
		_play_character_animation("Walking_Backwards", clampf(absolute_speed / move_speed * 1.25, 0.8, 1.4))
	elif absolute_speed > move_speed + 0.7:
		_play_character_animation("Running_A", clampf(absolute_speed / sprint_speed * 1.35, 0.9, 1.5))
	else:
		_play_character_animation("Walking_A", clampf(absolute_speed / move_speed * 1.25, 0.8, 1.4))

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_state(position_: Vector3, body_rotation: float, head_rotation: float, movement_speed: float, movement_velocity: Vector3) -> void:
	remote_position = position_
	remote_body_rotation = body_rotation
	remote_head_rotation = head_rotation
	remote_move_speed = movement_speed
	remote_velocity = movement_velocity
