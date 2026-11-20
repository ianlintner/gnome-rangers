extends Node3D
## Capture dressing for Rootfall Hollow: the level plus stand-in actors and 3 fixed cameras.
##
## Cameras (select with `--camera <name>`; names are children of this node):
##   CamApproach   gnome-height view down the approach path from the checkpoint
##   CamArenaWide  from the fog gate across the boss arena, sun beams in frame
##   CamHero       ground-level hero shot echoing the concept art: Grukk looming over the gnome
##
## The level scene itself stays actor-free (gameplay cards own the actors); the stand-ins here are
## the imported hero models in their neutral pose, only so captures show scale and rim light.

const GNOME_AT := Vector3(-1.2, 0.0, -297.5)
const GRUKK_AT := Vector3(3.0, 0.0, -308.0)

@onready var _gnome: Node3D = $Actors/Gnome
@onready var _grukk: Node3D = $Actors/Grukk


func _ready() -> void:
	_gnome.position = GNOME_AT
	_gnome.look_at(GRUKK_AT, Vector3.UP, true)
	_grukk.position = GRUKK_AT
	_grukk.look_at(GNOME_AT, Vector3.UP, true)
	_aim($CamApproach, Vector3(-1.5, 1.5, 6.0), Vector3(6.0, 2.6, -30.0), 62.0)
	_aim($CamArenaWide, Vector3(3.0, 2.4, -279.0), Vector3(0.0, 4.5, -312.0), 64.0)
	_aim($CamHero, Vector3(-1.8, 0.7, -291.0), Vector3(1.4, 3.0, -307.0), 50.0)


func _aim(camera: Camera3D, from: Vector3, target: Vector3, fov_degrees: float) -> void:
	camera.fov = fov_degrees
	camera.look_at_from_position(from, target, Vector3.UP)
