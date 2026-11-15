class_name TimeControls
extends HBoxContainer

signal settings_requested()

var _sol: Label
var _pause: Button
var _settings: Button
var _speeds: Dictionary = {}
var _last_clock := ""

func _ready() -> void:
	_sol = UiHelpers.label("", 14)
	_sol.add_theme_font_size_override("font_size", 14)
	_sol.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_sol)
	_pause = UiHelpers.button("", _toggle_pause)
	_compact_control(_pause, 64.0)
	add_child(_pause)
	_settings = UiHelpers.button("⚙", func(): settings_requested.emit())
	_compact_control(_settings, 34.0)
	_settings.tooltip_text = UiHelpers.translated(&"menu.settings")
	add_child(_settings)
	for speed in [0.5, 1.0, 2.0, 4.0]:
		var choice := UiHelpers.button("×%s" % speed, func(): GameClock.set_speed(speed); refresh())
		_compact_control(choice, 38.0)
		choice.toggle_mode = true
		_speeds[speed] = choice
		add_child(choice)
	SignalBus.language_changed.connect(func(_code): refresh())
	SignalBus.sol_started.connect(func(_sol_number): refresh())
	SignalBus.state_restored.connect(refresh)
	refresh()

func _compact_control(button: Button, width: float) -> void:
	button.custom_minimum_size = Vector2(width, 30.0)
	button.add_theme_font_size_override("font_size", 13)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_left = 5.0
		style.content_margin_right = 5.0
		style.content_margin_top = 2.0
		style.content_margin_bottom = 2.0
		button.add_theme_stylebox_override(state, style)

func _process(_delta: float) -> void:
	var clock := GameClock.get_snapshot()
	var signature := "%s:%s:%s:%s" % [clock.get("sol", 1), clock.get("paused", false), clock.get("speed", 1.0), int(clock.get("elapsed", 0.0))]
	if signature != _last_clock:
		_last_clock = signature
		refresh()

func refresh() -> void:
	if _sol == null:
		return
	var clock: Dictionary = GameClock.get_snapshot()
	_last_clock = "%s:%s:%s:%s" % [clock.get("sol", 1), clock.get("paused", false), clock.get("speed", 1.0), int(clock.get("elapsed", 0.0))]
	var cycle := GameClock.get_cycle_snapshot()
	_sol.text = UiHelpers.translated(&"hud.sol", {"sol": int(clock.get("sol", 1))}) + " · " + UiHelpers.translated(&"ui.cycle_day" if cycle["day"] else &"ui.cycle_night")
	_sol.tooltip_text = UiHelpers.translated(&"ui.cycle_next", {"seconds": ceili(float(cycle["seconds_to_change"]))}) + "\n" + UiHelpers.translated(&"ui.sol_tip")
	_pause.text = get_tree().root.get_node("LocalizationDB").translate_key(&"ui.resume" if clock.get("paused", false) else &"ui.pause")
	_pause.tooltip_text = UiHelpers.translated(&"ui.pause_tip")
	_settings.tooltip_text = UiHelpers.translated(&"menu.settings")
	for speed in _speeds:
		_speeds[speed].button_pressed = is_equal_approx(float(clock.get("speed", 1.0)), float(speed))
		_speeds[speed].tooltip_text = UiHelpers.translated(&"hud.speed", {"speed": speed})

func _toggle_pause() -> void:
	GameClock.set_paused(not GameClock.get_snapshot().get("paused", false))
	refresh()

