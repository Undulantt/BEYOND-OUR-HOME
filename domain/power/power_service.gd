class_name PowerService
extends RefCounted

var building_service
var grid_service
var snapshot := GameContracts.EnergySnapshot.new()

func rebuild_from_state() -> void:
	snapshot = GameContracts.EnergySnapshot.new()
	snapshot.stored = float(GameState.data.get("power", {}).get("stored", 0.0))
	# Reconstruct the paused preview after loading, once grid and buildings exist.
	if building_service != null and grid_service != null:
		step(0.0)

func step(delta_seconds: float) -> void:
	var inputs: Dictionary = building_service.get_power_inputs() if building_service != null else {}
	var links: Array = grid_service.get_energy_links() if grid_service != null else []
	var generators: Array = inputs.get("generators", [])
	var consumers: Array = inputs.get("consumers", [])
	var sol_seconds := float(ConfigDB.balance["time"]["sol_seconds_x1"])
	var fraction := delta_seconds / sol_seconds
	var next := GameContracts.EnergySnapshot.new()
	next.capacity = maxf(0.0, float(inputs.get("battery_capacity", 0.0)))
	var total_capacity := maxf(next.capacity, float(inputs.get("battery_total_capacity", next.capacity)))
	var pooled := clampf(float(GameState.data["power"].get("stored", 0.0)) + float(GameState.data["power"].get("locked_stored", 0.0)), 0.0, total_capacity)
	next.stored = minf(pooled, next.capacity)
	var locked := pooled - next.stored
	var charge_rate := maxf(0.0, float(inputs.get("battery_charge_rate", 0.0)))
	var discharge_rate := maxf(0.0, float(inputs.get("battery_discharge_rate", charge_rate)))
	var connected: Dictionary = {}
	for link in links:
		if link is Dictionary and bool(link.get("connected", true)):
			connected[String(link.get("building_id", ""))] = true
	var unrestricted := grid_service == null
	for source in generators:
		if not source is Dictionary:
			continue
		var id := String(source.get("building_id", ""))
		if bool(source.get("enabled", true)) and (unrestricted or connected.has(id)):
			next.generation += maxf(0.0, float(source.get("output", 0.0)))
	var ordered := consumers.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(GameState.data["power"]["priorities"].get(String(a.get("building_id", "")), a.get("priority", 2)))
		var pb := int(GameState.data["power"]["priorities"].get(String(b.get("building_id", "")), b.get("priority", 2)))
		return pa < pb if pa != pb else String(a.get("building_id", "")) < String(b.get("building_id", "")))
	# A zero-delta preview must include battery support without spending charge.
	var allocation_fraction := fraction if fraction > 0.0 else SimulationRunner.STEP_SECONDS / sol_seconds
	var available := next.generation + minf(discharge_rate, next.stored / allocation_fraction)
	var allocated_total := 0.0
	for consumer in ordered:
		if not consumer is Dictionary:
			continue
		var id := String(consumer.get("building_id", ""))
		var demand := maxf(0.0, float(consumer.get("demand", 0.0)))
		var enabled := bool(consumer.get("enabled", true)) and (unrestricted or connected.has(id))
		var priority := int(GameState.data["power"]["priorities"].get(id, consumer.get("priority", 2)))
		if bool(consumer.get("enabled", true)):
			next.demand += demand
		var allocated := demand if enabled and available + 0.000001 >= demand else 0.0
		available -= allocated
		allocated_total += allocated
		next.by_building[id] = {"allocated": allocated, "demand": demand,
			"powered": enabled and allocated >= demand, "priority": priority}
	var net := next.generation - allocated_total
	if net >= 0.0:
		next.stored = minf(next.capacity, next.stored + minf(net, charge_rate) * fraction)
	else:
		next.stored = maxf(0.0, next.stored + net * fraction)
	GameState.data["power"]["stored"] = next.stored
	GameState.data["power"]["locked_stored"] = locked
	snapshot = next
	SignalBus.energy_changed.emit(get_snapshot())

func get_snapshot() -> GameContracts.EnergySnapshot:
	var copy := GameContracts.EnergySnapshot.new()
	copy.generation = snapshot.generation
	copy.demand = snapshot.demand
	copy.stored = snapshot.stored
	copy.capacity = snapshot.capacity
	copy.by_building = snapshot.by_building.duplicate(true)
	return copy

func set_priority(building_id: StringName, priority: int) -> void:
	if priority >= 1 and priority <= 4:
		GameState.data["power"]["priorities"][String(building_id)] = priority

func is_powered(building_id: StringName) -> bool:
	return bool(snapshot.by_building.get(String(building_id), {}).get("powered", false))

func validate_energy_spend(amount: float) -> GameContracts.ValidationResult:
	if not is_finite(amount) or amount < 0.0:
		return GameContracts.failure(&"invalid_energy_amount")
	if float(GameState.data["power"].get("stored", 0.0)) < amount:
		return GameContracts.failure(&"insufficient_energy", {"required": amount})
	return GameContracts.success()

func spend_stored_energy(amount: float, reason: StringName) -> GameContracts.ValidationResult:
	var result := validate_energy_spend(amount)
	if not result.ok:
		return result
	GameState.data["power"]["stored"] = float(GameState.data["power"]["stored"]) - amount
	snapshot.stored = float(GameState.data["power"]["stored"])
	SignalBus.energy_changed.emit(get_snapshot())
	return result
