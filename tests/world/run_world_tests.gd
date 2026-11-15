extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameState.reset(1234)
	var ledger := ResourceLedger.new()
	ledger.initialize(ConfigDB.balance["initial_inventory"])
	var grid := GridService.new()
	var buildings := BuildingService.new()
	var power := PowerService.new()
	var production := ProductionService.new()
	var research := ResearchService.new()
	var scan := ScanService.new()
	var tunnels := TunnelNetwork.new()
	buildings.ledger = ledger
	buildings.grid = grid
	buildings.power = power
	buildings.research = research
	grid.building_service = buildings
	power.building_service = buildings
	power.grid_service = grid
	production.building_service = buildings
	production.power = power
	production.ledger = ledger
	research.power = power
	scan.grid = grid
	scan.power = power
	_check(buildings.initialize_layout().ok, "initial layout")
	var initial_graph := TunnelNetwork.topology(GameState.data["buildings"]["instances"])
	_check(initial_graph["neighbors"]["base_1"].has("tunnel_1") and initial_graph["neighbors"]["base_1"].has("tunnel_2"), "base ports meet both starter tunnels")
	_check(initial_graph["neighbors"]["isru_1"].has("tunnel_isru"), "ISRU port meets its tunnel")
	_check(initial_graph["neighbors"]["greenhouse_1"].has("tunnel_2"), "greenhouse port meets its tunnel")
	_check(initial_graph["connected"].has("isru_1") and initial_graph["connected"].has("greenhouse_1"), "starter buildings connect through matching ports")
	_check(not TunnelNetwork.has_tunnel_port({"type": "solar_panel", "origin": [0, 0], "size": [3, 3]}), "unmarked model has no tunnel port")
	# Revalidate the starter ISRU site as a fresh placement: the 2x2 structure
	# must recover its authored lateral offset to meet the 1-cell tunnel.
	var starter_isru: Dictionary = GameState.data["buildings"]["instances"]["isru_1"].duplicate(true)
	GameState.data["buildings"]["instances"].erase("isru_1")
	GameState.data["buildings"]["instances"]["isru_power_probe"] = {
		"type": "solar_panel", "origin": [6, 14], "size": [3, 3], "enabled": true, "health": 100.0}
	var isru_request := GameContracts.PlacementRequest.new(&"isru", Vector2i(10, 14), 2)
	var isru_placement := buildings.validate_placement(isru_request)
	_check(isru_placement.ok and isru_placement.cells.size() == 4
		and isru_placement.params.get("offset_m", []) == [0.0, 1.0],
		"new ISRU placement recovers the starter site's tunnel offset")
	if isru_placement.ok:
		var isru_probe := {"type": "isru", "origin": [10, 14], "size": [2, 2],
			"rotation_quarters": 2, "offset_m": isru_placement.params["offset_m"]}
		GameState.data["buildings"]["instances"]["isru_port_probe"] = isru_probe
		var isru_graph := TunnelNetwork.topology(GameState.data["buildings"]["instances"])
		_check(isru_graph["neighbors"]["isru_port_probe"].has("tunnel_isru"),
			"new ISRU placement connects to its adjacent tunnel")
	GameState.data["buildings"]["instances"].erase("isru_power_probe")
	GameState.data["buildings"]["instances"].erase("isru_port_probe")
	GameState.data["buildings"]["instances"]["isru_1"] = starter_isru
	var wrong_port := buildings.validate_placement(GameContracts.PlacementRequest.new(&"tunnel", Vector2i(14, 17)))
	_check(not wrong_port.ok, "adjacency without matching markers is rejected")
	_check(grid.is_revealed(Vector2i(31, 31)), "initial 32 map")
	_check(not grid.is_revealed(Vector2i(32, 31)), "outside initial map")
	_check(grid.terrain_at(Vector2i(10, 14)) == &"aquifer", "aquifer")
	_check(grid.terrain_at(Vector2i(24, 23)) == &"iron_regolith", "mineral")
	_check(ledger.get_amount(&"iron_plates") == 32.0, "initial buildings free")
	var tunnel := GameContracts.PlacementRequest.new(&"tunnel", Vector2i(15, 17))
	_check(buildings.place(tunnel).ok, "tutorial tunnel")
	# Probe an isolated tunnel site in revealed space so each lab orientation
	# exercises marker alignment without relying on the starter layout geometry.
	for tunnel_rotation in range(4):
		GameState.data["buildings"]["instances"]["isolated_tunnel_probe"] = {
			"type": "tunnel", "origin": [25, 20], "size": [1, 1], "rotation_quarters": tunnel_rotation
		}
		for lab_rotation in range(4):
			var alignment_found := false
			for x in range(22, 29):
				for y in range(17, 24):
					var aligned := buildings.validate_placement(GameContracts.PlacementRequest.new(
						&"laboratory", Vector2i(x, y), lab_rotation))
					if aligned.ok and aligned.cells.size() == 4:
						alignment_found = true
						break
				if alignment_found:
					break
			_check(alignment_found, "lab rotation %d aligns with a tunnel in isolation" % lab_rotation)
	GameState.data["buildings"]["instances"].erase("isolated_tunnel_probe")
	var lab := GameContracts.PlacementRequest.new(&"laboratory", Vector2i(15, 18))
	_check(buildings.place(lab).ok, "tutorial lab")
	var lab_instance: Dictionary = GameState.data["buildings"]["instances"]["laboratory_4"]
	_check(lab_instance["size"] == [2, 2], "2x2 building occupies four cells")
	var built_graph := TunnelNetwork.topology(GameState.data["buildings"]["instances"])
	_check(built_graph["neighbors"]["base_1"].has("tunnel_3") and built_graph["neighbors"]["tunnel_3"].has("laboratory_4"), "tutorial ports meet exactly")
	# Existing rotated 2x2 layout entries keep the same cells and port positions
	# as the authored, quarter-turned model.
	var isru_item: Dictionary = GameState.data["buildings"]["instances"]["isru_1"]
	_check(isru_item["size"] == [2, 2] and isru_item["rotation_quarters"] == 2
		and TunnelNetwork.ports_meet(isru_item, Vector2i(11, 15), GameState.data["buildings"]["instances"]["tunnel_isru"], Vector2i.RIGHT),
		"rotated 2x2 ISRU port meets its tunnel at the occupied edge")
	var overlap_iron := ledger.get_amount(&"iron_plates")
	var rotated_overlap := {"type": "laboratory", "origin": [22, 22], "size": [2, 2], "rotation_quarters": 1}
	GameState.data["buildings"]["instances"]["rotated_lab_test"] = rotated_overlap
	var overlap := buildings.place(GameContracts.PlacementRequest.new(&"laboratory", Vector2i(23, 23), 3))
	_check(not overlap.ok and overlap.error_code == &"zone_occupied"
		and is_equal_approx(ledger.get_amount(&"iron_plates"), overlap_iron),
		"rotated 2x2 overlap is rejected without charging")
	GameState.data["buildings"]["instances"].erase("rotated_lab_test")
	var invalid := buildings.place(GameContracts.PlacementRequest.new(&"laboratory", Vector2i(250, 250)))
	_check(not invalid.ok and ledger.get_amount(&"iron_plates") == 15.0, "invalid placement free")
	GameState.data["research"]["unlocked"].append("solar_panel")
	var panel := GameContracts.PlacementRequest.new(&"solar_panel", Vector2i(10, 18))
	_check(buildings.place(panel).ok, "tutorial panel")
	_check(buildings.validate_placement(GameContracts.PlacementRequest.new(&"solar_panel", Vector2i(11, 11))).error_code == &"zone_occupied",
		"solar panel clears the base model overhang")
	_check(buildings.validate_placement(GameContracts.PlacementRequest.new(&"solar_panel", Vector2i(7, 13))).error_code == &"zone_occupied",
		"solar panel clears the ISRU model overhang")
	_check(buildings._has_visual_overhang_conflict(Rect2i(12, 12, 2, 2), &"battery"),
		"portless battery clears the base model overhang")
	_check(buildings._has_visual_overhang_conflict(Rect2i(8, 13, 2, 2), &"battery"),
		"portless battery clears the ISRU model overhang")
	_check(ledger.get_amount(&"iron_plates") == 5.0, "tutorial budget")
	_check(not buildings.place(GameContracts.PlacementRequest.new(&"isru", Vector2i(26, 26))).ok, "isru needs aquifer")
	_check(not buildings.place(GameContracts.PlacementRequest.new(&"mine", Vector2i(24, 23))).ok, "mine locked")
	_check(not grid.reserve_zone(&"rocket_1", Rect2i(30, 30, 8, 8)).ok, "zone boundary")
	_check(not scan.scan(Vector2i(32, 0)).ok, "scan maximum 256")
	_check(not scan.scan(Vector2i(6, 6)).ok, "scan adjacency")
	_check(not scan.scan(Vector2i(4, 0)).ok, "scan locked")
	GameState.data["research"]["unlocked"].append("satellite_scan")
	GameState.data["research"]["points"] = 8.0
	GameState.data["power"]["stored"] = 6.0
	_check(scan.scan(Vector2i(4, 0)).ok, "scan contiguous")
	_check(grid.is_revealed(Vector2i(32, 0)), "sector revealed")
	_check(not scan.scan(Vector2i(4, 0)).ok, "scan once")
	buildings.apply_damage(&"tunnel_1", 20.0, &"test")
	_check(tunnels.get_snapshot()["oxygen_leak_per_sol"] == 4.0, "breach leak")
	var task := buildings.request_repair(&"tunnel_1", &"weld", &"crew_1")
	_check(task.ok, "repair task")
	var task_id := StringName(task.params.get("task_id", ""))
	_check(buildings.apply_task_result(task_id, &"tunnel_1", {"completed": true}).ok, "repair apply")
	_check(not buildings.apply_task_result(task_id, &"tunnel_1", {"completed": true}).ok, "repair once")
	_check(buildings.get_status(&"tunnel_1").condition == &"fragile", "weld fragile")
	_check(tunnels.get_snapshot()["oxygen_leak_per_sol"] == 0.0, "repair stops leak")
	power.step(0.1)
	_check(power.is_powered(&"isru_1"), "initial reactor powers isru")
	var oxygen_before := ledger.get_amount(&"oxygen")
	production.step(0.1)
	_check(ledger.get_amount(&"oxygen") > oxygen_before, "powered isru produces")
	GameState.data["buildings"]["instances"]["reactor_1"]["fuel_sols"] = 0.0
	GameState.data["buildings"]["instances"]["solar_panel_5"]["enabled"] = false
	power.step(0.1)
	_check(not power.is_powered(&"isru_1"), "reactor outage")
	oxygen_before = ledger.get_amount(&"oxygen")
	production.step(0.1)
	_check(is_equal_approx(ledger.get_amount(&"oxygen"), oxygen_before), "unpowered isru stops")
	var food_before := ledger.get_amount(&"food")
	production.step(30.0)
	_check(GameState.data["buildings"]["instances"]["greenhouse_1"]["crop"] == "dead", "crop dies after grace")
	_check(is_equal_approx(ledger.get_amount(&"food"), food_before), "dead crop no food")
	GameState.data["buildings"]["instances"]["reactor_1"]["fuel_sols"] = 14.0
	power.step(0.1)
	_check(research.start_research(&"battery").ok, "research starts with lab")
	_check(research.consume_work({"task_id": "science_1", "target_id": "laboratory_4", "work_hours": 14.0}).ok, "research work")
	_check(GameState.data["research"]["unlocked"].has("battery"), "battery unlocked")
	_check(not research.consume_work({"task_id": "science_1", "target_id": "laboratory_4", "work_hours": 14.0}).ok, "research work once")
	var saved := GameState.to_dict()
	GameState.from_dict(saved)
	_check(buildings.get_all_statuses().size() == 10, "state restored building count")
	var scene: PackedScene = load("res://scenes/world/world.tscn")
	var world: MartianWorld = scene.instantiate()
	get_tree().root.add_child(world)
	world.configure(buildings, grid)
	_check(world.get_node("Buildings").get_child_count() == 10, "world renders buildings")
	var resource_nodes := world.get_node("Terrain/ResourceNodes")
	_check(resource_nodes.get_child_count() == 40, "initial aquifer and mineral deposits render at exact resource cells")
	var first_resource_node := resource_nodes.get_child(0) as MeshInstance3D
	_check(first_resource_node != null and first_resource_node.mesh is SphereMesh
		and first_resource_node.scale.y <= 0.15, "resource node markers stay low profile")
	var first_mineral := resource_nodes.get_node_or_null("iron_regolith_24_23") as MeshInstance3D
	_check(first_mineral != null and first_mineral.position.x >= 48.0 and first_mineral.position.x < 50.0
		and first_mineral.position.z >= 46.0 and first_mineral.position.z < 48.0,
		"mineral marker sits inside its actual 2 m resource cell")
	grid.set_sector_terrain(Vector2i(4, 0), &"iron_regolith")
	world.rebuild_from_state()
	_check(world.get_node("Terrain/ResourceNodes").get_child_count() == 104,
		"scanned mineral deposits render from revealed terrain")
	grid.set_sector_terrain(Vector2i(5, 0), &"iron_regolith")
	world.rebuild_from_state()
	_check(world.get_node("Terrain/ResourceNodes").get_child_count() == 104,
		"unrevealed mineral deposits stay hidden")
	var visual_ports: Dictionary = {}
	for id in ["base_1", "isru_1", "greenhouse_1", "tunnel_isru", "tunnel_1", "tunnel_2", "tunnel_3", "laboratory_4"]:
		var model := world.get_node("Buildings").get_node_or_null(id) as Node3D
		_check(model != null, "visual exists for %s" % id)
		if model == null:
			continue
		var actual := _visual_port_positions(model)
		visual_ports[id] = actual
		_check(not actual.is_empty(), "visual keeps authored markers for %s" % id)
		_check(is_equal_approx(model.global_position.y, 0.006), "authored model ground plane for %s" % id)
		for marker_node in model.find_children("*", "Marker3D", true, false):
			var marker := marker_node as Marker3D
			_check(is_equal_approx(marker.global_position.y, 0.406), "3D port height for %s" % id)
		for point in actual:
			_check(_has_point(TunnelNetwork.port_positions(GameState.data["buildings"]["instances"][id]), point), "visual marker agrees with topology for %s" % id)
	for id in ["base_1", "isru_1", "greenhouse_1", "tunnel_isru", "tunnel_1", "tunnel_2", "tunnel_3", "laboratory_4"]:
		for other in built_graph["neighbors"].get(id, []):
			if visual_ports.has(id) and visual_ports.has(other):
				_check(_ports_touch(visual_ports[id], visual_ports[other]), "visible ports coincide for %s and %s" % [id, other])
	world.begin_placement(&"laboratory")
	var rotate_key := InputEventKey.new()
	rotate_key.keycode = KEY_R
	rotate_key.pressed = true
	world._unhandled_input(rotate_key)
	_check(world.placement_rotation_quarters == 1, "R rotates placement preview")
	world.cancel_placement()
	_check(world.focus_target(&"base_1"), "focus target")
	world.rebuild_from_state()
	_check(world.get_node("Buildings").get_child_count() == 10, "world restore without duplicates")
	world.queue_free()
	if failures.is_empty():
		print("R2 world tests passed")
		get_tree().call_deferred("quit", 0)
	else:
		for message in failures:
			push_error(message)
		get_tree().call_deferred("quit", 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _visual_port_positions(model: Node3D) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for node in model.find_children("*", "Marker3D", true, false):
		var marker := node as Marker3D
		if marker != null:
			points.append(Vector2(marker.global_position.x, marker.global_position.z))
	return points

func _has_point(points: Array[Vector2], expected: Vector2) -> bool:
	for point in points:
		if point.distance_to(expected) <= 0.025:
			return true
	return false

func _ports_touch(a: Array[Vector2], b: Array[Vector2]) -> bool:
	for point in a:
		if _has_point(b, point):
			return true
	return false
