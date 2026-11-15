class_name ResourceLedger
extends RefCounted

var report
var infinite_resources := false

func set_infinite_resources(enabled: bool) -> void:
	infinite_resources = enabled

func initialize(initial_inventory: Dictionary) -> void:
	infinite_resources = false
	GameState.data["inventory"] = initial_inventory.duplicate(true)
	GameState.data["ledger_entries"] = []

func get_amount(resource_id: StringName) -> float:
	return float(GameState.data.get("inventory", {}).get(String(resource_id), 0.0))

func get_snapshot() -> Dictionary:
	return GameState.data.get("inventory", {}).duplicate(true)

func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if not _valid_amount(cost[id]):
			return false
		if not infinite_resources and get_amount(StringName(id)) < float(cost[id]):
			return false
	return true

func spend(cost: Dictionary, reason: String) -> bool:
	if not can_afford(cost):
		return false
	if infinite_resources:
		return true
	var delta := {}
	for id in cost:
		var amount := float(cost[id])
		GameState.data["inventory"][id] = get_amount(StringName(id)) - amount
		delta[id] = -amount
	_record(delta, reason)
	return true

func add(delta: Dictionary, reason: String) -> void:
	for id in delta:
		if not _valid_amount(delta[id]):
			push_error("Invalid resource delta %s" % id)
			return
	for id in delta:
		GameState.data["inventory"][id] = get_amount(StringName(id)) + float(delta[id])
	_record(delta, reason)

func _record(delta: Dictionary, reason: String) -> void:
	if delta.is_empty():
		return
	var clock: Dictionary = GameState.data["clock"]
	var entry := {"delta": delta.duplicate(true), "reason": reason,
		"sol": int(clock["sol"]), "sim_time": float(clock["elapsed"])}
	GameState.data["ledger_entries"].append(entry)
	SignalBus.resources_changed.emit(delta.duplicate(true), reason)
	if report != null:
		report.record_ledger(entry)

func _valid_amount(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0
