extends Node3D

const ASSET_PATH := "res://addons/kaykit_dungeon_remastered/Assets/gltf/"
const DUNGEON_ENEMY_SCRIPT := preload("res://scripts/dungeon_enemy.gd")
const LEVEL_COUNT := 3
const ROOM_SIZE := 48.0
const ROOM_SPACING := 48.0
const LEVEL_HEIGHT := 8.0
const FLOOR_RISE := 4.0
const STAIR_RUN := 24.0
const STAIR_OVERLAP := 0.6
const WALL_HEIGHT := 8.0
const DOOR_WIDTH := 16.0
const INSIDE_LOBBY_SIZE := 12.0
const INSIDE_LOBBY_HEIGHT := 4.0
const INSIDE_LOBBY_DOOR_WIDTH := 8.0
const MODULE_OFFSETS := [-20.0, -12.0, -4.0, 4.0, 12.0, 20.0]
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const ENEMY_ACTIVE_DISTANCE := 58.0
const ENEMY_CULL_INTERVAL := 0.30

var level_rooms: Array[Array] = []
var stair_directions: Array[Vector2i] = []
var stair_rooms: Array[Vector2i] = []
var level_offsets: Array[Vector2] = []
var packed_assets: Dictionary = {}
var stone_material: StandardMaterial3D
var inside_lobby_center := Vector3.ZERO
var inside_lobby_direction := Vector2i.ZERO
var inside_lobby_safe_locked := true
var players_who_left_inside_lobby: Dictionary = {}
var inside_lobby_return_barrier: CollisionShape3D
var enemy_serial := 0
var enemy_cull_elapsed := 0.0

func _physics_process(delta: float) -> void:
	# The entrance is one-way per player. Each client enforces it only for its
	# authoritative character, avoiding multiplayer position conflicts.
	for node in get_tree().get_nodes_in_group("chain_allies"):
		if not node is CharacterBody3D or not str(node.name).begins_with("Player_"):
			continue
		var player := node as CharacterBody3D
		if player.get_multiplayer_authority() != multiplayer.get_unique_id():
			continue
		var peer_id := player.get_multiplayer_authority()
		var inside := is_player_inside_lobby(player.global_position)
		if not players_who_left_inside_lobby.has(peer_id):
			if not inside:
				players_who_left_inside_lobby[peer_id] = true
				_set_inside_lobby_return_barrier(true)
			continue
	enemy_cull_elapsed += delta
	if enemy_cull_elapsed >= ENEMY_CULL_INTERVAL:
		enemy_cull_elapsed = 0.0
		_update_enemy_distance_activation()

func _update_enemy_distance_activation() -> void:
	var simulation_players: Array[Node3D] = []
	var render_players: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("chain_allies"):
		if not node is Node3D or not str(node.name).begins_with("Player_"):
			continue
		var player := node as Node3D
		if multiplayer.is_server():
			simulation_players.append(player)
		if player.get_multiplayer_authority() == multiplayer.get_unique_id():
			render_players.append(player)
			if not multiplayer.is_server():
				simulation_players.append(player)
	var maximum_squared := ENEMY_ACTIVE_DISTANCE * ENEMY_ACTIVE_DISTANCE
	for node in get_tree().get_nodes_in_group("dungeon_enemies"):
		if not node is Node3D or not node.has_method("set_distance_state"):
			continue
		var simulation_active := false
		var render_active := false
		for player in simulation_players:
			if (node as Node3D).global_position.distance_squared_to(player.global_position) <= maximum_squared:
				simulation_active = true
				break
		for player in render_players:
			if (node as Node3D).global_position.distance_squared_to(player.global_position) <= maximum_squared:
				render_active = true
				break
		node.set_distance_state(simulation_active, render_active)

func reset_player_inside_lobby_access(peer_id: int) -> void:
	players_who_left_inside_lobby.erase(peer_id)
	if peer_id == multiplayer.get_unique_id():
		_set_inside_lobby_return_barrier(false)

func _set_inside_lobby_return_barrier(active: bool) -> void:
	if inside_lobby_return_barrier:
		inside_lobby_return_barrier.set_deferred("disabled", not active)

func generate(seed_value: int) -> void:
	stone_material = _material(Color("#555b65"))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var level_start := Vector2i.ZERO
	level_offsets.append(Vector2.ZERO)
	for level in range(LEVEL_COUNT):
		var room_count := rng.randi_range(2, 4)
		var blocked := stair_rooms[-1] if level > 0 else Vector2i(999999, 999999)
		var rooms := _make_linear_layout(rng, level_start, room_count, blocked)
		level_rooms.append(rooms)
		if level < LEVEL_COUNT - 1:
			var stair_direction: Vector2i = rooms[-1] - rooms[-2]
			var stair_room: Vector2i = rooms[-1] + stair_direction
			stair_directions.append(stair_direction)
			stair_rooms.append(stair_room)
			level_start = stair_room + stair_direction
			var current_offset: Vector2 = level_offsets[level]
			level_offsets.append(current_offset - Vector2(stair_direction.x, stair_direction.y) * (ROOM_SIZE * 0.5))
	for level in range(LEVEL_COUNT):
		_build_level(level, level_rooms[level], rng)
	_build_inside_lobby(rng)
	for level in range(LEVEL_COUNT - 1):
		_build_stair_zone(level, stair_rooms[level], stair_directions[level], rng)

func get_spawn_position(index: int) -> Vector3:
	var toward_room := Vector3(-inside_lobby_direction.x, 0, -inside_lobby_direction.y)
	var sideways := Vector3(-toward_room.z, 0, toward_room.x)
	var offsets := [-2.4, -0.8, 0.8, 2.4]
	return inside_lobby_center - toward_room * 3.2 + sideways * offsets[index % offsets.size()] + Vector3.UP * 1.05

func get_spawn_facing_yaw() -> float:
	var toward_room := Vector3(-inside_lobby_direction.x, 0, -inside_lobby_direction.y)
	return atan2(-toward_room.x, -toward_room.z)

func is_player_inside_lobby(player_position: Vector3) -> bool:
	var local := player_position - inside_lobby_center
	return absf(local.x) <= INSIDE_LOBBY_SIZE * 0.5 and absf(local.z) <= INSIDE_LOBBY_SIZE * 0.5 and local.y >= -0.5 and local.y <= INSIDE_LOBBY_HEIGHT + 1.0

func is_inside_lobby_safe_locked() -> bool:
	# Kept for compatibility with older calls. Protection is now positional and
	# evaluated independently for every player instead of being unlocked once.
	return true

func can_enemy_target(player: Node3D) -> bool:
	return not is_player_inside_lobby(player.global_position)

func can_enemy_enter(target_position: Vector3) -> bool:
	return not is_player_inside_lobby(target_position)

func unlock_inside_lobby() -> void:
	inside_lobby_safe_locked = false

func _make_linear_layout(rng: RandomNumberGenerator, start: Vector2i, count: int, blocked: Vector2i) -> Array:
	var rooms: Array = [start]
	var previous_direction: Vector2i = DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
	while rooms.size() < count:
		var candidates: Array[Vector2i] = []
		var preferred: Array[Vector2i] = [previous_direction]
		for direction in DIRECTIONS:
			if direction != -previous_direction:
				preferred.append(direction)
		for direction in preferred:
			var candidate: Vector2i = rooms[-1] + direction
			if rooms.has(candidate) or candidate == blocked:
				continue
			if _touches_non_previous_room(candidate, rooms):
				continue
			candidates.append(direction)
		if candidates.is_empty():
			rooms = [start]
			previous_direction = DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
			continue
		var chosen: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		rooms.append(rooms[-1] + chosen)
		previous_direction = chosen
	return rooms

func _touches_non_previous_room(candidate: Vector2i, rooms: Array) -> bool:
	for direction in DIRECTIONS:
		var neighbour: Vector2i = candidate + direction
		if rooms.has(neighbour) and neighbour != rooms[-1]:
			return true
	return false

func _build_level(level: int, rooms: Array, rng: RandomNumberGenerator) -> void:
	for index in range(rooms.size()):
		var room: Vector2i = rooms[index]
		var incoming_direction: Vector2i = -stair_directions[level - 1] if level > 0 and index == 0 else Vector2i.ZERO
		if level == 0 and index == 0:
			inside_lobby_direction = -(rooms[1] - rooms[0])
			incoming_direction = inside_lobby_direction
		var outgoing_direction: Vector2i = stair_directions[level] if level < LEVEL_COUNT - 1 and index == rooms.size() - 1 else Vector2i.ZERO
		var center := _room_position(level, room)
		_build_room_surfaces(center)
		_build_room_walls(center, room, rooms, rng, incoming_direction, outgoing_direction)
		_add_room_columns(center)
		_add_ceiling_lamps(center)
		_spawn_enemy_packs(center, rng)

func _spawn_enemy_packs(center: Vector3, rng: RandomNumberGenerator) -> void:
	var pack_count := rng.randi_range(2, 3)
	for pack_index in range(pack_count):
		var enemy_type := rng.randi_range(0, 3)
		var member_count := rng.randi_range(3, 5)
		var angle := TAU * float(pack_index) / float(pack_count) + rng.randf_range(-0.28, 0.28)
		var radius := rng.randf_range(7.0, 16.0)
		var pack_center := center + Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
		for member in range(member_count):
			var member_angle := TAU * float(member) / float(member_count)
			var member_radius := 1.5 + 0.42 * float(member % 3)
			var spawn_position := pack_center + Vector3(cos(member_angle) * member_radius, 0, sin(member_angle) * member_radius)
			spawn_position.x = clampf(spawn_position.x, center.x - 19.0, center.x + 19.0)
			spawn_position.z = clampf(spawn_position.z, center.z - 19.0, center.z + 19.0)
			var enemy := CharacterBody3D.new()
			enemy.name = "DungeonEnemy_%04d" % enemy_serial
			enemy_serial += 1
			enemy.set_script(DUNGEON_ENEMY_SCRIPT)
			enemy.enemy_type = enemy_type
			enemy.home_center = center
			enemy.position = spawn_position
			add_child(enemy)

func _build_inside_lobby(rng: RandomNumberGenerator) -> void:
	var first_room_center := _room_position(0, level_rooms[0][0])
	# Align both visible wall planes (each sits 0.5 m inside its room bounds).
	inside_lobby_center = first_room_center + Vector3(inside_lobby_direction.x, 0, inside_lobby_direction.y) * 29.0
	_build_inside_lobby_surfaces()
	var exit_direction := -inside_lobby_direction
	for direction in DIRECTIONS:
		_build_inside_lobby_wall(direction, direction == exit_direction, rng)
	_build_inside_lobby_return_barrier(exit_direction)
	_add_ceiling_lamp(inside_lobby_center + Vector3(0, INSIDE_LOBBY_HEIGHT - 0.9, 0))
	add_to_group("dungeon_safe_state")

func _build_inside_lobby_return_barrier(exit_direction: Vector2i) -> void:
	var body := StaticBody3D.new()
	body.name = "InsideLobbyOneWayBarrier"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var horizontal := exit_direction.y != 0
	shape.size = Vector3(5.0, INSIDE_LOBBY_HEIGHT, 0.35) if horizontal else Vector3(0.35, INSIDE_LOBBY_HEIGHT, 5.0)
	shape_node.shape = shape
	shape_node.position = inside_lobby_center + Vector3(exit_direction.x, 0.0, exit_direction.y) * (INSIDE_LOBBY_SIZE * 0.5 - 0.25) + Vector3.UP * (INSIDE_LOBBY_HEIGHT * 0.5)
	shape_node.disabled = true
	body.add_child(shape_node)
	add_child(body)
	inside_lobby_return_barrier = shape_node

func _build_inside_lobby_surfaces() -> void:
	# Four clean 6x6 modules fit the 12x12 room without the heavily compressed
	# border pieces that broke the low-poly mesh. The doorway-side row ends at
	# the visible wall plane (5.5 m) instead of protruding through the lintel.
	var exit_axis := Vector3(-inside_lobby_direction.x, 0, -inside_lobby_direction.y)
	var sideways := Vector3(-exit_axis.z, 0, exit_axis.x)
	for front_value in [false, true]:
		var front: bool = front_value
		# Let the doorway-side row continue half a metre beneath the facade so
		# there is no visible void at the ceiling transition.
		var along: float = 3.0 if front else -3.0
		var along_scale: float = 1.5
		for side_value in [-1.0, 1.0]:
			var side: float = side_value
			var offset: Vector3 = exit_axis * along + sideways * side * 3.0
			var scale_: Vector3 = Vector3(along_scale, 1, 1.5) if absf(exit_axis.x) > 0.5 else Vector3(1.5, 1, along_scale)
			_add_inside_lobby_surface_piece(offset, scale_)
	_box(inside_lobby_center + Vector3(0, -0.12, 0), Vector3(12, 0.24, 12), stone_material, false)
	_box(inside_lobby_center + Vector3(0, INSIDE_LOBBY_HEIGHT, 0), Vector3(12, 0.18, 12), stone_material, false)

func _add_inside_lobby_surface_piece(offset: Vector3, scale_: Vector3) -> void:
	var position := inside_lobby_center + offset
	_asset_model("floor_tile_large.gltf.glb", position, Vector3.ZERO, scale_)
	_asset_model("floor_tile_large.gltf.glb", position + Vector3(0, INSIDE_LOBBY_HEIGHT - 0.08, 0), Vector3(180, 0, 0), scale_)

func _build_inside_lobby_wall(direction: Vector2i, doorway: bool, rng: RandomNumberGenerator) -> void:
	var horizontal := direction.y != 0
	var rotation_y := 0.0
	if direction == Vector2i.DOWN:
		rotation_y = 180.0
	elif direction == Vector2i.LEFT:
		rotation_y = 90.0
	elif direction == Vector2i.RIGHT:
		rotation_y = -90.0
	if doorway:
		# The aligned facade of the large room owns this shared wall and doorway.
		# Do not generate a second coplanar wall here, which would z-fight.
		return
	for offset in [-4.0, 0.0, 4.0]:
		var position := inside_lobby_center + Vector3(offset, 0, direction.y * 5.5) if horizontal else inside_lobby_center + Vector3(direction.x * 5.5, 0, offset)
		var asset := "wall_cracked.gltf.glb" if rng.randf() < 0.14 else "wall.gltf.glb"
		_asset_model(asset, position, Vector3(0, rotation_y, 0))
		var size := Vector3(4, INSIDE_LOBBY_HEIGHT, 0.8) if horizontal else Vector3(0.8, INSIDE_LOBBY_HEIGHT, 4)
		_box(position + Vector3.UP * (INSIDE_LOBBY_HEIGHT * 0.5), size, stone_material, false)
	# One uninterrupted collider backs the modular visuals and closes any tiny
	# gaps between their individual bounds.
	var wall_position := inside_lobby_center + Vector3(direction.x, 0, direction.y) * 5.5 + Vector3.UP * 2.0
	var wall_size := Vector3(12, INSIDE_LOBBY_HEIGHT, 2.2) if horizontal else Vector3(2.2, INSIDE_LOBBY_HEIGHT, 12)
	_box(wall_position, wall_size, stone_material, false)

func _build_room_surfaces(center: Vector3) -> void:
	for x in MODULE_OFFSETS:
		for z in MODULE_OFFSETS:
			_asset_model("floor_tile_large.gltf.glb", center + Vector3(x, 0, z), Vector3.ZERO, Vector3(2, 1, 2))
			_box(center + Vector3(x, -0.12, z), Vector3(8, 0.24, 8), stone_material, false)
			_asset_model("floor_tile_large.gltf.glb", center + Vector3(x, LEVEL_HEIGHT - 0.08, z), Vector3(180, 0, 0), Vector3(2, 1, 2))
			_box(center + Vector3(x, LEVEL_HEIGHT, z), Vector3(8, 0.18, 8), stone_material, false)

func _build_room_walls(center: Vector3, room: Vector2i, rooms: Array, rng: RandomNumberGenerator, incoming: Vector2i, outgoing: Vector2i) -> void:
	for direction in DIRECTIONS:
		var neighbour: Vector2i = room + direction
		var stair_door: bool = direction == incoming or direction == outgoing
		var inside_connection: bool = room == level_rooms[0][0] and direction == inside_lobby_direction
		if inside_connection:
			_build_inside_connection_facade(center, direction, rng)
		elif stair_door:
			_build_modular_wall(center, direction, true, rng)
		elif not rooms.has(neighbour):
			_build_modular_wall(center, direction, false, rng)
		elif direction == Vector2i.RIGHT or direction == Vector2i.DOWN:
			# A shared boundary is created once, never by both rooms.
			_build_modular_wall(center, direction, true, rng)

func _build_inside_connection_facade(center: Vector3, direction: Vector2i, rng: RandomNumberGenerator) -> void:
	var horizontal := direction.y != 0
	var rotation_y := 0.0
	if direction == Vector2i.DOWN:
		rotation_y = 180.0
	elif direction == Vector2i.LEFT:
		rotation_y = 90.0
	elif direction == Vector2i.RIGHT:
		rotation_y = -90.0
	var wall_center := center + Vector3(direction.x, 0, direction.y) * 23.5
	# Lower half: solid wall except for the true 8 x 4 metre doorway.
	for offset in [-20.0, -12.0, 12.0, 20.0]:
		var position := wall_center + (Vector3(offset, 0, 0) if horizontal else Vector3(0, 0, offset))
		var asset := "wall_cracked.gltf.glb" if rng.randf() < 0.14 else "wall.gltf.glb"
		_asset_model(asset, position, Vector3(0, rotation_y, 0), Vector3(2, 1, 1))
		var size := Vector3(8, 4, 0.8) if horizontal else Vector3(0.8, 4, 8)
		_box(position + Vector3.UP * 2.0, size, stone_material, false)
	for offset in [-6.0, 6.0]:
		var position := wall_center + (Vector3(offset, 0, 0) if horizontal else Vector3(0, 0, offset))
		_asset_model("wall.gltf.glb", position, Vector3(0, rotation_y, 0))
		var size := Vector3(4, 4, 0.8) if horizontal else Vector3(0.8, 4, 4)
		_box(position + Vector3.UP * 2.0, size, stone_material, false)
	# Upper half: a complete wall closes the space above the Inside Lobby.
	for offset in MODULE_OFFSETS:
		var position := wall_center + (Vector3(offset, 4, 0) if horizontal else Vector3(0, 4, offset))
		_asset_model("wall.gltf.glb", position, Vector3(0, rotation_y, 0), Vector3(2, 1, 1))
		var size := Vector3(8, 4, 0.8) if horizontal else Vector3(0.8, 4, 8)
		_box(position + Vector3.UP * 2.0, size, stone_material, false)
	# Continuous structural colliders: two solid sides around the doorway and a
	# complete lintel above it. Visual module borders can no longer be crossed.
	for side in [-1.0, 1.0]:
		var side_position := wall_center + (Vector3(side * 14.0, 2.0, 0) if horizontal else Vector3(0, 2.0, side * 14.0))
		var side_size := Vector3(20, 4, 2.2) if horizontal else Vector3(2.2, 4, 20)
		_box(side_position, side_size, stone_material, false)
	var lintel_position := wall_center + Vector3.UP * 6.0
	var lintel_size := Vector3(48, 4, 2.2) if horizontal else Vector3(2.2, 4, 48)
	_box(lintel_position, lintel_size, stone_material, false)
	_add_connection_door_pillars(wall_center, direction)

func _add_connection_door_pillars(wall_center: Vector3, direction: Vector2i) -> void:
	var horizontal := direction.y != 0
	for side in [-1.0, 1.0]:
		var position := wall_center
		position += Vector3(side * INSIDE_LOBBY_DOOR_WIDTH * 0.5, 0, 0) if horizontal else Vector3(0, 0, side * INSIDE_LOBBY_DOOR_WIDTH * 0.5)
		var rotation := Vector3(0, 0 if horizontal else 90, 0)
		_asset_model("wall_pillar.gltf.glb", position, rotation, Vector3(0.55, 1, 0.55))
		# Continue the jamb through the upper facade. Without this second module,
		# the raw side of the wall above the four-metre doorway is exposed as a
		# long black cut when viewed from either room.
		_asset_model("wall_pillar.gltf.glb", position + Vector3.UP * 4.0, rotation, Vector3(0.55, 1, 0.55))
		_box(position + Vector3.UP * 4.0, Vector3(2.0, 8, 2.0), stone_material, false)

func _build_modular_wall(center: Vector3, direction: Vector2i, doorway: bool, rng: RandomNumberGenerator) -> void:
	var horizontal := direction.y != 0
	var rotation_y := 0.0
	if direction == Vector2i.DOWN:
		rotation_y = 180.0
	elif direction == Vector2i.LEFT:
		rotation_y = 90.0
	elif direction == Vector2i.RIGHT:
		rotation_y = -90.0
	for offset in MODULE_OFFSETS:
		if doorway and absf(offset) < DOOR_WIDTH * 0.5:
			continue
		var position := center + Vector3(offset, 0, direction.y * 23.5) if horizontal else center + Vector3(direction.x * 23.5, 0, offset)
		var asset := "wall_cracked.gltf.glb" if rng.randf() < 0.14 else "wall.gltf.glb"
		_asset_model(asset, position, Vector3(0, rotation_y, 0), Vector3(2, 1, 1))
		_asset_model(asset, position + Vector3(0, 4, 0), Vector3(0, rotation_y, 0), Vector3(2, 1, 1))
		var size := Vector3(8, WALL_HEIGHT, 0.8) if horizontal else Vector3(0.8, WALL_HEIGHT, 8)
		_box(position + Vector3(0, WALL_HEIGHT * 0.5, 0), size, stone_material, false)
	if doorway:
		_add_doorway_pillars(center, direction)
		_add_continuous_door_collisions(center, direction)

func _add_doorway_pillars(center: Vector3, direction: Vector2i) -> void:
	var horizontal := direction.y != 0
	for side in [-1.0, 1.0]:
		var position := center + Vector3(direction.x, 0, direction.y) * 23.5
		position += Vector3(side * DOOR_WIDTH * 0.5, 0, 0) if horizontal else Vector3(0, 0, side * DOOR_WIDTH * 0.5)
		var rotation := Vector3(0, 0 if horizontal else 90, 0)
		_asset_model("wall_pillar.gltf.glb", position, rotation)
		_asset_model("wall_pillar.gltf.glb", position + Vector3(0, 4, 0), rotation)
		var jamb_size := Vector3(4.0, WALL_HEIGHT, 1.5) if horizontal else Vector3(1.5, WALL_HEIGHT, 4.0)
		_box(position + Vector3(0, WALL_HEIGHT * 0.5, 0), jamb_size, stone_material, false)

func _add_continuous_door_collisions(center: Vector3, direction: Vector2i) -> void:
	var horizontal := direction.y != 0
	var side_length := (ROOM_SIZE - DOOR_WIDTH) * 0.5
	var side_center := DOOR_WIDTH * 0.5 + side_length * 0.5
	for side in [-1.0, 1.0]:
		var position := center + Vector3(direction.x, 0, direction.y) * 23.5
		position += Vector3(side * side_center, 0, 0) if horizontal else Vector3(0, 0, side * side_center)
		var size := Vector3(side_length, WALL_HEIGHT, 1.4) if horizontal else Vector3(1.4, WALL_HEIGHT, side_length)
		_box(position + Vector3(0, WALL_HEIGHT * 0.5, 0), size, stone_material, false)

func _add_room_columns(center: Vector3) -> void:
	for x in [-16.0, 16.0]:
		for z in [-16.0, 16.0]:
			var position := center + Vector3(x, 0, z)
			_asset_model("pillar.gltf.glb", position, Vector3.ZERO, Vector3(1.25, 1, 1.25))
			_asset_model("pillar.gltf.glb", position + Vector3(0, 4, 0), Vector3.ZERO, Vector3(1.25, 1, 1.25))
			_box(position + Vector3(0, 4, 0), Vector3(1.8, 8, 1.8), stone_material, false)

func _add_ceiling_lamps(center: Vector3) -> void:
	for x in [-12.0, 12.0]:
		for z in [-12.0, 12.0]:
			_add_ceiling_lamp(center + Vector3(x, LEVEL_HEIGHT - 0.9, z))

func _add_ceiling_lamp(position_: Vector3) -> void:
	var fixture := Node3D.new()
	fixture.position = position_
	var chain := MeshInstance3D.new()
	var chain_mesh := CylinderMesh.new()
	chain_mesh.top_radius = 0.055
	chain_mesh.bottom_radius = 0.055
	chain_mesh.height = 0.7
	chain_mesh.radial_segments = 8
	chain_mesh.material = _material(Color("#28231f"))
	chain.mesh = chain_mesh
	chain.position.y = 0.35
	fixture.add_child(chain)
	var shade := MeshInstance3D.new()
	var shade_mesh := CylinderMesh.new()
	shade_mesh.top_radius = 0.16
	shade_mesh.bottom_radius = 0.72
	shade_mesh.height = 0.48
	shade_mesh.radial_segments = 12
	shade_mesh.material = _material(Color("#39332c"))
	shade.mesh = shade_mesh
	shade.position.y = -0.2
	fixture.add_child(shade)
	var glow := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.24
	glow_mesh.height = 0.42
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = Color("#ffd08a")
	glow_material.emission_enabled = true
	glow_material.emission = Color("#ff9b4a")
	glow_material.emission_energy_multiplier = 4.0
	glow_mesh.material = glow_material
	glow.mesh = glow_mesh
	glow.position.y = -0.52
	fixture.add_child(glow)
	var light := OmniLight3D.new()
	light.position.y = -0.7
	light.light_color = Color("#ffad62")
	light.light_energy = 2.2
	light.omni_range = 19.0
	light.shadow_enabled = false
	fixture.add_child(light)
	add_child(fixture)

func _build_stair_zone(lower_level: int, room: Vector2i, direction: Vector2i, rng: RandomNumberGenerator) -> void:
	var lower_room_center := _room_position(lower_level, level_rooms[lower_level][-1])
	var upper_room_center := _room_position(lower_level + 1, level_rooms[lower_level + 1][0])
	var center := Vector3(
		(lower_room_center.x + upper_room_center.x) * 0.5,
		lower_room_center.y,
		(lower_room_center.z + upper_room_center.z) * 0.5
	)
	_build_stair_flight(center, direction)
	_build_stair_tunnel(center, direction)

func _build_tall_stair_wall(center: Vector3, direction: Vector2i, rng: RandomNumberGenerator) -> void:
	var horizontal := direction.y != 0
	var rotation_y := 0.0 if direction == Vector2i.UP else 180.0 if direction == Vector2i.DOWN else 90.0 if direction == Vector2i.LEFT else -90.0
	for offset in MODULE_OFFSETS:
		var position := center + Vector3(offset, 0, direction.y * 23.5) if horizontal else center + Vector3(direction.x * 23.5, 0, offset)
		var asset := "wall_cracked.gltf.glb" if rng.randf() < 0.12 else "wall.gltf.glb"
		for row in range(4):
			_asset_model(asset, position + Vector3(0, row * 4.0, 0), Vector3(0, rotation_y, 0), Vector3(2, 1, 1))
		var size := Vector3(8, LEVEL_HEIGHT * 2.0, 0.8) if horizontal else Vector3(0.8, LEVEL_HEIGHT * 2.0, 8)
		_box(position + Vector3(0, LEVEL_HEIGHT, 0), size, stone_material, false)

func _build_stair_end_half(center: Vector3, direction: Vector2i, start_y: float, rng: RandomNumberGenerator) -> void:
	var horizontal := direction.y != 0
	var rotation_y := 0.0 if direction == Vector2i.UP else 180.0 if direction == Vector2i.DOWN else 90.0 if direction == Vector2i.LEFT else -90.0
	for offset in MODULE_OFFSETS:
		var position := center + Vector3(offset, start_y, direction.y * 23.5) if horizontal else center + Vector3(direction.x * 23.5, start_y, offset)
		var asset := "wall_cracked.gltf.glb" if rng.randf() < 0.12 else "wall.gltf.glb"
		_asset_model(asset, position, Vector3(0, rotation_y, 0), Vector3(2, 1, 1))
		_asset_model(asset, position + Vector3(0, 4, 0), Vector3(0, rotation_y, 0), Vector3(2, 1, 1))
		var size := Vector3(8, LEVEL_HEIGHT, 0.8) if horizontal else Vector3(0.8, LEVEL_HEIGHT, 8)
		_box(position + Vector3(0, LEVEL_HEIGHT * 0.5, 0), size, stone_material, false)

func _add_stair_zone_columns(center: Vector3) -> void:
	for x in [-20.0, 20.0]:
		for z in [-20.0, 20.0]:
			var position := center + Vector3(x, 0, z)
			for row in range(4):
				_asset_model("pillar.gltf.glb", position + Vector3(0, row * 4.0, 0))
			_box(position + Vector3(0, LEVEL_HEIGHT, 0), Vector3(1.5, LEVEL_HEIGHT * 2.0, 1.5), stone_material, false)

func _build_stair_flight(center: Vector3, direction: Vector2i) -> void:
	var run := STAIR_RUN + STAIR_OVERLAP * 2.0
	var step_count := 64
	var step_depth := run / step_count
	for step in range(step_count):
		# Half-step offsets make both transitions symmetrical: there is no tall
		# first riser when climbing and no raised lip when descending.
		var top_height := (step + 0.5) * (FLOOR_RISE / step_count)
		var along := -run * 0.5 + step_depth * (step + 0.5)
		var position := center + Vector3(direction.x * along, top_height * 0.5, direction.y * along)
		var size := Vector3(step_depth + 0.02, top_height, 12.0) if direction.x != 0 else Vector3(12.0, top_height, step_depth + 0.02)
		_box(position, size, stone_material, false)
		var surface_position := center + Vector3(direction.x * along, top_height, direction.y * along)
		_add_floor_panel(surface_position, direction, step_depth + 0.025, 12.0)
	_add_stair_ramp_collision(center, direction, run)

func _build_stair_tunnel(center: Vector3, direction: Vector2i) -> void:
	var run := STAIR_RUN + STAIR_OVERLAP * 2.0
	_add_single_sloped_side_walls(center, direction, run)
	_add_single_sloped_ceiling(center, direction, run)

func _add_single_sloped_side_walls(center: Vector3, direction: Vector2i, run: float) -> void:
	var forward := Vector3(direction.x, 0, direction.y)
	var perpendicular := Vector3(-direction.y, 0, direction.x)
	var basis := Basis(forward, Vector3.UP, perpendicular)
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var body := StaticBody3D.new()
		body.transform = Transform3D(basis, center + perpendicular * side * 6.15)
		var half_run := run * 0.5
		var half_thickness := 0.4
		# Stair-zone centers use the lower floor height (not the midpoint between
		# levels), so the wall must run from 0..8 metres at the lower entrance and
		# from 4..12 metres at the upper entrance.
		var low_bottom := 0.0
		var high_bottom := FLOOR_RISE
		var points := PackedVector3Array([
			Vector3(-half_run, low_bottom, -half_thickness),
			Vector3(-half_run, low_bottom, half_thickness),
			Vector3(-half_run, low_bottom + LEVEL_HEIGHT, -half_thickness),
			Vector3(-half_run, low_bottom + LEVEL_HEIGHT, half_thickness),
			Vector3(half_run, high_bottom, -half_thickness),
			Vector3(half_run, high_bottom, half_thickness),
			Vector3(half_run, high_bottom + LEVEL_HEIGHT, -half_thickness),
			Vector3(half_run, high_bottom + LEVEL_HEIGHT, half_thickness),
		])
		_add_original_sloped_wall_visual(body, side, run)
		var collision := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		collision.shape = shape
		body.add_child(collision)
		add_child(body)

func _add_original_sloped_wall_visual(body: StaticBody3D, side: float, run: float) -> void:
	# Shear the original dungeon wall instead of rotating it. Its horizontal
	# edges follow the stairs while its ends remain perfectly vertical.
	var visual_holder := Node3D.new()
	var slope := FLOOR_RISE / run
	var shear_basis := Basis(
		Vector3(1.0, slope, 0.0),
		Vector3.UP,
		Vector3.BACK
	)
	visual_holder.transform = Transform3D(shear_basis, Vector3.UP * (FLOOR_RISE * 0.5))
	body.add_child(visual_holder)
	var packed: PackedScene = packed_assets.get("wall.gltf.glb")
	if not packed:
		packed = load(ASSET_PATH + "wall.gltf.glb") as PackedScene
		packed_assets["wall.gltf.glb"] = packed
	var module_count := 6
	var module_length := run / module_count
	for module in range(module_count):
		var model := packed.instantiate() as Node3D
		model.position = Vector3(-run * 0.5 + module_length * (module + 0.5), 0, 0)
		model.rotation_degrees.y = 180.0 if side > 0.0 else 0.0
		model.scale = Vector3(module_length / 4.0, LEVEL_HEIGHT / 4.0, 1.0)
		visual_holder.add_child(model)

func _make_sloped_wall_mesh(points: PackedVector3Array, side: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	_append_wall_quad(vertices, normals, indices, points[0], points[4], points[6], points[2])
	_append_wall_quad(vertices, normals, indices, points[5], points[1], points[3], points[7])
	_append_wall_quad(vertices, normals, indices, points[2], points[6], points[7], points[3])
	_append_wall_quad(vertices, normals, indices, points[1], points[5], points[4], points[0])
	_append_wall_quad(vertices, normals, indices, points[1], points[0], points[2], points[3])
	_append_wall_quad(vertices, normals, indices, points[4], points[5], points[7], points[6])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, stone_material)
	return mesh

func _append_wall_quad(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var start := vertices.size()
	var normal := (b - a).cross(c - a).normalized()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	for unused in range(4):
		normals.append(normal)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))

func _add_single_sloped_ceiling(center: Vector3, direction: Vector2i, run: float) -> void:
	var angle := atan2(FLOOR_RISE, run)
	var slope_length := sqrt(run * run + FLOOR_RISE * FLOOR_RISE)
	var holder := StaticBody3D.new()
	var thickness := 0.3
	# Match the visible room-ceiling height exactly. Previously the collision's
	# half-thickness offset was also applied to the tiles, lifting them above the
	# horizontal ceiling and exposing a dark step at both transitions.
	holder.position = center + Vector3(0, LEVEL_HEIGHT + FLOOR_RISE * 0.5 - 0.08, 0)
	if direction.x != 0:
		holder.rotation.z = angle * direction.x
	else:
		holder.rotation.x = -angle * direction.y
	var packed: PackedScene = packed_assets.get("floor_tile_large.gltf.glb")
	if not packed:
		packed = load(ASSET_PATH + "floor_tile_large.gltf.glb") as PackedScene
		packed_assets["floor_tile_large.gltf.glb"] = packed
	# Room ceilings use this asset at scale 2 (an 8x8 module). Use that exact
	# scale here as well, rather than the smaller 1:1 pattern used previously.
	var module_count := 3
	var module_spacing := 8.08
	for module in range(module_count):
		var along := module_spacing * (module - 1)
		for lateral in [-4.0, 4.0]:
			var model := packed.instantiate() as Node3D
			model.position = Vector3(along, 0, lateral) if direction.x != 0 else Vector3(lateral, 0, along)
			model.rotation_degrees.x = 180.0
			# Only the first and last modules need a 2% extension along the
			# stair axis so their edge reaches the horizontal room ceiling.
			var along_scale := 2.04 if module != 1 else 2.0
			model.scale = Vector3(along_scale, 1.0, 2.0) if direction.x != 0 else Vector3(2.0, 1.0, along_scale)
			holder.add_child(model)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(slope_length, thickness, 12.7) if direction.x != 0 else Vector3(12.7, thickness, slope_length)
	collision.shape = shape
	# Keep the collider above the visible underside instead of lowering the
	# ceiling mesh into the stairwell.
	collision.position.y = thickness * 0.5
	holder.add_child(collision)
	add_child(holder)

func _add_floor_panel(position_: Vector3, direction: Vector2i, length: float, width: float, upside_down := false) -> void:
	var scale_ := Vector3(length / 4.0, 1.0, width / 4.0) if direction.x != 0 else Vector3(width / 4.0, 1.0, length / 4.0)
	_asset_model("floor_tile_large.gltf.glb", position_, Vector3(180.0, 0, 0) if upside_down else Vector3.ZERO, scale_)

func _add_stair_ramp_collision(center: Vector3, direction: Vector2i, run: float) -> void:
	var body := StaticBody3D.new()
	var angle := atan2(FLOOR_RISE, run)
	var ramp_thickness := 0.12
	# Place the upper face exactly at y=0 and y=LEVEL_HEIGHT. Previously it
	# protruded above the upper landing and blocked the player when going down.
	var top_offset := cos(angle) * ramp_thickness * 0.5
	body.position = center + Vector3(0, FLOOR_RISE * 0.5 - top_offset, 0)
	if direction.x != 0:
		body.rotation.z = angle * direction.x
	else:
		body.rotation.x = -angle * direction.y
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(sqrt(run * run + FLOOR_RISE * FLOOR_RISE), ramp_thickness, 11.8) if direction.x != 0 else Vector3(11.8, ramp_thickness, sqrt(run * run + FLOOR_RISE * FLOOR_RISE))
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _room_position(level: int, grid_position: Vector2i) -> Vector3:
	var offset := level_offsets[level] if level < level_offsets.size() else Vector2.ZERO
	return Vector3(grid_position.x * ROOM_SPACING + offset.x, level * FLOOR_RISE, grid_position.y * ROOM_SPACING + offset.y)

func _asset_model(file_name: String, position_: Vector3, rotation_degrees := Vector3.ZERO, scale_ := Vector3.ONE) -> Node3D:
	var packed: PackedScene = packed_assets.get(file_name)
	if not packed:
		packed = load(ASSET_PATH + file_name) as PackedScene
		if not packed:
			push_warning("Could not load dungeon asset: " + file_name)
			return null
		packed_assets[file_name] = packed
	var model := packed.instantiate() as Node3D
	model.position = position_
	model.rotation_degrees = rotation_degrees
	model.scale = scale_
	add_child(model)
	return model

func _box(position_: Vector3, size_: Vector3, material_: Material, visible_mesh := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position_
	if visible_mesh:
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size_
		mesh.material = material_
		mesh_instance.mesh = mesh
		body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	return material
