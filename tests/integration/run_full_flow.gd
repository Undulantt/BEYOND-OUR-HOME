extends Node

var failures := 0
var main: MissionMain

func _ready() -> void:
	main = load("res://scenes/integration/main.tscn").instantiate()
	add_child(main)
	call_deferred("_run")

func _run() -> void:
	check(main.menu.visible and not main.hud.visible and not GameState.is_running(), "menu is initial screen")
	var profiles: Array[StringName] = [&"medic", &"medic", &"medic", &"medic"]
	main.menu.start_requested.emit(profiles)
	check(GameState.is_running(), "new game starts")
	check(main.hud.visible and main.world.visible and not main.menu.visible, "game screen visible")
	get_window().size = Vector2i(960, 540)
	await get_tree().process_frame
	check(get_window().size == Vector2i(960, 540), "960 window selected")
	check(main.hud._workspace.get_global_rect().end.x <= main.hud.get_global_rect().end.x, "workspace fits scaled canvas")
	check(main.hud._vitals._labels["pressure"].get_global_rect().end.x <= main.hud.get_global_rect().end.x, "vitals fit scaled canvas")
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	check(main.hud._workspace.get_global_rect().end.x <= main.hud.get_global_rect().end.x, "workspace fits 1280 canvas")
	check(main.crew.get_snapshot().size() == 4, "real roster")
	check(main.building.get_all_statuses().size() >= 4, "initial base")
	check(main.power.is_powered(&"isru_1"), "initial power connected")
	var before := main.ledger.get_amount(&"iron_plates")
	main.world.placement_requested.emit(GameContracts.PlacementRequest.new(&"tunnel", Vector2i(15, 17)))
	check(main.ledger.get_amount(&"iron_plates") == before - 1.0, "world to HUD to building placement")
	main.world.placement_requested.emit(GameContracts.PlacementRequest.new(&"laboratory", Vector2i(15, 18)))
	check(main.ledger.get_amount(&"iron_plates") == before - 17.0, "laboratory placement")
	main.power.step(0.0)
	var lab_id := StringName("")
	for status in main.building.get_all_statuses():
		if status.type == &"laboratory":
			lab_id = status.building_id
	check(not String(lab_id).is_empty(), "laboratory exists")
	check(main.research.start_research(&"solar_panel").ok, "research starts")
	check(main.crew.queue_research(&"crew_1", lab_id, 8.0).ok, "research task assigned")
	check(main.crew.queue_research(&"crew_2", lab_id, 8.0).ok, "second research task assigned")
	check(GameClock.advance_to_sol(2).ok, "advance to sol 2")
	check(main.research.get_snapshot()["unlocked"].has("solar_panel"), "research unlocks")
	main.world.placement_requested.emit(GameContracts.PlacementRequest.new(&"solar_panel", Vector2i(10, 18)))
	check(main.ledger.get_amount(&"iron_plates") == before - 27.0, "panel constructed")
	check(main.rockets.reserve_landing_zone(&"rocket_1", Rect2i(22, 22, 8, 8)).ok, "landing zone reserved")
	check(main.rockets.confirm_manifest(&"rocket_1", {"chips": 2}).ok, "manifest confirmed")
	var chips_before := main.ledger.get_amount(&"chips")
	check(GameClock.set_speed(4.0).ok, "x4 selected")
	check(GameClock.advance_to_sol(7).ok, "advance through breach to first rocket")
	check(main.ledger.get_amount(&"chips") == chips_before + 2.0, "rocket cargo delivered once")
	check(main.events.get_snapshot().size() >= 1, "mission event occurred")
	check(GameClock.get_snapshot()["speed"] == 4.0, "event did not slow clock")
	check(GameClock.advance_to_sol(12).ok, "advance to dust storm")
	main.session.update(1.0)
	var solar_id := StringName("")
	for status in main.building.get_all_statuses():
		if status.type == &"solar_panel":
			solar_id = status.building_id
	check(not String(solar_id).is_empty(), "solar panel exists")
	check(float(main.building.get_status(solar_id).modifiers.get("dust", 0.0)) > 0.0, "storm deposits panel dust")
	check(main.dialogue.get_entries().any(func(item): return item.get("id") == "event_dust_storm"), "storm warning logged")
	check(GameClock.get_snapshot()["speed"] == 4.0, "storm keeps x4")
	main._save_game()
	var saved_inventory := main.ledger.get_snapshot()
	main._return_to_menu()
	check(main.menu.visible and not main.hud.visible, "return to menu")
	main.menu.continue_requested.emit()
	check(main.hud.visible and not main.menu.visible, "continue returns to game")
	check(main.ledger.get_snapshot() == saved_inventory, "load preserves resources")
	check(main.rockets.get_snapshot()[0]["cargo_transferred"], "rocket remains transferred after load")
	check(main.dialogue.get_entries().size() > 0, "dialogue restored")
	check(main.building.set_enabled(&"isru_1", false).ok, "disable oxygen production")
	check(main.building.set_enabled(&"greenhouse_1", false).ok, "disable food production")
	for resource in [&"oxygen", &"water", &"food"]:
		var amount := main.ledger.get_amount(resource)
		if amount > 0.0:
			check(main.ledger.spend({String(resource): amount}, "test_shortage"), "empty %s" % resource)
	var ending: GameContracts.ValidationResult = GameClock.advance_to_sol(20)
	check(not ending.ok and GameState.data.get("result") == "defeat", "survival failure ends game")
	check(main.hud._final.visible, "final result visible")
	if failures == 0:
		print("Integrated flow passed")
	get_tree().quit(1 if failures > 0 else 0)

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
