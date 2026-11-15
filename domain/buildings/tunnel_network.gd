class_name TunnelNetwork
extends RefCounted

const PORT_SCENE_ROOT := "res://assets/3D assests/3dmodels_markers/"
const PORT_SCENES := {
	"base": "main_base.tscn",
	"isru": "isru.tscn",
	"greenhouse": "green_house.tscn",
	"laboratory": "laboratory.tscn",
	"refinery": "refinery.tscn",
	"printer_3d": "3d_printer.tscn",
	"tunnel": "tunnel_straight_2.tscn",
}
const TUNNEL_VARIANTS := {
	"straight": "tunnel_straight_2.tscn",
	"corner": "tunnel_corner.tscn",
	"t": "tunnel_intersection_t.tscn",
	"intersection": "tunnel_intersection.tscn",
	"cross": "tunnel_intersection.tscn",
}
const PORT_EPSILON := 0.025
static var _local_ports_cache: Dictionary = {}

static func marker_scene(item_or_type: Variant, variant: String = "") -> PackedScene:
	var item: Dictionary = item_or_type if item_or_type is Dictionary else {"type": String(item_or_type)}
	var type := String(item.get("type", ""))
	var filename := String(TUNNEL_VARIANTS.get(variant, "")) if type == "tunnel" and not variant.is_empty() else ""
	if filename.is_empty() and type == "tunnel":
		filename = String(TUNNEL_VARIANTS.get(String(item.get("variant", item.get("model_variant", ""))), PORT_SCENES.get(type, "")))
	if filename.is_empty():
		filename = String(PORT_SCENES.get(type, ""))
	if filename.is_empty():
		return null
	return load(PORT_SCENE_ROOT + filename) as PackedScene

static func has_tunnel_port(item: Dictionary) -> bool:
	return not marker_local_positions(item).is_empty()

static func marker_local_positions(item: Dictionary) -> Array[Vector2]:
	if String(item.get("type", "")) == "tunnel":
		var all_ports: Array[Vector2] = []
		for variant in TUNNEL_VARIANTS:
			var variant_scene := marker_scene(item, String(variant))
			for point in _scene_marker_positions(variant_scene):
				if not all_ports.has(point):
					all_ports.append(point)
		return all_ports
	var packed := marker_scene(item)
	return _scene_marker_positions(packed)

static func _scene_marker_positions(packed: PackedScene) -> Array[Vector2]:
	var empty: Array[Vector2] = []
	if packed == null:
		return empty
	var key := packed.resource_path
	if _local_ports_cache.has(key):
		return (_local_ports_cache[key] as Array[Vector2]).duplicate()
	var result: Array[Vector2] = []
	var root := packed.instantiate() as Node3D
	if root == null:
		return result
	for marker in root.find_children("*", "Marker3D", true, false):
		var marker_3d := marker as Marker3D
		if marker_3d != null:
			var point := _local_position_under_root(marker_3d, root)
			result.append(Vector2(point.x, point.z))
	root.free()
	_local_ports_cache[key] = result.duplicate()
	return result

static func _local_position_under_root(node: Node3D, root: Node3D) -> Vector3:
	var point := Vector3.ZERO
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			point = (current as Node3D).transform * point
		current = current.get_parent()
	return point

static func port_positions(item: Dictionary) -> Array[Vector2]:
	var origin: Array = item.get("origin", [0, 0])
	var size: Array = item.get("size", [1, 1])
	var center := Vector2(float(origin[0]) * 2.0 + float(size[0]), float(origin[1]) * 2.0 + float(size[1]))
	var offset_data: Variant = item.get("offset_m", Vector2.ZERO)
	var offset: Vector2 = offset_data if offset_data is Vector2 else Vector2(float(offset_data[0]), float(offset_data[1])) if offset_data is Array and offset_data.size() >= 2 else Vector2.ZERO
	var quarters: int = posmod(int(item.get("rotation_quarters", 0)), 4)
	var result: Array[Vector2] = []
	for local_point in marker_local_positions(item):
		var rotated_offset := local_point.rotated(-float(quarters) * PI * 0.5)
		result.append(center + offset + rotated_offset)
	return result

static func has_port_at(item: Dictionary, cell: Vector2i, direction: Vector2i) -> bool:
	return not _ports_at_cell_face(item, cell, direction).is_empty()

static func _ports_at_cell_face(item: Dictionary, cell: Vector2i, direction: Vector2i) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var rect := _rect(item)
	if not rect.has_point(cell):
		return result
	var origin: Array = item.get("origin", [0, 0])
	var size: Array = item.get("size", [1, 1])
	var center := Vector2(float(origin[0]) * 2.0 + float(size[0]), float(origin[1]) * 2.0 + float(size[1]))
	var offset_data: Variant = item.get("offset_m", Vector2.ZERO)
	var item_offset: Vector2 = offset_data if offset_data is Vector2 else Vector2(float(offset_data[0]), float(offset_data[1])) if offset_data is Array and offset_data.size() >= 2 else Vector2.ZERO
	var half_size := Vector2(float(size[0]), float(size[1]))
	for port in port_positions(item):
		var relative: Vector2 = port - center - item_offset
		var face_matches := false
		var cell_matches := false
		match direction:
			Vector2i.UP:
				face_matches = absf(relative.y + half_size.y) <= PORT_EPSILON
				cell_matches = port.x >= float(cell.x * 2) - PORT_EPSILON and port.x <= float((cell.x + 1) * 2) + PORT_EPSILON
			Vector2i.DOWN:
				face_matches = absf(relative.y - half_size.y) <= PORT_EPSILON
				cell_matches = port.x >= float(cell.x * 2) - PORT_EPSILON and port.x <= float((cell.x + 1) * 2) + PORT_EPSILON
			Vector2i.LEFT:
				face_matches = absf(relative.x + half_size.x) <= PORT_EPSILON
				cell_matches = port.y >= float(cell.y * 2) - PORT_EPSILON and port.y <= float((cell.y + 1) * 2) + PORT_EPSILON
			Vector2i.RIGHT:
				face_matches = absf(relative.x - half_size.x) <= PORT_EPSILON
				cell_matches = port.y >= float(cell.y * 2) - PORT_EPSILON and port.y <= float((cell.y + 1) * 2) + PORT_EPSILON
		if face_matches and cell_matches:
			result.append(port)
	return result

static func ports_meet(a: Dictionary, a_cell: Vector2i, b: Dictionary, direction: Vector2i) -> bool:
	for a_port in _ports_at_cell_face(a, a_cell, direction):
		for b_port in _ports_at_cell_face(b, a_cell + direction, -direction):
			if a_port.distance_to(b_port) <= PORT_EPSILON:
				return true
	return false

static func topology(instances: Dictionary) -> Dictionary:
	var occupied: Dictionary = {}
	var neighbors: Dictionary = {}
	for id in instances:
		var item: Dictionary = instances[id]
		if not has_tunnel_port(item):
			continue
		neighbors[id] = []
		var rect := _rect(item)
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				occupied[Vector2i(x, y)] = id
	for cell: Vector2i in occupied:
		var id: String = occupied[cell]
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var other: String = occupied.get(cell + direction, "")
			if not other.is_empty() and other != id and not neighbors[id].has(other) and ports_meet(instances[id], cell, instances[other], direction):
				neighbors[id].append(other)
	var connected: Dictionary = {}
	var queue: Array[String] = []
	for id in neighbors:
		if instances[id].get("type") == "base" and is_open(instances[id]):
			connected[id] = true
			queue.append(id)
	var cursor := 0
	while cursor < queue.size():
		var id := queue[cursor]
		cursor += 1
		for other: String in neighbors[id]:
			if not connected.has(other) and is_open(instances[other]):
				connected[other] = true
				queue.append(other)
	return {"neighbors": neighbors, "connected": connected}

static func is_open(item: Dictionary) -> bool:
	return has_tunnel_port(item) and item.get("condition", "normal") not in ["breached", "destroyed"] and not bool(item.get("isolated", false)) and bool(item.get("enabled", true)) and float(item.get("health", 100.0)) > 0.0

static func _rect(item: Dictionary) -> Rect2i:
	var origin: Array = item.get("origin", [0, 0])
	var size: Array = item.get("size", [1, 1])
	return Rect2i(int(origin[0]), int(origin[1]), int(size[0]), int(size[1]))

func rebuild_from_state() -> void:
	pass

func get_snapshot() -> Dictionary:
	var components: Array[Dictionary] = []
	var links: Array[Dictionary] = []
	var leaks: Array[Dictionary] = []
	var total := 0.0
	var instances: Dictionary = GameState.data.get("buildings", {}).get("instances", {})
	var graph := topology(instances)
	for id in instances:
		var item: Dictionary = instances[id]
		if item.get("type") != "tunnel":
			continue
		var loss := 0.0
		if item.get("condition") == "breached" and not bool(item.get("isolated", false)):
			for neighbor: String in graph["neighbors"].get(id, []):
				if graph["connected"].has(neighbor):
					loss = float(ConfigDB.balance["events"]["tunnel_breach"]["oxygen_loss_per_sol"])
					break
		if loss > 0.0:
			leaks.append({"building_id": id, "oxygen_loss_per_sol": loss})
			total += loss
		components.append({"building_id": id, "condition": item.get("condition", "normal"), "isolated": bool(item.get("isolated", false))})
		links.append({"building_id": id, "connected": graph["connected"].has(id), "neighbors": graph["neighbors"].get(id, []).duplicate()})
	return {"components": components, "links": links, "leaks": leaks, "oxygen_leak_per_sol": total}
