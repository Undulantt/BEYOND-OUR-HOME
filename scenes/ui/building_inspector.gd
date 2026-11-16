class_name BuildingInspector
extends PanelContainer

signal lesson_requested(id: StringName)

var services: Dictionary = {}
var target_id: StringName = &""
var _column: VBoxContainer
var _refresh_queued := false
var _last_energy_signature := ""
var _feedback_text := ""

func _ready() -> void:
	_column = UiHelpers.column(self)
	SignalBus.building_changed.connect(func(_id, _kind): refresh())
	SignalBus.energy_changed.connect(_on_energy_changed)
	SignalBus.language_changed.connect(func(_code): refresh())
	SignalBus.state_restored.connect(refresh)
	refresh()

func configure(dependencies: Dictionary) -> void:
	services = dependencies
	refresh()

func show_target(id: StringName) -> void:
	if id != target_id:
		_feedback_text = ""
	target_id = id
	refresh()

func request_refresh() -> void:
	if _refresh_queued or String(target_id).is_empty():
		return
	_refresh_queued = true
	call_deferred("_deferred_refresh")

func _on_energy_changed(_snapshot: GameContracts.EnergySnapshot) -> void:
	if not services.has("building") or String(target_id).is_empty():
		return
	var status: BuildingStatus = services["building"].get_status(target_id)
	if status != null and _energy_signature(status) != _last_energy_signature:
		request_refresh()

func _energy_signature(status: BuildingStatus) -> String:
	return "%s:%s:%s" % [status.powered, status.condition, status.modifiers.get("crop", "")]

func _deferred_refresh() -> void:
	_refresh_queued = false
	var focus := get_viewport().gui_get_focus_owner()
	if (focus is LineEdit or focus is OptionButton) and is_ancestor_of(focus):
		return
	refresh()

func refresh() -> void:
	if _column == null:
		return
	UiHelpers.clear(_column)
	visible = false
	if not services.has("building") or String(target_id).is_empty():
		return
	var status: BuildingStatus = services["building"].get_status(target_id)
	if status == null:
		return
	_last_energy_signature = _energy_signature(status)
	visible = true
	_column.add_child(UiHelpers.label(_tr(StringName("building.%s" % status.type)), 20))
	_column.add_child(UiHelpers.button(_tr(&"learning.curiosity"), func(): lesson_requested.emit(target_id)))
	if not _feedback_text.is_empty():
		_column.add_child(UiHelpers.label(_feedback_text))
	_column.add_child(UiHelpers.label(_tr(&"ui.building_health", {"health": int(status.health), "condition": _tr(StringName("condition.%s" % status.condition))})))
	if status.demand > 0.0:
		_column.add_child(UiHelpers.label("%s: %.1f" % [_tr(&"inspector.power_demand"), status.demand]))
	if not status.production.is_empty():
		_column.add_child(UiHelpers.label("%s: %s" % [_tr(&"inspector.production"), UiHelpers.resource_text(status.production)]))
	for warning in status.warnings:
		_column.add_child(UiHelpers.label("⚠ " + _tr(StringName("building.warning.%s" % warning))))
	for next_key in status.next_consequence_keys:
		_column.add_child(UiHelpers.label(_tr(next_key)))
	if status.type != &"tunnel":
		var controls := UiHelpers.row(_column)
		controls.add_child(UiHelpers.button(_tr(&"ui.enable" if not status.enabled else &"ui.disable"), func(): services["building"].set_enabled(target_id, not status.enabled)))
	if status.type == &"greenhouse" and services.has("production") and status.modifiers.get("crop") in ["none", "dead"]:
		_column.add_child(UiHelpers.label(_tr(&"ui.cost", {"cost": UiHelpers.resource_text({"seeds": ConfigDB.balance["buildings"]["greenhouse"]["seed_cost"]})})))
		_column.add_child(UiHelpers.button(_tr(&"ui.plant_seed"), func(): _show_result(services["production"].plant_seed(target_id))))
	if status.type == &"solar_panel":
		_column.add_child(UiHelpers.button(_tr(&"ui.unprotect_panel" if status.modifiers.get("storm_protected", false) else &"ui.protect_panel"), func(): _show_result(services["building"].set_storm_protection(target_id, not status.modifiers.get("storm_protected", false)))))
	if status.type == &"printer_3d" and services.has("production"):
		for recipe_id in ConfigDB.balance["buildings"]["printer_3d"]["recipes"]:
			_column.add_child(UiHelpers.label(UiHelpers.resource_text(ConfigDB.balance["buildings"]["printer_3d"]["recipes"][recipe_id])))
			_column.add_child(UiHelpers.button(_tr(&"ui.print", {"item": _tr(StringName("resource.%s" % recipe_id))}), func(): _show_result(services["production"].print_recipe(target_id, StringName(recipe_id)))))
	var worker: OptionButton
	if status.condition == &"breached" and services.has("crew"):
		var mode := OptionButton.new()
		for method in ["seal", "weld", "spare_parts"]:
			mode.add_item(_tr(StringName("ui.repair_mode.%s" % method)))
			mode.set_item_metadata(mode.item_count - 1, method)
		_column.add_child(mode)
		worker = _crew_choices()
		_column.add_child(UiHelpers.button(_tr(&"ui.repair_selected"), func(): _show_result(services["crew"].assign_eva_repair(StringName(worker.get_selected_metadata()), target_id, StringName(mode.get_selected_metadata()))), true))
	if status.type == &"reactor":
		_column.add_child(UiHelpers.label(_tr(&"ui.fuel_remaining", {"sols": String.num(float(status.modifiers.get("fuel_sols", 0)), 1)})))
	if services.has("crew") and status.type in [&"tunnel", &"solar_panel", &"reactor"]:
		var action := &"isolate" if status.type == &"tunnel" else &"clean" if status.type == &"solar_panel" else &"refuel"
		var validation: GameContracts.ValidationResult = services["building"].validate_action(target_id, action)
		if validation.ok:
			if action == &"refuel":
				_column.add_child(UiHelpers.label(UiHelpers.resource_text({"nuclear_core": 1})))
			if worker == null:
				worker = _crew_choices()
			_column.add_child(UiHelpers.button(_tr(StringName("ui.action.%s" % action)), func(): _show_result(services["crew"].assign_building_action(StringName(worker.get_selected_metadata()), target_id, action))))
	if not String(target_id) in ["base_1", "isru_1", "greenhouse_1", "reactor_1"]:
		_column.add_child(UiHelpers.button(_tr(&"ui.remove_building"), _confirm_remove))
	_column.add_child(UiHelpers.label(_tr(&"inspector.local_log")))
	for item in services["building"].get_log(target_id):
		_column.add_child(UiHelpers.label(_tr(StringName(item.get("message_key", "")), item.get("params", {}))))

func _show_result(result: GameContracts.ValidationResult) -> void:
	_feedback_text = _tr(&"ui.action_done") if result.ok else _tr(result.message_key, result.params)
	refresh()

func _crew_choices() -> OptionButton:
	_column.add_child(UiHelpers.label(_tr(&"ui.choose_worker")))
	var picker := OptionButton.new()
	for member in services["crew"].get_snapshot():
		if member.get("alive", false):
			picker.add_item(UiHelpers.entity_name(member["id"]))
			picker.set_item_metadata(picker.item_count - 1, member["id"])
	_column.add_child(picker)
	return picker

func _confirm_remove() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = _tr(&"ui.remove_warning")
	dialog.title = _tr(&"ui.remove_building")
	add_child(dialog)
	var id := target_id
	dialog.confirmed.connect(func(): _show_result(services["building"].remove(id)); dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(480, 180))

func _tr(key: StringName, params: Dictionary = {}) -> String:
	return get_tree().root.get_node("LocalizationDB").translate_key(key, params)

