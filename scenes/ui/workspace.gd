class_name MissionWorkspace
extends PanelContainer

signal focus_requested(target_id: StringName)
signal tab_opened(id: StringName)

const TABS := [&"build", &"crew", &"energy", &"rocket", &"laboratory", &"resources", &"codex"]
var services: Dictionary = {}
var world: Node
var active_tab: StringName = &"build"
var _body: VBoxContainer
var _feedback: Label
var _tab_buttons: Dictionary = {}
var _tab_picker: OptionButton
var _build_type: StringName = &"laboratory"
var _build_cell := Vector2i(0, 0)
var _manifest: Dictionary = {}
var _rocket_id: StringName = &"rocket_1"
var _refresh_queued := false
var _scroll: ScrollContainer
var _coordinates_open := false
var _build_quote: Label
var _place_button: Button
var _manifest_quote: Label
var _manifest_confirm: Button
var _rocket_cell := Vector2i(22, 22)
var _scan_cell := Vector2i(4, 0)
var _lab_hours := 8.0
var _research_choice := "solar_panel"
var _research_bar: ProgressBar
var _research_status: Label

func _ready() -> void:
	custom_minimum_size = Vector2(0, 0)
	var column := UiHelpers.column(self)
	_tab_picker = OptionButton.new()
	_tab_picker.fit_to_longest_item = false
	_tab_picker.custom_minimum_size.y = 36
	column.add_child(_tab_picker)
	for id in TABS:
		_tab_picker.add_item(_tr(StringName("tab.%s" % id)))
		_tab_picker.set_item_metadata(_tab_picker.item_count - 1, id)
	_tab_picker.item_selected.connect(func(index): open_tab(StringName(_tab_picker.get_item_metadata(index))))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_body = UiHelpers.column(_scroll)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback = UiHelpers.label("")
	_feedback.hide()
	column.add_child(_feedback)
	SignalBus.language_changed.connect(func(_code): refresh())
	SignalBus.state_restored.connect(request_refresh)
	SignalBus.resources_changed.connect(_on_resources_changed)
	SignalBus.building_changed.connect(func(_id, _kind): request_refresh())
	SignalBus.crew_changed.connect(func(_id): request_refresh())
	SignalBus.rocket_changed.connect(func(_id, _kind): request_refresh())
	SignalBus.research_changed.connect(_on_research_changed)
	SignalBus.tick_advanced.connect(func(_dt): _update_research_progress())
	refresh()

func configure(dependencies: Dictionary) -> void:
	services = dependencies
	refresh()

func reset_drafts() -> void:
	_manifest = {}
	_rocket_id = &"rocket_1"
	_rocket_cell = Vector2i(22, 22)
	_scan_cell = Vector2i(4, 0)
	_lab_hours = 8.0
	_research_choice = "solar_panel"
	_coordinates_open = false
	active_tab = &"build"
	if _feedback != null:
		_feedback.text = ""
		_feedback.hide()

func _on_research_changed(_id: StringName, change: StringName) -> void:
	if change == &"progress":
		_update_research_progress()
	elif change == &"unlocked" and active_tab == &"laboratory":
		_feedback.text = _tr(&"ui.research_unlocked", {"technology": UiHelpers.technology_name(String(_id))})
		_feedback.show()
		refresh()
	else:
		request_refresh()

func _update_research_progress() -> void:
	if active_tab != &"laboratory" or not is_instance_valid(_research_bar) or _research_bar.is_queued_for_deletion() or not services.has("research"):
		return
	var state: Dictionary = services["research"].get_snapshot()
	var active := String(state.get("active", ""))
	if active.is_empty():
		return
	_research_bar.value = float(state.get("progress", 0.0))
	if is_instance_valid(_research_status):
		_research_status.text = _tr(&"ui.research_progress", {"done": String.num(_research_bar.value, 1), "total": _research_bar.max_value})

func set_world(world_node: Node) -> void:
	world = world_node
	refresh()

func apply_placement(request: GameContracts.PlacementRequest) -> void:
	if not services.has("building"):
		return
	var validation: GameContracts.PlacementResult = services["building"].validate_placement(request)
	if not validation.ok:
		_feedback.text = _quote(validation)
		_feedback.show()
		return
	_act(services["building"].place(request))

func open_tab(id: StringName) -> void:
	if TABS.has(id):
		active_tab = id
		refresh()
		_scroll.scroll_vertical = 0
		tab_opened.emit(id)

func _on_resources_changed(delta: Dictionary, _reason: String) -> void:
	if active_tab == &"resources":
		request_refresh()
	elif active_tab == &"build":
		for resource in delta:
			if resource not in ["oxygen", "water", "food"]:
				request_refresh()
				return

func request_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_deferred_refresh")

func _deferred_refresh() -> void:
	_refresh_queued = false
	var focus := get_viewport().gui_get_focus_owner()
	if (focus is LineEdit or focus is OptionButton) and _body.is_ancestor_of(focus):
		return
	refresh()

func refresh() -> void:
	if _body == null:
		return
	for index in TABS.size():
		_tab_picker.set_item_text(index, _tr(StringName("tab.%s" % TABS[index])))
		if TABS[index] == active_tab:
			_tab_picker.select(index)
	var scroll_position := _scroll.scroll_vertical
	UiHelpers.clear(_body)
	match active_tab:
		&"build": _show_build()
		&"crew": _show_crew()
		&"energy": _show_energy()
		&"rocket": _show_rocket()
		&"laboratory": _show_laboratory()
		&"resources": _show_resources()
		&"codex": _show_codex()
	_scroll.set_deferred("scroll_vertical", scroll_position)

func _show_build() -> void:
	if not services.has("building"):
		_missing()
		return
	var kinds: Array = ConfigDB.balance.get("buildings", {}).keys()
	var picker := OptionButton.new()
	picker.fit_to_longest_item = false
	for kind in kinds:
		picker.add_item(_tr(StringName("building.%s" % kind)))
		picker.set_item_metadata(picker.item_count - 1, kind)
	_body.add_child(picker)
	for i in picker.item_count:
		if picker.get_item_metadata(i) == String(_build_type):
			picker.select(i)
	picker.item_selected.connect(func(index): _build_type = StringName(picker.get_item_metadata(index)); refresh())
	var definition := BuildingDefinition.from_balance(_build_type)
	_body.add_child(UiHelpers.label(_tr(&"ui.cost", {"cost": UiHelpers.resource_text(definition.cost)})))
	if world != null and world.has_method("begin_placement"):
		_body.add_child(UiHelpers.button(_tr(&"ui.pick_on_map"), func(): world.begin_placement(_build_type); _feedback.text = _tr(&"ui.placement_help"); _feedback.show(), true))
	_body.add_child(UiHelpers.label(_tr(&"ui.build_help")))
	var advanced := CheckButton.new()
	advanced.text = _tr(&"ui.coordinates")
	advanced.custom_minimum_size.y = 44
	advanced.button_pressed = _coordinates_open
	_body.add_child(advanced)
	var coordinates := UiHelpers.column(_body)
	coordinates.visible = _coordinates_open
	advanced.toggled.connect(func(enabled): _coordinates_open = enabled; coordinates.visible = enabled)
	var location := UiHelpers.row(coordinates)
	var x := SpinBox.new()
	x.min_value = 0
	x.max_value = 255
	x.value = _build_cell.x
	location.add_child(UiHelpers.label("X"))
	location.add_child(x)
	var y := SpinBox.new()
	y.min_value = 0
	y.max_value = 255
	y.value = _build_cell.y
	location.add_child(UiHelpers.label("Y"))
	location.add_child(y)
	x.value_changed.connect(func(value): _build_cell.x = int(value); _update_build_quote())
	y.value_changed.connect(func(value): _build_cell.y = int(value); _update_build_quote())
	_build_quote = UiHelpers.label("")
	coordinates.add_child(_build_quote)
	_place_button = UiHelpers.button(_tr(&"ui.place"), func(): _act(services["building"].place(GameContracts.PlacementRequest.new(_build_type, _build_cell))))
	coordinates.add_child(_place_button)
	_update_build_quote()

func _update_build_quote() -> void:
	if not is_instance_valid(_build_quote) or not is_instance_valid(_place_button):
		return
	var quote: GameContracts.PlacementResult = services["building"].validate_placement(GameContracts.PlacementRequest.new(_build_type, _build_cell))
	_build_quote.text = _quote(quote)
	_place_button.disabled = not quote.ok

func _show_crew() -> void:
	if not services.has("crew"):
		_missing()
		return
	for member in services["crew"].get_snapshot():
		if not member.get("alive", false):
			continue
		var id := StringName(member["id"])
		_body.add_child(UiHelpers.label("%s · %s" % [UiHelpers.entity_name(String(id)), _tr(StringName("profile.%s" % member["profile_id"]))], 22))
		var context: Dictionary = services["crew"].get_exposure_context(id)
		_body.add_child(UiHelpers.label(_tr(StringName("crew.exposure." + String(context.exposure)))))
		_body.add_child(UiHelpers.label(_tr(&"ui.crew_vitals", {"health": int(member.get("health", 0)), "dose": int(member.get("dose", 0))})))
		var task_id := StringName(member.get("task_id", ""))
		if not String(task_id).is_empty():
			var task: Dictionary = GameState.data["crew"]["tasks"].get(String(task_id), {})
			_body.add_child(UiHelpers.label("%s: %.1f / %.1f h" % [_tr(StringName("task.%s" % task.get("task_type", ""))), float(task.get("completed_hours", 0)), float(task.get("required_hours", 0))]))
			_body.add_child(UiHelpers.button(_tr(&"ui.cancel_task"), func(): _act(services["crew"].cancel_task(task_id))))
		var row := HFlowContainer.new()
		_body.add_child(row)
		row.add_child(UiHelpers.button(_tr(&"ui.shelter"), func(): _act(services["crew"].order_shelter(id, true))))
		row.add_child(UiHelpers.button(_tr(&"ui.leave_shelter"), func(): _act(services["crew"].order_shelter(id, false))))
		row.add_child(UiHelpers.button(_tr(&"ui.medicine"), func(): _act(services["crew"].use_medicine(id))))
		var priority := OptionButton.new()
		for category in ["survival", "emergency_eva", "production", "science_construction"]:
			priority.add_item(_tr(StringName("category.%s" % category)))
			priority.set_item_metadata(priority.item_count - 1, category)
		_body.add_child(priority)
		var rank := SpinBox.new()
		rank.min_value = 1
		rank.max_value = 4
		rank.value = 1
		_body.add_child(rank)
		_body.add_child(UiHelpers.button(_tr(&"ui.set_priority"), func(): _act(services["crew"].set_priority(id, StringName(priority.get_selected_metadata()), int(rank.value)))))
		var category_allowed: bool = not member.get("forbidden_categories", []).has(priority.get_selected_metadata())
		var toggle := UiHelpers.button(_tr(&"ui.allow_category" if not category_allowed else &"ui.forbid_category"), func(): _act(services["crew"].set_category_allowed(id, StringName(priority.get_selected_metadata()), member.get("forbidden_categories", []).has(priority.get_selected_metadata()))))
		_body.add_child(toggle)
		priority.item_selected.connect(func(_idx): toggle.text = _tr(&"ui.allow_category" if member.get("forbidden_categories", []).has(priority.get_selected_metadata()) else &"ui.forbid_category"))
		var sleep := UiHelpers.column(_body)
		sleep.add_child(UiHelpers.label(_tr(&"ui.sleep_hours")))
		var hours := SpinBox.new()
		hours.min_value = 4
		hours.max_value = 16
		hours.value = float(member.get("sleep_hours", 8.0))
		sleep.add_child(hours)
		sleep.add_child(UiHelpers.button(_tr(&"ui.save"), func(): _act(services["crew"].set_sleep_hours(id, hours.value))))

func _show_energy() -> void:
	if not services.has("power"):
		_missing()
		return
	var snapshot: Dictionary = services["power"].get_snapshot().as_dict()
	_body.add_child(UiHelpers.label(_tr(&"ui.energy_summary", {"generation": snapshot.get("generation", 0), "demand": snapshot.get("demand", 0), "stored": snapshot.get("stored", 0)})))
	for id in snapshot.get("by_building", {}):
		var data: Dictionary = snapshot["by_building"][id]
		_body.add_child(UiHelpers.label("%s · %s" % [UiHelpers.entity_name(id), _tr(&"ui.powered") if data.get("powered", false) else _tr(&"ui.unpowered")]))
		var row := UiHelpers.row(_body)
		for rank in [1, 2, 3, 4]:
			var choice := UiHelpers.button(str(rank), func(): services["power"].set_priority(StringName(id), rank); refresh())
			choice.custom_minimum_size.x = 52
			choice.toggle_mode = true
			choice.button_pressed = int(data.get("priority", 0)) == rank
			choice.tooltip_text = _tr(&"ui.priority_help")
			row.add_child(choice)

func _show_rocket() -> void:
	if not services.has("rocket"):
		_missing()
		return
	var plans: Array = services["rocket"].get_snapshot()
	var picker := OptionButton.new()
	for plan in plans:
		picker.add_item("%s · %s" % [UiHelpers.entity_name(plan["id"]), _tr(&"hud.sol", {"sol": plan["arrival_sol"]})])
		picker.set_item_metadata(picker.item_count - 1, plan["id"])
	_body.add_child(picker)
	for i in picker.item_count:
		if picker.get_item_metadata(i) == String(_rocket_id):
			picker.select(i)
	picker.item_selected.connect(func(index): _rocket_id = StringName(picker.get_item_metadata(index)); refresh())
	var current: Dictionary = {}
	for plan in plans:
		if plan["id"] == String(_rocket_id):
			current = plan
	if current.is_empty():
		return
	_body.add_child(UiHelpers.label(_tr(&"ui.rocket_state", {"mass": current["mass_limit"], "state": _tr(&"ui.confirmed") if current["confirmed"] else _tr(&"ui.unconfirmed")})))
	if current["confirmed"]:
		_body.add_child(UiHelpers.label(UiHelpers.resource_text(current["manifest"])))
		if not current["landed"] and int(GameClock.get_snapshot().get("sol", 1)) >= int(current["arrival_sol"]):
			_body.add_child(UiHelpers.button(_tr(&"ui.trigger_arrival"), func(): _act(services["rocket"].trigger_arrival(_rocket_id))))
		if current["landed"] and current["disposition"] == "available" and services.has("crew"):
			var crew_picker := OptionButton.new()
			for member in services["crew"].get_snapshot():
				if member.get("alive", false):
					crew_picker.add_item(UiHelpers.entity_name(String(member["id"])))
					crew_picker.set_item_metadata(crew_picker.item_count - 1, member["id"])
			_body.add_child(crew_picker)
			if crew_picker.item_count > 0:
				var selected_crew := func() -> StringName: return StringName(crew_picker.get_selected_metadata())
				var salvage_quote: GameContracts.ValidationResult = services["rocket"].validate_salvage(_rocket_id, selected_crew.call())
				var salvage_status := UiHelpers.label(_quote(salvage_quote))
				_body.add_child(salvage_status)
				var salvage := UiHelpers.button(_tr(&"action.salvage_rocket"), func(): _act(services["rocket"].salvage(_rocket_id, selected_crew.call())))
				salvage.disabled = not salvage_quote.ok
				_body.add_child(salvage)
				var profile_picker := OptionButton.new()
				for profile_id in Astronaut.profiles():
					profile_picker.add_item(_tr(StringName("profile.%s" % profile_id)))
					profile_picker.set_item_metadata(profile_picker.item_count - 1, profile_id)
				_body.add_child(profile_picker)
				var replacement_quote: GameContracts.ValidationResult = services["rocket"].validate_exchange(_rocket_id, selected_crew.call(), StringName(profile_picker.get_selected_metadata()))
				var replacement_status := UiHelpers.label(_quote(replacement_quote))
				_body.add_child(replacement_status)
				var exchange := UiHelpers.button(_tr(&"action.replace_astronaut"), func(): _act(services["rocket"].exchange(_rocket_id, selected_crew.call(), StringName(profile_picker.get_selected_metadata()))))
				exchange.disabled = not replacement_quote.ok
				_body.add_child(exchange)
				var update_actions := func(_index: int):
					var next_salvage: GameContracts.ValidationResult = services["rocket"].validate_salvage(_rocket_id, selected_crew.call())
					var next_exchange: GameContracts.ValidationResult = services["rocket"].validate_exchange(_rocket_id, selected_crew.call(), StringName(profile_picker.get_selected_metadata()))
					salvage.disabled = not next_salvage.ok
					exchange.disabled = not next_exchange.ok
					salvage_status.text = _quote(next_salvage)
					replacement_status.text = _quote(next_exchange)
				crew_picker.item_selected.connect(update_actions)
				profile_picker.item_selected.connect(update_actions)
		return
	for item in ConfigDB.balance.get("rockets", {}).get("cargo_mass", {}):
		var row := UiHelpers.row(_body)
		row.add_child(UiHelpers.label(_tr(StringName("resource.%s" % item)) if item != "astronaut_replacement" else _tr(&"action.replace_astronaut")))
		var count := SpinBox.new()
		count.min_value = 0
		count.max_value = 99
		count.step = 1
		count.value = int(_manifest.get(item, 0))
		count.value_changed.connect(func(value): _manifest[item] = int(value); _refresh_quote())
		row.add_child(count)
	var quote: GameContracts.ValidationResult = services["rocket"].validate_manifest(_rocket_id, _manifest)
	_manifest_quote = UiHelpers.label(_quote(quote))
	_body.add_child(_manifest_quote)
	_body.add_child(UiHelpers.label(_tr(&"ui.landing_help")))
	var zone := UiHelpers.row(_body)
	var zx := SpinBox.new()
	var zy := SpinBox.new()
	for spin in [zx, zy]:
		spin.min_value = 0
		spin.max_value = 255
		zone.add_child(UiHelpers.label("X" if spin == zx else "Y"))
		zone.add_child(spin)
	zx.value = _rocket_cell.x
	zy.value = _rocket_cell.y
	zx.value_changed.connect(func(value): _rocket_cell.x = int(value))
	zy.value_changed.connect(func(value): _rocket_cell.y = int(value))
	_body.add_child(UiHelpers.button(_tr(&"ui.reserve_zone"), func(): _act(services["rocket"].reserve_landing_zone(_rocket_id, Rect2i(int(zx.value), int(zy.value), int(ConfigDB.balance["rockets"]["landing_zone_size"]), int(ConfigDB.balance["rockets"]["landing_zone_size"]))))))
	var confirm := UiHelpers.button(_tr(&"action.confirm_manifest"), func(): _act(services["rocket"].confirm_manifest(_rocket_id, _manifest)))
	confirm.disabled = not quote.ok or current["zone"].is_empty()
	_manifest_confirm = confirm
	_body.add_child(confirm)

func _show_laboratory() -> void:
	if not services.has("research"):
		_missing()
		return
	var state: Dictionary = services["research"].get_snapshot()
	var active := String(state.get("active", ""))
	_body.add_child(UiHelpers.label(_tr(&"ui.research_help")))
	if active.is_empty():
		var technology := OptionButton.new()
		technology.fit_to_longest_item = false
		for tech in ConfigDB.balance.get("research", {}):
			technology.add_item("%s · %s h" % [UiHelpers.technology_name(tech), ConfigDB.balance["research"][tech]])
			technology.set_item_metadata(technology.item_count - 1, tech)
			if tech == _research_choice:
				technology.select(technology.item_count - 1)
		_body.add_child(technology)
		var quote: GameContracts.ValidationResult = services["research"].validate_research(StringName(_research_choice))
		var explanation := UiHelpers.label(_quote(quote))
		_body.add_child(explanation)
		var start := UiHelpers.button(_tr(&"action.research"), func(): _act(services["research"].start_research(StringName(_research_choice))), true)
		start.disabled = not quote.ok
		_body.add_child(start)
		technology.item_selected.connect(func(index):
			_research_choice = String(technology.get_item_metadata(index))
			var next_quote: GameContracts.ValidationResult = services["research"].validate_research(StringName(_research_choice))
			explanation.text = _quote(next_quote)
			start.disabled = not next_quote.ok)
	else:
		_body.add_child(UiHelpers.label(UiHelpers.technology_name(active), 22))
		var progress := ProgressBar.new()
		_research_bar = progress
		progress.max_value = float(ConfigDB.balance["research"][active])
		progress.value = float(state.get("progress", 0.0))
		progress.custom_minimum_size.y = 28
		_body.add_child(progress)
		_research_status = UiHelpers.label("")
		_body.add_child(_research_status)
		_update_research_progress()
	var laboratories := OptionButton.new()
	if services.has("crew") and services.has("building"):
		for status in services["building"].get_all_statuses():
			if status.type == &"laboratory" and status.powered:
				laboratories.add_item(UiHelpers.entity_name(String(status.building_id)))
				laboratories.set_item_metadata(laboratories.item_count - 1, status.building_id)
	_body.add_child(laboratories)
	laboratories.visible = laboratories.item_count > 1
	if laboratories.item_count > 0:
		_body.add_child(UiHelpers.label(_tr(&"ui.research_hours")))
		var hours := SpinBox.new()
		hours.min_value = 1
		hours.max_value = 16
		hours.value = _lab_hours
		hours.value_changed.connect(func(value): _lab_hours = value)
		_body.add_child(hours)
		var worker := OptionButton.new()
		for member in services["crew"].get_snapshot():
			if member.get("alive", false) and String(member.get("task_id", "")).is_empty():
				worker.add_item(UiHelpers.entity_name(member["id"]))
				worker.set_item_metadata(worker.item_count - 1, member["id"])
		_body.add_child(worker)
		var assign := UiHelpers.button(_tr(&"ui.assign_worker"), func(): _act(services["crew"].queue_research(StringName(worker.get_selected_metadata()), StringName(laboratories.get_selected_metadata()), hours.value)), true)
		assign.disabled = worker.item_count == 0
		_body.add_child(assign)
	else:
		_body.add_child(UiHelpers.button(_tr(&"ui.build_lab"), func(): _build_type = &"laboratory"; open_tab(&"build")))
	if services.has("scan") and state.get("unlocked", []).has("satellite_scan"):
		_body.add_child(UiHelpers.label(_tr(&"action.scan"), 19))
		var row := UiHelpers.row(_body)
		var sx := SpinBox.new()
		var sy := SpinBox.new()
		for spin in [sx, sy]:
			spin.min_value = 0
			spin.max_value = 31
			row.add_child(spin)
		sx.value = _scan_cell.x
		sy.value = _scan_cell.y
		sx.value_changed.connect(func(value): _scan_cell.x = int(value))
		sy.value_changed.connect(func(value): _scan_cell.y = int(value))
		var quote_scan: GameContracts.ValidationResult = services["scan"].validate_scan(Vector2i(int(sx.value), int(sy.value)))
		var scan_quote_label := UiHelpers.label(_quote(quote_scan))
		_body.add_child(scan_quote_label)
		var update_scan := func(_value): scan_quote_label.text = _quote(services["scan"].validate_scan(Vector2i(int(sx.value), int(sy.value))))
		sx.value_changed.connect(update_scan)
		sy.value_changed.connect(update_scan)
		_body.add_child(UiHelpers.button(_tr(&"action.scan"), func(): _act(services["scan"].scan(Vector2i(int(sx.value), int(sy.value))))))

func _show_resources() -> void:
	if not services.has("ledger"):
		_missing()
		return
	for id in services["ledger"].get_snapshot():
		_body.add_child(UiHelpers.label("%s: %.1f" % [_tr(StringName("resource.%s" % id)), services["ledger"].get_amount(StringName(id))]))

func _show_codex() -> void:
	if services.has("dialogue"):
		_body.add_child(UiHelpers.label(_tr(&"onboarding.help")))
		_body.add_child(UiHelpers.button(_tr(&"onboarding.recall"), services["dialogue"].recall_tutorial, true))
		_body.add_child(UiHelpers.button(_tr(&"onboarding.reactivate"), services["dialogue"].reactivate_tutorial))
		_body.add_child(UiHelpers.button(_tr(&"onboarding.restart"), services["dialogue"].restart_tutorial))
	for source in get_tree().root.get_node("NasaDataCatalog").get_sources():
		_body.add_child(UiHelpers.label(source["title"], 19))
		_body.add_child(UiHelpers.label(_tr(StringName(source["explanation_key"]))))
		_body.add_child(UiHelpers.label(_tr(StringName(source["model_limit_key"]))))
		_body.add_child(UiHelpers.label("%s · %s" % [source["url"], source["retrieved_on"]]))
	for event in get_tree().root.get_node("NasaDataCatalog").get_curated_events():
		_body.add_child(UiHelpers.label("%s · %s · %s" % [event["id"], event["class"], event["peak_utc"]]))

func _quote(result: GameContracts.ValidationResult) -> String:
	if not result.ok:
		return _tr(result.message_key, result.params)
	if result.params.has("mass"):
		return _tr(&"ui.manifest_mass", result.params)
	return _tr(&"ui.cost", {"cost": UiHelpers.resource_text(result.costs)}) if not result.costs.is_empty() else _tr(&"ui.ready")

func _act(result: GameContracts.ValidationResult) -> void:
	_feedback.text = _quote(result)
	if result.ok and result.params.has("building_id") and GameState.data.get("tutorial", {}).get("guided", false):
		# A guided build is one deliberate placement, with an explicit success state.
		_coordinates_open = false
		if world != null:
			world.cancel_placement()
		_feedback.text = _tr(&"onboarding.built")
	_feedback.show()
	refresh()

func _refresh_quote() -> void:
	if services.has("rocket"):
		var result: GameContracts.ValidationResult = services["rocket"].validate_manifest(_rocket_id, _manifest)
		_feedback.text = _quote(result)
		_feedback.show()
		if is_instance_valid(_manifest_quote):
			_manifest_quote.text = _quote(result)
		if is_instance_valid(_manifest_confirm):
			var reserved := false
			for plan in services["rocket"].get_snapshot():
				if plan["id"] == String(_rocket_id):
					reserved = not plan["zone"].is_empty()
			_manifest_confirm.disabled = not result.ok or not reserved

func _missing() -> void:
	_body.add_child(UiHelpers.label(_tr(&"ui.waiting_for_service")))

func _tr(key: StringName, params: Dictionary = {}) -> String:
	return get_tree().root.get_node("LocalizationDB").translate_key(key, params)

