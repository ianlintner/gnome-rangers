extends Node
## Generates `levels/rootfall_hollow/rootfall_hollow.tscn`, `checkpoint.tscn` and the baked
## navigation mesh from [RootfallLayout] and the imported props.
##
## Usage (needs the props imported first; no display required):
##   godot --headless --import --path .
##   godot --headless --path . res://tools/level/build_rootfall.tscn
##
## The output is committed. Re-run it after changing the layout or the props, then re-run the
## tests. Placement is seeded, so the same inputs give the same level.

const LEVEL_SCENE: String = "res://levels/rootfall_hollow/rootfall_hollow.tscn"
const CHECKPOINT_SCENE: String = "res://levels/checkpoint/checkpoint.tscn"
const FOG_GATE_SCENE: String = "res://levels/rootfall_hollow/fog_gate.tscn"
const NAVMESH_PATH: String = "res://levels/rootfall_hollow/navmesh.res"
const ENVIRONMENT_PATH: String = "res://fx/environment/forest_day.tres"
const TEXTURES: String = "res://assets/textures/%s/%s_%s.jpg"

## Direction the sun's light travels: steep, toward +Z so the player looks into the beams.
const SUN_DIRECTION := RootfallCanopy.SUN_DIRECTION

var _factory := PropFactory.new()


func _ready() -> void:
	_build_checkpoint()
	var level: Node3D = _build_level()
	add_child(level)
	await get_tree().process_frame
	_bake_navigation(level)
	var packed := PackedScene.new()
	if packed.pack(level) != OK or ResourceSaver.save(packed, LEVEL_SCENE) != OK:
		push_error("build_rootfall: failed to save %s" % LEVEL_SCENE)
		get_tree().quit(1)
		return
	print("build_rootfall: wrote %s" % LEVEL_SCENE)
	get_tree().quit(0)


func _build_checkpoint() -> void:
	var checkpoint := Node3D.new()
	checkpoint.name = "Checkpoint"
	checkpoint.set_script(load("res://levels/checkpoint/checkpoint.gd"))
	var ring: StaticBody3D = _factory.make_body(
		"mushroom_ring", "Ring", Vector3.ZERO, 0.0, PropFactory.Collision.NONE
	)
	checkpoint.add_child(ring)
	var interactable := Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt_text = "Rest"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var sphere := SphereShape3D.new()
	sphere.radius = 3.2
	shape.shape = sphere
	shape.position.y = 0.8
	interactable.add_child(shape)
	checkpoint.add_child(interactable)
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.position.y = 1.2
	glow.light_color = Color(1.0, 0.86, 0.6)
	glow.light_energy = 0.6
	glow.omni_range = 7.0
	checkpoint.add_child(glow)
	_own_all(checkpoint, checkpoint)
	var packed := PackedScene.new()
	packed.pack(checkpoint)
	ResourceSaver.save(packed, CHECKPOINT_SCENE)
	checkpoint.free()
	print("build_rootfall: wrote %s" % CHECKPOINT_SCENE)


func _build_level() -> Node3D:
	var level := Node3D.new()
	level.name = "RootfallHollow"
	level.set_script(load("res://levels/rootfall_hollow/rootfall_hollow.gd"))
	_add_environment(level)
	_add_ground(level)
	RootfallCanopy.add_to(level)
	var props := Node3D.new()
	props.name = "Props"
	level.add_child(props)
	props.owner = level
	RootfallProps.new(_factory).populate(props, level)
	_add_arena_wall(level)
	_add_decals(level)
	_add_foliage(level)
	_add_markers(level)
	_add_gate(level)
	var audio := AudioStreamPlayer.new()
	audio.name = "AmbientLoop"
	audio.stream = load("res://assets/audio/forest_ambient_loop.wav") as AudioStream
	audio.autoplay = true
	audio.volume_db = -14.0
	_attach(level, audio)
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	_attach(level, region)
	return level


func _attach(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = parent if parent.owner == null else parent.owner


func _own_all(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		if child.scene_file_path.is_empty():
			_own_all(child, owner_node)


func _add_environment(level: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = load(ENVIRONMENT_PATH) as Environment
	_attach(level, world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 3.0
	sun.light_volumetric_fog_energy = 4.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_split_1 = 0.2
	_attach(level, sun)
	sun.look_at_from_position(
		Vector3(0.0, 40.0, 0.0), SUN_DIRECTION * 10.0 + Vector3(0.0, 40.0, 0.0)
	)


func _ground_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var id: String = "forrest_ground_01"
	material.albedo_texture = load(TEXTURES % [id, id, "Diffuse"]) as Texture2D
	material.albedo_color = Color(0.8, 0.74, 0.62)
	material.normal_enabled = true
	material.normal_texture = load(TEXTURES % [id, id, "nor_gl"]) as Texture2D
	material.roughness_texture = load(TEXTURES % [id, id, "Rough"]) as Texture2D
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.18
	return material


func _add_ground(level: Node3D) -> void:
	var rect: Rect2 = RootfallLayout.GROUND_RECT
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	_attach(level, ground)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = rect.size
	plane.material = _ground_material()
	mesh_instance.mesh = plane
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.add_child(mesh_instance)
	mesh_instance.owner = level
	mesh_instance.position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, 0.4, rect.size.y)
	shape.shape = box
	shape.position = Vector3(rect.get_center().x, -0.2, rect.get_center().y)
	ground.add_child(shape)
	shape.owner = level


func _add_arena_wall(level: Node3D) -> void:
	var wall := StaticBody3D.new()
	wall.name = "ArenaWall"
	_attach(level, wall)
	var segments: int = 36
	var radius: float = RootfallLayout.ARENA_RADIUS + 1.6
	var gate_angle: float = RootfallLayout.GATE_HALF_WIDTH / radius
	for i: int in range(segments):
		var theta: float = float(i) / float(segments) * TAU
		if absf(wrapf(theta, -PI, PI)) < gate_angle:
			continue
		var shape := CollisionShape3D.new()
		shape.name = "Segment%d" % i
		var box := BoxShape3D.new()
		box.size = Vector3(2.0 * PI * radius / float(segments) + 0.4, 16.0, 1.0)
		shape.shape = box
		shape.transform = Transform3D(
			# The box's long local X axis must run along the perimeter: the tangent at angle theta
			# (position (sin, cos) in XZ) is (cos, -sin), which is X rotated by theta about Y.
			Basis(Vector3.UP, theta),
			RootfallLayout.ARENA_CENTER + Vector3(sin(theta) * radius, 8.0, cos(theta) * radius)
		)
		wall.add_child(shape)
		shape.owner = level


func _add_decals(level: Node3D) -> void:
	var id: String = "leaves_forest_ground"
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var group := Node3D.new()
	group.name = "LeafLitterDecals"
	_attach(level, group)
	var albedo := load(TEXTURES % [id, id, "Diffuse"]) as Texture2D
	var normal := load(TEXTURES % [id, id, "nor_gl"]) as Texture2D
	for i: int in range(RootfallLayout.PATH_XZ.size() - 1):
		var start: Vector2 = RootfallLayout.PATH_XZ[i]
		var finish: Vector2 = RootfallLayout.PATH_XZ[i + 1]
		var steps: int = int(start.distance_to(finish) / 11.0)
		for step: int in range(steps):
			var at: Vector2 = start.lerp(finish, float(step) / float(maxi(steps, 1)))
			at += Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			var decal := Decal.new()
			decal.name = "Litter_%d_%d" % [i, step]
			decal.size = Vector3(14.0, 4.0, 14.0)
			decal.texture_albedo = albedo
			decal.texture_normal = normal
			decal.modulate = Color(0.75, 0.62, 0.45, 0.85)
			decal.distance_fade_enabled = true
			decal.distance_fade_begin = 45.0
			decal.distance_fade_length = 15.0
			group.add_child(decal)
			decal.owner = level
			decal.position = Vector3(at.x, 0.5, at.y)
			decal.rotation.y = rng.randf_range(0.0, TAU)


func _add_foliage(level: Node3D) -> void:
	var group := Node3D.new()
	group.name = "Foliage"
	_attach(level, group)
	var fern := load("res://assets/props/fern_cluster/fern_cluster.glb") as PackedScene
	var rock := load("res://assets/props/rock_mossy/rock_mossy.glb") as PackedScene
	var layers: Array[Dictionary] = [
		{
			"name": "FernsNear",
			"scene": fern,
			"count": 2400,
			"height": 2.2,
			"vis": 55.0,
			"seed": 11,
			"wind": true
		},
		{
			"name": "FernsBig",
			"scene": fern,
			"count": 450,
			"height": 4.5,
			"vis": 95.0,
			"seed": 12,
			"wind": true
		},
		{
			"name": "Pebbles",
			"scene": rock,
			"count": 1400,
			"height": 0.4,
			"vis": 38.0,
			"seed": 13,
			"wind": false
		},
	]
	for layer: Dictionary in layers:
		var scatter := FoliageScatter.new()
		scatter.name = layer["name"]
		scatter.source_scene = layer["scene"] as PackedScene
		scatter.count = layer["count"]
		scatter.target_size = layer["height"]
		scatter.visibility_end = layer["vis"]
		scatter.seed_value = layer["seed"]
		scatter.wind = layer["wind"]
		scatter.area = RootfallLayout.GROUND_RECT.grow(-4.0)
		group.add_child(scatter)
		scatter.owner = level


func _add_markers(level: Node3D) -> void:
	var checkpoint := (load(CHECKPOINT_SCENE) as PackedScene).instantiate() as Node3D
	checkpoint.name = "Checkpoint"
	checkpoint.position = RootfallLayout.CHECKPOINT_POS
	_attach(level, checkpoint)
	for entry: Array in [
		["PlayerStart", RootfallLayout.PLAYER_START_POS],
		["ArenaCenter", RootfallLayout.ARENA_CENTER],
		["BossSpawn", RootfallLayout.ARENA_CENTER + Vector3(0.0, 0.0, 3.0)],
	]:
		var marker := Marker3D.new()
		marker.name = entry[0]
		marker.position = entry[1]
		_attach(level, marker)
	(level.get_node("PlayerStart") as Node3D).rotation.y = PI  # face down the path (-Z)


func _add_gate(level: Node3D) -> void:
	# The fog-gate kit (trigger, fog wall, seals, boss spawn) is its own scene; the level only
	# places it so its tuning stays in `fog_gate.tscn`.
	var gate := (load(FOG_GATE_SCENE) as PackedScene).instantiate() as Node3D
	gate.name = "FogGate"
	gate.position = RootfallLayout.GATE_POS
	level.add_child(gate)
	gate.owner = level


func _bake_navigation(level: Node3D) -> void:
	var region := level.get_node("NavigationRegion3D") as NavigationRegion3D
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.agent_radius = 0.5  # the cat is ~0.9 m at the shoulder; the boss is steered separately
	navmesh.agent_height = 1.0
	navmesh.agent_max_climb = 0.25
	navmesh.agent_max_slope = 40.0
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	navmesh.region_min_size = 4.0
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, level)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	print(
		(
			"build_rootfall: navmesh %d polygons, %d vertices"
			% [navmesh.get_polygon_count(), navmesh.get_vertices().size()]
		)
	)
	if ResourceSaver.save(navmesh, NAVMESH_PATH) != OK:
		push_error("build_rootfall: failed to save %s" % NAVMESH_PATH)
		return
	region.navigation_mesh = load(NAVMESH_PATH) as NavigationMesh
