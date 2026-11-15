extends Node

var main: MissionMain
var failures: Array[String] = []
var checks := 0
var observations: Dictionary = {}

func _ready() -> void:
	main = preload("res://scenes/integration/main.tscn").instantiate()
	add_child(main)
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL ", label)

func reset() -> void:
	main._start_new([&"medic", &"medic", &"medic", &"medic"])

func lab() -> StringName:
	main.building.place(GameContracts.PlacementRequest.new(&"tunnel", Vector2i(15, 17)))
	var result := main.building.place(GameContracts.PlacementRequest.new(&"laboratory", Vector2i(15, 18)))
	main.power.step(0.0)
	return StringName(result.params["building_id"])

func run() -> void:
	reset()
	var laboratory := lab()
	main.research.start_research(&"solar_panel")
	main.crew.queue_research(&"crew_1", laboratory, 8.0)
	main.hud._workspace.open_tab(&"laboratory")
	main.session.update(10.0)
	observations["research_after_10_seconds"] = main.research.get_snapshot()
	check(float(main.research.get_snapshot()["progress"]) > 0.0, "QA-001 partial research must advance before the task finishes")
	var bars := main.hud._workspace.find_children("*", "ProgressBar", true, false)
	check(not bars.is_empty() and float(bars[0].value) > 0.0, "QA-001 research bar must update while simulation runs")
	var spent := float(GameState.data["crew"]["members"]["crew_1"]["worked_hours_today"])
	main.building.set_enabled(&"reactor_1", false)
	main.session.update(1.0)
	check(is_equal_approx(float(GameState.data["crew"]["members"]["crew_1"]["worked_hours_today"]), spent), "QA-003 blocked work must not consume the daily work budget")
	reset()
	GameState.data["clock"]["elapsed"] = 15.0
	if main.world.has_method("_sync_daylight"):
		main.world._sync_daylight()
	var sunlight := float(main.world.get_node("Sun").light_energy)
	GameState.data["clock"]["elapsed"] = 45.0
	if main.world.has_method("_sync_daylight"):
		main.world._sync_daylight()
	observations["sunlight"] = {"day": sunlight, "night": main.world.get_node("Sun").light_energy}
	check(float(main.world.get_node("Sun").light_energy) < sunlight * 0.5, "QA-002 night must visibly change world lighting")
	reset()
	main.building.set_enabled(&"greenhouse_1", false)
	main.production.step(31.0)
	check(main.building.get_status(&"greenhouse_1").modifiers["crop"] == "dead", "QA-004 switching a greenhouse off must not freeze crop damage")
	reset()
	GameState.data["research"]["unlocked"].append("battery")
	var battery_result := main.building.place(GameContracts.PlacementRequest.new(&"battery", Vector2i(22, 14)))
	check(battery_result.ok, "battery fixture is placed")
	var battery := StringName(battery_result.params["building_id"])
	main.building.set_enabled(battery, false)
	check(float(main.building.get_power_inputs()["battery_capacity"]) == 0.0, "QA-005 disabled batteries must not provide capacity")
	GameState.data["power"]["stored"] = 10.0
	main.power.step(0.0)
	check(main.power.get_snapshot().stored == 0.0, "offline battery energy is unavailable")
	main.building.set_enabled(battery, true)
	main.power.step(0.0)
	check(main.power.get_snapshot().stored == 10.0, "switching batteries off and on preserves their stored energy")
	main.building.apply_damage(battery, 100.0, &"test")
	check(float(main.building.get_power_inputs()["battery_capacity"]) == 0.0, "QA-005 destroyed batteries must not provide capacity")
	reset()
	var printer := BuildingDefinition.from_balance(&"printer_3d")
	GameState.data["buildings"]["instances"]["printer_test"] = main.building._new_instance("printer_test", printer, Vector2i(22, 14))
	GameState.data["buildings"]["instances"]["solar_test"] = main.building._new_instance("solar_test", BuildingDefinition.from_balance(&"solar_panel"), Vector2i(10, 18))
	main.ledger.add({"iron_plates": 20.0, "chips": 10.0}, "test_fixture")
	main.power.step(0.0)
	check(main.power.is_powered(&"printer_test"), "printer fixture has power")
	main.building.set_enabled(&"printer_test", false)
	var stock := main.ledger.get_snapshot()
	check(not main.production.print_recipe(&"printer_test", &"spare_parts").ok, "QA-006 a disabled printer must reject a recipe before the next tick")
	check(main.ledger.get_snapshot() == stock, "QA-006 rejected printing must not spend or create resources")
	reset()
	laboratory = lab()
	main.crew.queue_research(&"crew_1", laboratory, 8.0)
	main.building.remove(laboratory)
	check(String(GameState.data["crew"]["members"]["crew_1"]["task_id"]).is_empty(), "QA-007 removing a task target must release its astronaut")
	reset()
	main.building.apply_damage(&"tunnel_1", 30.0, &"test")
	check(main.crew.assign_eva_repair(&"crew_1", &"tunnel_1", &"spare_parts").ok, "first repair is accepted")
	check(not main.crew.assign_eva_repair(&"crew_2", &"tunnel_1", &"spare_parts").ok, "QA-008 duplicate repairs on the same breach must be rejected")
	main.crew.cancel_task(StringName(GameState.data["crew"]["members"]["crew_1"]["task_id"]))
	check(GameState.data["buildings"].get("pending_tasks", {}).is_empty(), "QA-008 cancelling work must release its pending building action")
	reset()
	main.crew.set_category_allowed(&"crew_1", &"production", false)
	var pending: int = GameState.data["buildings"].get("pending_tasks", {}).size()
	check(not main.crew.assign_building_action(&"crew_1", &"reactor_1", &"refuel").ok, "forbidden work rejected")
	check(GameState.data["buildings"].get("pending_tasks", {}).size() == pending, "QA-009 rejected work must not create pending actions")
	reset()
	var previous := SaveService.export_state()
	var invalid: Array[StringName] = [&"unknown", &"medic", &"medic", &"medic"]
	check(not main.session.start_new(invalid, 33).ok, "invalid new game rejected")
	check(GameState.data == previous, "QA-010 an invalid new game must preserve the current mission")
	reset()
	var malformed := SaveService.export_state()
	malformed["clock"]["elapsed"] = NAN
	check(not SaveService._validate(malformed), "QA-011 save validator must reject a non-finite clock")
	malformed = SaveService.export_state()
	malformed["buildings"]["instances"]["base_1"]["origin"] = [14]
	check(not SaveService._validate(malformed), "QA-011 save validator must reject malformed nested building data")
	reset()
	main.hud._workspace._manifest = {"chips": 50}
	main.world.camera_rig.focus_cell(Vector2i(200, 200))
	reset()
	check(main.hud._workspace._manifest.is_empty(), "QA-012 a new mission must not inherit a previous cargo draft")
	check(main.world.camera_rig.focus.distance_to(Vector3(32, 0, 32)) < 1.0, "QA-012 a new mission must center the camera on its colony")
	main.session.update(NAN)
	check(is_finite(main.session.runner.accumulator), "QA-013 a non-finite delta must not poison the simulation clock")
	reset()
	laboratory = lab()
	main.research.start_research(&"solar_panel")
	main.crew.queue_research(&"crew_1", laboratory, 8.0)
	var legacy_id: String = GameState.data["crew"]["members"]["crew_1"]["task_id"]
	GameState.data["crew"]["tasks"][legacy_id]["completed_hours"] = 2.0
	check(SaveService.import_state(SaveService.export_state()) == OK, "legacy partial research state can load")
	main.power.step(0.0)
	main.session.update(0.1)
	check(float(main.research.get_snapshot()["progress"]) > 2.0, "QA-001 legacy uncredited partial work is recovered exactly once")
	var migrated := float(main.research.get_snapshot()["progress"])
	main.session.update(0.1)
	check(float(main.research.get_snapshot()["progress"]) < migrated + 0.03, "QA-001 recovered legacy work is not counted twice")
	reset()
	GameState.data["buildings"]["pending_tasks"] = {"legacy_orphan": {"target_id": "reactor_1", "crew_id": "crew_1", "mode": "refuel"}}
	check(SaveService.import_state(SaveService.export_state()) == OK, "legacy orphan action state loads")
	check(GameState.data["buildings"]["pending_tasks"].is_empty(), "QA-009 loading removes legacy orphan building actions")
	reset()
	main.rockets.reserve_landing_zone(&"rocket_1", Rect2i(22, 22, 8, 8))
	main.rockets.confirm_manifest(&"rocket_1", {"astronaut_replacement": 1})
	GameState.data["clock"]["sol"] = 7
	main.rockets.trigger_arrival(&"rocket_1")
	main.crew.order_shelter(&"crew_1", true)
	main.hud._workspace.open_tab(&"rocket")
	var selectors := main.hud._workspace._body.find_children("*", "OptionButton", true, false)
	var crew_selector: OptionButton = selectors[1]
	crew_selector.select(1)
	crew_selector.item_selected.emit(1)
	var salvage_button: Button
	for button in main.hud._workspace._body.find_children("*", "Button", true, false):
		if button.text == UiHelpers.translated(&"action.salvage_rocket"):
			salvage_button = button
	check(main.rockets.validate_salvage(&"rocket_1", &"crew_2").ok and salvage_button != null and not salvage_button.disabled, "QA-014 changing the selected astronaut must refresh rocket action validation")
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "observations": observations}
	var file := FileAccess.open("user://break-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("Break test result: ", result)
	get_tree().quit(0 if failures.is_empty() else 1)
