extends Node

const BALANCE_PATH := "res://data/balance.json"
var balance: Dictionary = {}
var error_message: String = ""

func _ready() -> void:
	load_balance()

func load_balance() -> bool:
	error_message = ""
	if not FileAccess.file_exists(BALANCE_PATH):
		error_message = "Missing %s" % BALANCE_PATH
		push_error(error_message)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_PATH))
	if not parsed is Dictionary:
		error_message = "Invalid JSON object: %s" % BALANCE_PATH
		push_error(error_message)
		return false
	var candidate: Dictionary = parsed
	var invalid_path := _find_invalid_number(candidate)
	if not invalid_path.is_empty():
		error_message = "Non-finite number at %s" % invalid_path
		push_error(error_message)
		return false
	for section in ["time", "astronaut", "initial_inventory", "buildings", "rockets", "events"]:
		if not candidate.has(section) or not candidate[section] is Dictionary:
			error_message = "Missing section %s in %s" % [section, BALANCE_PATH]
			push_error(error_message)
			return false
	var time: Dictionary = candidate["time"]
	if float(time.get("sol_seconds_x1", 0)) <= 0 or int(time.get("total_sols", 0)) <= 0:
		error_message = "Invalid time duration"
		push_error(error_message)
		return false
	var speeds: Array = time.get("speed_multipliers", [])
	if speeds.is_empty() or not speeds.has(1.0) or not speeds.has(4.0):
		error_message = "Invalid speed_multipliers"
		push_error(error_message)
		return false
	for id in candidate["initial_inventory"]:
		if not _nonnegative_number(candidate["initial_inventory"][id]):
			error_message = "Negative initial inventory: %s" % id
			push_error(error_message)
			return false
	var arrivals: Array = candidate["rockets"].get("arrival_sols", [])
	if arrivals.size() != 4:
		error_message = "Expected four rocket arrival sols"
		push_error(error_message)
		return false
	var previous := 0
	for arrival in arrivals:
		if int(arrival) <= previous or int(arrival) > int(time["total_sols"]):
			error_message = "Invalid rocket arrival sol: %s" % arrival
			push_error(error_message)
			return false
		previous = int(arrival)
	for type_id in candidate["buildings"]:
		var building: Dictionary = candidate["buildings"][type_id]
		var size: Array = building.get("size", [])
		if size.size() != 2 or float(size[0]) <= 0.0 or float(size[1]) <= 0.0:
			error_message = "Invalid building size: %s" % type_id
			push_error(error_message)
			return false
		for resource_id in building.get("cost", {}):
			if not _nonnegative_number(building["cost"][resource_id]):
				error_message = "Invalid cost: %s.%s" % [type_id, resource_id]
				push_error(error_message)
				return false
	var weights: Dictionary = candidate.get("scan", {}).get("terrain_weights", {})
	var total_weight := 0.0
	for terrain_id in weights:
		if not _nonnegative_number(weights[terrain_id]):
			error_message = "Invalid terrain weight: %s" % terrain_id
			push_error(error_message)
			return false
		total_weight += float(weights[terrain_id])
	if not is_equal_approx(total_weight, 1.0):
		error_message = "Terrain weights must sum to one"
		push_error(error_message)
		return false
	balance = candidate.duplicate(true)
	return true

func get_section(section: StringName) -> Dictionary:
	return balance.get(String(section), {}).duplicate(true)

func _nonnegative_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0

func _find_invalid_number(value: Variant, path: String = "root") -> String:
	if value is float and not is_finite(value):
		return path
	if value is Dictionary:
		for key in value:
			var found := _find_invalid_number(value[key], "%s.%s" % [path, key])
			if not found.is_empty():
				return found
	if value is Array:
		for index in value.size():
			var found := _find_invalid_number(value[index], "%s[%d]" % [path, index])
			if not found.is_empty():
				return found
	return ""
