extends CharacterBody3D

const CHARACTER_BASE := "res://addons/kaykit_character_pack_adventures/Characters/gltf/"
const CHARACTER_FILES := ["Knight.glb", "Rogue_Hooded.glb", "Mage.glb", "Barbarian.glb"]
const CHARACTER_SCALES := [0.73, 0.80, 0.60, 0.75]
const WEAPON_BASE := "res://addons/kaykit_character_pack_adventures/Assets/gltf/"

@export var move_speed := 5.5
@export var sprint_speed := 9.0
@export var acceleration := 32.0
@export var deceleration := 55.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.0022
@export var max_stamina := 100.0
@export var stamina_drain_per_second := 28.0
@export var stamina_regen_per_second := 20.0

@onready var head: Node3D = $Head
@onready var stamina_bar: ProgressBar = get_node_or_null("../Interface/StaminaBar")
@onready var sword: Node3D = $Head/Camera3D/Sword
@onready var offhand: Node3D = $Head/Camera3D/Offhand
@onready var attack_ray: RayCast3D = $Head/Camera3D/AttackRay
@onready var first_person_camera: Camera3D = $Head/Camera3D
@onready var third_person_camera: Camera3D = $Head/ThirdPersonArm/ThirdPersonCamera

var stamina := max_stamina
var attack_in_progress := false
var sword_rest_position := Vector3.ZERO
var sword_rest_rotation := Vector3.ZERO
var offhand_rest_position := Vector3.ZERO
var offhand_rest_rotation := Vector3.ZERO
var network_ready := false
var remote_position := Vector3.ZERO
var remote_body_rotation := 0.0
var remote_head_rotation := 0.0
var character_model: Node3D
var character_animation: AnimationPlayer
var current_character_animation := ""
var third_person_enabled := false
var character_class := 0
var blocking := false
var barbarian_left_next := true

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = stamina
	sword_rest_position = sword.position
	sword_rest_rotation = sword.rotation_degrees
	offhand_rest_position = offhand.position
	offhand_rest_rotation = offhand.rotation_degrees

func configure_network_player(peer_id: int, character_index: int, _character_color: Color, display_name: String) -> void:
	set_multiplayer_authority(peer_id)
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
	_load_character_model(character_index)
	_setup_third_person_weapons(character_index)
	if local_player:
		_setup_first_person_weapons(character_index)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _weapon_asset(file_name: String, parent: Node3D, position_ := Vector3.ZERO, rotation_ := Vector3.ZERO, scale_ := 1.0) -> Node3D:
	var packed := load(WEAPON_BASE + file_name) as PackedScene
	if not packed:
		push_error("No se pudo cargar el arma: " + file_name)
		return null
	var weapon := packed.instantiate() as Node3D
	weapon.position = position_
	weapon.rotation_degrees = rotation_
	weapon.scale = Vector3.ONE * scale_
	parent.add_child(weapon)
	return weapon

func _setup_first_person_weapons(class_index: int) -> void:
	for child in sword.get_children():
		child.visible = false
	sword.position = sword_rest_position
	sword.rotation_degrees = sword_rest_rotation
	offhand.position = offhand_rest_position
	offhand.rotation_degrees = offhand_rest_rotation
	match class_index:
		0:
			_weapon_asset("sword_1handed.gltf", sword, Vector3(0.0, 0.28, 0.0), Vector3.ZERO, 0.72)
			_weapon_asset("shield_badge.gltf", offhand, Vector3.ZERO, Vector3(0.0, 180.0, 0.0), 0.72)
		1:
			sword.position = Vector3(0.0, -0.34, -0.92)
			sword.rotation_degrees = Vector3(0.0, 180.0, 0.0)
			_weapon_asset("crossbow_2handed.gltf", sword, Vector3.ZERO, Vector3.ZERO, 0.62)
		2:
			_weapon_asset("wand.gltf", sword, Vector3(0.0, 0.2, 0.0), Vector3.ZERO, 0.9)
		3:
			_weapon_asset("sword_1handed.gltf", sword, Vector3(0.0, 0.28, 0.0), Vector3.ZERO, 0.7)
			_weapon_asset("sword_1handed.gltf", offhand, Vector3(0.0, 0.28, 0.0), Vector3.ZERO, 0.7)

func _setup_third_person_weapons(class_index: int) -> void:
	if not character_model:
		return
	var skeletons := character_model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	match class_index:
		0:
			_attach_to_hand(skeleton, "handslot.r", "sword_1handed.gltf")
			_attach_to_hand(skeleton, "handslot.l", "shield_badge.gltf")
		1:
			_attach_to_hand(skeleton, "handslot.r", "crossbow_2handed.gltf")
		2:
			_attach_to_hand(skeleton, "handslot.r", "wand.gltf")
		3:
			_attach_to_hand(skeleton, "handslot.r", "sword_1handed.gltf")
			_attach_to_hand(skeleton, "handslot.l", "sword_1handed.gltf")

func _attach_to_hand(skeleton: Skeleton3D, bone_name: String, file_name: String) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	_weapon_asset(file_name, attachment)

func _load_character_model(character_index: int) -> void:
	character_index = clampi(character_index, 0, CHARACTER_FILES.size() - 1)
	var packed := load(CHARACTER_BASE + CHARACTER_FILES[character_index]) as PackedScene
	if not packed:
		push_error("No se pudo cargar el personaje: " + CHARACTER_FILES[character_index])
		return
	character_model = packed.instantiate() as Node3D
	character_model.name = "AdventurerModel"
	# Los modelos tienen los pies en Y=0; el fondo del controlador está en Y=-0.9.
	character_model.position = Vector3(0.0, -0.90, 0.0)
	character_model.rotation_degrees.y = 180.0
	character_model.scale = Vector3.ONE * CHARACTER_SCALES[character_index]
	$BodyVisual.add_child(character_model)
	var animation_players := character_model.find_children("*", "AnimationPlayer", true, false)
	if not animation_players.is_empty():
		character_animation = animation_players[0] as AnimationPlayer
		_play_character_animation("Idle")

func _play_character_animation(animation_name: String) -> void:
	if not character_animation or current_character_animation == animation_name:
		return
	if not character_animation.has_animation(animation_name):
		return
	current_character_animation = animation_name
	character_animation.play(animation_name, 0.16)

func _input(event: InputEvent) -> void:
	if not network_ready or not is_multiplayer_authority():
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
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton:
		if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if character_class == 0:
				_set_blocking(event.pressed)
			elif character_class == 3 and event.pressed:
				_whirlwind()

func _set_camera_mode(use_third_person: bool) -> void:
	third_person_enabled = use_third_person
	first_person_camera.current = not use_third_person
	third_person_camera.current = use_third_person
	sword.visible = not use_third_person
	offhand.visible = not use_third_person
	$BodyVisual.visible = use_third_person

func _attack() -> void:
	if attack_in_progress or blocking:
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
	if third_person_enabled:
		_play_character_animation(animation_name)
	_play_attack_animation(pivot, rest_position, rest_rotation, attack_rotation, true)

func _play_attack_animation(pivot: Node3D, rest_position: Vector3, rest_rotation: Vector3, attack_rotation: Vector3, apply_hit: bool) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "rotation_degrees", attack_rotation, 0.10)
	tween.parallel().tween_property(pivot, "position", rest_position + Vector3(0.0, 0.03, -0.62), 0.10)
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
		_play_character_animation(animation_name)
		_finish_remote_action(duration)

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
	var shot := _ranged_query(22.0)
	var origin: Vector3 = shot.origin
	var end: Vector3 = shot.end
	_remote_ranged_effect.rpc(0, origin, end)
	_spawn_ranged_effect(0, origin, end)
	_remote_character_action.rpc("2H_Ranged_Shoot", 0.55)
	if third_person_enabled:
		_play_character_animation("2H_Ranged_Shoot")
	_deliver_projectile_hit(shot.collider, origin.distance_to(end) / 18.0)
	_finish_local_action(0.55)

func _cast_magic_ray() -> void:
	if attack_in_progress:
		return
	attack_in_progress = true
	var shot := _ranged_query(18.0)
	var origin: Vector3 = shot.origin
	var end: Vector3 = shot.end
	_remote_ranged_effect.rpc(1, origin, end)
	_spawn_ranged_effect(1, origin, end)
	_remote_character_action.rpc("Spellcast_Shoot", 0.48)
	if third_person_enabled:
		_play_character_animation("Spellcast_Shoot")
	var target: Object = shot.collider
	if target and target.has_method("receive_hit"):
		target.receive_hit(1)
	_finish_local_action(0.48)

func _ranged_query(max_range: float) -> Dictionary:
	var origin := first_person_camera.global_position
	var end := origin - first_person_camera.global_transform.basis.z * max_range
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return {
		"origin": origin,
		"end": result.get("position", end),
		"collider": result.get("collider", null)
	}

func _deliver_projectile_hit(target: Object, travel_time: float) -> void:
	await get_tree().create_timer(travel_time).timeout
	if is_instance_valid(target) and target.has_method("receive_hit"):
		target.receive_hit(1)

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
		projectile.scale = Vector3.ONE * 0.42
		projectile.look_at(end, Vector3.UP)
		projectile.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90.0))
		var duration := origin.distance_to(end) / 18.0
		var tween := projectile.create_tween()
		tween.tween_property(projectile, "global_position", end, duration)
		tween.tween_callback(projectile.queue_free)
	else:
		var beam := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		var distance := origin.distance_to(end)
		mesh.top_radius = 0.035
		mesh.bottom_radius = 0.035
		mesh.height = distance
		mesh.radial_segments = 8
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.25, 0.65, 1.0, 0.9)
		material.emission_enabled = true
		material.emission = Color(0.18, 0.55, 1.0)
		material.emission_energy_multiplier = 5.0
		mesh.material = material
		beam.mesh = mesh
		get_parent().add_child(beam)
		beam.global_position = (origin + end) * 0.5
		beam.quaternion = Quaternion(Vector3.UP, (end - origin).normalized())
		var tween := beam.create_tween()
		tween.tween_property(beam, "scale", Vector3(0.05, 1.0, 0.05), 0.16)
		tween.tween_callback(beam.queue_free)

func _whirlwind() -> void:
	if attack_in_progress or blocking:
		return
	attack_in_progress = true
	_remote_character_action.rpc("2H_Melee_Attack_Spinning", 0.75)
	if third_person_enabled:
		_play_character_animation("2H_Melee_Attack_Spinning")
	var tween := create_tween().set_trans(Tween.TRANS_QUAD)
	tween.tween_property(sword, "rotation_degrees", sword_rest_rotation + Vector3(0.0, 0.0, -180.0), 0.20)
	tween.parallel().tween_property(offhand, "rotation_degrees", offhand_rest_rotation + Vector3(0.0, 0.0, 180.0), 0.20)
	tween.tween_callback(_apply_whirlwind_hit)
	tween.tween_property(sword, "rotation_degrees", sword_rest_rotation, 0.35)
	tween.parallel().tween_property(offhand, "rotation_degrees", offhand_rest_rotation, 0.35)
	tween.tween_callback(_finish_attack)

func _apply_whirlwind_hit() -> void:
	for target in get_tree().get_nodes_in_group("damageable"):
		if target is Node3D and global_position.distance_to((target as Node3D).global_position) <= 2.6:
			if target.has_method("receive_hit"):
				target.receive_hit(2)

func _apply_sword_hit() -> void:
	attack_ray.force_raycast_update()
	if not attack_ray.is_colliding():
		return
	var target := attack_ray.get_collider()
	if target and target.has_method("receive_hit"):
		target.receive_hit(1)

func _finish_attack() -> void:
	attack_in_progress = false
	current_character_animation = ""
	_play_character_animation("Idle")

func _physics_process(delta: float) -> void:
	if not network_ready:
		return
	if not is_multiplayer_authority():
		var moving := global_position.distance_to(remote_position) > 0.025
		global_position = global_position.lerp(remote_position, minf(1.0, delta * 14.0))
		rotation.y = lerp_angle(rotation.y, remote_body_rotation, minf(1.0, delta * 14.0))
		head.rotation.x = lerp_angle(head.rotation.x, remote_head_rotation, minf(1.0, delta * 14.0))
		if not attack_in_progress:
			_play_character_animation("Running_A" if moving else "Idle")
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var is_sprinting := Input.is_key_pressed(KEY_SHIFT) and not direction.is_zero_approx() and stamina > 0.0
	var current_speed := sprint_speed if is_sprinting else move_speed
	if is_sprinting:
		stamina = maxf(0.0, stamina - stamina_drain_per_second * delta)
	else:
		stamina = minf(max_stamina, stamina + stamina_regen_per_second * delta)
	if stamina_bar:
		stamina_bar.value = stamina
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if direction.is_zero_approx():
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, deceleration * delta)
	else:
		var next_speed := move_toward(horizontal_velocity.length(), current_speed, acceleration * delta)
		horizontal_velocity = direction * next_speed
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()
	_sync_state.rpc(global_position, rotation.y, head.rotation.x)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_state(position_: Vector3, body_rotation: float, head_rotation: float) -> void:
	remote_position = position_
	remote_body_rotation = body_rotation
	remote_head_rotation = head_rotation
