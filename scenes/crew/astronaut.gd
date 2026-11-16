class_name AstronautVisual
extends Node3D

var crew_id: StringName
var _material: StandardMaterial3D

func set_crew_state(status: Dictionary) -> void:
	crew_id = StringName(status.get("id", ""))
	visible = bool(status.get("alive", true))
	var suit: MeshInstance3D = $Suit
	if _material == null:
		_material = StandardMaterial3D.new()
		suit.material_override = _material
	var material := _material
	material.albedo_color = Color(0.93, 0.92, 0.84) if bool(status.get("shelter", false)) else Color(0.94, 0.58, 0.24)
	if float(status.get("health", 100.0)) < 35.0:
		material.albedo_color = Color(0.8, 0.25, 0.2)
	suit.material_override = material
