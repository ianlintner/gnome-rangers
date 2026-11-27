class_name MountAnimator
extends Node
## Builds the cat's AnimationTree from the clips its model actually has and plays them for
## the mount's states.
##
## The tree is a state machine: `Locomotion` (a BlendSpace1D over ground speed: idle, walk,
## run, gallop) plus one-shot or looping nodes for `Pounce`, `Hit` and `Flee`. A clip that
## the model lacks is skipped, so a state without a node falls back to `Locomotion` and a
## model without an AnimationPlayer simply stays still. The pounce node runs through a
## TimeScale so the clip fits the pounce timings in [MountStats].

## Mount state name -> animation-tree node. Everything else plays `Locomotion`.
const STATE_NODES: Dictionary = {
	&"Pounce": &"Pounce",
	&"Hurt": &"Hit",
	&"Flee": &"Flee",
}
## Animation-tree node -> clip name.
const NODE_CLIPS: Dictionary = {
	&"Pounce": &"pounce",
	&"Hit": &"hit",
	&"Flee": &"flee",
}
const LOCOMOTION: StringName = &"Locomotion"
## Walk and run clips sit at these fractions of the ridden walk speed on the blend space.
const WALK_CLIP_FRACTION: float = 0.35

var tree: AnimationTree = null

var _playback: AnimationNodeStateMachinePlayback = null
var _nodes: Dictionary = {}
## Time scale applied to the pounce clip so it fits the pounce timings.
var _pounce_scale: float = 1.0


## Builds the tree under `model` for the AnimationPlayer found there. Safe without clips.
func setup(model: Node, stats: MountStats) -> void:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return
	var root := AnimationNodeStateMachine.new()
	root.add_node(LOCOMOTION, _build_locomotion(player, stats))
	_nodes[LOCOMOTION] = true
	for node_name: StringName in NODE_CLIPS:
		var clip: StringName = NODE_CLIPS[node_name]
		if not player.has_animation(clip):
			continue
		root.add_node(node_name, _build_clip_node(node_name, player, stats))
		root.add_transition(LOCOMOTION, node_name, AnimationNodeStateMachineTransition.new())
		root.add_transition(node_name, LOCOMOTION, AnimationNodeStateMachineTransition.new())
		_nodes[node_name] = true
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	# The rider sits on the saddle bone, so the pose must advance with the physics tick (not
	# per rendered frame) for the seat, and every fight, to be frame-rate independent.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	model.add_child(tree)
	tree.tree_root = root
	tree.anim_player = tree.get_path_to(player)
	tree.active = true
	if _nodes.has(&"Pounce"):
		tree.set("parameters/Pounce/scale/scale", _pounce_scale)
	_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_playback.start(LOCOMOTION)


## Feeds the ground speed (m/s) to the locomotion blend.
func set_speed(speed: float) -> void:
	if tree != null:
		tree.set("parameters/Locomotion/blend_position", speed)


## Plays the animation for a mount state, falling back to locomotion when it has no clip.
func play_for_state(state_name: StringName) -> void:
	if _playback == null:
		return
	var node_name: StringName = STATE_NODES.get(state_name, LOCOMOTION)
	if not _nodes.has(node_name):
		node_name = LOCOMOTION
	if _playback.get_current_node() == node_name and node_name != &"Hit":
		return
	if node_name == LOCOMOTION:
		_playback.travel(LOCOMOTION)
	else:
		_playback.start(node_name)  # one-shots restart cleanly even mid-transition


## True when the tree has a node for `node_name` (tests and fallbacks).
func has_node_for(node_name: StringName) -> bool:
	return _nodes.has(node_name)


## The animation-tree node currently playing, or empty without a tree.
func current_node() -> StringName:
	return _playback.get_current_node() if _playback != null else &""


func _build_locomotion(player: AnimationPlayer, stats: MountStats) -> AnimationNodeBlendSpace1D:
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = maxf(stats.gallop_speed, 1.0)
	var points: Array = [
		[&"idle", 0.0],
		[&"walk", stats.walk_speed * WALK_CLIP_FRACTION],
		[&"run", stats.walk_speed],
		[&"gallop", stats.gallop_speed],
	]
	for point: Array in points:
		if player.has_animation(point[0]):
			var clip := AnimationNodeAnimation.new()
			clip.animation = point[0]
			space.add_blend_point(clip, point[1], -1, point[0])
	return space


func _build_clip_node(
	node_name: StringName, player: AnimationPlayer, stats: MountStats
) -> AnimationRootNode:
	var clip := AnimationNodeAnimation.new()
	clip.animation = NODE_CLIPS[node_name]
	if node_name != &"Pounce":
		return clip
	var blend := AnimationNodeBlendTree.new()
	var scale := AnimationNodeTimeScale.new()
	blend.add_node(&"clip", clip)
	blend.add_node(&"scale", scale)
	blend.connect_node(&"scale", 0, &"clip")
	blend.connect_node(&"output", 0, &"scale")
	var total: float = stats.pounce_windup + stats.pounce_leap_time + stats.pounce_recovery
	var length: float = player.get_animation(&"pounce").length
	_pounce_scale = length / maxf(total, 0.01)
	return blend
