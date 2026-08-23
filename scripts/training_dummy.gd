extends StaticBody3D

const WARRIOR_PATH := "res://addons/kaykit_character_pack_skeletons/addons/kaykit_character_pack_skeletons/Characters/gltf/Skeleton_Warrior.glb"
const BLADE_PATH := "res://addons/kaykit_character_pack_skeletons/addons/kaykit_character_pack_skeletons/Assets/gltf/Skeleton_Blade.gltf"
const MAX_HEALTH := 1000
const ATTACK_RANGE := 2.0
const REGEN_DELAY := 5.0
const REGEN_PER_SECOND := 100.0

@export var target_title := "SKELETON WARRIOR"
@export var is_ally := false
@export_enum("Contraataque", "Pasivo", "Agresivo") var combat_mode := 0
@export_range(1, MAX_HEALTH) var starting_health := MAX_HEALTH

var hit_count := 0
var health := MAX_HEALTH
var regen_accumulator := 0.0
var seconds_since_damage := 0.0
var last_hit_by_peer: Dictionary = {}
var animation_player: AnimationPlayer
var counterattacking := false
var health_sprite: Sprite3D
var health_text: Label3D

@onready var counter: Label3D = $Counter

func _ready() -> void:
	health = clampi(starting_health, 1, MAX_HEALTH)
	if is_ally:
		add_to_group("chain_allies")
	else:
		add_to_group("damageable")
		add_to_group("counterattack_targets")
	_setup_skeleton()
	_setup_health_bar()
	_update_counter()

func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if not is_ally and combat_mode == 2:
		_try_aggressive_attack()
	if health >= MAX_HEALTH:
		return
	seconds_since_damage += delta
	if seconds_since_damage < REGEN_DELAY:
		return
	regen_accumulator += delta
	if regen_accumulator < 1.0:
		return
	regen_accumulator -= 1.0
	var regenerated := mini(int(REGEN_PER_SECOND), MAX_HEALTH - health)
	health = mini(MAX_HEALTH, health + regenerated)
	_update_health_bar()
	_spawn_floating_number(regenerated, true)
	if multiplayer.has_multiplayer_peer():
		_sync_health.rpc(health)

func _setup_health_bar() -> void:
	health_sprite = Sprite3D.new()
	health_sprite.position = Vector3(0.0, 2.62, 0.0)
	health_sprite.pixel_size = 0.0045
	health_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_sprite.no_depth_test = true
	add_child(health_sprite)
	health_text = Label3D.new()
	health_text.position = Vector3(0.0, 2.62, 0.01)
	health_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_text.no_depth_test = true
	health_text.font_size = 24
	health_text.outline_size = 6
	health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(health_text)
	_update_health_bar()

func _update_health_bar() -> void:
	if not health_sprite or not health_text:
		return
	var image := Image.create(256, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.10, 0.01, 0.015, 0.96))
	var fill_width := int(252.0 * float(health) / float(MAX_HEALTH))
	if fill_width > 0:
		image.fill_rect(Rect2i(2, 2, fill_width, 20), Color(0.80, 0.035, 0.05, 1.0))
	health_sprite.texture = ImageTexture.create_from_image(image)
	health_text.text = "%d/%d" % [health, MAX_HEALTH]

func _setup_skeleton() -> void:
	var packed := load(WARRIOR_PATH) as PackedScene
	if not packed:
		push_error("Could not load the Skeleton Warrior")
		return
	var model := packed.instantiate() as Node3D
	model.name = "SkeletonWarriorModel"
	model.scale = Vector3.ONE * 0.78
	add_child(model)
	var animation_players := model.find_children("*", "AnimationPlayer", true, false)
	if not animation_players.is_empty():
		animation_player = animation_players[0] as AnimationPlayer
		_play_animation("Idle_Combat")
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "handslot.r"
		(skeletons[0] as Skeleton3D).add_child(attachment)
		var blade_scene := load(BLADE_PATH) as PackedScene
		if blade_scene:
			attachment.add_child(blade_scene.instantiate())

func _play_animation(animation_name: String, speed := 1.0) -> void:
	if animation_player and animation_player.has_animation(animation_name):
		animation_player.speed_scale = speed
		animation_player.play(animation_name, 0.12)

func receive_hit(_damage: int) -> void:
	if is_ally:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_hit.rpc_id(1, _damage)
		return
	_accept_hit(multiplayer.get_unique_id(), _damage)

@rpc("any_peer", "call_remote", "reliable")
func _request_hit(_damage: int) -> void:
	if not multiplayer.is_server():
		return
	_accept_hit(multiplayer.get_remote_sender_id(), _damage)

func _accept_hit(peer_id: int, damage: int) -> void:
	var now := Time.get_ticks_msec()
	var previous := int(last_hit_by_peer.get(peer_id, -1000))
	if now - previous < 250:
		return
	last_hit_by_peer[peer_id] = now
	_register_hit(damage)
	if multiplayer.has_multiplayer_peer():
		_sync_hits.rpc(hit_count, health)
	if combat_mode == 0:
		_start_counterattack(peer_id)

@rpc("authority", "call_remote", "reliable")
func _sync_hits(total: int, current_health: int) -> void:
	var damage_received := maxi(0, health - current_health)
	hit_count = total
	health = current_health
	_update_counter()
	_update_health_bar()
	_play_animation("Hit_A")
	if damage_received > 0:
		_spawn_floating_number(damage_received, false)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_health(current_health: int) -> void:
	var restored := maxi(0, current_health - health)
	health = current_health
	_update_health_bar()
	if restored > 0:
		_spawn_floating_number(restored, true)

func _register_hit(damage: int) -> void:
	hit_count += 1
	var damage_received := mini(health, maxi(0, damage))
	health -= damage_received
	seconds_since_damage = 0.0
	regen_accumulator = 0.0
	_update_counter()
	_update_health_bar()
	_play_animation("Hit_A")
	if damage_received > 0:
		_spawn_floating_number(damage_received, false)

func _update_counter() -> void:
	if is_ally:
		counter.text = "%s\nALLY" % target_title
	else:
		var mode_names := ["COUNTERATTACK", "PASSIVE", "AGGRESSIVE"]
		counter.text = "%s\nHits: %d · Mode: %s" % [target_title, hit_count, mode_names[combat_mode]]

func is_chain_ally() -> bool:
	return is_ally

func receive_chain_healing(amount: int) -> void:
	if not is_ally or amount <= 0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_healing.rpc_id(1, amount)
		return
	_apply_healing(amount)

@rpc("any_peer", "call_remote", "reliable")
func _request_healing(amount: int) -> void:
	if multiplayer.is_server():
		_apply_healing(amount)

func _apply_healing(amount: int) -> void:
	var restored := mini(amount, MAX_HEALTH - health)
	if restored <= 0:
		return
	health += restored
	_update_health_bar()
	_spawn_floating_number(restored, true)
	if multiplayer.has_multiplayer_peer():
		_sync_health.rpc(health)

func _spawn_floating_number(amount: int, healing: bool) -> void:
	var label := Label3D.new()
	label.text = ("+" if healing else "-") + str(amount)
	label.modulate = Color(0.20, 1.0, 0.30) if healing else Color(1.0, 0.10, 0.08)
	label.font_size = 44
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	get_parent().add_child(label)
	label.global_position = global_position + Vector3(0.0, 2.35, 0.0)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(0.0, 0.9, 0.0), 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9)
	tween.chain().tween_callback(label.queue_free)

func receive_knockback(origin: Vector3, force: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_knockback.rpc_id(1, origin, force)
		return
	_apply_knockback(origin, force)

@rpc("any_peer", "call_remote", "reliable")
func _request_knockback(origin: Vector3, force: float) -> void:
	if multiplayer.is_server():
		_apply_knockback(origin, force)

func _apply_knockback(origin: Vector3, force: float) -> void:
	var direction := global_position - origin
	direction.y = 0.0
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	var target_position := global_position + direction.normalized() * force
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target_position, 0.16)
	if multiplayer.has_multiplayer_peer():
		_sync_knockback.rpc(target_position)

@rpc("authority", "call_remote", "reliable")
func _sync_knockback(target_position: Vector3) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target_position, 0.16)

func cycle_combat_mode() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_cycle_combat_mode.rpc_id(1)
		return
	_set_combat_mode((combat_mode + 1) % 3)

@rpc("any_peer", "call_remote", "reliable")
func _request_cycle_combat_mode() -> void:
	if multiplayer.is_server():
		_set_combat_mode((combat_mode + 1) % 3)

func _set_combat_mode(mode: int) -> void:
	combat_mode = clampi(mode, 0, 2)
	_update_counter()
	if multiplayer.has_multiplayer_peer():
		_sync_combat_mode.rpc(combat_mode)

@rpc("authority", "call_remote", "reliable")
func _sync_combat_mode(mode: int) -> void:
	combat_mode = clampi(mode, 0, 2)
	_update_counter()

func _try_aggressive_attack() -> void:
	if counterattacking:
		return
	var nearest_player: Node3D
	var nearest_distance := ATTACK_RANGE + 0.001
	for candidate in get_tree().get_nodes_in_group("chain_allies"):
		if candidate is Node3D and str(candidate.name).begins_with("Player_"):
			var candidate_position := Vector2((candidate as Node3D).global_position.x, (candidate as Node3D).global_position.z)
			var own_position := Vector2(global_position.x, global_position.z)
			var distance := own_position.distance_to(candidate_position)
			if distance <= ATTACK_RANGE and distance < nearest_distance:
				nearest_distance = distance
				nearest_player = candidate as Node3D
	if nearest_player:
		_start_counterattack(nearest_player.get_multiplayer_authority())

func _start_counterattack(peer_id: int) -> void:
	if counterattacking or combat_mode == 1:
		return
	counterattacking = true
	_play_counterattack()
	if multiplayer.has_multiplayer_peer():
		_play_counterattack_remote.rpc()
	await get_tree().create_timer(0.28).timeout
	_damage_player(peer_id, 10)
	await get_tree().create_timer(0.34).timeout
	counterattacking = false
	_play_animation("Idle_Combat")

@rpc("authority", "call_remote", "reliable")
func _play_counterattack_remote() -> void:
	_play_counterattack()

func _play_counterattack() -> void:
	_play_animation("1H_Melee_Attack_Slice_Horizontal", 1.35)

func _damage_player(peer_id: int, amount: int) -> void:
	if combat_mode == 1:
		return
	var player := get_parent().get_node_or_null("Player_%d" % peer_id)
	if not player:
		return
	var enemy_horizontal := Vector2(global_position.x, global_position.z)
	var player_horizontal := Vector2(player.global_position.x, player.global_position.z)
	if enemy_horizontal.distance_to(player_horizontal) > ATTACK_RANGE:
		return
	if peer_id == multiplayer.get_unique_id() or not multiplayer.has_multiplayer_peer():
		player.receive_damage(amount, "physical")
	else:
		player.receive_server_damage.rpc_id(peer_id, amount, "physical")
