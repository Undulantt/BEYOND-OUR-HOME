class_name Astronaut
extends RefCounted

static func profiles() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/crew/profiles.json"))
	return parsed if parsed is Dictionary else {}

static func create(id: StringName, profile_id: StringName) -> Dictionary:
	return {"id": String(id), "profile_id": String(profile_id), "alive": true,
		"health": 100.0, "fatigue": 0.0, "dose": 0.0,
		"shelter": false, "task_id": "", "priorities": {"survival": 1,
		"emergency_eva": 2, "production": 3, "science_construction": 4},
		"forbidden_categories": [], "sleep_hours": 8.0,
		"worked_hours_today": 0.0, "sleep_hours_today": 0.0, "dose_today": 0.0}
