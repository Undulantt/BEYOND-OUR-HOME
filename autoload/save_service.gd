extends Node

const SAVE_SCHEMA := 1
var rebuild_targets: Array = []

func configure(targets: Array) -> void:
	rebuild_targets = targets.duplicate()

func export_state() -> Dictionary:
	return GameState.to_dict()

func import_state(value: Dictionary) -> Error:
	if not _validate(value):
		return ERR_INVALID_DATA
	GameState.from_dict(value)
	for target in rebuild_targets:
		if target != null and target.has_method("rebuild_from_state"):
			target.rebuild_from_state()
	SignalBus.state_restored.emit()
	return OK

func save_to_slot(slot_id: StringName) -> Error:
	if not _valid_slot(slot_id) or not _validate(GameState.data):
		return ERR_INVALID_PARAMETER
	var dir := "user://saves"
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if dir_error != OK:
		return dir_error
	var target := "%s/%s.json" % [dir, slot_id]
	var temp := target + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(export_state(), "", true, true))
	file.flush()
	file.close()
	var target_absolute := ProjectSettings.globalize_path(target)
	var temp_absolute := ProjectSettings.globalize_path(temp)
	var backup_absolute := target_absolute + ".bak"
	if FileAccess.file_exists(target_absolute):
		DirAccess.remove_absolute(backup_absolute)
		var backup_error := DirAccess.rename_absolute(target_absolute, backup_absolute)
		if backup_error != OK:
			return backup_error
	var move_error := DirAccess.rename_absolute(temp_absolute, target_absolute)
	if move_error != OK and FileAccess.file_exists(backup_absolute):
		DirAccess.rename_absolute(backup_absolute, target_absolute)
	return move_error

func load_from_slot(slot_id: StringName) -> Error:
	if not _valid_slot(slot_id):
		return ERR_INVALID_PARAMETER
	var path := "user://saves/%s.json" % slot_id
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return ERR_INVALID_DATA
	return import_state(parsed)

func _valid_slot(slot_id: StringName) -> bool:
	var value := String(slot_id)
	if value.is_empty():
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true

func _validate(value: Dictionary) -> bool:
	if not _safe_tree(value) or value.get("schema_version") != SAVE_SCHEMA:
		return false
	for key in ["clock", "inventory", "power", "life_support", "crew", "buildings", "world", "research", "events", "rockets", "reports"]:
		if not value.get(key) is Dictionary:
			return false
	var clock: Dictionary = value["clock"]
	if not _integer(clock.get("sol"), 1, int(ConfigDB.balance["time"]["total_sols"])) or not _integer(clock.get("started_sol"), 0, int(clock["sol"])):
		return false
	if not _number(clock.get("elapsed"), 0) or not _number(clock.get("speed"), 0) or not clock.get("paused") is bool:
		return false
	if int(clock.get("sol", 0)) < 1 or int(clock.get("sol", 0)) > int(ConfigDB.balance["time"]["total_sols"]):
		return false
	if int(clock.get("started_sol", -1)) < 0 or int(clock.get("started_sol", 0)) > int(clock["sol"]):
		return false
	if float(clock.get("elapsed", -1.0)) < 0.0 or float(clock.get("elapsed", 0.0)) >= float(ConfigDB.balance["time"]["sol_seconds_x1"]):
		return false
	if not ConfigDB.balance["time"]["speed_multipliers"].has(float(clock.get("speed", -1.0))):
		return false
	for amount in value["inventory"].values():
		if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) < 0.0:
			return false
	if not value.get("ledger_entries", []) is Array or not value.get("settings", {}) is Dictionary or not value.get("dialogue", {}) is Dictionary or not value.get("tutorial", {}) is Dictionary:
		return false
	if not value.get("result", "") in ["", "victory", "defeat"]:
		return false
	var power: Dictionary = value["power"]
	if not _number(power.get("stored", 0), 0) or not _number(power.get("locked_stored", 0), 0) or not power.get("priorities", {}) is Dictionary:
		return false
	for priority in power.get("priorities", {}).values():
		if not _integer(priority, 1, 4):
			return false
	if not _validate_buildings(value["buildings"]) or not _validate_crew(value["crew"], value["buildings"].has("instances")):
		return false
	if not _validate_world(value["world"]) or not _validate_research(value["research"]) or not _validate_rockets(value["rockets"]):
		return false
	for item in value["events"].get("items", {}).values() if value["events"].get("items", {}) is Dictionary else [null]:
		if not item is Dictionary or not item.get("type") in ["tunnel_breach", "dust_storm", "solar_flare"] or not item.get("phase") in ["warning", "active", "ended"]:
			return false
		if not _integer(item.get("start_sol"), 1) or not _integer(item.get("end_sol"), 1) or not item.get("target_ids", []) is Array:
			return false
		for target in item.get("target_ids", []):
			if not target is String:
				return false
	for bucket in value["reports"].values():
		if not bucket is Dictionary:
			return false
		for category in ["production", "consumption", "cargo", "other_income"]:
			if not _amounts(bucket.get(category, {})):
				return false
		if not bucket.get("facts", []) is Array:
			return false
		for fact in bucket.get("facts", []):
			if not fact is Dictionary or not fact.get("message_key") is String or not fact.get("params", {}) is Dictionary or not fact.get("impact", {}) is Dictionary:
				return false
	for entry in value.get("ledger_entries", []):
		if not entry is Dictionary or not entry.get("delta") is Dictionary or not entry.get("reason") is String:
			return false
		for amount in entry["delta"].values():
			if not _number(amount):
				return false
	for entry in value.get("dialogue", {}).get("entries", []) if value.get("dialogue", {}).get("entries", []) is Array else [null]:
		if not entry is Dictionary or not entry.get("message_key") is String or not entry.get("params", {}) is Dictionary:
			return false
	if not value.get("tutorial", {}).get("completed", []) is Array or not value.get("tutorial", {}).get("skipped", false) is bool:
		return false
	for flag in ["guided", "initialized", "pause_owned"]:
		if not value.get("tutorial", {}).get(flag, false) is bool:
			return false
	if not value.get("tutorial", {}).get("current", "") is String:
		return false
	for step in value.get("tutorial", {}).get("completed", []):
		if not step is String:
			return false
	var life: Dictionary = value["life_support"]
	if not life.get("supply", {}) is Dictionary or not _amounts(life.get("shortages", {})) or not _number(life.get("oxygen_leak_per_sol", 0), 0):
		return false
	for supply in life.get("supply", {}).values():
		if not supply is Dictionary:
			return false
		for resource in ["oxygen", "water", "food"]:
			if not supply.get(resource, true) is bool:
				return false
	var settings: Dictionary = value.get("settings", {})
	if not settings.get("language", "es") in ["es", "en"] or not settings.get("ui_scale", 1.0) in [1.0, 1.15, 1.25]:
		return false
	if not settings.get("show_tutorial", true) is bool:
		return false
	for key in ["master_volume", "sfx_volume", "ambient_volume"]:
		if not _number(settings.get(key, 0.8), 0, 1):
			return false
	return true

func _safe_tree(value: Variant, depth: int = 0) -> bool:
	if depth > 48:
		return false
	if value is float:
		return is_finite(value)
	if value is Dictionary:
		for key in value:
			if not key is String or not _safe_tree(value[key], depth + 1):
				return false
		return true
	if value is Array:
		for item in value:
			if not _safe_tree(item, depth + 1):
				return false
		return true
	return value == null or value is String or value is bool or value is int

func _number(value: Variant, minimum: float = -INF, maximum: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _integer(value: Variant, minimum: float = 0, maximum: float = INF) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

func _amounts(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for amount in value.values():
		if not _number(amount, 0):
			return false
	return true

func _pair(value: Variant, minimum: int = 0) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0], minimum, 256) and _integer(value[1], minimum, 256)

func _validate_buildings(state: Dictionary) -> bool:
	if not state.has("instances"):
		return true # Minimal domain test states predate the instance partition.
	if not state["instances"] is Dictionary or not _integer(state.get("next_id"), 1):
		return false
	for item in state["instances"].values():
		if not item is Dictionary or not ConfigDB.balance["buildings"].has(item.get("type")) or not _pair(item.get("origin")) or not _pair(item.get("size"), 1):
			return false
		if not _number(item.get("health"), 0, 100) or not item.get("enabled") is bool:
			return false
		if not item.get("id") is String or not item.get("condition") in ["normal", "breached", "fragile", "destroyed"]:
			return false
		for key in ["fuel_sols", "dust", "unpowered_sols"]:
			if not _number(item.get(key, 0), 0):
				return false
	for key in ["pending_tasks", "applied_tasks", "logs"]:
		if not state.get(key, {}) is Dictionary:
			return false
	for log in state.get("logs", {}).values():
		if not log is Array:
			return false
		for entry in log:
			if not entry is Dictionary or not entry.get("message_key") is String or not entry.get("params", {}) is Dictionary:
				return false
	for task in state.get("pending_tasks", {}).values():
		if not task is Dictionary or not task.get("target_id") is String or not task.get("mode") in ["seal", "weld", "spare_parts", "clean", "refuel"]:
			return false
	return true

func _validate_crew(state: Dictionary, full: bool) -> bool:
	if not state.has("members"):
		return not full
	if not state["members"] is Dictionary or not state.get("tasks") is Dictionary or not state.get("completed_work", []) is Array:
		return false
	for member in state["members"].values():
		if not member is Dictionary or not member.get("alive") is bool or not member.get("task_id") is String or not Astronaut.profiles().has(member.get("profile_id")):
			return false
		if not member.get("id") is String or not member.get("shelter") is bool or not _number(member.get("sleep_hours"), 4, 16):
			return false
		for key in ["health", "fatigue", "dose", "worked_hours_today"]:
			if not _number(member.get(key, 0), 0):
				return false
		if not member.get("priorities") is Dictionary or not member.get("forbidden_categories") is Array:
			return false
		for rank in member["priorities"].values():
			if not _integer(rank, 1, 4):
				return false
		var task_id: String = member["task_id"]
		if not task_id.is_empty() and not state["tasks"].has(task_id):
			return false
	for task in state["tasks"].values():
		if not task is Dictionary or not state["members"].has(task.get("crew_id")) or not task.get("target_id") is String:
			return false
		if not task.get("task_type") in ["research", "repair", "refuel", "clean"] or not task.get("category") in ["survival", "emergency_eva", "production", "science_construction"] or not task.get("state") in ["queued", "active", "blocked", "suspended", "completed", "cancelled"]:
			return false
		if not _number(task.get("required_hours"), 0.000001) or not _number(task.get("completed_hours"), 0, float(task["required_hours"])):
			return false
	for work in state.get("completed_work", []):
		if not work is Dictionary or not work.get("task_id") is String or not work.get("target_id") is String or not _number(work.get("work_hours"), 0):
			return false
	return _integer(state.get("next_task_id"), 1) and _integer(state.get("next_crew_id"), 1)

func _validate_world(state: Dictionary) -> bool:
	for key in ["revealed", "terrain", "reservations"]:
		if not state.get(key, {}) is Dictionary:
			return false
	for zone in state.get("reservations", {}).values():
		if not zone is Array or zone.size() != 4:
			return false
		for component in zone:
			if not _integer(component, 0, 256):
				return false
	for revealed in state.get("revealed", {}).values():
		if not revealed is bool:
			return false
	for terrain in state.get("terrain", {}).values():
		if terrain not in ["aquifer", "iron_regolith", "sterile"]:
			return false
	return true

func _validate_research(state: Dictionary) -> bool:
	if state.is_empty():
		return true
	if not state.get("unlocked") is Array or not state.get("seen_tasks", {}) is Dictionary or not _number(state.get("points"), 0) or not _number(state.get("progress"), 0):
		return false
	var active: Variant = state.get("active")
	if not active is String or (not active.is_empty() and not ConfigDB.balance["research"].has(active)):
		return false
	for tech in state["unlocked"]:
		if not ConfigDB.balance["research"].has(tech):
			return false
	for credited in state.get("seen_tasks", {}).values():
		if not credited is bool and not _number(credited, 0):
			return false
	return true

func _validate_rockets(state: Dictionary) -> bool:
	if not state.get("plans", {}) is Dictionary:
		return false
	for plan in state.get("plans", {}).values():
		if not plan is Dictionary or not _number(plan.get("mass_limit"), 0) or not _amounts(plan.get("manifest")) or not _integer(plan.get("arrival_sol"), 1, 42):
			return false
		if not plan.get("zone") is Array or not plan["zone"].size() in [0, 4]:
			return false
		for coordinate in plan["zone"]:
			if not _integer(coordinate, 0, 256):
				return false
		for item in plan["manifest"]:
			if not ConfigDB.balance["rockets"]["cargo_mass"].has(item) or not _integer(plan["manifest"][item]):
				return false
		for key in ["confirmed", "landed", "cargo_transferred"]:
			if not plan.get(key) is bool:
				return false
		if not plan.get("disposition") in ["available", "salvaged", "exchanged"]:
			return false
	return true
