extends CharacterBody3D

@export var move_speed := 5.5
@export var sprint_speed := 9.0
@export var acceleration := 18.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.0022
@export var max_stamina := 100.0
@export var stamina_drain_per_second := 28.0
@export var stamina_regen_per_second := 20.0

@onready var head: Node3D = $Head
@onready var stamina_bar: ProgressBar = get_node_or_null("../Interface/StaminaBar")
@onready var sword: Node3D = $Head/Camera3D/Sword
@onready var attack_ray: RayCast3D = $Head/Camera3D/AttackRay

var stamina := max_stamina
var attack_in_progress := false
var sword_rest_position := Vector3.ZERO
var sword_rest_rotation := Vector3.ZERO
var network_ready := false
var remote_position := Vector3.ZERO
var remote_body_rotation := 0.0
var remote_head_rotation := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = stamina
	sword_rest_position = sword.position
	sword_rest_rotation = sword.rotation_degrees

func configure_network_player(peer_id: int, character_index: int, character_color: Color, display_name: String) -> void:
	set_multiplayer_authority(peer_id)
	network_ready = true
	remote_position = global_position
	var local_player := is_multiplayer_authority()
	$Head/Camera3D.current = local_player
	$Head/Camera3D/Sword.visible = local_player
	$BodyVisual.visible = not local_player
	$BodyVisual/Name.text = display_name
	var material := $BodyVisual/Torso.material_override.duplicate() as StandardMaterial3D
	material.albedo_color = character_color
	$BodyVisual/Torso.material_override = material
	$BodyVisual/HeadMesh.material_override = material
	if local_player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if not network_ready or not is_multiplayer_authority():
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

func _attack() -> void:
	if attack_in_progress:
		return
	attack_in_progress = true
	_remote_attack.rpc()
	_play_attack_animation()

func _play_attack_animation() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(sword, "rotation_degrees", Vector3(-28.0, -4.0, -24.0), 0.10)
	tween.parallel().tween_property(sword, "position", sword_rest_position + Vector3(0.0, 0.03, -0.62), 0.10)
	tween.tween_callback(_apply_sword_hit)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sword, "rotation_degrees", sword_rest_rotation, 0.20)
	tween.parallel().tween_property(sword, "position", sword_rest_position, 0.20)
	tween.tween_callback(_finish_attack)

@rpc("authority", "call_remote", "unreliable")
func _remote_attack() -> void:
	if not attack_in_progress:
		attack_in_progress = true
		_play_attack_animation()

func _apply_sword_hit() -> void:
	attack_ray.force_raycast_update()
	if not attack_ray.is_colliding():
		return
	var target := attack_ray.get_collider()
	if target and target.has_method("receive_hit"):
		target.receive_hit(1)

func _finish_attack() -> void:
	attack_in_progress = false

func _physics_process(delta: float) -> void:
	if not network_ready:
		return
	if not is_multiplayer_authority():
		global_position = global_position.lerp(remote_position, minf(1.0, delta * 14.0))
		rotation.y = lerp_angle(rotation.y, remote_body_rotation, minf(1.0, delta * 14.0))
		head.rotation.x = lerp_angle(head.rotation.x, remote_head_rotation, minf(1.0, delta * 14.0))
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
	var target := direction * current_speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	move_and_slide()
	_sync_state.rpc(global_position, rotation.y, head.rotation.x)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_state(position_: Vector3, body_rotation: float, head_rotation: float) -> void:
	remote_position = position_
	remote_body_rotation = body_rotation
	remote_head_rotation = head_rotation
