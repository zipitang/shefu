class_name SettingsPanel
extends Control
## 设置面板 —— 半透明遮罩 + 居中面板，条目列表式。
## 【为什么做成浮层而不是独立界面】
## 设置是「随时打开、改完就走」的东西：在对局里调个音量不该被迫退回大厅。
## 所以它是任意界面之上的一层，关掉后原地继续。
##
## 用法：  SettingsPanel.open(host_node)     —— host 一般是当前 Screen

const PANEL_W := 580.0
const ROW_LABEL_W := 128.0

var _res_opt: OptionButton
var _vol_pct: Label
var _box: VBoxContainer


## 在 host 之上打开设置层
static func open(host: Node) -> void:
	if host == null:
		return
	if host.get_node_or_null("SettingsPanel") != null:
		return                        # 已经开着，不重复叠
	var layer := SettingsPanel.new()
	layer.name = "SettingsPanel"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 200
	host.add_child(layer)


func _ready() -> void:
	# ---- 遮罩：点空白处关闭 ----
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close())
	add_child(dim)

	# ---- 面板本体 ----
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UITheme.frost_style(Color(0.055, 0.042, 0.088, 0.98), Color(0.91, 0.76, 0.42, 0.62), 18, 1, 26.0))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	add_child(panel)

	_box = UITheme.mk_vbox(14)
	panel.add_child(_box)

	# 标题
	var head := UITheme.mk_hbox(12)
	_box.add_child(head)
	head.add_child(UITheme.mk_label("设  置", 26, UITheme.GOLD, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close_x := UITheme.mk_icon_button("exit", "关闭（Esc）", 34)
	close_x.pressed.connect(_close)
	head.add_child(close_x)

	_box.add_child(HSeparator.new())

	# ---------------- 显示 ----------------
	_box.add_child(_section("显 示"))

	var mode := _combo(["窗口化", "全屏"], 1 if Settings.fullscreen else 0)
	mode.item_selected.connect(func(i: int):
		Settings.set_fullscreen(i == 1)
		_sync())
	_box.add_child(_row("显示模式", "全屏铺满显示器；窗口化保留系统边框，便于随时切出去", mode))

	_res_opt = _combo(_res_labels(), _res_index())
	_res_opt.item_selected.connect(func(i: int):
		var o: Dictionary = Settings.RES_OPTS[i]
		Settings.set_resolution(int(o["w"]), int(o["h"])))
	_box.add_child(_row("窗口尺寸", "仅在窗口化时生效；若超过屏幕可用区会自动等比缩小", _res_opt))

	# ---------------- 声音 ----------------
	_box.add_child(_section("声 音"))

	var vol_row := UITheme.mk_hbox(10)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = Settings.master_volume * 100.0
	slider.custom_minimum_size = Vector2(200, 26)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol_pct = UITheme.mk_label("%d%%" % int(Settings.master_volume * 100.0), 15,
		Color(0.91, 0.84, 0.66))
	_vol_pct.custom_minimum_size = Vector2(48, 0)
	slider.value_changed.connect(func(v: float):
		Settings.set_volume(v / 100.0)
		_vol_pct.text = "%d%%" % int(v))
	# 松手才试听一声，拖动过程中不响（否则就是「哒哒哒」机关枪）
	slider.drag_ended.connect(func(changed: bool):
		if changed:
			Sfx.play("ui_tick", -3.0))
	vol_row.add_child(slider)
	vol_row.add_child(_vol_pct)
	_box.add_child(_row("音效音量", "全部界面与技能音效的总音量", vol_row))

	# ---------------- 表现 ----------------
	_box.add_child(_section("表 现"))

	var gy := CheckButton.new()
	gy.text = "开启"
	gy.button_pressed = Settings.gyro
	gy.toggled.connect(func(v: bool):
		Settings.set_gyro(v)
		Sfx.play("ui_toggle", -8.0))
	UITheme.attach_ui_sfx(gy)
	_box.add_child(_row("陀螺仪视差", "移动端倾斜设备 / 桌面端拖动海报时，背景与角色产生纵深位移", gy))

	var ex := CheckButton.new()
	ex.text = "开启"
	ex.button_pressed = Settings.effects
	ex.toggled.connect(func(v: bool):
		Settings.set_effects(v)
		Sfx.play("ui_toggle", -8.0))
	UITheme.attach_ui_sfx(ex)
	_box.add_child(_row("特效与动效", "关闭后所有补间 / 粒子停用（低配设备或截图比对用）", ex))

	_box.add_child(HSeparator.new())

	var foot := UITheme.mk_hbox(10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	_box.add_child(foot)
	var done := UITheme.mk_gold_button("完 成", 19)
	done.pressed.connect(_close)
	foot.add_child(done)

	_sync()
	# 打开动画
	panel.scale = Vector2(0.94, 0.94)
	panel.pivot_offset = panel.custom_minimum_size * 0.5
	panel.modulate.a = 0.0
	dim.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK)
	tw.tween_property(panel, "modulate:a", 1.0, 0.16)
	tw.tween_property(dim, "modulate:a", 1.0, 0.16)
	Sfx.play("ui_open", -6.0)


# ------------------------------------------------------------------ 小工具
func _section(t: String) -> Control:
	var h := UITheme.mk_hbox(10)
	h.add_child(UITheme.mk_label(t, 17, UITheme.GOLD))
	var ln := HSeparator.new()
	ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ln.modulate = Color(1, 1, 1, 0.18)
	h.add_child(ln)
	return h


## 一行设置：左侧固定宽说明 + 右侧控件
func _row(title: String, tip: String, ctl: Control) -> Control:
	var h := UITheme.mk_hbox(14)
	var lv := UITheme.mk_vbox(1)
	lv.custom_minimum_size = Vector2(ROW_LABEL_W, 0)
	lv.add_child(UITheme.mk_label(title, 16, UITheme.TEXT))
	var t := UITheme.mk_label(tip, 11, UITheme.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(ROW_LABEL_W, 0)
	lv.add_child(t)
	h.add_child(lv)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	return h


func _combo(items: Array, sel: int) -> OptionButton:
	var b := OptionButton.new()
	for i in items.size():
		b.add_item(str(items[i]), i)
	b.selected = clampi(sel, 0, maxi(0, items.size() - 1))
	UITheme.style_option_button(b, 40.0)
	UITheme.attach_ui_sfx(b)
	return b


func _res_labels() -> Array:
	var out := []
	for o in Settings.RES_OPTS:
		out.append(str(o["label"]))
	return out


func _res_index() -> int:
	for i in Settings.RES_OPTS.size():
		var o: Dictionary = Settings.RES_OPTS[i]
		if int(o["w"]) == Settings.window_w and int(o["h"]) == Settings.window_h:
			return i
	return 0


## 全屏时「窗口尺寸」无意义，置灰但不隐藏（隐藏会让面板高度跳一下）
func _sync() -> void:
	if _res_opt != null:
		_res_opt.disabled = Settings.fullscreen
		_res_opt.modulate.a = 0.45 if Settings.fullscreen else 1.0


func _close() -> void:
	Sfx.play("ui_back", -8.0)
	queue_free()


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
