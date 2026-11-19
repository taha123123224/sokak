extends Node
## v4.18 global interface audio. Every button, toggle, slider, tab bar and popup that is created anywhere
## (menu, login, settings, pause, HUD buy menu, dialogs) gets hover / click / toggle / tab / open sounds,
## so no screen is silent. Controls built with UI.btn() already play their own sounds and carry
## meta "sfx" -> skipped here so nothing plays twice. Sounds route to the "UI" bus (Settings > Ses).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node)

static func on() -> bool:
	return bool(GS.settings.get("ui_sounds", true))

func _on_node(n: Node) -> void:
	if n.has_meta("sfx") or n.has_meta("no_sfx"):
		return
	if n is Window and n != get_tree().root:
		n.set_meta("sfx", true)
		(n as Window).about_to_popup.connect(func(): if on(): SFX.ui("ui_open", -8))
		return
	if not (n is Control):
		return
	n.set_meta("sfx", true)
	if n is CheckBox or n is CheckButton:
		(n as BaseButton).toggled.connect(func(_on): if on(): SFX.ui("ui_toggle", -6))
		(n as Control).mouse_entered.connect(func(): if on(): SFX.ui("ui_hover", -16))
	elif n is OptionButton:
		(n as OptionButton).pressed.connect(func(): if on(): SFX.ui("ui_open", -10))
		(n as OptionButton).item_selected.connect(func(_i): if on(): SFX.ui("ui_click", -6))
		(n as Control).mouse_entered.connect(func(): if on(): SFX.ui("ui_hover", -16))
	elif n is BaseButton:
		(n as BaseButton).pressed.connect(func(): if on(): SFX.ui("ui_click", -6))
		(n as Control).mouse_entered.connect(func():
			if on() and not (n as BaseButton).disabled:
				SFX.ui("ui_hover", -16))
	elif n is Slider:
		(n as Slider).drag_ended.connect(func(_c): if on(): SFX.ui("ui_slider", -8))
	elif n is TabBar:
		(n as TabBar).tab_changed.connect(func(_t): if on(): SFX.ui("ui_tab", -6))
	elif n is TabContainer:
		(n as TabContainer).tab_changed.connect(func(_t): if on(): SFX.ui("ui_tab", -6))
	elif n is LineEdit:
		(n as LineEdit).text_submitted.connect(func(_t): if on(): SFX.ui("ui_click", -8))
