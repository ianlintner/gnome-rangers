@tool
extends EditorScenePostImport
## Project-wide post-import for Meshy humanoids: clip names, loop modes and the rim-light pass.
##
## Reads `import.json` next to the imported GLB (written by tools/meshy/meshy.py from the manifest):
##   clips: [{name, meshy_clip, loop, ...}]  `meshy_clip` is the name inside the GLB and `name`
##          the project name (`idle`, `walk`, `attack_light_1`, ...).
##   rim_light: true for dark actors; adds the shared rim-light next pass (PLAN art direction).

const RIM_PASS: String = "res://fx/materials/rim_light_pass.tres"


func _post_import(scene: Node) -> Object:
	var doc: Dictionary = _load_document(get_source_file().get_base_dir().path_join("import.json"))
	if doc.is_empty():
		push_warning("humanoid_post_import: no import.json for %s" % get_source_file())
		return scene
	for node: Node in scene.find_children("*", "AnimationPlayer", true, true):
		_rename_clips(node as AnimationPlayer, doc.get("clips", []))
	if doc.get("rim_light", false):
		_add_rim_light(scene)
	return scene


func _load_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _rename_clips(player: AnimationPlayer, clips: Array) -> void:
	var library: AnimationLibrary = player.get_animation_library(&"")
	if library == null:
		return
	for entry: Dictionary in clips:
		var source := StringName(String(entry["meshy_clip"]))
		var target := StringName(String(entry["name"]))
		if not library.has_animation(source):
			push_warning("humanoid_post_import: clip '%s' not in GLB" % source)
			continue
		if source != target:
			library.rename_animation(source, target)
		var anim: Animation = library.get_animation(target)
		anim.loop_mode = Animation.LOOP_LINEAR if entry.get("loop", false) else Animation.LOOP_NONE


func _add_rim_light(scene: Node) -> void:
	var rim := load(RIM_PASS) as Material
	for node: Node in scene.find_children("*", "MeshInstance3D", true, true):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null:
				material.next_pass = rim
