extends SceneTree
## Writes the SkeletonProfileHumanoid retarget settings into a GLB's `.import` sidecar.
##
## Meshy rigs use the Mixamo skeleton (`skeleton_template: mixamo`). This maps those bones to
## Godot's SkeletonProfileHumanoid (BoneMap) so every humanoid shares bone names and animation
## clips can be swapped between rigs, and it attaches the clip-naming post-import script.
##
## Usage (then re-run `godot --headless --import --path .`):
##   godot --headless -s tools/import/configure_humanoid_import.gd --path . -- \
##       res://assets/characters/gnome_ranger/gnome_ranger.glb [more.glb ...]

const POST_IMPORT_SCRIPT: String = "res://tools/import/humanoid_post_import.gd"
const SKELETON_NODE: String = "PATH:Armature/Skeleton3D"
const MIXAMO_PREFIX: String = "mixamorig_"

## SkeletonProfileHumanoid bone -> Mixamo bone (without prefix and side).
const CENTRE_BONES: Dictionary = {
	&"Hips": "Hips",
	&"Spine": "Spine",
	&"Chest": "Spine1",
	&"UpperChest": "Spine2",
	&"Neck": "Neck",
	&"Head": "Head",
}
const SIDED_BONES: Dictionary = {
	"Shoulder": "Shoulder",
	"UpperArm": "Arm",
	"LowerArm": "ForeArm",
	"Hand": "Hand",
	"UpperLeg": "UpLeg",
	"LowerLeg": "Leg",
	"Foot": "Foot",
	"Toes": "ToeBase",
}


func _initialize() -> void:
	var paths: PackedStringArray = OS.get_cmdline_user_args()
	if paths.is_empty():
		push_error("configure_humanoid_import.gd: usage: -- <res://model.glb> [...]")
		quit(2)
		return
	var failed: bool = false
	for path: String in paths:
		failed = not _configure(path) or failed
	quit(1 if failed else 0)


func _configure(glb_path: String) -> bool:
	var sidecar: String = glb_path + ".import"
	var config := ConfigFile.new()
	if config.load(sidecar) != OK:
		push_error("no %s; run `godot --headless --import --path .` first" % sidecar)
		return false
	var settings: Dictionary = {
		"nodes": {SKELETON_NODE: {"retarget/bone_map": _build_bone_map()}},
	}
	config.set_value("params", "_subresources", settings)
	config.set_value("params", "import_script/path", POST_IMPORT_SCRIPT)
	if config.save(sidecar) != OK:
		push_error("cannot write %s" % sidecar)
		return false
	print("configured %s" % sidecar)
	return true


func _build_bone_map() -> BoneMap:
	var bone_map := BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	for profile_bone: StringName in CENTRE_BONES:
		bone_map.set_skeleton_bone_name(
			profile_bone, MIXAMO_PREFIX + String(CENTRE_BONES[profile_bone])
		)
	for side: String in ["Left", "Right"]:
		for part: String in SIDED_BONES:
			var skeleton_bone: String = MIXAMO_PREFIX + side + String(SIDED_BONES[part])
			bone_map.set_skeleton_bone_name(StringName(side + part), StringName(skeleton_bone))
	return bone_map
