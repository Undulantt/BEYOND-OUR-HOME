class_name AdminPanel
extends PanelContainer

var services: Dictionary = {}
var _feedback: Label
var _column: VBoxContainer
var _infinite_button: Button

func _ready() -> void:
	_column = UiHelpers.column(self)
	SignalBus.language_changed.connect(_rebuild)
	_rebuild()

func _rebuild(_code: StringName = &"") -> void:
	if _column == null:
		return
	UiHelpers.clear(_column)
	var column := _column
	column.add_child(UiHelpers.label(_tr(&"ui.admin"), 22))
	_infinite_button = UiHelpers.button("", _toggle_infinite_resources)
	column.add_child(_infinite_button)
	_refresh_infinite_button()
	var sol := SpinBox.new()
	sol.min_value = 2
	sol.max_value = 42
	column.add_child(sol)
	column.add_child(UiHelpers.button(_tr(&"ui.advance_sol"), func(): _show(GameClock.advance_to_sol(int(sol.value)))))
	for id in [&"tunnel_breach", &"dust_storm", &"solar_flare"]:
		var row := UiHelpers.row(column)
		row.add_child(UiHelpers.button(_tr(StringName("ui.trigger.%s" % id)), _trigger_event.bind(id)))
		row.add_child(UiHelpers.button(_tr(&"ui.clear_event"), _clear_event.bind(id)))
	var rocket_id := LineEdit.new()
	rocket_id.placeholder_text = "rocket_1"
	column.add_child(rocket_id)
	column.add_child(UiHelpers.button(_tr(&"ui.trigger_arrival"), func(): if services.has("rocket"): _show(services["rocket"].trigger_arrival(StringName(rocket_id.text)))))
	var building_id := LineEdit.new()
	building_id.placeholder_text = "tunnel_1"
	column.add_child(building_id)
	column.add_child(UiHelpers.button(_tr(&"ui.remove_building"), func(): if services.has("building"): _show(services["building"].remove(StringName(building_id.text)))))
	_feedback = UiHelpers.label("")
	column.add_child(_feedback)

func configure(dependencies: Dictionary) -> void:
	services = dependencies
	_refresh_infinite_button()

func _toggle_infinite_resources() -> void:
	if not services.has("ledger"):
		return
	var ledger = services["ledger"]
	ledger.set_infinite_resources(not ledger.infinite_resources)
	_refresh_infinite_button()
	_show(GameContracts.success())

func _refresh_infinite_button() -> void:
	if not is_instance_valid(_infinite_button):
		return
	var enabled: bool = services.has("ledger") and services["ledger"].infinite_resources
	_infinite_button.text = _tr(&"ui.infinite_resources_on" if enabled else &"ui.infinite_resources_off")

func _trigger_event(id: StringName) -> void:
	if services.has("event"):
		_show(services["event"].trigger_event(id))

func _clear_event(id: StringName) -> void:
	if services.has("event"):
		_show(services["event"].clear_event(id))

func _show(result: GameContracts.ValidationResult) -> void:
	_feedback.text = _tr(&"ui.ready") if result.ok else _tr(result.message_key, result.params)

func _tr(key: StringName, params: Dictionary = {}) -> String:
	return get_tree().root.get_node("LocalizationDB").translate_key(key, params)

