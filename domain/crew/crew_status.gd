class_name CrewStatus
extends RefCounted

var id: StringName
var profile_id: StringName
var alive: bool
var health: float
var fatigue: float
var dose: float
var shelter: bool
var task_id: StringName
var priorities: Dictionary
var forbidden_categories: Array

static func from_dict(value: Dictionary) -> CrewStatus:
	var result := CrewStatus.new()
	result.id = StringName(value.get("id", ""))
	result.profile_id = StringName(value.get("profile_id", ""))
	result.alive = bool(value.get("alive", false))
	result.health = float(value.get("health", 0.0))
	result.fatigue = float(value.get("fatigue", 0.0))
	result.dose = float(value.get("dose", 0.0))
	result.shelter = bool(value.get("shelter", false))
	result.task_id = StringName(value.get("task_id", ""))
	result.priorities = value.get("priorities", {}).duplicate(true)
	result.forbidden_categories = value.get("forbidden_categories", []).duplicate(true)
	return result
