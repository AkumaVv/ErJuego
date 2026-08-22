extends StaticBody3D

var hit_count := 0
var reaction_tween: Tween

@onready var counter: Label3D = $Counter

func _ready() -> void:
	counter.text = "MUÑECO DE PRÁCTICA\nGolpes: 0 · Inmortal"

func receive_hit(_damage: int) -> void:
	hit_count += 1
	counter.text = "MUÑECO DE PRÁCTICA\nGolpes: %d · Inmortal" % hit_count
	if reaction_tween and reaction_tween.is_valid():
		reaction_tween.kill()
	scale = Vector3.ONE
	reaction_tween = create_tween()
	reaction_tween.set_trans(Tween.TRANS_BACK)
	reaction_tween.tween_property(self, "scale", Vector3(0.9, 1.08, 0.9), 0.07)
	reaction_tween.tween_property(self, "scale", Vector3.ONE, 0.16)
