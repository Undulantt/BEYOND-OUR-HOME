extends Node

var main: MissionMain
var checks := 0
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var captures: Array[String] = []

func _ready() -> void:
	main = preload("res://scenes/integration/main.tscn").instantiate()
	add_child(main)
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL ", label)

func settle() -> void:
	for frame in 5:
		await get_tree().process_frame

func capture(label: String) -> void:
	for entry in main.dialogue.get_entries():
		main.dialogue.acknowledge(StringName(entry["id"]))
	await settle()
	await RenderingServer.frame_post_draw
	var path := "user://models-%s.png" % label
	get_viewport().get_texture().get_image().save_png(path)
	captures.append(path)

func bounds_in_world(model: Node3D) -> AABB:
	return model.global_transform * main.world._model_bounds(model)

func run() -> void:
	main._start_new([&"medic", &"engineer_a", &"botanist_a", &"scientist_a"])
	GameClock.set_paused(true)
	GameState.data["clock"]["elapsed"] = 15.0
	main.dialogue.skip_tutorial()
	main.hud.close_panel()
	await settle()
	await capture("initial")
	var gallery := Node3D.new()
	main.world.add_child(gallery)
	var index := 0
	for kind in MartianWorld.BUILDING_MODELS:
		var packed: PackedScene = MartianWorld.BUILDING_MODELS[kind]
		var definition := BuildingDefinition.from_balance(StringName(kind))
		for turn in 4:
			var model := packed.instantiate() as Node3D
			gallery.add_child(model)
			model.rotation.y = float(turn) * PI * 0.5
			var origin := [50, 50]
			var footprint := [definition.footprint.x, definition.footprint.y]
			check(main.world._fit_model_to_footprint(model, origin, footprint), "%s rotation %d fits" % [kind, turn])
			var bounds := bounds_in_world(model)
			var rect := Rect2(Vector2(50.0, 50.0), Vector2(footprint[0], footprint[1]))
			check(rect.grow(0.001).encloses(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))), "%s rotation %d stays in its occupied cells" % [kind, turn])
			check(absf(bounds.get_center().x - rect.get_center().x) < 0.001 and absf(bounds.get_center().z - rect.get_center().y) < 0.001, "%s rotation %d centered" % [kind, turn])
			var ground_y := bounds.position.y
			if kind == "landing_pad":
				for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
					if String(mesh.name).replace(".", "").replace("_", "") == "Cylinder009":
						ground_y = (mesh.global_transform * mesh.get_aabb()).position.y
			check(absf(ground_y - 0.025) < 0.001, "%s rests above ground" % kind)
			if turn == 0:
				measurements.append({"type": kind, "footprint": footprint, "size": [bounds.size.x, bounds.size.y, bounds.size.z], "scale": model.scale.x})
			model.queue_free()
		index += 1
	for packed: PackedScene in [MartianWorld.TUNNEL_STRAIGHT, MartianWorld.TUNNEL_CORNER, MartianWorld.TUNNEL_T, MartianWorld.TUNNEL_CROSS]:
		var model := packed.instantiate() as Node3D
		gallery.add_child(model)
		var raw := main.world._model_bounds(model)
		measurements.append({"type": packed.resource_path.get_file(), "raw_position": [raw.position.x, raw.position.y, raw.position.z], "raw_size": [raw.size.x, raw.size.y, raw.size.z]})
		model.queue_free()
	# Every orthogonal neighbor mask must point the selected asset's ports at neighbors.
	var original := GameState.to_dict()
	# Replacing the starter ISRU at its same site must recover the authored 1 m
	# offset so the rotated 2x2 port lands on the one-cell tunnel port.
	GameState.data["research"]["unlocked"].append("isru")
	main.ledger.add(BuildingDefinition.from_balance(&"isru").cost, "isru-port-test-funding")
	GameState.data["buildings"]["instances"].erase("isru_1")
	var replacement_isru := main.building.place(GameContracts.PlacementRequest.new(&"isru", Vector2i(10, 14), 2))
	check(replacement_isru.ok, "ISRU placement remains proximity-powered beside an open tunnel")
	if replacement_isru.ok:
		var replacement_item: Dictionary = GameState.data["buildings"]["instances"][String(replacement_isru.params["building_id"])]
		check(replacement_item["offset_m"] == [0.0, 1.0], "ISRU placement applies the 1 m port alignment offset")
		check(TunnelNetwork.ports_meet(replacement_item, Vector2i(11, 15), original["buildings"]["instances"]["tunnel_isru"], Vector2i(1, 0)), "placed ISRU port physically meets its tunnel")
	GameState.from_dict(original)
	SignalBus.state_restored.emit()
	# Place every building through its real service, with explicit test terrain/funding.
	for kind in MartianWorld.BUILDING_MODELS:
		GameState.from_dict(original)
		SignalBus.state_restored.emit()
		var definition := BuildingDefinition.from_balance(StringName(kind))
		GameState.data["research"]["unlocked"].append(kind)
		main.ledger.add(definition.cost, "model-test-funding")
		var at := Vector2i(24, 23)
		GameState.data["buildings"]["instances"]["qa_tunnel"] = main.building._new_instance("qa_tunnel", BuildingDefinition.from_balance(&"tunnel"), Vector2i(23, 24))
		if definition.terrain_rule != &"any":
			for x in definition.footprint.x:
				for y in definition.footprint.y:
					GameState.data["world"]["terrain"]["%d,%d" % [at.x + x, at.y + y]] = String(definition.terrain_rule)
		var inventory := main.ledger.get_snapshot()
		var request := GameContracts.PlacementRequest.new(StringName(kind), at)
		var placed := main.building.place(request)
		check(placed.ok, "%s places using its real requirements" % kind)
		if placed.ok:
			var id := StringName(placed.params["building_id"])
			var status := main.building.get_status(id)
			check(status.cells.size() == definition.footprint.x * definition.footprint.y, "%s occupies its complete footprint" % kind)
			var visual: Node3D = main.world.buildings_root.get_node(NodePath(String(id)))
			check(visual.scene_file_path == MartianWorld.BUILDING_MODELS[kind].resource_path, "%s renders replacement asset without a fallback cube" % kind)
			check(main.world._building_at(at) == id, "%s remains selectable on the map" % kind)
			for resource in definition.cost:
				check(is_equal_approx(main.ledger.get_amount(StringName(resource)), float(inventory.get(resource, 0.0)) - float(definition.cost[resource])), "%s spends %s exactly once" % [kind, resource])
			var after := main.ledger.get_snapshot()
			check(not main.building.place(request).ok and main.ledger.get_snapshot() == after, "%s rejects overlap without charging twice" % kind)
	GameState.from_dict(original)
	SignalBus.state_restored.emit()
	var instances: Dictionary = GameState.data["buildings"]["instances"]
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var center_tunnel := fixture("tunnel", Vector2i(16, 16))
	var asset_ports := {
		"tunnel_straight_2.tscn": [Vector2i.UP, Vector2i.DOWN],
		"tunnel_corner.tscn": [Vector2i.UP, Vector2i.LEFT],
		"tunnel_intersection_t.tscn": [Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT],
		"tunnel_intersection.tscn": [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	}
	for mask in 16:
		instances.clear()
		for bit in 4:
			if mask & (1 << bit):
				var cell := Vector2i(16, 16) + directions[bit]
				instances["neighbor_%d" % bit] = {"type": "tunnel", "origin": [cell.x, cell.y], "size": [1, 1], "condition": "normal", "health": 100.0, "isolated": false}
		var selected := main.world._tunnel_model(center_tunnel)
		var model: Node3D = selected["scene"].instantiate()
		gallery.add_child(model)
		model.rotation.y = selected["rotation"]
		check(main.world._fit_model_to_footprint(model, [16, 16], [1, 1], true), "tunnel mask %d fits" % mask)
		var actual_ports: Array[Vector2i] = []
		for port: Vector2i in asset_ports[selected["scene"].resource_path.get_file()]:
			var point := model.global_transform * Vector3(port.x, 0.0, port.y)
			var direction := Vector2i(roundi((point.x - 16.5) * 2.0), roundi((point.z - 16.5) * 2.0))
			actual_ports.append(direction)
			check(Vector2(point.x, point.z).is_equal_approx(Vector2(16.5, 16.5) + Vector2(direction) * 0.5), "tunnel mask %d port stays at the cell edge" % mask)
		for bit in 4:
			if mask & (1 << bit):
				check(actual_ports.has(directions[bit]), "tunnel mask %d points its authored port at neighbor %d" % [mask, bit])
		model.queue_free()
	# A laboratory next to a tunnel must be represented as a physical connection.
	instances.clear()
	instances["laboratory_test"] = fixture("laboratory", Vector2i(17, 16), Vector2i(2, 2))
	check(main.world._tunnel_connections(center_tunnel).has(Vector2i(1, 0)), "visual tunnel recognizes neighboring laboratory")
	# The starter ISRU occupies two logical cells per side. Its authored port and
	# one-cell tunnel must still resolve to the same physical junction at 2 m/cell.
	instances.clear()
	var isru := fixture("isru", Vector2i(10, 14), Vector2i(2, 2))
	isru["rotation_quarters"] = 2
	isru["offset_m"] = [0.0, 1.0]
	instances["isru_test"] = isru
	var isru_tunnel := fixture("tunnel", Vector2i(12, 15))
	instances["isru_tunnel"] = isru_tunnel
	check(TunnelNetwork.ports_meet(isru_tunnel, Vector2i(12, 15), isru, Vector2i(-1, 0)), "ISRU marker meets adjacent tunnel in topology")
	check(main.world._tunnel_connections(isru_tunnel).has(Vector2i(-1, 0)), "visual tunnel recognizes rotated 2x2 ISRU port")
	# A real chain must reach the base; diagonal contact and sealed/broken segments do not.
	instances.clear()
	instances["base_1"] = fixture("base", Vector2i(10, 10), Vector2i(3, 3))
	instances["a"] = fixture("tunnel", Vector2i(13, 11))
	instances["b"] = fixture("tunnel", Vector2i(14, 11))
	instances["c"] = fixture("tunnel", Vector2i(15, 11))
	instances["remote"] = fixture("tunnel", Vector2i(22, 22))
	instances["diagonal"] = fixture("tunnel", Vector2i(16, 12))
	check(linked("c"), "tunnel chain connects to base")
	check(not linked("remote"), "detached tunnel is not reported connected")
	check(not linked("diagonal"), "diagonal contact does not connect a tunnel")
	main.building.apply_damage(&"b", 30.0, &"test")
	check(not linked("b") and not linked("c"), "breach disconnects the downstream branch")
	check(main.tunnel.get_snapshot()["oxygen_leak_per_sol"] == 4.0, "connected breach leaks exactly once")
	check(main.building.request_action_task(&"b", &"isolate", &"crew_1").ok, "damaged tunnel can be isolated")
	check(main.world.buildings_root.get_node("b").find_children("SealedPort_*", "MeshInstance3D", true, false).size() == 2, "isolating closes both physical tunnel ports")
	check(is_zero_approx(main.tunnel.get_snapshot()["oxygen_leak_per_sol"]), "isolation stops the leak")
	check(not main.building._touches_tunnel(Rect2i(14, 10, 1, 1)), "sealed tunnel cannot satisfy construction connection")
	var repair := main.building.request_repair(&"b", &"weld", &"crew_1")
	check(repair.ok and main.building.apply_task_result(StringName(repair.params.get("task_id", "")), &"b", {"completed": true}).ok, "repair completes through building service")
	check(linked("b") and linked("c"), "repair restores downstream connectivity")
	check(main.world.buildings_root.get_node("b").find_children("SealedPort_*", "MeshInstance3D", true, false).is_empty(), "repair opens the connected ports again")
	main.building.apply_damage(&"remote", 30.0, &"test")
	check(is_zero_approx(main.tunnel.get_snapshot()["oxygen_leak_per_sol"]), "disconnected broken tunnel cannot drain colony oxygen")
	main.building.set_enabled(&"b", false)
	check(not linked("c"), "disabled conduit does not carry the network")
	check(not main.grid._can_link(instances["b"], instances["c"]), "disabled conduit cannot relay energy")
	main.building.set_enabled(&"b", true)
	check(main.building.remove(&"b").ok and not linked("c"), "removing a bridge disconnects the branch")
	instances["b"] = fixture("tunnel", Vector2i(14, 11))
	check(linked("c"), "replacing the bridge reconnects the branch")
	var chain_state := GameState.to_dict()
	GameState.from_dict(chain_state)
	check(linked("c"), "network is reconstructed from saved state")
	# Atlas of all sixteen physical junction configurations, using the real renderer.
	instances = GameState.data["buildings"]["instances"]
	instances.clear()
	for mask in 16:
		var center := Vector2i(6 + (mask % 4) * 6, 6 + (mask / 4) * 6)
		instances["mask_%d" % mask] = fixture("tunnel", center)
		for bit in 4:
			if mask & (1 << bit):
				instances["mask_%d_neighbor_%d" % [mask, bit]] = fixture("tunnel", center + directions[bit])
	main.world.rebuild_from_state()
	for mask in 16:
		var model := main.world.buildings_root.get_node("mask_%d" % mask)
		var neighbor_count := 0
		for bit in 4:
			if mask & (1 << bit):
				neighbor_count += 1
		var expected_caps := 2 - neighbor_count if neighbor_count <= 1 else 0
		check(model.find_children("SealedPort_*", "MeshInstance3D", true, false).size() == expected_caps, "tunnel mask %d seals only unused ports" % mask)
	main.hud.hide()
	main.world.terrain_root.hide()
	for visual in main.world._crew_visuals.values():
		visual.hide()
	var floor_visual := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(36.0, 36.0)
	floor_visual.mesh = floor_mesh
	floor_visual.position = Vector3(16.0, -0.01, 16.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("253442")
	floor_visual.material_override = floor_material
	gallery.add_child(floor_visual)
	for mask in 16:
		var caption := Label3D.new()
		caption.text = "%02d" % mask
		caption.font_size = 64
		caption.pixel_size = 0.012
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		caption.position = Vector3(6 + mask % 4 * 6, 0.6, 8.6 + (mask / 4) * 6)
		gallery.add_child(caption)
	var camera := Camera3D.new()
	main.world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28.0
	camera.position = Vector3(15.0, 50.0, 15.0)
	camera.look_at(Vector3(15.0, 0.0, 15.0), Vector3.FORWARD)
	camera.current = true
	await capture("tunnel-atlas")
	# Show every replacement building beside a labelled footprint at the same world scale.
	main.world.buildings_root.hide()
	for child in gallery.get_children():
		if child is Label3D:
			child.queue_free()
	index = 0
	for kind in MartianWorld.BUILDING_MODELS:
		var model: Node3D = MartianWorld.BUILDING_MODELS[kind].instantiate()
		gallery.add_child(model)
		var definition := BuildingDefinition.from_balance(StringName(kind))
		var at := [3 + index % 4 * 8, 3 + (index / 4) * 9]
		main.world._fit_model_to_footprint(model, at, [definition.footprint.x, definition.footprint.y])
		var caption := Label3D.new()
		caption.text = "%s %d×%d" % [kind, definition.footprint.x, definition.footprint.y]
		caption.font_size = 40
		caption.pixel_size = 0.018
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		caption.position = Vector3(at[0] + definition.footprint.x * 0.5, 0.8, at[1] + definition.footprint.y + 0.8)
		gallery.add_child(caption)
		for edge in [
			[Vector3(at[0], 0.005, at[1]), Vector3(definition.footprint.x, 0.01, 0.025)],
			[Vector3(at[0], 0.005, at[1] + definition.footprint.y), Vector3(definition.footprint.x, 0.01, 0.025)],
			[Vector3(at[0], 0.005, at[1]), Vector3(0.025, 0.01, definition.footprint.y)],
			[Vector3(at[0] + definition.footprint.x, 0.005, at[1]), Vector3(0.025, 0.01, definition.footprint.y)]
		]:
			var outline := MeshInstance3D.new()
			var line := BoxMesh.new()
			line.size = edge[1]
			outline.mesh = line
			outline.position = edge[0] + line.size * 0.5
			gallery.add_child(outline)
		index += 1
	camera.position = Vector3(40.0, 50.0, 45.0)
	camera.look_at(Vector3(16.0, 0.0, 16.0), Vector3.UP)
	camera.size = 35.0
	await capture("building-gallery")
	camera.queue_free()
	gallery.queue_free()
	main.world.camera_rig.camera.current = true
	main.world.buildings_root.show()
	main.world.terrain_root.show()
	main.hud.show()
	for visual in main.world._crew_visuals.values():
		visual.show()
	GameState.from_dict(original)
	SignalBus.state_restored.emit()
	await settle()
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "measurements": measurements, "captures": captures}
	var output := FileAccess.open("user://models-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("MODELS QA: ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)

func fixture(kind: String, at: Vector2i, footprint: Vector2i = Vector2i.ONE) -> Dictionary:
	return {"id": kind, "type": kind, "origin": [at.x, at.y], "size": [footprint.x, footprint.y], "condition": "normal", "health": 100.0, "enabled": true, "isolated": false}

func linked(id: String) -> bool:
	for link in main.tunnel.get_snapshot()["links"]:
		if link["building_id"] == id:
			return link["connected"]
	return false
