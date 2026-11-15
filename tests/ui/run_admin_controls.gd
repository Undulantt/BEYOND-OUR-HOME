extends Node

var failures := 0
var panel: AdminPanel
var ledger := ResourceLedger.new()
var events := EventService.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameState.reset(42)
	ledger.initialize({"iron_plates": 0.0})
	panel = AdminPanel.new()
	panel.position = Vector2(24, 24)
	panel.size = Vector2(360, 420)
	add_child(panel)
	panel.configure({"ledger": ledger, "event": events})
	await _settle()
	var infinite_button := _button(LocalizationDB.translate_key(&"ui.infinite_resources_off"))
	_check(infinite_button != null, "infinite resources toggle is visible")
	if infinite_button != null:
		await _click(infinite_button)
	_check(ledger.infinite_resources, "clicking the toggle enables infinite resources")
	_check(ledger.can_afford({"iron_plates": 100000.0}), "infinite mode accepts a cost larger than inventory")
	_check(is_equal_approx(ledger.get_amount(&"iron_plates"), 0.0), "affordability check does not change inventory")
	var breach_button := _button(LocalizationDB.translate_key(&"ui.trigger.tunnel_breach"))
	_check(breach_button != null, "Activar brecha button is visible")
	if breach_button != null:
		await _click(breach_button)
	var breach: Dictionary = GameState.data.get("events", {}).get("items", {}).get("tunnel_breach", {})
	_check(breach.get("phase") == "active", "clicking Activar brecha activates the tunnel breach event")
	call_deferred("_finish")

func _button(text: String) -> Button:
	for node in panel.find_children("*", "Button", true, false):
		if node.text == text:
			return node
	return null

func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await _settle()

func _settle() -> void:
	for frame in 5:
		await get_tree().process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)

func _finish() -> void:
	if failures == 0:
		print("Admin control UI tests passed")
	else:
		push_error("Admin control UI tests failed: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
