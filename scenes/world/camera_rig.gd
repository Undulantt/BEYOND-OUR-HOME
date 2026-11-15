class_name CameraRig
extends Node3D

@onready var camera: Camera3D = $Camera3D
const CELL_SIZE := 2.0
var focus := Vector3(32.0, 0.0, 32.0)
# A closer default keeps the colony's 3D silhouettes readable while leaving
# enough surrounding terrain visible for placement and navigation.
var zoom := 40.0
var map_view := Rect2(0.0, 0.0, 0.65, 1.0)

func set_map_view(rect: Rect2) -> void:
	map_view = rect
	_apply()

func _ready() -> void:
	_apply()

func _process(delta: float) -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is OptionButton:
		return
	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		direction.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		direction.z += 1.0
	if direction != Vector3.ZERO:
		focus += direction.normalized() * delta * zoom * 0.45
		var map_limit := float(ConfigDB.balance["map"]["maximum_size"]) * CELL_SIZE
		focus.x = clampf(focus.x, 0.0, map_limit)
		focus.z = clampf(focus.z, 0.0, map_limit)
		_apply()

func zoom_by(amount: float) -> void:
	zoom = clampf(zoom + amount, 18.0, 176.0)
	_apply()

func focus_cell(cell: Vector2i) -> void:
	focus = Vector3((float(cell.x) + 0.5) * CELL_SIZE, 0.0,
		(float(cell.y) + 0.5) * CELL_SIZE)
	_apply()

func _apply() -> void:
	if camera == null:
		return
	position = focus
	# Look across the colony from its south edge. This keeps the long east-west
	# starter layout readable left-to-right and gives buildings more visible
	# side walls than the high, diagonal strategy-map angle.
	camera.position = Vector3(zoom * 0.42, zoom * 0.78, zoom)
	camera.look_at(focus, Vector3.UP)
	camera.size = zoom
	# Keep the focused colony in the map area to the left of the HUD panels.
	var viewport_size := get_viewport().get_visible_rect().size
	var center := map_view.get_center()
	camera.h_offset = zoom * viewport_size.x / maxf(1.0, viewport_size.y) * (0.5 - center.x)
	camera.v_offset = zoom * (center.y - 0.5)
