extends SceneTree

const BASE := "res://addons/kaykit_dungeon_remastered/Assets/gltf/"
const FILES := [
	"wall.gltf.glb", "wall_corner.gltf.glb", "wall_doorway.glb",
	"floor_tile_large.gltf.glb", "floor_tile_small.gltf.glb",
	"pillar.gltf.glb", "torch_mounted.gltf.glb", "chest.glb",
	"barrel_large.gltf.glb", "box_stacked.gltf.glb", "rubble_large.gltf.glb"
]

func _initialize() -> void:
	for file_name in FILES:
		var packed := load(BASE + file_name) as PackedScene
		if not packed:
			print(file_name, " LOAD_FAILED")
			continue
		var instance := packed.instantiate() as Node3D
		root.add_child(instance)
		var bounds := _bounds(instance)
		print(file_name, " | position=", bounds.position, " size=", bounds.size)
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
