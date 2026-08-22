extends CharacterBody3D

const CHARACTER_BASE := "res://addons/kaykit_character_pack_adventures/Characters/gltf/"
const CHARACTER_FILES := ["Knight.glb", "Rogue_Hooded.glb", "Mage.glb", "Barbarian.glb"]
const CHARACTER_SCALES := [0.73, 0.80, 0.60, 0.75]

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
@onready var attack_ray: RayCast3D = $Head/Camera3D/AttackRay
@onready var first_person_camera: Camera3D = $Head/Camera3D
@onready var third_person_camera: Camera3D = $Head/ThirdPersonArm/ThirdPersonCamera

var stamina := max_stamina
var attack_in_progress := false
var sword_rest_position := Vector3.ZERO
var sword_rest_rotation := Vector3.ZERO
var network_ready := false
var remote_position := Vector3.ZERO
var remote_body_rotation := 0.0
var remote_head_rotation := 0.0
var character_model: Node3D
var character_animation: AnimationPlayer
var current_character_animation := ""
var third_person_enabled := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = stamina
	sword_rest_position = sword.position
	sword_rest_rotation = sword.rotation_degrees

func configure_network_player(peer_id: int, character_index: int, _character_color: Color, display_name: String) -> void:
	set_multiplayer_authority(peer_id)
	network_ready = true
	remote_position = global_position
	var local_player := is_multiplayer_authority()
	$Head/Camera3D.current = local_player
	$Head/ThirdPersonArm/ThirdPersonCamera.current = false
	$Head/Camera3D/Sword.visible = local_player
	$BodyVisual.visible = not local_player
	$BodyVisual/Name.text = display_name
	_load_character_model(character_index)
	if local_player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_attack()

func _set_camera_mode(use_third_person: bool) -> void:
	third_person_enabled = use_third_person
	first_person_camera.current = not use_third_person
	third_person_camera.current = use_third_person
	sword.visible = not use_third_person
	$BodyVisual.visible = use_third_person

func _attack() -> void:
	if attack_in_progress:
		return
	attack_in_progress = true
	_remote_attack.rpc()
	if third_person_enabled:
		_play_character_animation("1H_Melee_Attack_Stab")
	_play_attack_animation(true)

func _play_attack_animation(apply_hit: bool) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(sword, "rotation_degrees", Vector3(-28.0, -4.0, -24.0), 0.10)
	tween.parallel().tween_property(sword, "position", sword_rest_position + Vector3(0.0, 0.03, -0.62), 0.10)
	if apply_hit:
		tween.tween_callback(_apply_sword_hit)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sword, "rotation_degrees", sword_rest_rotation, 0.20)
	tween.parallel().tween_property(sword, "position", sword_rest_position, 0.20)
	tween.tween_callback(_finish_attack)

@rpc("authority", "call_remote", "unreliable")
func _remote_attack() -> void:
	if not attack_in_progress:
		attack_in_progress = true
		_play_character_animation("1H_Melee_Attack_Stab")
		_play_attack_animation(false)

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
