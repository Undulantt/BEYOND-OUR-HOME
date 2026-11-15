class_name PlacementPreview
extends Node3D

const CELL_SIZE := 2.0

var mesh_instance: MeshInstance3D
var direction_indicator: MeshInstance3D

func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	direction_indicator = MeshInstance3D.new()
	direction_indicator.name = "DirectionIndicator"
	var indicator_mesh := BoxMesh.new()
	indicator_mesh.size = Vector3(0.22, 0.08, 0.65)
	direction_indicator.mesh = indicator_mesh
	var indicator_material := StandardMaterial3D.new()
	indicator_material.albedo_color = Color(0.95, 0.95, 0.95, 0.85)
	indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	direction_indicator.material_override = indicator_material
	add_child(direction_indicator)
	hide()

func show_at(origin: Vector2i, size: Vector2i, valid: bool, rotation_quarters: int = 0,
		offset_m: Vector2 = Vector2.ZERO) -> void:
	if mesh_instance == null or direction_indicator == null:
		return
	var turns := posmod(rotation_quarters, 4)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x * CELL_SIZE, 0.12, size.y * CELL_SIZE)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.85, 0.45, 0.55) if valid else Color(0.95, 0.2, 0.2, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	var rotated_size := Vector2i(size.y, size.x) if turns % 2 == 1 else size
	position = Vector3((origin.x + rotated_size.x * 0.5) * CELL_SIZE + offset_m.x, 0.15,
		(origin.y + rotated_size.y * 0.5) * CELL_SIZE + offset_m.y)
	rotation.y = float(turns) * PI * 0.5
	direction_indicator.position = Vector3(0.0, 0.09, -size.y * CELL_SIZE * 0.5 + 0.42)
	show()
