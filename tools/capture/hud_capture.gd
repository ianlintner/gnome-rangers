extends Control
## Capture fixture: drives the HUD entirely through EventBus signals so the
## screenshot exercises the same path as gameplay.

@export var mount_bar: bool = false
@export var locked_on: bool = false
@export var draw_bow: bool = false
@export var boss_bar: bool = false

@onready var hud: CanvasLayer = $HUD
@onready var camera: Camera3D = $Camera3D
@onready var target: Node3D = get_node(NodePath("The Hollow Warden")) as Node3D
@onready var background: ColorRect = $Background


func _ready() -> void:
	background.color = Palette.FOREST_SHADOW
	EventBus.player_health_changed.emit(62.0, 100.0)
	EventBus.player_stamina_changed.emit(48.0, 100.0)
	if mount_bar:
		EventBus.mount_mounted.emit()
		EventBus.mount_health_changed.emit(78.0, 120.0)
	if locked_on:
		EventBus.lock_on_changed.emit(target)
	if draw_bow:
		EventBus.aim_changed.emit(true)
		EventBus.bow_draw_changed.emit(0.75)
	if boss_bar:
		EventBus.boss_engaged.emit(target)
