extends Node

class CrewStub extends RefCounted:
	func create_roster(profiles: Array[StringName]) -> GameContracts.ValidationResult:
		var crew := {}
		for index in profiles.size():
			crew["crew_%d" % index] = {"id": "crew_%d" % index,
				"profile_id": String(profiles[index]), "alive": true}
		GameState.data["crew"] = crew
		return GameContracts.success()
	func get_snapshot() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for value in GameState.data["crew"].values():
			result.append(value.duplicate(true))
		return result
	func step(_dt: float) -> void:
		pass

class BuildingStub extends RefCounted:
	var output: float = 8.0
	func initialize_layout() -> GameContracts.ValidationResult:
		GameState.data["buildings"] = {"base_1": {"type": "base"}}
		return GameContracts.success()
	func get_power_inputs() -> Dictionary:
		return {"generators": [{"building_id": "solar_1", "output": output}],
			"consumers": [{"building_id": "base_1", "demand": 1.0, "priority": 1}],
			"battery_capacity": 24.0, "battery_charge_rate": 8.0}

class GridStub extends RefCounted:
	func get_energy_links() -> Array[Dictionary]:
		return [{"building_id": "solar_1"}, {"building_id": "base_1"}]
	func step(_dt: float) -> void:
		pass

class TunnelStub extends RefCounted:
	var leak: float = 0.0
	func get_snapshot() -> Dictionary:
		return {"oxygen_leak_per_sol": leak}

class ProductionStub extends RefCounted:
	var ledger: ResourceLedger
	func step(dt: float) -> void:
		var amount := 4.0 * dt / 60.0
		ledger.add({"oxygen": amount, "water": amount, "food": amount}, "production_isru_greenhouse")

class RocketStub extends RefCounted:
	var arrivals: Array[int] = []
	func on_sol_started(sol: int) -> void:
		if sol in [7, 14, 21, 28]:
			arrivals.append(sol)

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run_tests")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)

func inventories_close(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or not is_equal_approx(float(a[key]), float(b[key])):
			return false
	return true

func build_session() -> Dictionary:
	var crew := CrewStub.new()
	var building := BuildingStub.new()
	var grid := GridStub.new()
	var tunnel := TunnelStub.new()
	var ledger := ResourceLedger.new()
	var report := SolReportService.new()
	ledger.report = report
	var power := PowerService.new()
	power.building_service = building
	power.grid_service = grid
	var life := LifeSupportService.new()
	life.ledger = ledger
	life.crew_service = crew
	life.tunnel_network = tunnel
	var production := ProductionStub.new()
	production.ledger = ledger
	var rocket := RocketStub.new()
	var session := GameSession.new()
	session.configure({"crew": crew, "building": building, "grid": grid, "ledger": ledger,
		"report": report, "power": power, "life_support": life, "production": production,
		"rocket": rocket})
	return {"session": session, "crew": crew, "ledger": ledger, "power": power,
		"life": life, "tunnel": tunnel, "report": report, "rocket": rocket,
		"building": building}

func run_tests() -> void:
	check(not ConfigDB.balance.is_empty(), "balance loads")
	var context := build_session()
	var profiles: Array[StringName] = [&"medic", &"medic", &"medic", &"medic"]
	check(context["session"].start_new(profiles, 41).ok, "four repeated profiles start")
	check(GameState.data["crew"].size() == 4, "four distinct crew instances")
	var before: Dictionary = context["ledger"].get_snapshot()
	check(not context["ledger"].spend({"iron_plates": 100.0}, "test"), "overspend rejected")
	check(context["ledger"].get_snapshot() == before, "failed spend atomic")
	context["power"].step(0.1)
	check(context["power"].is_powered(&"base_1"), "power allocated")
	check(context["power"].get_snapshot().stored > 0.0, "battery charged")
	context["building"].output = 0.0
	context["power"].step(0.1)
	check(context["power"].is_powered(&"base_1"), "night demand covered by battery")
	context["building"].output = 8.0
	context["tunnel"].leak = 4.0
	context["life"].step(0.1)
	check(context["ledger"].get_amount(&"oxygen") < 16.0, "breach costs oxygen")
	context["ledger"].spend({"food": context["ledger"].get_amount(&"food")}, "test_empty")
	context["life"].step(0.1)
	check(not context["life"].get_crew_supply(&"crew_0").get("food", true), "food shortage reported")
	context["tunnel"].leak = 0.0
	var snapshot := SaveService.export_state()
	check(SaveService.import_state(snapshot) == OK, "state restored")
	check(SaveService.save_to_slot(&"core_test") == OK, "save slot written")
	context["ledger"].spend({"iron_plates": 1.0}, "test")
	check(SaveService.load_from_slot(&"core_test") == OK, "save slot loaded")
	check(inventories_close(GameState.data["inventory"], snapshot["inventory"]), "slot restores inventory")
	var bad := snapshot.duplicate(true)
	bad["inventory"]["oxygen"] = -1.0
	check(SaveService.import_state(bad) == ERR_INVALID_DATA, "invalid save rejected")
	check(inventories_close(GameState.data["inventory"], snapshot["inventory"]), "invalid save leaves game intact")
	context = build_session()
	context["session"].start_new(profiles, 41)
	check(GameClock.set_speed(4.0).ok, "x4 available")
	context["session"].update(0.25)
	var four_speed := float(GameState.data["clock"]["elapsed"])
	var four_inventory: Dictionary = context["ledger"].get_snapshot()
	context = build_session()
	context["session"].start_new(profiles, 41)
	context["session"].update(1.0)
	check(is_equal_approx(float(GameState.data["clock"]["elapsed"]), four_speed), "x1/x4 same simulated step")
	check(inventories_close(context["ledger"].get_snapshot(), four_inventory), "x1/x4 same resource balances")
	GameClock.set_paused(true)
	context["session"].update(10.0)
	check(is_equal_approx(float(GameState.data["clock"]["elapsed"]), 1.0), "manual pause freezes simulation")
	GameClock.set_paused(false)
	check(GameClock.advance_to_sol(7).ok, "admin advances normal steps to sol 7")
	check(int(GameState.data["clock"]["sol"]) == 7, "admin target reached")
	check(context["rocket"].arrivals == [7], "arrival occurs at start of target sol")
	var at_arrival := SaveService.export_state()
	check(SaveService.import_state(at_arrival) == OK, "arrival state reloads")
	context["session"].update(0.1)
	check(context["rocket"].arrivals == [7], "arrival not repeated after reload")
	check(GameClock.advance_to_sol(42).ok, "42-sol campaign advances")
	check(context["rocket"].arrivals == [7, 14, 21, 28], "four scheduled arrivals once")
	context["session"].runner.advance_to_sol(43)
	check(String(GameState.data["result"]) == "victory", "victory at end of sol 42")
	context = build_session()
	context["session"].start_new(profiles, 41)
	for member in GameState.data["crew"].values():
		member["alive"] = false
	context["session"].update(0.1)
	check(String(GameState.data["result"]) == "defeat", "last death defeats")
	if failures.is_empty():
		print("R1 core tests passed")
		get_tree().quit(0)
	else:
		print("R1 core tests failed: ", failures)
		get_tree().quit(1)
