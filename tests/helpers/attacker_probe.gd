class_name AttackerProbe
extends Area3D
## Stand-in attacker for i-frame tests: while `active`, every physics tick it hits
## every [HurtboxComponent] overlapping it. Card 5's HitboxComponent replaces this
## in gameplay; tests keep it so they do not depend on card 5 internals.

var active: bool = false
var damage: float = 10.0


func _init(size: Vector3 = Vector3(20, 4, 20)) -> void:
	collision_layer = 0
	collision_mask = 1 << 6
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)


func _physics_process(_delta: float) -> void:
	if not active:
		return
	for area: Area3D in get_overlapping_areas():
		var hurtbox := area as HurtboxComponent
		if hurtbox != null:
			hurtbox.receive_hit(damage, self)
