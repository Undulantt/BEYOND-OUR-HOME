extends Node

var main: MissionMain
var routes: Array[Dictionary] = []
var failures: Array[String] = []

func _ready() -> void:
	main = preload("res://scenes/integration/main.tscn").instantiate()
	add_child(main)
	call_deferred("run")

func require(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		print("FAIL ", label)

func run() -> void:
	SettingsService.apply_settings({"show_tutorial": false})
	for route in ["single_worker_8h", "two_workers_8h", "wait_then_research", "repair_and_first_rocket"]:
		main._start_new([&"engineer_a", &"medic", &"botanist_a", &"scientist_a"])
		main.dialogue.skip_tutorial()
		require(main.building.place(GameContracts.PlacementRequest.new(&"tunnel", Vector2i(15, 17))).ok, route + " tunnel")
		var lab := main.building.place(GameContracts.PlacementRequest.new(&"laboratory", Vector2i(15, 18)))
		require(lab.ok, route + " lab")
		main.power.step(0.0)
		if route == "wait_then_research":
			main.session.update(90.0)
		require(main.research.start_research(&"solar_panel").ok, route + " research starts")
		var lab_id := StringName(lab.params["building_id"])
		require(main.crew.queue_research(&"crew_4", lab_id, 8.0).ok, route + " scientist assigned")
		if route != "single_worker_8h":
			require(main.crew.queue_research(&"crew_1", lab_id, 8.0).ok, route + " second worker assigned")
		var elapsed := 0.0
		while elapsed < 120.0 and not main.research.get_snapshot().get("unlocked", []).has("solar_panel"):
			main.session.update(0.1)
			elapsed += 0.1
		var unlocked: bool = main.research.get_snapshot().get("unlocked", []).has("solar_panel")
		var record := {"route": route, "solar_unlocked": unlocked, "seconds_until_unlock_or_timeout": snappedf(elapsed, 0.1), "sol": GameClock.get_snapshot().get("sol"), "research_progress": main.research.get_snapshot().get("progress"), "iron_after_lab": main.ledger.get_amount(&"iron_plates")}
		if unlocked:
			require(main.building.place(GameContracts.PlacementRequest.new(&"solar_panel", Vector2i(10, 18))).ok, route + " solar panel")
			record["iron_after_solar"] = main.ledger.get_amount(&"iron_plates")
		if route == "repair_and_first_rocket":
			require(main.rockets.reserve_landing_zone(&"rocket_1", Rect2i(22, 22, 8, 8)).ok, "landing zone")
			require(main.rockets.confirm_manifest(&"rocket_1", {"nuclear_core": 1, "spare_parts": 1, "seeds": 1}).ok, "safe first cargo")
			require(GameClock.advance_to_sol(6).ok, "reach breach")
			require(main.crew.assign_eva_repair(&"crew_1", &"tunnel_1", &"spare_parts").ok, "beginner repair")
			require(GameClock.advance_to_sol(7).ok, "reach first rocket")
			record["leak_after_repair"] = main.tunnel.get_snapshot()["oxygen_leak_per_sol"]
			require(main.rockets.salvage(&"rocket_1", &"crew_2").ok, "salvage")
			record["iron_after_salvage"] = main.ledger.get_amount(&"iron_plates")
			require(main.research.start_research(&"battery").ok, "battery research")
			require(main.crew.queue_research(&"crew_4", lab_id, 8.0).ok, "battery scientist")
			require(main.crew.queue_research(&"crew_1", lab_id, 8.0).ok, "battery engineer")
			var guard := 0
			while guard < 1200 and not main.research.get_snapshot()["unlocked"].has("battery"):
				main.session.update(0.1)
				guard += 1
			require(main.building.place(GameContracts.PlacementRequest.new(&"battery", Vector2i(10, 21))).ok, "battery becomes affordable after salvage")
			record["iron_after_battery"] = main.ledger.get_amount(&"iron_plates")
			record["living_crew"] = main.crew.get_snapshot().filter(func(member): return member.get("alive", false)).size()
			record["inventory"] = main.ledger.get_snapshot()
			record["battery_capacity"] = main.building.get_power_inputs()["battery_capacity"]
		routes.append(record)
	var result := {"passed": failures.is_empty(), "failures": failures, "routes": routes}
	var file := FileAccess.open("user://beginner-routes-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("BEGINNER ROUTES: ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
