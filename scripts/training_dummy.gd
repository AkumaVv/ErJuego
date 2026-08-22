extends StaticBody3D

var hit_count := 0
var reaction_tween: Tween
var last_hit_by_peer: Dictionary = {}

@onready var counter: Label3D = $Counter

func _ready() -> void:
	counter.text = "MUÑECO DE PRÁCTICA\nGolpes: 0 · Inmortal"

func receive_hit(_damage: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_hit.rpc_id(1, _damage)
		return
	_accept_hit(multiplayer.get_unique_id())

@rpc("any_peer", "call_remote", "reliable")
func _request_hit(_damage: int) -> void:
	if not multiplayer.is_server():
		return
	_accept_hit(multiplayer.get_remote_sender_id())

func _accept_hit(peer_id: int) -> void:
	var now := Time.get_ticks_msec()
	var previous := int(last_hit_by_peer.get(peer_id, -1000))
	if now - previous < 250:
		return
	last_hit_by_peer[peer_id] = now
	_register_hit()
	if multiplayer.has_multiplayer_peer():
		_sync_hits.rpc(hit_count)

@rpc("authority", "call_remote", "reliable")
func _sync_hits(total: int) -> void:
	hit_count = total
	_update_reaction()

func _register_hit() -> void:
	hit_count += 1
	_update_reaction()

func _update_reaction() -> void:
	counter.text = "MUÑECO DE PRÁCTICA\nGolpes: %d · Inmortal" % hit_count
	if reaction_tween and reaction_tween.is_valid():
		reaction_tween.kill()
	scale = Vector3.ONE
	reaction_tween = create_tween()
	reaction_tween.set_trans(Tween.TRANS_BACK)
	reaction_tween.tween_property(self, "scale", Vector3(0.9, 1.08, 0.9), 0.07)
	reaction_tween.tween_property(self, "scale", Vector3.ONE, 0.16)
