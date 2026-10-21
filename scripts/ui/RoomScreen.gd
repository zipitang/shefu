class_name RoomScreen
extends Control
## 房间（等待厅）：开房间后进入，不再直接开局
## ------------------------------------------------------------------
## · 房号 + 座位（东/南/西/北）+ 人数
## · 座位可添加/踢出 AI；人数变化时自动补齐/裁剪座位
## · 「开始对局」才真正进入 Battle，并由 Battle 开场选择【人】

signal start_game(cfg: Dictionary)
signal back_to_hall

const SEATS := ["东", "南", "西", "北"]
const SEAT_DESC := {
	"东": "先手",
	"南": "后手·补气",
	"西": "后手·补气",
	"北": "后手·补气",
}

var _base_cfg: Dictionary = {}
var room_code: String = ""
var player_count := 2
var ai_level := 2
var sel_chara := "chara_小乔儿"
var _seat_filled: Array = []          ## bool[4]，座位是否有人
var _seat_chara: Array = []           ## String[4]，座位角色 id
var _seat_names: Array = []           ## String[4]

var _seat_box: GridContainer
var _count_opt: OptionButton
var _code_lbl: Label
var _hint_lbl: Label


func setup(cfg: Dictionary) -> void:
	_base_cfg = cfg.duplicate(true)
	sel_chara = str(cfg.get("chara_id", "chara_小乔儿"))
	player_count = int(cfg.get("player_count", 2))
	ai_level = int(cfg.get("ai_level", 2))


func _ready() -> void:
	if room_code.is_empty():
		room_code = "%06d" % randi_range(100000, 999999)
	_rebuild_seats()
	_build()
	_refresh()


# ==================================================================== 座位数据
func _rebuild_seats() -> void:
	_seat_filled = [true, false, false, false]   # 东 = 玩家
	_seat_chara = [sel_chara, "", "", ""]
	_seat_names = ["你", "", "", ""]
	_fill_ai()


## 按人数补齐 AI 到目标座位数（东→南→西→北）
func _fill_ai() -> void:
	var others := ["chara_马曜", "chara_青蘅", "chara_唐森", "chara_白樰", "chara_孟谢菲", "chara_楚伞"]
	var k := 0
	for i in SEATS.size():
		if i < player_count and not _seat_filled[i]:
			_seat_filled[i] = true
			_seat_chara[i] = others[k % others.size()]
			_seat_names[i] = "电脑·" + str(SEATS[i])
			k += 1
	# 超出人数的座位清空
	for i in range(SEATS.size()):
		if i >= player_count:
			_seat_filled[i] = false
			_seat_chara[i] = ""
			_seat_names[i] = ""


# ==================================================================== 布局
func _build() -> void:
	add_child(UITheme.bg_rect("bg_room", 0.14))

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 20
	root.offset_bottom = -20
	add_child(root)

	# 顶部：房号
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	head.add_child(UITheme.mk_label("🏠  房间", 34, UITheme.GOLD, true))
	head.add_child(UITheme.mk_label("房号", 15, UITheme.TEXT_DIM))
	_code_lbl = UITheme.mk_label(room_code, 30, UITheme.AZURE, true)
	head.add_child(_code_lbl)
	var copy := UITheme.mk_button("复制房号", 14)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(room_code)
		_hint_lbl.text = "房号已复制：" + room_code
		Sfx.play("ui_click", -8.0))
	head.add_child(copy)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var gear := UITheme.mk_icon_button("gear", "设置：全屏 · 窗口化 · 音量 · 表现", 38)
	gear.pressed.connect(func(): SettingsPanel.open(self))
	head.add_child(gear)
	var back := UITheme.mk_button("← 返回大厅", 16)
	back.pressed.connect(func(): back_to_hall.emit())
	head.add_child(back)

	# 中部：座位
	var mid := UITheme.mk_panel(Color(0.086, 0.071, 0.118, 0.92), UITheme.PANEL_LINE)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var mv := UITheme.mk_vbox(10)
	mid.add_child(mv)
	mv.add_child(UITheme.mk_label("座位", 18, UITheme.GOLD_DIM))
	_seat_box = GridContainer.new()
	_seat_box.columns = 4
	_seat_box.add_theme_constant_override("h_separation", 12)
	_seat_box.add_theme_constant_override("v_separation", 12)
	_seat_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(_seat_box)

	# 底部：设置 + 开始
	var bar := UITheme.mk_panel(UITheme.PANEL_HI, UITheme.PANEL_LINE)
	root.add_child(bar)
	var bv := UITheme.mk_vbox(8)
	bar.add_child(bv)
	_hint_lbl = UITheme.mk_label("", 13, UITheme.TEXT_DIM)
	bv.add_child(_hint_lbl)

	var row := UITheme.mk_hbox(16)
	bv.add_child(row)
	row.add_child(UITheme.mk_label("人数", 15, UITheme.TEXT_DIM))
	_count_opt = OptionButton.new()
	_count_opt.add_item("2 人", 0)
	_count_opt.add_item("3 人", 1)
	_count_opt.add_item("4 人", 2)
	_count_opt.selected = player_count - 2
	_count_opt.item_selected.connect(func(i):
		player_count = 2 + i
		_rebuild_seats()
		_refresh()
		Sfx.play("ui_click", -10.0))
	row.add_child(_count_opt)
	UITheme.attach_ui_sfx(_count_opt)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp2)
	var start := UITheme.mk_gold_button("▶  开始对局", 22)
	start.custom_minimum_size = Vector2(240, 56)
	start.pressed.connect(_on_start)
	row.add_child(start)


func _refresh() -> void:
	for ch in _seat_box.get_children():
		ch.queue_free()
	for i in SEATS.size():
		_seat_box.add_child(_make_seat(i))
	var filled := 0
	for i in SEATS.size():
		if _seat_filled[i]:
			filled += 1
	_hint_lbl.text = "已就位 %d / %d" % [filled, player_count]


func _make_seat(i: int) -> Control:
	var seat: String = SEATS[i]
	var is_me := (i == 0)
	var occupied: bool = _seat_filled[i] and i < player_count

	var pnl := UITheme.mk_panel(UITheme.PANEL_HI, UITheme.SEAT_COLORS.get(seat, UITheme.PANEL_LINE) if occupied else UITheme.PANEL_LINE)
	pnl.custom_minimum_size = Vector2(0, 300)
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.mk_vbox(6)
	pnl.add_child(v)

	# 座位徽标
	var hd := UITheme.mk_hbox(8)
	v.add_child(hd)
	var badge := UITheme.mk_label(seat, 26, UITheme.seat_color(seat), true)
	hd.add_child(badge)
	hd.add_child(UITheme.mk_label(SEAT_DESC.get(seat, ""), 12, UITheme.TEXT_DIM))

	# 角色立绘（严格 9:16，居中）
	var art_row := HBoxContainer.new()
	art_row.alignment = BoxContainer.ALIGNMENT_CENTER
	art_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(art_row)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(132, 235)
	frame.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.PANEL_LINE, 8, 2))
	art_row.add_child(frame)
	if occupied:
		var art := TextureRect.new()
		var c: Dictionary = CardDB.get_chara(str(_seat_chara[i]))
		art.texture = CardView.texture_for(c.get("art", ""))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.custom_minimum_size = Vector2(126, 224)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(art)
	else:
		var empty := UITheme.mk_label("空位", 18, UITheme.TEXT_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(empty)

	# 名字 / 角色名
	var nm: String = str(_seat_names[i]) if occupied else "—"
	var nl := UITheme.mk_label(nm, 17, UITheme.GOLD if is_me else UITheme.TEXT, true)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	if occupied:
		var c2: Dictionary = CardDB.get_chara(str(_seat_chara[i]))
		var cl := UITheme.mk_label(str(c2.get("name", "")), 14, UITheme.TEXT_DIM)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cl)

	# 操作按钮
	var btn_row := UITheme.mk_hbox(6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_row)
	if is_me:
		var you := UITheme.mk_label("★ 房主（你）", 13, UITheme.GOLD_DIM)
		btn_row.add_child(you)
	elif occupied:
		var kick := UITheme.mk_button("踢出", 13)
		kick.pressed.connect(func():
			_seat_filled[i] = false
			_seat_chara[i] = ""
			_seat_names[i] = ""
			_refresh()
			Sfx.play("ui_click", -8.0))
		btn_row.add_child(kick)
	else:
		var add := UITheme.mk_button("＋ 添加电脑", 13)
		add.pressed.connect(func():
			var others := ["chara_马曜", "chara_青蘅", "chara_唐森", "chara_白樰", "chara_孟谢菲", "chara_楚伞"]
			_seat_filled[i] = true
			_seat_chara[i] = others[randi_range(0, others.size() - 1)]
			_seat_names[i] = "电脑·" + seat
			_refresh()
			Sfx.play("ui_click", -8.0))
		btn_row.add_child(add)
	return pnl


func _on_start() -> void:
	# 补齐所有目标座位
	_fill_ai()
	var ok := true
	for i in player_count:
		if not _seat_filled[i]:
			ok = false
	if not ok:
		_hint_lbl.text = "还有空位，请补齐对手后再开始"
		return
	Sfx.play("turn", -3.0)
	start_game.emit({
		"chara_id": sel_chara,
		"player_count": player_count,
		"ai_level": ai_level,
		"tutorial": bool(_base_cfg.get("tutorial", true)),
		"room_code": room_code,
	})
