extends SceneTree

const BASE := "res://addons/kaykit_character_pack_adventures/Characters/gltf/"
const FILES := [
	"Knight.glb", "Rogue_Hooded.glb", "Mage.glb", "Barbarian.glb"
]

func _initialize() -> void:
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
		instance.queue_free()
	quit()

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
