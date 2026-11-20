extends SceneTree
## Prints the skeleton, clip list, triangle count, texture sizes and height of an imported model.
##
## Usage: godot --headless -s tools/inspect_asset.gd -- res://assets/characters/<name>/<name>.glb
## Exits non-zero when the model fails to load or has no skeleton / no clips.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("inspect_asset.gd: usage: -- <res://model.glb>")
		quit(2)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		push_error("inspect_asset.gd: cannot load %s" % args[0])
		quit(1)
		return
	var root: Node = packed.instantiate()
	root.name = "Inspected"
	get_root().add_child(root)
	var failed: bool = false
	print("== %s" % args[0])
	failed = _print_skeleton(root) or failed
	failed = _print_clips(root) or failed
	_print_meshes(root)
	quit(1 if failed else 0)


func _print_skeleton(root: Node) -> bool:
	var skeletons: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_error("inspect_asset.gd: no Skeleton3D")
		return true
	for node: Node in skeletons:
		var skeleton := node as Skeleton3D
		var names: PackedStringArray = []
		for i in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(i))
		print("skeleton %s: %d bones" % [root.get_path_to(skeleton), names.size()])
		print("  bones: %s" % ", ".join(names))
	return false


func _print_clips(root: Node) -> bool:
	var players: Array[Node] = root.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("inspect_asset.gd: no AnimationPlayer")
		return true
	var count: int = 0
	for node: Node in players:
		var player := node as AnimationPlayer
		for clip_name in player.get_animation_list():
			var anim: Animation = player.get_animation(clip_name)
			count += 1
			print(
				(
					"  clip %-16s %6.2fs  tracks=%-3d loop=%s"
					% [clip_name, anim.length, anim.get_track_count(), anim.loop_mode != 0]
				)
			)
	print("clips: %d" % count)
	return count == 0


func _print_meshes(root: Node) -> void:
	var tris: int = 0
	var top: float = -INF
	var bottom: float = INF
	var textures: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var inst := node as MeshInstance3D
		if inst.mesh == null:
			continue
		for s in inst.mesh.get_surface_count():
			var arrays: Array = inst.mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			tris += (indices.size() if not indices.is_empty() else verts.size()) / 3
			_collect_textures(inst.mesh.surface_get_material(s), textures)
		# Skinned meshes ignore their node transform; the skeleton pose places them.
		var box: AABB = inst.get_aabb()
		if inst.skin == null:
			box = _transform_to(root, inst) * box
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	print("triangles: %d" % tris)
	print("rest height (AABB y): %.3f .. %.3f m (%.3f m tall)" % [bottom, top, top - bottom])
	for tex_name: String in textures:
		var size: Vector2i = textures[tex_name]
		print("texture %-12s %dx%d" % [tex_name, size.x, size.y])


func _transform_to(root: Node, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null:
			result = spatial.transform * result
		current = current.get_parent()
	return result


func _collect_textures(material: Material, out: Dictionary) -> void:
	var std := material as BaseMaterial3D
	if std == null:
		return
	var slots: Dictionary = {
		"albedo": std.albedo_texture,
		"normal": std.normal_texture,
		"orm": std.orm_texture,
		"metallic": std.metallic_texture,
		"roughness": std.roughness_texture,
		"emission": std.emission_texture,
	}
	for slot_name: String in slots:
		var tex := slots[slot_name] as Texture2D
		if tex != null:
			out[slot_name] = Vector2i(tex.get_width(), tex.get_height())
