extends Node3D
## Sandbox capture scene for the cat mount: each CatSlot holds a cat posed on a named clip with the
## gnome ranger statically attached to the cat's `saddle` bone (BoneAttachment3D).
##
## Each slot is configured with metadata: `clip` (animation name) and `time` (seconds to freeze at).

const SADDLE_BONE: StringName = &"saddle"
## Gnome origin (feet) relative to the saddle bone; seats the hips on the blanket.
const RIDER_OFFSET: Vector3 = Vector3(0.0, -0.46, 0.0)

@export var rider_scene: PackedScene


func _ready() -> void:
	for slot: Node3D in find_children("CatSlot*", "Node3D", false, false):
		_setup_slot(slot)


func _setup_slot(slot: Node3D) -> void:
	var skeleton: Skeleton3D = slot.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.find_bone(SADDLE_BONE) == -1:
		push_error("mount_showcase: %s has no saddle bone" % slot.name)
		return
	# Look the cat's own player up before the rider (which has its own) joins the subtree.
	var player: AnimationPlayer = slot.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var attachment := BoneAttachment3D.new()
	attachment.name = "SaddleAttachment"
	attachment.bone_name = SADDLE_BONE
	skeleton.add_child(attachment)
	var rider: Node3D = rider_scene.instantiate() as Node3D
	attachment.add_child(rider)
	# The saddle bone's local axes follow the glTF bone convention, so seat the rider in the
	# mount's frame (upright, facing the same way) and let the attachment carry it from there.
	rider.global_transform = Transform3D(
		slot.global_basis, attachment.global_position + slot.global_basis * RIDER_OFFSET
	)
	var clip: StringName = StringName(String(slot.get_meta("clip", "idle")))
	if player != null and player.has_animation(clip):
		player.play(clip)
		player.seek(float(slot.get_meta("time", 0.0)), true)
		player.pause()
