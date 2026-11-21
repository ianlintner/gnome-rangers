extends GutTest
## Cat mount import: clip list, saddle bone, tail chain and the rim-light pass.

const CAT_SCENE: String = "res://assets/characters/cat_mount/cat_mount.glb"
const REQUIRED_CLIPS: Array[StringName] = [
	&"idle", &"walk", &"run", &"gallop", &"pounce", &"hit", &"flee", &"sit"
]
const MAX_TRIANGLES: int = 30000

var _cat: Node3D


func before_each() -> void:
	_cat = (load(CAT_SCENE) as PackedScene).instantiate() as Node3D
	add_child_autofree(_cat)


func test_required_clips_present_and_named() -> void:
	var player: AnimationPlayer = _cat.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_not_null(player, "cat has an AnimationPlayer")
	for clip: StringName in REQUIRED_CLIPS:
		assert_true(player.has_animation(clip), "clip %s" % clip)


func test_cycles_loop_and_one_shots_do_not() -> void:
	var player: AnimationPlayer = _cat.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip: StringName in [&"idle", &"walk", &"run", &"gallop", &"flee", &"sit"]:
		assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR, "%s loops" % clip)
	for clip: StringName in [&"pounce", &"hit"]:
		assert_eq(
			player.get_animation(clip).loop_mode, Animation.LOOP_NONE, "%s is one-shot" % clip
		)


func _bone_rotations(animation: Animation, bone: String, time: float) -> Quaternion:
	for track in animation.get_track_count():
		if (
			animation.track_get_type(track) == Animation.TYPE_ROTATION_3D
			and str(animation.track_get_path(track)).ends_with(":" + bone)
		):
			return animation.rotation_track_interpolate(track, time)
	fail_test("rotation track for %s" % bone)
	return Quaternion.IDENTITY


func test_loops_close_on_their_starting_pose() -> void:
	var player: AnimationPlayer = _cat.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var expected_seconds: Dictionary = {
		&"idle": 3.0, &"walk": 1.2, &"run": 0.8, &"gallop": 0.6, &"flee": 0.8, &"sit": 2.0
	}
	for clip: StringName in expected_seconds:
		var animation: Animation = player.get_animation(clip)
		assert_almost_eq(animation.length, float(expected_seconds[clip]), 0.04, "%s length" % clip)
		for bone: String in ["spine_02", "front_upper_l", "rear_shin_r", "tail_03"]:
			var start: Quaternion = _bone_rotations(animation, bone, 0.0)
			var end: Quaternion = _bone_rotations(animation, bone, animation.length)
			assert_lt(start.angle_to(end), 0.02, "%s %s closes its loop" % [clip, bone])


func test_sit_loop_stays_seated_and_sit_down_holds() -> void:
	var player: AnimationPlayer = _cat.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(player.has_animation(&"sit_down"), "sit_down transition clip")
	var sit: Animation = player.get_animation(&"sit")
	var down: Animation = player.get_animation(&"sit_down")
	assert_eq(down.loop_mode, Animation.LOOP_NONE, "sit_down is a one-shot")
	var standing: Quaternion = _bone_rotations(down, "rear_shin_l", 0.0)
	var seated: Quaternion = _bone_rotations(down, "rear_shin_l", down.length)
	assert_gt(standing.angle_to(seated), 0.5, "sit_down changes pose")
	for time: float in [0.0, sit.length * 0.5, sit.length]:
		var pose: Quaternion = _bone_rotations(sit, "rear_shin_l", time)
		assert_lt(pose.angle_to(seated), 0.05, "sit loop holds the seated pose at %.2fs" % time)


func test_saddle_bone_and_tail_chain() -> void:
	var skeleton: Skeleton3D = _cat.find_child("Skeleton3D", true, false) as Skeleton3D
	assert_not_null(skeleton, "cat has a Skeleton3D")
	assert_gt(skeleton.find_bone(&"saddle"), -1, "saddle socket bone")
	assert_gt(skeleton.find_bone(&"head"), -1, "head bone")
	assert_gt(skeleton.find_bone(&"jaw"), -1, "jaw bone")
	for paw: StringName in [&"front_paw_l", &"front_paw_r", &"rear_paw_l", &"rear_paw_r"]:
		assert_gt(skeleton.find_bone(paw), -1, "paw bone %s" % paw)
	var tail_bones: int = 0
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_name(index).begins_with("tail_"):
			tail_bones += 1
	assert_gte(tail_bones, 5, "tail chain has at least five bones")


func test_triangle_budget_and_rim_light() -> void:
	var triangles: int = 0
	for node: Node in _cat.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			assert_not_null(material.next_pass, "rim-light pass on surface %d" % surface)
	assert_lte(triangles, MAX_TRIANGLES, "hero triangle budget")
