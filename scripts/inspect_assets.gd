extends SceneTree

const BASE := "res://addons/kaykit_character_pack_adventures/Characters/gltf/"
const FILES := [
	"Knight.glb", "Rogue_Hooded.glb", "Mage.glb", "Barbarian.glb"
]

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("skeleton-inspect"):
		await _inspect_character("res://addons/kaykit_character_pack_skeletons/addons/kaykit_character_pack_skeletons/Characters/gltf/Skeleton_Warrior.glb")
		quit()
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("ui-shot="):
			await _ui_shot(argument.trim_prefix("ui-shot="))
			quit()
			return
		if argument.begins_with("fp-shot="):
			await _first_person_shot(int(argument.trim_prefix("fp-shot=")))
			quit()
			return
		if argument.begins_with("f3-shot="):
			await _first_person_shot(int(argument.trim_prefix("f3-shot=")), true)
			quit()
			return
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

func _ui_shot(window_name: String) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.players[1] = 0
	main.player_names[1] = "VisualTest"
	main._spawn_player(1, 0, "VisualTest")
	await process_frame
	if window_name == "both":
		main._toggle_game_window("character")
		main._toggle_game_window("inventory")
	else:
		main._toggle_game_window(window_name)
	for frame in range(8):
		await process_frame
	var image := root.get_texture().get_image()
	var path := "res://.godot/ui_%s.png" % window_name
	image.save_png(path)

func _inspect_character(path: String) -> void:
	var packed := load(path) as PackedScene
	var instance := packed.instantiate() as Node3D
	root.add_child(instance)
	await process_frame
	for animation_node in instance.find_children("*", "AnimationPlayer", true, false):
		print("SKELETON_ANIMATIONS=", (animation_node as AnimationPlayer).get_animation_list())
	var meshes: Array[String] = []
	for mesh_node in instance.find_children("*", "MeshInstance3D", true, false):
		meshes.append(str(mesh_node.name))
	print("SKELETON_MESHES=", meshes)

func _first_person_shot(character_index: int, third_person := false) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.players[1] = character_index
	main.player_names[1] = "VisualTest"
	main._spawn_player(1, character_index, "VisualTest")
	for frame in range(12):
		await process_frame
	var player := main.get_node("Player_1")
	player._set_camera_mode(third_person)
	if character_index == 0:
		player._set_blocking(true)
	else:
		player._update_movement_animation(0.0)
	for frame in range(8):
		await process_frame
	var image := root.get_texture().get_image()
	var path := "res://.godot/%s_class_%d.png" % ["f3" if third_person else "fp", character_index]
	var error := image.save_png(path)
	print("FP_SHOT class=", character_index, " path=", path, " size=", image.get_size(), " error=", error)

func _class_smoke_test() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.players[1] = 3
	main.player_names[1] = "SmokeTest"
	main._spawn_player(1, 3, "SmokeTest")
	await process_frame
	await process_frame
	var player := main.get_node("Player_1")
	var skeleton_enemy := main.get_node("TrainingDummy")
	var ally_dummy := main.get_node("TrainingAlly")
	player.character_class = 0
	player.health = 100
	player.blocking = true
	player.receive_damage(20, "physical")
	player.receive_damage(20, "magic")
	print("KNIGHT_BLOCK_HEALTH_EXPECTED_89=", player.health)
	player.blocking = false
	ally_dummy.health = 699
	ally_dummy.seconds_since_damage = 5.0
	ally_dummy.regen_accumulator = 0.99
	await create_timer(0.05).timeout
	print("ALLY_REGEN_HEALTH=", ally_dummy.health)
	player.health = 100
	player.global_position = skeleton_enemy.global_position + Vector3(1.5, 0.0, 0.0)
	skeleton_enemy.receive_hit(1)
	await create_timer(0.7).timeout
	print("SKELETON_COUNTERATTACK_NEAR_HEALTH=", player.health)
	player.health = player.max_health
	player._update_health_ui()
	player.global_position = skeleton_enemy.global_position + Vector3(0.0, 0.0, 3.0)
	skeleton_enemy.receive_hit(1)
	await create_timer(0.7).timeout
	print("SKELETON_COUNTERATTACK_FAR_HEALTH=", player.health)
	player.global_position = skeleton_enemy.global_position + Vector3(0.0, 0.0, 1.5)
	skeleton_enemy.cycle_combat_mode()
	skeleton_enemy.receive_hit(1)
	await create_timer(0.7).timeout
	print("SKELETON_COUNTERATTACK_DISABLED_HEALTH=", player.health)
	skeleton_enemy.combat_mode = 2
	player.health = 100
	await create_timer(0.7).timeout
	print("SKELETON_AGGRESSIVE_HEALTH=", player.health)
	var enemy_two := main.get_node("TrainingEnemy2")
	var enemy_two_test_position: Vector3 = enemy_two.global_position
	skeleton_enemy.combat_mode = 1
	enemy_two.combat_mode = 1
	player.global_position = Vector3(0.0, 1.05, 7.0)
	player.rotation.y = 0.0
	enemy_two.global_position = Vector3(0.0, 0.05, 4.5)
	await physics_frame
	player.character_class = 1
	player.attack_in_progress = false
	player.secondary_cooldown_ends_at = 0.0
	skeleton_enemy.health = 1000
	enemy_two.health = 1000
	player._rogue_double_piercing()
	await create_timer(0.8).timeout
	print("ROGUE_DOUBLE_PIERCE_HEALTHS=", enemy_two.health, ",", skeleton_enemy.health)
	enemy_two.global_position = enemy_two_test_position
	player.character_class = 2
	player.attack_in_progress = false
	player.secondary_cooldown_ends_at = 0.0
	player.health = 90
	ally_dummy.health = 699
	ally_dummy.seconds_since_damage = 0.0
	ally_dummy.regen_accumulator = 0.0
	skeleton_enemy.health = 1000
	enemy_two.health = 1000
	player._mage_chain()
	await create_timer(0.9).timeout
	print("MAGE_CHAIN_ENEMIES_ALLIES=", enemy_two.health, ",", skeleton_enemy.health, ",", ally_dummy.health, ",", player.health)
	player.character_class = 3
	player.attack_in_progress = false
	player.secondary_cooldown_ends_at = 0.0
	player.global_position = Vector3(0.0, 1.05, 5.5)
	skeleton_enemy.health = 1000
	enemy_two.health = 1000
	player._whirlwind()
	await create_timer(1.0).timeout
	print("BARBARIAN_TRIPLE_AREA_HEALTHS=", enemy_two.health, ",", skeleton_enemy.health)
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
