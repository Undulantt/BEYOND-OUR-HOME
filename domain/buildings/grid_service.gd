class_name GridService
extends RefCounted

var building_service

func initialize() -> void:
	GameState.data["world"] = {"revealed": {}, "terrain": {}, "reservations": {}}
	for x in 4:
		for y in 4:
			GameState.data["world"]["revealed"]["%d,%d" % [x, y]] = true

func rebuild_from_state() -> void:
	pass

func step(_delta_seconds: float) -> void:
	pass

func is_revealed(cell: Vector2i) -> bool:
	var maximum := int(ConfigDB.balance["map"]["maximum_size"])
	if cell.x < 0 or cell.y < 0 or cell.x >= maximum or cell.y >= maximum:
		return false
	var sector_size := int(ConfigDB.balance["map"]["scan_sector_size"])
	return bool(GameState.data.get("world", {}).get("revealed", {}).get("%d,%d" % [cell.x / sector_size, cell.y / sector_size], false))

func terrain_at(cell: Vector2i) -> StringName:
	if not is_revealed(cell):
		return &"unknown"
	var key := "%d,%d" % [cell.x, cell.y]
	var terrain: Dictionary = GameState.data["world"].get("terrain", {})
	if terrain.has(key):
		return StringName(terrain[key])
	var layout := _layout()
	for patch in layout.get("terrain_patches", []):
		var values: Array = patch.get("rect", [])
		if values.size() == 4 and Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3])).has_point(cell):
			return StringName(patch["type"])
	return &"sterile"

func set_sector_terrain(sector: Vector2i, terrain_type: StringName) -> void:
	var size := int(ConfigDB.balance["map"]["scan_sector_size"])
	for x in size:
		for y in size:
			GameState.data["world"]["terrain"]["%d,%d" % [sector.x * size + x, sector.y * size + y]] = String(terrain_type)

func reveal_sector(sector: Vector2i) -> void:
	GameState.data["world"]["revealed"]["%d,%d" % [sector.x, sector.y]] = true

func validate_zone(rect: Rect2i, purpose: StringName) -> GameContracts.ValidationResult:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return GameContracts.failure(&"invalid_zone")
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var cell := Vector2i(x, y)
			if not is_revealed(cell):
				return GameContracts.failure(&"outside_revealed_map")
			if _occupied(cell, purpose):
				return GameContracts.failure(&"zone_occupied")
	return GameContracts.success()

func reserve_zone(owner_id: StringName, rect: Rect2i) -> GameContracts.ValidationResult:
	if String(owner_id).is_empty():
		return GameContracts.failure(&"invalid_owner")
	var reservations: Dictionary = GameState.data["world"]["reservations"]
	if reservations.has(String(owner_id)):
		return GameContracts.failure(&"zone_already_reserved")
	var result := validate_zone(rect, &"landing")
	if result.ok:
		reservations[String(owner_id)] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	return result

func release_zone(owner_id: StringName) -> void:
	GameState.data["world"].get("reservations", {}).erase(String(owner_id))

func get_energy_links() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if building_service == null:
		return result
	var buildings: Dictionary = GameState.data.get("buildings", {}).get("instances", {})
	var linked: Dictionary = {}
	for id in buildings:
		if buildings[id].get("type", "") == "reactor" and building_service.is_reactor_active(StringName(id)):
			for all_id in buildings:
				linked[all_id] = true
			break
	for id in buildings:
		var item: Dictionary = buildings[id]
		var charged := float(GameState.data.get("power", {}).get("stored", 0.0)) + float(GameState.data.get("power", {}).get("locked_stored", 0.0)) > 0.0
		var source: bool = item.get("type") == "solar_panel" or (item.get("type") == "battery" and charged)
		if source and bool(item.get("enabled", true)) and float(item.get("health", 0.0)) > 0.0:
			linked[id] = true
	var changed := true
	while changed:
		changed = false
		for id in buildings:
			if linked.has(id):
				continue
			var candidate: Dictionary = buildings[id]
			for other_id in linked:
				if _can_link(candidate, buildings[other_id]):
					linked[id] = true
					changed = true
					break
	for id in buildings:
		result.append({"building_id": id, "connected": linked.has(id)})
	return result

func _can_link(a: Dictionary, b: Dictionary) -> bool:
	if (a.get("type") == "tunnel" and not TunnelNetwork.is_open(a)) or (b.get("type") == "tunnel" and not TunnelNetwork.is_open(b)):
		return false
	var a_rect := _rect(a)
	var b_rect := _rect(b)
	var distance := _edge_distance(a_rect, b_rect)
	if a.get("type") == "tunnel" or b.get("type") == "tunnel":
		return distance <= 1.0
	return distance <= float(ConfigDB.balance["map"]["energy_link_range_tiles"])

func _edge_distance(a: Rect2i, b: Rect2i) -> float:
	var dx := maxi(0, maxi(a.position.x - b.end.x + 1, b.position.x - a.end.x + 1))
	var dy := maxi(0, maxi(a.position.y - b.end.y + 1, b.position.y - a.end.y + 1))
	return sqrt(float(dx * dx + dy * dy))

func _occupied(cell: Vector2i, _purpose: StringName) -> bool:
	for item in GameState.data.get("buildings", {}).get("instances", {}).values():
		if _rect(item).has_point(cell):
			return true
	for raw in GameState.data.get("world", {}).get("reservations", {}).values():
		var values: Array = raw
		if Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3])).has_point(cell):
			return true
	return false

func _rect(item: Dictionary) -> Rect2i:
	var origin: Array = item.get("origin", [0, 0])
	var size: Array = item.get("size", [1, 1])
	return Rect2i(int(origin[0]), int(origin[1]), int(size[0]), int(size[1]))

func _layout() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/initial_layout.json"))
	return parsed if parsed is Dictionary else {}
