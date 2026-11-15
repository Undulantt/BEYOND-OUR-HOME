extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run_tests")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)

func run_tests() -> void:
	var crew := CrewService.new()
	var building := BuildingService.new()
	var grid := GridService.new()
	var power := PowerService.new()
	var ledger := ResourceLedger.new()
	var life := LifeSupportService.new()
	var events := EventService.new()
	var rockets := RocketService.new()
	var report := SolReportService.new()
	var research := ResearchService.new()
	var tunnel := TunnelNetwork.new()
	var production := ProductionService.new()
	building.grid = grid
	building.ledger = ledger
	building.power = power
	building.research = research
	grid.building_service = building
	power.building_service = building
	power.grid_service = grid
	life.crew_service = crew
	life.ledger = ledger
	life.tunnel_network = tunnel
	crew.life_support = life
	crew.building_service = building
	crew.ledger = ledger
	crew.rocket_service = rockets
	crew.report = report
	research.crew_service = crew
	research.power = power
	events.building_service = building
	events.report = report
	rockets.grid = grid
	rockets.ledger = ledger
	rockets.crew_service = crew
	rockets.report = report
	production.ledger = ledger
	production.building_service = building
	production.power = power
	ledger.report = report
	var session := GameSession.new()
	session.configure({"crew": crew, "building": building, "grid": grid, "power": power,
		"ledger": ledger, "life_support": life, "event": events, "rocket": rockets,
		"research": research, "production": production, "report": report})
	var same: Array[StringName] = [&"medic", &"medic", &"medic", &"medic"]
	check(session.start_new(same, 19).ok, "repeated roster accepted")
	check(crew.get_snapshot().size() == 4, "four independent crew")
	var legacy := SaveService.export_state()
	legacy["autonomy"] = {"percent": 20.0}
	legacy["crew"]["members"]["crew_1"]["morale"] = 0.0
	legacy["crew"]["members"]["crew_1"]["break_remaining"] = 1.0
	check(SaveService.import_state(legacy) == OK, "legacy indicators save loads")
	check(not GameState.data.has("autonomy") and not crew.get_snapshot()[0].has("morale") and not crew.get_snapshot()[0].has("break_remaining"), "retired indicators are removed on load")
	GameState.data["crew"]["members"]["crew_1"]["health"] = 60.0
	check(float(GameState.data["crew"]["members"]["crew_2"]["health"]) == 100.0, "health independent")
	GameState.data["crew"]["members"]["crew_1"]["dose"] = 24.0
	check(crew.use_medicine(&"crew_1").ok, "medicine applied")
	check(float(GameState.data["crew"]["members"]["crew_1"]["dose"]) == 24.0, "medicine preserves dose")
	check(not rockets.confirm_manifest(&"rocket_1", {"chips": 1}).ok, "zone required")
	check(rockets.reserve_landing_zone(&"rocket_1", Rect2i(22, 22, 8, 8)).ok, "landing reserved")
	var before := ledger.get_amount(&"chips")
	var iron_before := ledger.get_amount(&"iron_plates")
	check(not rockets.validate_manifest(&"rocket_1", {"iron_plates": 71}).ok, "iron cargo respects mass limit")
	check(not rockets.confirm_manifest(&"rocket_1", {"nuclear_core": 100}).ok, "overweight rejected")
	check(is_equal_approx(ledger.get_amount(&"chips"), before), "invalid manifest no cargo")
	check(rockets.confirm_manifest(&"rocket_1", {"chips": 2, "iron_plates": 10, "astronaut_replacement": 1}).ok, "manifest confirmed")
	check(not rockets.trigger_arrival(&"rocket_1").ok, "early arrival rejected")
	GameState.data["clock"]["sol"] = 7
	check(rockets.trigger_arrival(&"rocket_1").ok, "arrival succeeds")
	check(is_equal_approx(ledger.get_amount(&"chips"), before + 2.0), "cargo once")
	check(not rockets.trigger_arrival(&"rocket_1").ok, "arrival idempotent")
	check(is_equal_approx(ledger.get_amount(&"iron_plates"), iron_before + 10), "iron cargo delivered exactly once")
	check(rockets.exchange(&"rocket_1", &"crew_1", &"scientist_a").ok, "exchange succeeds")
	check(not rockets.salvage(&"rocket_1", &"crew_2").ok, "exchange excludes salvage")
	check(crew.get_snapshot().size() == 5, "replacement has new id")
	check(not bool(GameState.data["crew"]["members"]["crew_1"]["alive"]), "old crew retired")
	for index in range(2, 5):
		var rocket_id := StringName("rocket_%d" % index)
		check(rockets.reserve_landing_zone(rocket_id, Rect2i(22, 22, 8, 8)).ok, "later landing reserved %d" % index)
		check(rockets.confirm_manifest(rocket_id, {"seeds": 1}).ok, "later manifest confirmed %d" % index)
		GameState.data["clock"]["sol"] = index * 7
		check(rockets.trigger_arrival(rocket_id).ok, "later arrival %d" % index)
		check(rockets.salvage(rocket_id, &"crew_2").ok, "later salvage %d" % index)
		check(not rockets.exchange(rocket_id, &"crew_2", &"medic").ok, "salvage excludes exchange %d" % index)
	check(rockets.get_snapshot().size() == 4, "four rocket plans")
	GameState.data["clock"]["sol"] = 6
	events.on_sol_started(6)
	check(events.get_snapshot().size() == 1, "fixed breach once")
	events.on_sol_started(6)
	check(events.get_snapshot().size() == 1, "fixed breach idempotent")
	check(GameState.data["buildings"]["instances"]["tunnel_1"]["condition"] == "breached", "breach reaches building")
	check(crew.assign_eva_repair(&"crew_2", &"tunnel_1").ok, "eva repair queued")
	var task_id := String(GameState.data["crew"]["members"]["crew_2"]["task_id"])
	check(crew.order_shelter(&"crew_2").ok, "shelter ordered")
	crew.scheduler.progress(&"crew_2", 10.0)
	check(float(GameState.data["crew"]["tasks"][task_id]["completed_hours"]) == 0.0, "shelter suspends eva")
	crew.order_shelter(&"crew_2", false)
	crew.scheduler.progress(&"crew_2", 3.0)
	check(GameState.data["buildings"]["instances"]["tunnel_1"]["condition"] == "normal", "worked repair applied")
	check(GameState.data["crew"]["tasks"][task_id]["state"] == "completed", "task completes once")
	GameState.data["clock"]["speed"] = 4.0
	for sol in [11, 12, 14, 16]:
		GameState.data["clock"]["sol"] = sol
		events.on_sol_started(sol)
	check(not bool(GameState.data["events"].get("dust_storm_active", false)), "storm ends at sol 16")
	check(bool(GameState.data["events"].get("solar_flare_active", false)), "flare activates at sol 16")
	check(is_equal_approx(float(GameState.data["clock"]["speed"]), 4.0), "events preserve speed")
	check(SaveService.import_state(SaveService.export_state()) == OK, "mission state saves")
	check(not rockets.trigger_arrival(&"rocket_1").ok, "reload does not duplicate cargo")
	check(is_equal_approx(ledger.get_amount(&"chips"), before + 5.0), "cargo and salvage unchanged after reload")
	if failures.is_empty():
		print("R3 mission tests passed")
		get_tree().quit(0)
	else:
		print("R3 mission tests failed: ", failures)
		get_tree().quit(1)
