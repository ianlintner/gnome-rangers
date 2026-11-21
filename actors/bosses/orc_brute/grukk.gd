class_name Grukk
extends BossBase
## Grukk the Ironjaw: the first boss. All numbers and move choices live in `.tres`;
## this script only binds Grukk-specific presentation and the roar's player stagger.

@export_range(0.0, 20.0, 0.1) var roar_radius: float = 7.0
@export_range(0.0, 200.0, 1.0) var roar_poise_damage: float = 40.0
@export var roar_vfx_path: String = ""
@export var death_vfx_path: String = ""


func _ready() -> void:
	roar_started.connect(_on_roar_started)
	super._ready()


func _on_roar_started() -> void:
	if not roar_vfx_path.is_empty():
		var packed := load(roar_vfx_path) as PackedScene
		if packed != null:
			add_child(packed.instantiate())
	if target == null:
		return
	var delta: Vector3 = target.global_position - global_position
	delta.y = 0.0
	if delta.length() > roar_radius:
		return
	var player_poise: PoiseComponent = target.get_node_or_null("Poise") as PoiseComponent
	if player_poise != null:
		player_poise.take_poise_damage(roar_poise_damage)
