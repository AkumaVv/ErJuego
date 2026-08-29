extends Node3D

const STONE := Color("#59606b")
const DARK_STONE := Color("#353a43")
const FLOOR_STONE := Color("#454b55")
const KAYKIT := "res://addons/kaykit_dungeon_remastered/Assets/gltf/"
const ROOM_SIZE := 24.0
const WALL_HEIGHT := 8.0

func _ready() -> void:
	_build_asset_room()
	_place_asset_props()
	_place_asset_torches()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material

func _box(name_: String, position_: Vector3, size_: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name_
	body.position = position_
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_
	mesh.material = _material(color)
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body

func _torch(position_: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = position_
	light.light_color = color
	light.light_energy = 3.2
	light.omni_range = 8.0
	light.shadow_enabled = true
	add_child(light)
	var flame := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.32
	var glow := _material(color)
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 4.0
	mesh.material = glow
	flame.mesh = mesh
	flame.position = position_
	add_child(flame)

func _brick(position_: Vector3, size_: Vector3, shade: float) -> void:
	var brick := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_
	mesh.material = _material(STONE.lightened(shade))
	brick.mesh = mesh
	brick.position = position_
	add_child(brick)

func _brick_wall_z(z: float) -> void:
	for row in range(6):
		var offset := 1.0 if row % 2 else 0.0
		for column in range(-6, 7):
			var x := column * 2.0 + offset
			if absf(x) < 11.8:
				var shade := 0.035 if (row + column) % 3 == 0 else 0.0
				_brick(Vector3(x, 0.5 + row, z), Vector3(1.9, 0.9, 0.16), shade)

func _brick_wall_x(x: float) -> void:
	for row in range(6):
		var offset := 1.0 if row % 2 else 0.0
		for column in range(-6, 7):
			var z := column * 2.0 + offset
			if absf(z) < 11.8:
				var shade := 0.035 if (row + column) % 3 == 0 else 0.0
				_brick(Vector3(x, 0.5 + row, z), Vector3(0.16, 0.9, 1.9), shade)

func _model(file_name: String, position_: Vector3, rotation_y_degrees := 0.0, scale_ := 1.0) -> Node3D:
	var packed_scene := load(KAYKIT + file_name) as PackedScene
	if not packed_scene:
		push_warning("Could not load KayKit model: " + file_name)
		return null
	var model := packed_scene.instantiate() as Node3D
	model.position = position_
	model.rotation.y = deg_to_rad(rotation_y_degrees)
	model.scale = Vector3.ONE * scale_
	add_child(model)
	return model

func _decorate_with_kaykit() -> void:
	# Grupos de objetos que rompen la simetría de la sala y dan escala al espacio.
	_model("barrel_large.gltf.glb", Vector3(-9.4, 0.0, -8.8), 18.0)
	_model("barrel_small_stack.gltf.glb", Vector3(-8.1, 0.0, -9.1), -12.0)
	_model("box_stacked.gltf.glb", Vector3(8.7, 0.0, -8.7), 25.0)
	_model("box_small_decorated.gltf.glb", Vector3(7.5, 0.0, -9.4), -15.0)
	_model("torch_mounted.gltf.glb", Vector3(-7.0, 2.45, -11.35), 0.0)
	_model("torch_mounted.gltf.glb", Vector3(7.0, 2.45, -11.35), 0.0)

func _build_room() -> void:
	_box("Floor", Vector3(0, -0.5, 0), Vector3(24, 1, 24), FLOOR_STONE)
	_box("Ceiling", Vector3(0, 5.5, 0), Vector3(24, 1, 24), DARK_STONE)
	_box("NorthWall", Vector3(0, 2.5, -12), Vector3(24, 6, 1), STONE)
	_box("SouthWall", Vector3(0, 2.5, 12), Vector3(24, 6, 1), STONE)
	_box("WestWall", Vector3(-12, 2.5, 0), Vector3(1, 6, 24), STONE)
	_box("EastWall", Vector3(12, 2.5, 0), Vector3(1, 6, 24), STONE)

	# Revestimiento de ladrillos para una cámara de mazmorra clásica.
	_brick_wall_z(-11.48)
	_brick_wall_z(11.48)
	_brick_wall_x(-11.48)
	_brick_wall_x(11.48)
	for x in [-8.5, 8.5]:
		for z in [-8.5, 8.5]:
			_box("Pillar", Vector3(x, 2.0, z), Vector3(1.4, 4, 1.4), STONE.lightened(0.08))
	_torch(Vector3(-7.0, 3.0, -10.8), Color("#ff8a3d"))
	_torch(Vector3(7.0, 3.0, -10.8), Color("#ff8a3d"))
	_torch(Vector3(-7.0, 3.0, 10.8), Color("#ff8a3d"))
	_torch(Vector3(7.0, 3.0, 10.8), Color("#ff8a3d"))
	_decorate_with_kaykit()

func _asset_model(file_name: String, position_: Vector3, rotation_degrees := Vector3.ZERO, collision := false) -> Node3D:
	var packed_scene := load(KAYKIT + file_name) as PackedScene
	if not packed_scene:
		push_error("Could not load KayKit model: " + file_name)
		return null
	var model := packed_scene.instantiate() as Node3D
	model.position = position_
	model.rotation_degrees = rotation_degrees
	add_child(model)
	if collision:
		_add_asset_mesh_collisions(model)
	return model

func _add_asset_mesh_collisions(model: Node3D) -> void:
	if model is MeshInstance3D:
		(model as MeshInstance3D).create_trimesh_collision()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).create_trimesh_collision()

func _asset_box_collider(name_: String, position_: Vector3, size_: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = name_
	body.position = position_
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _build_asset_room() -> void:
	# Las piezas del pack miden 4x4 y forman una cuadrícula exacta de 24x24.
	for x in range(-10, 11, 4):
		for z in range(-10, 11, 4):
			_asset_model("floor_tile_large.gltf.glb", Vector3(x, 0.0, z))
			_asset_model("floor_tile_large.gltf.glb", Vector3(x, WALL_HEIGHT, z), Vector3(180.0, 0.0, 0.0))

	# Seis módulos de muro por lado, todos del pack y sin ladrillos provisionales.
	for offset in range(-10, 11, 4):
		var wall_asset := "wall_cracked.gltf.glb" if abs(offset) == 6 else "wall.gltf.glb"
		_asset_model(wall_asset, Vector3(offset, 0.0, -11.5))
		_asset_model(wall_asset, Vector3(offset, 4.0, -11.5))
		_asset_model(wall_asset, Vector3(offset, 0.0, 11.5), Vector3(0.0, 180.0, 0.0))
		_asset_model(wall_asset, Vector3(offset, 4.0, 11.5), Vector3(0.0, 180.0, 0.0))
		_asset_model(wall_asset, Vector3(-11.5, 0.0, offset), Vector3(0.0, 90.0, 0.0))
		_asset_model(wall_asset, Vector3(-11.5, 4.0, offset), Vector3(0.0, 90.0, 0.0))
		_asset_model(wall_asset, Vector3(11.5, 0.0, offset), Vector3(0.0, -90.0, 0.0))
		_asset_model(wall_asset, Vector3(11.5, 4.0, offset), Vector3(0.0, -90.0, 0.0))

	# Colisiones simples ajustadas a las medidas reales de suelo, techo y muros.
	_asset_box_collider("FloorCollision", Vector3(0.0, -0.10, 0.0), Vector3(ROOM_SIZE, 0.30, ROOM_SIZE))
	_asset_box_collider("CeilingCollision", Vector3(0.0, WALL_HEIGHT + 0.05, 0.0), Vector3(ROOM_SIZE, 0.20, ROOM_SIZE))
	_asset_box_collider("NorthWallCollision", Vector3(0.0, 2.0, -11.5), Vector3(ROOM_SIZE, WALL_HEIGHT, 1.0))
	_asset_box_collider("SouthWallCollision", Vector3(0.0, 2.0, 11.5), Vector3(ROOM_SIZE, WALL_HEIGHT, 1.0))
	_asset_box_collider("WestWallCollision", Vector3(-11.5, 2.0, 0.0), Vector3(1.0, WALL_HEIGHT, ROOM_SIZE))
	_asset_box_collider("EastWallCollision", Vector3(11.5, 2.0, 0.0), Vector3(1.0, WALL_HEIGHT, ROOM_SIZE))

	for x in [-8.0, 8.0]:
		for z in [-8.0, 8.0]:
			_asset_model("pillar.gltf.glb", Vector3(x, 0.0, z))
			_asset_model("pillar.gltf.glb", Vector3(x, 4.0, z))
			_asset_box_collider("PillarCollision", Vector3(x, 4.0, z), Vector3(1.5, 8.0, 1.5))

func _place_asset_props() -> void:
	# Objetos medidos y separados de las paredes y rutas de paso.
	_asset_model("barrel_large.gltf.glb", Vector3(-9.4, 0.05, -9.3), Vector3(0.0, 18.0, 0.0), true)
	_asset_model("barrel_small_stack.gltf.glb", Vector3(-7.5, 0.05, -9.0), Vector3(0.0, -12.0, 0.0), true)
	_asset_model("box_stacked.gltf.glb", Vector3(8.7, 0.05, -8.7), Vector3(0.0, 25.0, 0.0), true)

func _place_asset_torches() -> void:
	# El origen trasero del soporte queda pegado a la cara interior del muro.
	_asset_torch(Vector3(-6.0, 2.55, -10.99), Vector3.ZERO, Vector3(-6.0, 2.65, -10.40))
	_asset_torch(Vector3(6.0, 2.55, -10.99), Vector3.ZERO, Vector3(6.0, 2.65, -10.40))
	_asset_torch(Vector3(-6.0, 2.55, 10.99), Vector3(0.0, 180.0, 0.0), Vector3(-6.0, 2.65, 10.40))
	_asset_torch(Vector3(6.0, 2.55, 10.99), Vector3(0.0, 180.0, 0.0), Vector3(6.0, 2.65, 10.40))
	_asset_torch(Vector3(-10.99, 2.55, -4.0), Vector3(0.0, 90.0, 0.0), Vector3(-10.40, 2.65, -4.0))
	_asset_torch(Vector3(-10.99, 2.55, 4.0), Vector3(0.0, 90.0, 0.0), Vector3(-10.40, 2.65, 4.0))
	_asset_torch(Vector3(10.99, 2.55, -4.0), Vector3(0.0, -90.0, 0.0), Vector3(10.40, 2.65, -4.0))
	_asset_torch(Vector3(10.99, 2.55, 4.0), Vector3(0.0, -90.0, 0.0), Vector3(10.40, 2.65, 4.0))

func _asset_torch(model_position: Vector3, model_rotation: Vector3, light_position: Vector3) -> void:
	_asset_model("torch_mounted.gltf.glb", model_position, model_rotation)
	var light := OmniLight3D.new()
	light.position = light_position
	light.light_color = Color("#ff8a3d")
	light.light_energy = 3.0
	light.omni_range = 7.0
	# Stacked wall modules otherwise cast a hard horizontal seam across the lobby.
	light.shadow_enabled = false
	add_child(light)
