extends GutTest
## BowComponent aiming through the reticle with the over-the-shoulder camera offset.

const SHOULDER_OFFSET: float = 0.6
const TARGET_DISTANCE: float = 20.0

var _bow: BowComponent
var _camera: Camera3D
var _shooter: Node3D


func before_each() -> void:
	_shooter = Node3D.new()
	add_child_autofree(_shooter)
	_bow = BowComponent.new()
	_shooter.add_child(_bow)
	var data := BowData.new()
	data.aim_range = 60.0
	_bow.data = data
	_camera = Camera3D.new()
	_camera.current = true
	add_child_autofree(_camera)
	_camera.global_position = Vector3(0, 1.5, 5)


func _wall_at_reticle() -> StaticBody3D:
	# The wall is hit by the ray through the viewport centre; the x is where that is.
	var centre: Vector2 = _camera.get_viewport().get_visible_rect().size * 0.5
	var ray_from: Vector3 = _camera.project_ray_origin(centre)
	var point: Vector3 = ray_from + _camera.project_ray_normal(centre) * TARGET_DISTANCE
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 4, 0.2)
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = point
	return body


func test_aim_ray_uses_the_shoulder_offset() -> void:
	_camera.h_offset = SHOULDER_OFFSET
	var wall: StaticBody3D = _wall_at_reticle()
	await wait_physics_frames(2)
	var origin: Vector3 = Vector3(0, 1.0, 0)
	var direction: Vector3 = _bow.aim_direction(_shooter, origin, _camera, [])
	var expected: Vector3 = (wall.global_position - origin).normalized()
	# The offset wall sits off the camera's forward axis, so a forward-axis ray would miss.
	assert_gt(absf(wall.global_position.x), 0.3, "target is off-axis")
	assert_lt(direction.angle_to(expected), 0.01, "ray points at the reticle target")


func test_aim_without_camera_uses_the_shooter_facing() -> void:
	var direction: Vector3 = _bow.aim_direction(_shooter, Vector3.ZERO, null, [])
	assert_eq(direction, -_shooter.global_basis.z)
