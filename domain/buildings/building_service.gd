class_name BuildingService
extends RefCounted

# These authored marker models extend beyond their logical grid footprints.
# Portless models keep one cell clear of them; tunnels and other port-bearing
# models are exempt so their cylinders can meet the authored markers.
const VISUAL_OVERHANG_TYPES := [&"base", &"isru", &"refinery"]

var ledger: ResourceLedger
var grid: GridService
var power: PowerService
var research
var tunnel_network

func initialize_layout() -> GameContracts.ValidationResult:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/initial_layout.json"))
	if not parsed is Dictionary:
		return GameContracts.failure(&"invalid_initial_layout")
	GameState.data["buildings"] = {"instances": {}, "next_id": 1, "applied_tasks": {}, "logs": {}}
	grid.initialize()
	if research != null:
		research.initialize()
	else:
		GameState.data["research"] = {"unlocked": [], "points": 0.0, "active": "", "progress": 0.0, "seen_tasks": {}}
	for row in parsed.get("buildings", []):
		if not row is Dictionary or not row.has("id") or not row.has("type"):
			return GameContracts.failure(&"invalid_initial_layout")
		var origin: Array = row.get("origin", [])
		if origin.size() != 2:
			return GameContracts.failure(&"invalid_initial_layout")
		var definition := BuildingDefinition.from_balance(StringName(row["type"]))
		if definition == null:
			return GameContracts.failure(&"invalid_initial_layout")
		var id := String(row["id"])
		var instance := _new_instance(id, definition, Vector2i(int(origin[0]), int(origin[1])))
		instance["rotation_quarters"] = posmod(int(row.get("rotation_quarters", 0)), 4)
		var offset_m: Variant = row.get("offset_m", [0.0, 0.0])
		if offset_m is Array and offset_m.size() >= 2:
			instance["offset_m"] = [float(offset_m[0]), float(offset_m[1])]
		if instance["rotation_quarters"] % 2 == 1:
			instance["size"] = [definition.footprint.y, definition.footprint.x]
		GameState.data["buildings"]["instances"][id] = instance
		var suffix := id.get_slice("_", id.get_slice_count("_") - 1)
		if suffix.is_valid_int():
			GameState.data["buildings"]["next_id"] = maxi(int(GameState.data["buildings"]["next_id"]), int(suffix) + 1)
	GameState.data["buildings"]["instances"]["greenhouse_1"]["crop"] = "healthy"
	GameState.data["buildings"]["instances"]["greenhouse_1"]["seed_planted"] = true
	return GameContracts.success()

func rebuild_from_state() -> void:
	var tasks: Variant = GameState.data.get("crew", {}).get("tasks")
	if not tasks is Dictionary:
		return
	var pending: Dictionary = GameState.data.get("buildings", {}).get("pending_tasks", {})
	for id in pending.keys():
		if not tasks.has(id) or tasks[id].get("state") in ["completed", "cancelled"]:
			pending.erase(id)

func validate_placement(request: GameContracts.PlacementRequest) -> GameContracts.PlacementResult:
	if request == null:
		return _placement_failure(&"invalid_placement")
	var answer := GameContracts.PlacementResult.new()
	var definition := BuildingDefinition.from_balance(request.building_type)
	if definition == null:
		return _placement_failure(&"unknown_building")
	if request.rotation_quarters < 0 or request.rotation_quarters > 3:
		return _placement_failure(&"invalid_rotation")
	if not _is_unlocked(request.building_type):
		return _placement_failure(&"technology_locked")
	var size := definition.footprint
	if request.rotation_quarters % 2 == 1:
		size = Vector2i(size.y, size.x)
	var rect := Rect2i(request.origin, size)
	var zone_result := grid.validate_zone(rect, &"building")
	if not zone_result.ok:
		return _placement_failure(zone_result.error_code)
	if _has_visual_overhang_conflict(rect, request.building_type):
		return _placement_failure(&"zone_occupied")
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var cell := Vector2i(x, y)
			answer.cells.append(cell)
			if definition.terrain_rule != &"any" and grid.terrain_at(cell) != definition.terrain_rule:
				return _placement_failure(&"invalid_terrain")
	if _inside_reactor_exclusion(rect):
		return _placement_failure(&"reactor_exclusion")
	var connection_offset := Vector2.ZERO
	if definition.connection_rule == &"tunnel":
		var matched_offset: Variant = _find_tunnel_offset(rect, request.building_type, request.rotation_quarters)
		if matched_offset == null:
			return _placement_failure(&"tunnel_required")
		connection_offset = matched_offset
	elif request.building_type == &"isru":
		# ISRU still connects to power by proximity, but align its authored tunnel
		# marker when an open tunnel is adjacent. A 2x2 footprint has an even-meter
		# center while a one-cell tunnel has an odd-meter center, so the marker can
		# otherwise miss by one meter despite occupying neighboring cells.
		var isru_tunnel_offset: Variant = _find_tunnel_offset(rect, request.building_type, request.rotation_quarters)
		if isru_tunnel_offset != null:
			connection_offset = isru_tunnel_offset
	if definition.connection_rule == &"proximity" and request.building_type != &"reactor" and not _near_energized(rect):
		return _placement_failure(&"energy_connection_required")
	if not ledger.can_afford(definition.cost):
		return _placement_failure(&"insufficient_resources")
	answer.costs = definition.cost.duplicate(true)
	if definition.connection_rule == &"tunnel" or request.building_type == &"isru":
		answer.params["offset_m"] = [connection_offset.x, connection_offset.y]
	if definition.connection_rule == &"tunnel":
		answer.required_connections.append(&"tunnel")
	else:
		answer.required_connections.append(&"energy")
	return answer

func _has_visual_overhang_conflict(rect: Rect2i, candidate_type: StringName) -> bool:
	var candidate_has_ports := TunnelNetwork.PORT_SCENES.has(String(candidate_type))
	var buildings: Dictionary = GameState.data.get("buildings", {}).get("instances", {})
	for item: Dictionary in buildings.values():
		var type := StringName(item.get("type", ""))
		if type == &"tunnel" or not VISUAL_OVERHANG_TYPES.has(type):
			continue
		if not candidate_has_ports and grid._rect(item).grow(1).intersects(rect):
			return true
	for item: Dictionary in buildings.values():
		if TunnelNetwork.PORT_SCENES.has(String(item.get("type", ""))):
			continue
		if VISUAL_OVERHANG_TYPES.has(candidate_type) and grid._rect(item).grow(1).intersects(rect):
			return true
	return false

func place(request: GameContracts.PlacementRequest) -> GameContracts.PlacementResult:
	var result := validate_placement(request)
	if not result.ok:
		return result
	var definition := BuildingDefinition.from_balance(request.building_type)
	var id := "%s_%d" % [request.building_type, int(GameState.data["buildings"]["next_id"])]
	if not ledger.spend(definition.cost, "construction_%s" % id):
		return _placement_failure(&"insufficient_resources")
	GameState.data["buildings"]["next_id"] = int(GameState.data["buildings"]["next_id"]) + 1
	var instance := _new_instance(id, definition, request.origin)
	instance["rotation_quarters"] = request.rotation_quarters
	instance["offset_m"] = result.params.get("offset_m", [0.0, 0.0]).duplicate(true)
	if request.rotation_quarters % 2 == 1:
		instance["size"] = [definition.footprint.y, definition.footprint.x]
	GameState.data["buildings"]["instances"][id] = instance
	result.params["building_id"] = id
	SignalBus.building_changed.emit(StringName(id), &"placed")
	return result

func remove(building_id: StringName) -> GameContracts.ValidationResult:
	var id := String(building_id)
	if not GameState.data.get("buildings", {}).get("instances", {}).has(id):
		return GameContracts.failure(&"unknown_building")
	if id in ["base_1", "isru_1", "greenhouse_1", "reactor_1"]:
		return GameContracts.failure(&"initial_building_protected")
	GameState.data["buildings"]["instances"].erase(id)
	SignalBus.building_changed.emit(building_id, &"removed")
	return GameContracts.success()

func get_status(building_id: StringName) -> BuildingStatus:
	var item: Dictionary = GameState.data.get("buildings", {}).get("instances", {}).get(String(building_id), {})
	if item.is_empty():
		return null
	var result := BuildingStatus.new()
	result.building_id = building_id
	result.type = StringName(item["type"])
	var origin: Array = item["origin"]
	var size: Array = item["size"]
	for x in range(int(origin[0]), int(origin[0]) + int(size[0])):
		for y in range(int(origin[1]), int(origin[1]) + int(size[1])):
			result.cells.append(Vector2i(x, y))
	result.demand = float(ConfigDB.balance["buildings"][item["type"]].get("power", 0.0))
	result.powered = power != null and power.is_powered(building_id)
	result.enabled = bool(item.get("enabled", true))
	result.health = float(item.get("health", 100.0))
	result.condition = StringName(item.get("condition", "normal"))
	result.modifiers = {"crop": item.get("crop", ""), "dust": item.get("dust", 0.0), "fuel_sols": item.get("fuel_sols", 0.0), "storm_protected": item.get("storm_protected", false)}
	if result.powered and result.enabled and result.health > 0.0:
		var source: Dictionary = ConfigDB.balance["buildings"][item["type"]]
		if item["type"] in ["isru", "mine"]:
			result.production = source.get("output_per_sol", {}).duplicate(true)
		elif item["type"] == "greenhouse" and item.get("crop") == "healthy":
			result.production = {"food": float(source["food_per_sol"])}
		elif item["type"] == "refinery":
			result.production = {"iron_plates": float(source["output_iron_plates"])}
	if not result.powered and result.demand > 0.0:
		result.warnings.append(&"unpowered")
	if result.condition == &"breached":
		result.warnings.append(&"oxygen_leak")
	if item.get("crop", "") == "wilting":
		result.next_consequence_keys.append(&"crop_may_die")
	return result

func get_all_statuses() -> Array[BuildingStatus]:
	var result: Array[BuildingStatus] = []
	for id in GameState.data.get("buildings", {}).get("instances", {}):
		result.append(get_status(StringName(id)))
	return result

func get_log(building_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in GameState.data.get("buildings", {}).get("logs", {}).get(String(building_id), []):
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result

func set_storm_protection(building_id: StringName, protected: bool) -> GameContracts.ValidationResult:
	var item := _item(building_id)
	if item.is_empty():
		return GameContracts.failure(&"unknown_building")
	item["storm_protected"] = protected
	SignalBus.building_changed.emit(building_id, &"storm_protection")
	return GameContracts.success()

func apply_panel_dust(building_id: StringName, amount: float) -> void:
	var item := _item(building_id)
	if item.is_empty() or item.get("type") != "solar_panel" or not is_finite(amount) or amount <= 0.0:
		return
	if bool(item.get("storm_protected", false)):
		return
	item["dust"] = clampf(float(item.get("dust", 0.0)) + amount, 0.0, 1.0)

func set_enabled(building_id: StringName, enabled: bool) -> GameContracts.ValidationResult:
	var item := _item(building_id)
	if item.is_empty():
		return GameContracts.failure(&"unknown_building")
	item["enabled"] = enabled
	SignalBus.building_changed.emit(building_id, &"enabled")
	return GameContracts.success()

func get_power_inputs() -> Dictionary:
	var generators: Array[Dictionary] = []
	var consumers: Array[Dictionary] = []
	var capacity := 0.0
	var charge := 0.0
	var total_capacity := 0.0
	var sol := int(GameState.data.get("clock", {}).get("sol", 1))
	var elapsed := float(GameState.data.get("clock", {}).get("elapsed", 0.0))
	var day := fmod(float(sol - 1) + elapsed / float(ConfigDB.balance["time"]["sol_seconds_x1"]), 1.0) < 0.5
	for id in GameState.data.get("buildings", {}).get("instances", {}):
		var item: Dictionary = GameState.data["buildings"]["instances"][id]
		var kind := String(item["type"])
		var definition: Dictionary = ConfigDB.balance["buildings"][kind]
		var enabled := bool(item.get("enabled", true)) and float(item.get("health", 0.0)) > 0.0
		if kind == "reactor":
			generators.append({"building_id": id, "output": float(definition["global_output"]), "enabled": enabled and is_reactor_active(StringName(id))})
		elif kind == "solar_panel":
			var output := float(definition["day_output"]) * (1.0 if day else float(definition["night_multiplier"]))
			output *= maxf(0.0, 1.0 - float(item.get("dust", 0.0)))
			if bool(GameState.data.get("events", {}).get("dust_storm_active", false)):
				output *= float(definition["storm_multiplier"])
			generators.append({"building_id": id, "output": output, "enabled": enabled})
		elif kind == "battery":
			if float(item.get("health", 0.0)) > 0.0:
				total_capacity += float(definition["capacity"])
			if enabled:
				capacity += float(definition["capacity"])
				charge += float(definition["charge_rate"])
		var demand := float(definition.get("power", 0.0))
		if demand > 0.0:
			consumers.append({"building_id": id, "demand": demand, "enabled": enabled, "priority": 1 if kind in ["base", "isru"] else 2})
	return {"generators": generators, "consumers": consumers, "battery_capacity": capacity,
		"battery_charge_rate": charge, "battery_discharge_rate": charge, "battery_total_capacity": total_capacity}

func is_reactor_active(building_id: StringName) -> bool:
	var item := _item(building_id)
	return not item.is_empty() and item.get("type") == "reactor" and bool(item.get("enabled", true)) and float(item.get("health", 0.0)) > 0.0 and float(item.get("fuel_sols", 0.0)) > 0.0

func validate_action(building_id: StringName, action: StringName, _args: Dictionary = {}) -> GameContracts.ValidationResult:
	var item := _item(building_id)
	if item.is_empty():
		return GameContracts.failure(&"unknown_building")
	if action == &"isolate" and item.get("type") == "tunnel" and item.get("condition") == "breached":
		return GameContracts.success()
	if action == &"clean" and item.get("type") == "solar_panel":
		return GameContracts.success()
	if action == &"refuel" and item.get("type") == "reactor":
		return GameContracts.success() if ledger.can_afford({"nuclear_core": 1.0}) else GameContracts.failure(&"insufficient_resources")
	return GameContracts.failure(&"invalid_action")

func request_repair(building_id: StringName, mode: StringName, crew_id: StringName) -> GameContracts.ValidationResult:
	var item := _item(building_id)
	if item.is_empty() or item.get("condition") != "breached":
		return GameContracts.failure(&"repair_not_needed")
	if mode not in [&"seal", &"weld", &"spare_parts"] or String(crew_id).is_empty():
		return GameContracts.failure(&"invalid_repair")
	if _has_pending_target(building_id):
		return GameContracts.failure(&"building_task_pending")
	if mode == &"spare_parts" and not ledger.can_afford({"spare_parts": 1.0}):
		return GameContracts.failure(&"insufficient_resources")
	var task_id := "repair_%s_%d" % [building_id, int(GameState.data["buildings"]["next_id"])]
	GameState.data["buildings"]["next_id"] = int(GameState.data["buildings"]["next_id"]) + 1
	GameState.data["buildings"].get_or_add("pending_tasks", {})[task_id] = {"target_id": String(building_id), "mode": String(mode), "crew_id": String(crew_id)}
	var result := GameContracts.success()
	result.params = {"task_id": task_id, "work_hours": float(ConfigDB.balance["events"]["tunnel_breach"]["repair_hours"])}
	return result

func apply_damage(building_id: StringName, amount: float, reason: StringName) -> void:
	var item := _item(building_id)
	if item.is_empty() or not is_finite(amount) or amount <= 0.0:
		return
	item["health"] = maxf(0.0, float(item["health"]) - amount)
	if item.get("type") == "tunnel":
		item["condition"] = "breached"
		item["isolated"] = false
	elif float(item["health"]) <= 0.0:
		item["condition"] = "destroyed"
	_log(building_id, &"damage", &"warning", StringName("building.%s" % reason))
	SignalBus.building_changed.emit(building_id, &"damaged")

func apply_task_result(task_id: StringName, target_id: StringName, result: Dictionary) -> GameContracts.ValidationResult:
	var tasks: Dictionary = GameState.data["buildings"].get("pending_tasks", {})
	if GameState.data["buildings"]["applied_tasks"].has(String(task_id)):
		return GameContracts.failure(&"task_already_applied")
	if not tasks.has(String(task_id)) or tasks[String(task_id)].get("target_id") != String(target_id) or not bool(result.get("completed", false)):
		return GameContracts.failure(&"invalid_task_result")
	var task: Dictionary = tasks[String(task_id)]
	var item := _item(target_id)
	if item.is_empty():
		return GameContracts.failure(&"unknown_building")
	if task["mode"] == "spare_parts" and not ledger.spend({"spare_parts": 1.0}, "repair_%s" % task_id):
		return GameContracts.failure(&"insufficient_resources")
	if task["mode"] == "refuel" and not ledger.spend({"nuclear_core": 1.0}, "refuel_%s" % task_id):
		return GameContracts.failure(&"insufficient_resources")
	if task["mode"] == "refuel":
		item["fuel_sols"] = float(ConfigDB.balance["buildings"]["reactor"]["core_duration_sols"])
	elif task["mode"] == "clean":
		item["dust"] = 0.0
	else:
		item["condition"] = "fragile" if task["mode"] == "weld" else "normal"
		item["health"] = 100.0
		item["isolated"] = false
	GameState.data["buildings"]["applied_tasks"][String(task_id)] = true
	tasks.erase(String(task_id))
	_log(target_id, &"task", &"info", &"building.task_completed")
	SignalBus.building_changed.emit(target_id, &"repaired")
	return GameContracts.success()

func request_action_task(building_id: StringName, action: StringName, crew_id: StringName) -> GameContracts.ValidationResult:
	var checked := validate_action(building_id, action)
	if not checked.ok or String(crew_id).is_empty():
		return checked if not checked.ok else GameContracts.failure(&"invalid_crew")
	if action == &"isolate":
		_item(building_id)["isolated"] = true
		SignalBus.building_changed.emit(building_id, &"isolated")
		return checked
	if _has_pending_target(building_id):
		return GameContracts.failure(&"building_task_pending")
	var task_id := "%s_%s_%d" % [action, building_id, int(GameState.data["buildings"]["next_id"])]
	GameState.data["buildings"]["next_id"] = int(GameState.data["buildings"]["next_id"]) + 1
	GameState.data["buildings"].get_or_add("pending_tasks", {})[task_id] = {"target_id": String(building_id), "mode": String(action), "crew_id": String(crew_id)}
	checked.params = {"task_id": task_id, "work_hours": 3.0}
	return checked

func _has_pending_target(building_id: StringName) -> bool:
	for task in GameState.data.get("buildings", {}).get("pending_tasks", {}).values():
		if task.get("target_id") == String(building_id):
			return true
	return false

func cancel_pending_task(task_id: StringName) -> void:
	GameState.data.get("buildings", {}).get("pending_tasks", {}).erase(String(task_id))

func _new_instance(id: String, definition: BuildingDefinition, origin: Vector2i) -> Dictionary:
	return {"id": id, "type": String(definition.type_id), "origin": [origin.x, origin.y],
		"size": [definition.footprint.x, definition.footprint.y], "enabled": true,
		"health": 100.0, "condition": "normal", "isolated": false, "dust": 0.0,
		"fuel_sols": float(ConfigDB.balance["buildings"]["reactor"].get("core_duration_sols", 0.0)) if definition.type_id == &"reactor" else 0.0,
		"crop": "none", "seed_planted": false, "unpowered_sols": 0.0}

func _placement_failure(code: StringName) -> GameContracts.PlacementResult:
	var result := GameContracts.PlacementResult.new(false, code)
	return result

func _is_unlocked(type_id: StringName) -> bool:
	if type_id in [&"base", &"isru", &"greenhouse", &"tunnel", &"laboratory"]:
		return true
	return GameState.data.get("research", {}).get("unlocked", []).has(String(type_id))

func _inside_reactor_exclusion(rect: Rect2i) -> bool:
	for item in GameState.data["buildings"]["instances"].values():
		if item.get("type") != "reactor":
			continue
		var origin: Array = item["origin"]
		var size: Array = item["size"]
		var other := Rect2i(int(origin[0]), int(origin[1]), int(size[0]), int(size[1]))
		if grid._edge_distance(rect, other) <= float(ConfigDB.balance["map"]["reactor_exclusion_radius_tiles"]):
			return true
	return false

func _find_tunnel_offset(rect: Rect2i, building_type: StringName, rotation_quarters: int) -> Variant:
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for x in [-1.0, -0.5, 0.5, 1.0]:
		offsets.append(Vector2(x, 0.0))
		offsets.append(Vector2(0.0, x))
	for x in [-1.0, -0.5, 0.5, 1.0]:
		for y in [-1.0, -0.5, 0.5, 1.0]:
			offsets.append(Vector2(x, y))
	for offset in offsets:
		if _touches_tunnel(rect, building_type, rotation_quarters, offset):
			return offset
	return null

func _touches_tunnel(rect: Rect2i, building_type: StringName = &"laboratory", rotation_quarters: int = 0, offset_m: Vector2 = Vector2.ZERO) -> bool:
	var candidate := {"type": String(building_type), "origin": [rect.position.x, rect.position.y], "size": [rect.size.x, rect.size.y], "rotation_quarters": rotation_quarters, "offset_m": [offset_m.x, offset_m.y]}
	for item in GameState.data["buildings"]["instances"].values():
		if item.get("type") != "tunnel" and not (building_type == &"tunnel" and item.get("type") == "base"):
			continue
		if not TunnelNetwork.is_open(item):
			continue
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				var cell := Vector2i(x, y)
				for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
					if TunnelNetwork.ports_meet(candidate, cell, item, direction):
						return true
	return false

func _near_energized(rect: Rect2i) -> bool:
	for link in grid.get_energy_links():
		if not bool(link["connected"]):
			continue
		var other: Dictionary = _item(StringName(link["building_id"]))
		if grid._edge_distance(rect, grid._rect(other)) <= float(ConfigDB.balance["map"]["energy_link_range_tiles"]):
			return true
	return false

func _item(building_id: StringName) -> Dictionary:
	return GameState.data.get("buildings", {}).get("instances", {}).get(String(building_id), {})

func _log(building_id: StringName, kind: StringName, severity: StringName, key: StringName) -> void:
	var logs: Dictionary = GameState.data["buildings"]["logs"]
	var entries: Array = logs.get(String(building_id), [])
	var entry := BuildingLogEntry.new()
	entry.id = StringName("%s_%d" % [building_id, entries.size() + 1])
	entry.kind = kind
	entry.severity = severity
	entry.message_key = key
	entry.sol = int(GameState.data["clock"]["sol"])
	entry.reason_id = entry.id
	entries.append(entry.as_dict())
	logs[String(building_id)] = entries
	SignalBus.building_log_added.emit(building_id, entry)
