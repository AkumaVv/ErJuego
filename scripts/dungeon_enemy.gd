extends CharacterBody3D

const CHARACTER_ROOT := "res://addons/kaykit_character_pack_skeletons/addons/kaykit_character_pack_skeletons/Characters/gltf/"
const ASSET_ROOT := "res://addons/kaykit_character_pack_skeletons/addons/kaykit_character_pack_skeletons/Assets/gltf/"
const MODELS := ["Skeleton_Minion.glb", "Skeleton_Warrior.glb", "Skeleton_Rogue.glb", "Skeleton_Mage.glb"]
const WEAPONS := ["Skeleton_Axe.gltf", "Skeleton_Blade.gltf", "Skeleton_Crossbow.gltf", "Skeleton_Staff.gltf"]
# Order: Skeleton Minion, Warrior, Rogue and Mage.
const BASE_HEALTH := [12, 14, 10, 8]
const BASE_DAMAGE := [6, 5, 7, 8]
const VISION_RANGE := 36.0
const MELEE_RANGE := 3.0
const RANGED_RANGE := 24.0
const MOVE_SPEED := 3.12
const WANDER_SPEED := 1.495
const RANGED_COMBAT_SPEED := 2.35
const RANGED_PREFERRED_MIN := 11.0
const RANGED_PREFERRED_MAX := 19.0
const PROJECTILE_SPEED := 18.0
const WANDER_RADIUS := 17.0
const MAX_STEP_UP := 0.32
const STAIR_PROBE_DISTANCE := 0.72
# Dimensions follow the visible silhouette of each scaled skeleton model:
# Minion, Warrior, Rogue and Mage respectively.
const HITBOX_RADII := [0.44, 0.48, 0.43, 0.45]
const HITBOX_HEIGHTS := [1.38, 1.72, 1.55, 1.62]
# Measured from the imported meshes at their runtime scale. These include the
# complete skull/helmet silhouette but deliberately exclude held weapons.
const HEAD_HITBOX_RADII := [0.40, 0.38, 0.34, 0.38]
const HEAD_HITBOX_HEIGHTS := [1.34, 1.67, 1.51, 1.70]
const SHOULDER_HITBOX_WIDTHS := [1.18, 1.28, 1.20, 1.18]
const SHOULDER_HITBOX_RADII := [0.24, 0.27, 0.24, 0.25]
const SHOULDER_HITBOX_HEIGHTS := [1.08, 1.27, 1.16, 1.20]
const SILHOUETTE_HITBOX_SIZES := [
	Vector3(1.512, 1.690, 0.712),
	Vector3(1.515, 2.021, 1.138),
	Vector3(1.515, 1.800, 0.900),
	Vector3(1.512, 2.052, 1.354)
]

var enemy_type := 0
var max_health := 10
var health := 10
var base_damage := 5
var target: Node3D
var attack_cooldown := 0.0
var animation_player: AnimationPlayer
var model_root: Node3D
var remote_position := Vector3.ZERO
var remote_rotation := 0.0
var last_hit_by_peer: Dictionary = {}
var dying := false
var health_sprite: Sprite3D
var health_text: Label3D
var home_center := Vector3.ZERO
var wander_destination := Vector3.ZERO
var wander_wait := 0.0
var wander_rng := RandomNumberGenerator.new()
var combat_move_time := 0.0
var combat_move_direction := 0.0
var distance_simulation_active := true
var distance_render_active := true

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("dungeon_enemies")
	var safe_type := clampi(enemy_type, 0, BASE_HEALTH.size() - 1)
	max_health = BASE_HEALTH[safe_type]
	health = max_health
	base_damage = BASE_DAMAGE[safe_type]
	collision_layer = 1
	collision_mask = 1
	# Keep enemies attached to shallow ramps when crossing the many small stair
	# steps. The forward probe below handles the transition onto the ramp.
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	safe_type = clampi(enemy_type, 0, HITBOX_RADII.size() - 1)
	capsule.radius = HITBOX_RADII[safe_type]
	capsule.height = HITBOX_HEIGHTS[safe_type]
	collision.shape = capsule
	collision.position.y = capsule.height * 0.5
	add_child(collision)
	var head_collision := CollisionShape3D.new()
	head_collision.name = "HeadCollisionShape3D"
	var head_sphere := SphereShape3D.new()
	head_sphere.radius = HEAD_HITBOX_RADII[safe_type]
	head_collision.shape = head_sphere
	head_collision.position.y = HEAD_HITBOX_HEIGHTS[safe_type]
	add_child(head_collision)
	var shoulder_collision := CollisionShape3D.new()
	shoulder_collision.name = "ShoulderCollisionShape3D"
	var shoulder_capsule := CapsuleShape3D.new()
	shoulder_capsule.radius = SHOULDER_HITBOX_RADII[safe_type]
	shoulder_capsule.height = SHOULDER_HITBOX_WIDTHS[safe_type]
	shoulder_collision.shape = shoulder_capsule
	shoulder_collision.position.y = SHOULDER_HITBOX_HEIGHTS[safe_type]
	shoulder_collision.rotation_degrees.z = 90.0
	add_child(shoulder_collision)
	var silhouette_collision := CollisionShape3D.new()
	silhouette_collision.name = "SilhouetteCollisionShape3D"
	var silhouette_box := BoxShape3D.new()
	silhouette_box.size = SILHOUETTE_HITBOX_SIZES[safe_type]
	silhouette_collision.shape = silhouette_box
	silhouette_collision.position.y = silhouette_box.size.y * 0.5
	silhouette_collision.position.z = [-0.002, -0.023, -0.004, 0.015][safe_type]
	add_child(silhouette_collision)
	_setup_model()
	_setup_health_label()
	remote_position = global_position
	if home_center == Vector3.ZERO:
		home_center = global_position
	wander_rng.seed = hash(name)
	_choose_wander_destination()

func set_distance_state(simulation_active: bool, render_active: bool) -> void:
	if dying:
		return
	var simulation_changed := distance_simulation_active != simulation_active
	distance_simulation_active = simulation_active
	distance_render_active = render_active
	set_physics_process(simulation_active)
	if model_root:
		model_root.visible = render_active
	if health_sprite:
		health_sprite.visible = render_active
	if health_text:
		health_text.visible = render_active
	if animation_player:
		animation_player.active = render_active
	for shape_node in find_children("*", "CollisionShape3D", true, false):
		(shape_node as CollisionShape3D).set_deferred("disabled", not simulation_active)
	if simulation_changed and simulation_active:
		remote_position = global_position
		_play_first_available(["Idle_Combat", "Idle"])
	elif simulation_changed:
		velocity = Vector3.ZERO

func _setup_model() -> void:
	var packed := load(CHARACTER_ROOT + MODELS[enemy_type]) as PackedScene
	if not packed:
		return
	var model := packed.instantiate() as Node3D
	model_root = model
	model.scale = Vector3.ONE * 0.78
	model.rotation_degrees.y = 180.0
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation_player = players[0] as AnimationPlayer
		_play_first_available(["Idle_Combat", "Idle"])
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "handslot.r"
		(skeletons[0] as Skeleton3D).add_child(attachment)
		var weapon := load(ASSET_ROOT + WEAPONS[enemy_type]) as PackedScene
		if weapon:
			attachment.add_child(weapon.instantiate())

func _setup_health_label() -> void:
	health_sprite = Sprite3D.new()
	health_sprite.position = Vector3(0, 2.35, 0)
	health_sprite.pixel_size = 0.0045
	health_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_sprite.no_depth_test = true
	add_child(health_sprite)
	health_text = Label3D.new()
	health_text.position = Vector3(0, 2.35, 0.01)
	health_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_text.no_depth_test = true
	health_text.font_size = 22
	health_text.outline_size = 5
	health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(health_text)
	_update_health_label()

func _update_health_label() -> void:
	if not health_sprite or not health_text:
		return
	var image := Image.create(256, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.10, 0.01, 0.015, 0.96))
	var fill_width := int(252.0 * float(health) / float(max_health))
	if fill_width > 0:
		image.fill_rect(Rect2i(2, 2, fill_width, 20), Color(0.80, 0.035, 0.05, 1.0))
	health_sprite.texture = ImageTexture.create_from_image(image)
	health_text.text = "%d/%d" % [health, max_health]

func _physics_process(delta: float) -> void:
	if dying:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		global_position = global_position.lerp(remote_position, minf(1.0, delta * 12.0))
		rotation.y = lerp_angle(rotation.y, remote_rotation, minf(1.0, delta * 12.0))
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	_acquire_target()
	if not target:
		_wander(delta)
		_move_enemy()
		_sync_enemy_state.rpc(global_position, rotation.y)
		return
	var flat_delta := target.global_position - global_position
	flat_delta.y = 0.0
	var attack_range := MELEE_RANGE if enemy_type < 2 else RANGED_RANGE
	if flat_delta.length() <= attack_range and _has_line_of_sight(target):
		if enemy_type >= 2:
			_update_ranged_combat_movement(flat_delta, delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
		look_at(global_position + flat_delta, Vector3.UP)
		if attack_cooldown <= 0.0:
			_attack_target()
	else:
		var direction := flat_delta.normalized()
		velocity.x = direction.x * MOVE_SPEED
		velocity.z = direction.z * MOVE_SPEED
		look_at(global_position + direction, Vector3.UP)
		_play_first_available(["Running_A", "Walking_A"])
	_move_enemy()
	_sync_enemy_state.rpc(global_position, rotation.y)

func _update_ranged_combat_movement(to_target: Vector3, delta: float) -> void:
	combat_move_time -= delta
	if combat_move_time <= 0.0:
		# Short idle beats make the movement readable; most decisions produce a
		# left or right reposition instead of a stationary firing turret.
		combat_move_direction = 0.0 if wander_rng.randf() < 0.22 else (-1.0 if wander_rng.randf() < 0.5 else 1.0)
		combat_move_time = wander_rng.randf_range(0.45, 1.35) if combat_move_direction != 0.0 else wander_rng.randf_range(0.18, 0.48)
	if combat_move_direction == 0.0 or to_target.length_squared() < 0.01:
		velocity.x = move_toward(velocity.x, 0.0, RANGED_COMBAT_SPEED * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, RANGED_COMBAT_SPEED * 8.0 * delta)
		return
	var toward := to_target.normalized()
	var sideways := Vector3(-toward.z, 0.0, toward.x) * combat_move_direction
	var distance := to_target.length()
	var radial := Vector3.ZERO
	if distance < RANGED_PREFERRED_MIN:
		radial = -toward * 0.80
	elif distance > RANGED_PREFERRED_MAX:
		radial = toward * 0.42
	var movement := (sideways + radial).normalized()
	velocity.x = movement.x * RANGED_COMBAT_SPEED
	velocity.z = movement.z * RANGED_COMBAT_SPEED
	if attack_cooldown < 1.25:
		_play_first_available(["Walking_A", "Running_A"])

func _move_enemy() -> void:
	_assist_stair_ascent()
	move_and_slide()

func _assist_stair_ascent() -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if not is_on_floor() or horizontal_velocity.length_squared() < 0.01:
		return
	var direction := horizontal_velocity.normalized()
	var probe_position := global_position + direction * STAIR_PROBE_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(
		probe_position + Vector3.UP * (MAX_STEP_UP + 0.18),
		probe_position + Vector3.DOWN * 0.12
	)
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var surface_normal: Vector3 = result.normal
	var step_height: float = result.position.y - global_position.y
	# A near-horizontal surface slightly above the feet is a step or the stair
	# ramp. Vertical walls fail the normal check and can never be climbed.
	if surface_normal.dot(Vector3.UP) < 0.65 or step_height <= 0.01 or step_height > MAX_STEP_UP:
		return
	var upward_motion := Vector3.UP * (step_height + 0.015)
	if not test_move(global_transform, upward_motion):
		global_position += upward_motion

func _wander(delta: float) -> void:
	wander_wait = maxf(0.0, wander_wait - delta)
	var offset := wander_destination - global_position
	offset.y = 0.0
	if offset.length() < 0.7:
		velocity.x = move_toward(velocity.x, 0.0, WANDER_SPEED * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, WANDER_SPEED * 5.0 * delta)
		_play_first_available(["Idle_Combat", "Idle"])
		if wander_wait <= 0.0:
			wander_wait = wander_rng.randf_range(1.0, 3.5)
			_choose_wander_destination()
		return
	var direction := offset.normalized()
	velocity.x = direction.x * WANDER_SPEED
	velocity.z = direction.z * WANDER_SPEED
	look_at(global_position + direction, Vector3.UP)
	_play_first_available(["Walking_A", "Running_A"])

func _choose_wander_destination() -> void:
	var angle := wander_rng.randf_range(0.0, TAU)
	var distance := wander_rng.randf_range(2.0, WANDER_RADIUS)
	wander_destination = home_center + Vector3(cos(angle), 0.0, sin(angle)) * distance

func _acquire_target() -> void:
	# Line of sight is required only to acquire a new target. Once combat has
	# started, cover and other enemies do not erase aggro; distance, death and
	# protected areas still do.
	if target and (not is_instance_valid(target) or not _target_allowed(target) or global_position.distance_to(target.global_position) > VISION_RANGE):
		target = null
	if target:
		return
	var nearest_distance := VISION_RANGE + 0.01
	for candidate in get_tree().get_nodes_in_group("chain_allies"):
		if candidate is Node3D and str(candidate.name).begins_with("Player_") and _target_allowed(candidate):
			var distance := global_position.distance_to((candidate as Node3D).global_position)
			if distance < nearest_distance and _has_line_of_sight(candidate as Node3D):
				nearest_distance = distance
				target = candidate as Node3D

func _target_allowed(candidate: Node3D) -> bool:
	for safe_state in get_tree().get_nodes_in_group("dungeon_safe_state"):
		if safe_state.has_method("can_enemy_target") and not safe_state.can_enemy_target(candidate):
			return false
	return true

func _has_line_of_sight(candidate: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.25, candidate.global_position + Vector3.UP * 1.0)
	query.exclude = [self]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == candidate

func _attack_target() -> void:
	attack_cooldown = 1.25 if enemy_type < 2 else 2.0
	if enemy_type < 2:
		_play_first_available(["1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop"])
	else:
		_play_first_available(["1H_Ranged_Shoot", "2H_Ranged_Shoot", "Spellcast_Shoot"])
	var victim := target
	if enemy_type >= 2:
		_launch_ranged_attack(victim)
		return
	await get_tree().create_timer(0.32).timeout
	if not victim or not is_instance_valid(victim) or not _target_allowed(victim):
		return
	var allowed_range := MELEE_RANGE + 0.3 if enemy_type < 2 else RANGED_RANGE
	if global_position.distance_to(victim.global_position) > allowed_range or not _has_line_of_sight(victim):
		return
	var peer_id := victim.get_multiplayer_authority()
	if peer_id == multiplayer.get_unique_id() or not multiplayer.has_multiplayer_peer():
		victim.receive_damage(base_damage, "physical" if enemy_type != 3 else "magical")
	else:
		victim.receive_server_damage.rpc_id(peer_id, base_damage, "physical" if enemy_type != 3 else "magical")

func _launch_ranged_attack(victim: Node3D) -> void:
	if not victim or not is_instance_valid(victim):
		return
	var start := global_position + Vector3.UP * 1.35
	var finish := _predict_projectile_endpoint(start, victim)
	var duration := start.distance_to(finish) / PROJECTILE_SPEED
	_show_projectile.rpc(start, finish, enemy_type, duration)
	# Follow the same straight path as the visible projectile and test every
	# physics frame. Previously only the final point was checked, so a projectile
	# could visibly cross an edge of the character without registering the hit.
	var did_hit := await _track_projectile_collision(start, finish, duration, victim, enemy_type)
	if not did_hit:
		return
	var peer_id := victim.get_multiplayer_authority()
	var damage_type := "magic" if enemy_type == 3 else "physical"
	if peer_id == multiplayer.get_unique_id() or not multiplayer.has_multiplayer_peer():
		victim.receive_damage(base_damage, damage_type)
	else:
		victim.receive_server_damage.rpc_id(peer_id, base_damage, damage_type)

func _track_projectile_collision(start: Vector3, finish: Vector3, duration: float, victim: Node3D, type: int) -> bool:
	var elapsed := 0.0
	var previous := start
	while elapsed < duration:
		await get_tree().physics_frame
		if not victim or not is_instance_valid(victim) or not _target_allowed(victim):
			return false
		elapsed = minf(duration, elapsed + get_physics_process_delta_time())
		var current := start.lerp(finish, elapsed / maxf(duration, 0.001))
		# The ray prevents fast projectiles from skipping completely through the
		# capsule between two frames. Projectile radius is handled by the capsule
		# proximity check immediately afterwards.
		var query := PhysicsRayQueryParameters3D.create(previous, current)
		var excluded: Array[RID] = [get_rid()]
		# Enemy bodies do not block allied arrows or spells. The projectiles
		# themselves are visual Node3Ds and therefore never collide together.
		for other_enemy in get_tree().get_nodes_in_group("dungeon_enemies"):
			if other_enemy is CollisionObject3D and other_enemy != self:
				excluded.append((other_enemy as CollisionObject3D).get_rid())
		query.exclude = excluded
		query.collision_mask = 1
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty():
			return result.get("collider") == victim
		if _projectile_intersects_victim(current, victim, type):
			return true
		previous = current
	return false

func _predict_projectile_endpoint(start: Vector3, victim: Node3D) -> Vector3:
	var current_point := _victim_aim_point(victim)
	var movement := Vector3.ZERO
	if victim.has_method("get_projectile_prediction_velocity"):
		movement = victim.get_projectile_prediction_velocity()
	movement.y = 0.0
	# Two passes are sufficient here: the second flight-time estimate also
	# accounts for the extra distance introduced by leading the target.
	var flight_time := minf(start.distance_to(current_point) / PROJECTILE_SPEED, 1.0)
	var predicted := current_point + movement * flight_time
	flight_time = minf(start.distance_to(predicted) / PROJECTILE_SPEED, 1.0)
	return current_point + movement * flight_time

func _victim_aim_point(victim: Node3D) -> Vector3:
	var collision := victim.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision:
		return collision.global_position
	return victim.global_position

func _projectile_intersects_victim(endpoint: Vector3, victim: Node3D, type: int) -> bool:
	var victim_radius := 0.35
	var victim_height := 1.70
	var capsule_center := victim.global_position
	var collision := victim.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision and collision.shape is CapsuleShape3D:
		var capsule := collision.shape as CapsuleShape3D
		victim_radius = capsule.radius
		victim_height = capsule.height
		capsule_center = collision.global_position
	var projectile_radius := 0.13 if type == 2 else 0.16
	# CapsuleShape3D consists of a vertical segment plus its radius. Checking
	# against that segment uses exactly the same volume as player movement,
	# including torso, head and legs instead of only a sphere at the waist.
	var segment_half := maxf(0.0, victim_height * 0.5 - victim_radius)
	var segment_bottom := capsule_center - Vector3.UP * segment_half
	var segment_top := capsule_center + Vector3.UP * segment_half
	var segment := segment_top - segment_bottom
	var segment_length_squared := segment.length_squared()
	var closest := segment_bottom
	if segment_length_squared > 0.0001:
		var along := clampf((endpoint - segment_bottom).dot(segment) / segment_length_squared, 0.0, 1.0)
		closest = segment_bottom + segment * along
	# The 3 cm margin only compensates for network interpolation and is not a
	# second, invisible hitbox around the model.
	return endpoint.distance_to(closest) <= victim_radius + projectile_radius + 0.03

@rpc("authority", "call_local", "reliable")
func _show_projectile(start: Vector3, finish: Vector3, type: int, duration: float) -> void:
	var projectile := Node3D.new()
	get_parent().add_child(projectile)
	projectile.global_position = start
	projectile.look_at(finish, Vector3.UP)
	if type == 2:
		_build_visible_arrow(projectile)
	else:
		_build_magic_orb(projectile)
	var tween := projectile.create_tween()
	tween.tween_property(projectile, "global_position", finish, duration)
	tween.tween_callback(projectile.queue_free)

func _build_magic_orb(projectile: Node3D) -> void:
	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = mesh.radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#7fdcff")
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 3.0
	mesh.material = material
	orb.mesh = mesh
	projectile.add_child(orb)

func _build_visible_arrow(projectile: Node3D) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#7a3f1d")
	wood.roughness = 0.8
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#f2c75c")
	metal.metallic = 0.65
	metal.emission_enabled = true
	metal.emission = Color("#9b5a16")
	metal.emission_energy_multiplier = 0.7
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.035
	shaft_mesh.bottom_radius = 0.035
	shaft_mesh.height = 1.05
	shaft_mesh.material = wood
	shaft.mesh = shaft_mesh
	shaft.rotation_degrees.x = 90.0
	projectile.add_child(shaft)
	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.13
	tip_mesh.height = 0.30
	tip_mesh.material = metal
	tip.mesh = tip_mesh
	tip.position.z = -0.65
	tip.rotation_degrees.x = 90.0
	projectile.add_child(tip)

func receive_hit(damage: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_hit.rpc_id(1, damage)
		return
	_apply_hit(multiplayer.get_unique_id(), damage)

@rpc("any_peer", "call_remote", "reliable")
func _request_hit(damage: int) -> void:
	if multiplayer.is_server():
		_apply_hit(multiplayer.get_remote_sender_id(), damage)

func _apply_hit(peer_id: int, damage: int) -> void:
	if dying:
		return
	var now := Time.get_ticks_msec()
	if now - int(last_hit_by_peer.get(peer_id, -1000)) < 180:
		return
	last_hit_by_peer[peer_id] = now
	health = maxi(0, health - maxi(0, damage))
	_update_health_label()
	_spawn_damage_number(damage)
	_sync_health.rpc(health, damage)
	if health <= 0:
		_die.rpc()

@rpc("authority", "call_remote", "reliable")
func _sync_health(value: int, damage: int) -> void:
	health = value
	_update_health_label()
	_spawn_damage_number(damage)

func _spawn_damage_number(damage: int) -> void:
	var label := Label3D.new()
	label.text = "-%d" % damage
	label.modulate = Color("#ff2929")
	label.font_size = 38
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	get_parent().add_child(label)
	label.global_position = global_position + Vector3(0, 2.0, 0)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3.UP * 0.8, 0.75)
	tween.tween_property(label, "modulate:a", 0.0, 0.75)
	tween.chain().tween_callback(label.queue_free)

@rpc("authority", "call_local", "reliable")
func _die() -> void:
	if dying:
		return
	dying = true
	if multiplayer.is_server():
		var game := get_tree().current_scene
		if game and game.has_method("roll_personal_wand_drops"):
			game.roll_personal_wand_drops()
	velocity = Vector3.ZERO
	target = null
	for collision in find_children("*", "CollisionShape3D", true, false):
		(collision as CollisionShape3D).disabled = true
	var tween := create_tween().set_parallel(true)
	for mesh_node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		tween.tween_property(mesh_instance, "transparency", 1.0, 0.9)
	if health_sprite:
		tween.tween_property(health_sprite, "modulate:a", 0.0, 0.6)
	if health_text:
		tween.tween_property(health_text, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(queue_free)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_enemy_state(position_: Vector3, rotation_: float) -> void:
	remote_position = position_
	remote_rotation = rotation_

func _play_first_available(names: Array) -> void:
	if not animation_player:
		return
	for animation_name in names:
		if animation_player.has_animation(animation_name):
			if animation_player.current_animation != animation_name:
				animation_player.play(animation_name, 0.12)
			return
