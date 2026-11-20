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
