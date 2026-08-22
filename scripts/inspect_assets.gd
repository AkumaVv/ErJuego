extends SceneTree

const BASE := "res://addons/kaykit_character_pack_adventures/Characters/gltf/"
const FILES := [
	"Knight.glb", "Rogue_Hooded.glb", "Mage.glb", "Barbarian.glb"
]

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("class-smoke"):
		await _class_smoke_test()
		quit()
		return
	for file_name in FILES:
		var packed := load(BASE + file_name) as PackedScene
		if not packed:
			print(file_name, " LOAD_FAILED")
			continue
		var instance := packed.instantiate() as Node3D
		root.add_child(instance)
		await process_frame
		var bounds := _bounds(instance)
		print(file_name, " | position=", bounds.position, " size=", bounds.size)
		for animation_player in instance.find_children("*", "AnimationPlayer", true, false):
			print("  animations=", (animation_player as AnimationPlayer).get_animation_list())
		for skeleton_node in instance.find_children("*", "Skeleton3D", true, false):
			var skeleton := skeleton_node as Skeleton3D
			var bones: Array[String] = []
			for bone in range(skeleton.get_bone_count()):
				bones.append(skeleton.get_bone_name(bone))
			print("  bones=", bones)
		var meshes: Array[String] = []
		for mesh_node in instance.find_children("*", "MeshInstance3D", true, false):
			meshes.append((mesh_node as MeshInstance3D).name)
		print("  meshes=", meshes)
		instance.queue_free()
	quit()

func _class_smoke_test() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.character_select.select(3)
	main.name_input.text = "SmokeTest"
	main._on_host_pressed()
	await process_frame
	await process_frame
	var player := main.get_node("Player_1")
	player._attack()
	await create_timer(0.4).timeout
	player._whirlwind()
	await create_timer(0.9).timeout
	player.character_class = 0
	player._set_blocking(true)
	player._set_blocking(false)
	player.character_class = 1
	player._shoot_crossbow()
	await create_timer(0.7).timeout
	player.character_class = 2
	player._cast_magic_ray()
	await create_timer(0.6).timeout

func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var transformed := mesh_instance.global_transform * mesh_instance.get_aabb()
		if found:
			result = result.merge(transformed)
		else:
			result = transformed
			found = true
	return result
