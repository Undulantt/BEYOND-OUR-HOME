class_name SimulationRunner
extends RefCounted

const STEP_SECONDS := 0.1
var services: Dictionary = {}
var accumulator: float = 0.0

func configure(dependencies: Dictionary) -> void:
	services = dependencies
	GameClock.runner = self

func update(real_delta: float) -> void:
	if not is_finite(real_delta) or real_delta < 0.0:
		return
	if not GameState.is_running() or bool(GameState.data["clock"]["paused"]):
		return
	accumulator += real_delta * float(GameState.data["clock"]["speed"])
	while accumulator + 0.000001 >= STEP_SECONDS and GameState.is_running():
		accumulator -= STEP_SECONDS
		_step(STEP_SECONDS)
		if bool(GameState.data.get("clock", {}).get("paused", false)):
			# A guided objective may pause during a tick. Discard time spent reading,
			# rather than replaying the rest of this frame when the player resumes.
			accumulator = 0.0
			break

func advance_to_sol(target_sol: int) -> GameContracts.ValidationResult:
	if target_sol <= int(GameState.data["clock"]["sol"]):
		return GameContracts.failure(&"invalid_target_sol")
	var guard := int(ConfigDB.balance["time"]["sol_seconds_x1"] / STEP_SECONDS) * (target_sol - int(GameState.data["clock"]["sol"])) + 2
	while int(GameState.data["clock"]["sol"]) < target_sol and GameState.is_running() and guard > 0:
		_step(STEP_SECONDS)
		guard -= 1
	if not GameState.is_running():
		return GameContracts.failure(&"game_over")
	return GameContracts.success() if guard > 0 else GameContracts.failure(&"advance_limit")

func _step(dt: float) -> void:
	var clock: Dictionary = GameState.data["clock"]
	if int(clock.get("started_sol", 0)) < int(clock["sol"]):
		_on_sol_started(int(clock["sol"]))
	if services.has("event"):
		services["event"].step(dt)
	if services.has("grid"):
		services["grid"].step(dt)
	if services.has("power"):
		services["power"].step(dt)
	if services.has("production"):
		services["production"].step(dt)
	if services.has("life_support"):
		services["life_support"].step(dt)
	if services.has("crew"):
		services["crew"].step(dt)
	if services.has("research"):
		services["research"].step(dt)
	_check_defeat()
	if not GameState.is_running():
		return
	clock["elapsed"] = float(clock["elapsed"]) + dt
	SignalBus.tick_advanced.emit(dt)
	var duration := float(ConfigDB.balance["time"]["sol_seconds_x1"])
	if float(clock["elapsed"]) + 0.000001 < duration:
		return
	clock["elapsed"] = 0.0
	var ended_sol := int(clock["sol"])
	_on_sol_ended(ended_sol)
	if not GameState.is_running():
		SignalBus.sol_ended.emit(ended_sol)
		return
	clock["sol"] = int(clock["sol"]) + 1
	_on_sol_started(int(clock["sol"]))
	# Observers (including autosave) must see a resumable next-sol state.
	SignalBus.sol_ended.emit(ended_sol)

func _on_sol_started(sol: int) -> void:
	GameState.data["clock"]["started_sol"] = sol
	for name in ["event", "rocket"]:
		if services.has(name) and services[name].has_method("on_sol_started"):
			services[name].on_sol_started(sol)
	SignalBus.sol_started.emit(sol)

func _on_sol_ended(sol: int) -> void:
	for name in ["event", "rocket", "production", "crew", "research"]:
		if services.has(name) and services[name].has_method("on_sol_ended"):
			services[name].on_sol_ended(sol)
	if services.has("report"):
		services["report"].get_report(sol)
	_check_defeat()
	if GameState.is_running() and sol >= int(ConfigDB.balance["time"]["total_sols"]):
		_finish(&"victory")

func _check_defeat() -> void:
	if not services.has("crew"):
		return
	var living := 0
	for astronaut in services["crew"].get_snapshot():
		if astronaut is Dictionary and bool(astronaut.get("alive", false)):
			living += 1
	if living == 0:
		_finish(&"defeat")

func _finish(result: StringName) -> void:
	if String(GameState.data.get("result", "")).is_empty():
		GameState.data["result"] = String(result)
		SignalBus.game_over.emit(result)
