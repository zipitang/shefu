class_name HallScreen
extends Control
## 游戏大厅：选择角色 →（匹配 / 开房间）
## 【人】的选择已移入对局内开场流程（见 BattleScreen 开场选择层）
##
## 角色选择：**恒定 4 列**，点头像在右侧展开 9:16 动态海报。
##   · 头像区固定 4 列（176px）—— 12 张一屏排开，点击任何一张都不会改变排布，
##     视线和肌肉记忆都稳定；（曾有「点开变 2 列」的方案，用户否掉了。）
##   · 右侧 9:16 窗口是**多层伪 3D 海报**：
##       最远层  背景 —— 放大 1.26 倍、整体压暗，位移幅度最大（远景）
##       中间层  地面投影 —— 贴住人物脚下，随呼吸缩放，人物才「站得住」
##       近景层  对局立绘 —— 位移只有背景的 ~30%，并做极缓的呼吸起伏
##     位移量按层递减 = 透视纵深。陀螺仪（移动端）与鼠标拖动共同驱动。
##     立绘角度始终不变（人物不歪），只有位置与极轻微的呼吸缩放 ——
##     这是「2.5D 立牌」而不是「纸片乱晃」的分界线。
## 再点一次已选中的头像 / 按 Esc / 点窗口右上角，收起海报。

signal start_game(cfg: Dictionary)
signal open_codex
signal open_room(cfg: Dictionary)

# ---------------- 角色格子（恒定 4 列） ----------------
## 【为什么不再是 224】224 的头像 + 名字条在 4 列下会顶满甚至溢出左栏，
## 相邻两列几乎贴在一起 —— 就是用户报的「头像太大、互相重叠」。
## 176 是实测「12 张一屏排得下、又看得清脸」的平衡点。
const FACE_GRID := 176.0
const TILE_PAD := 5.0          ## 金框内边距
const NAME_H := 24.0
const SUB_H := 18.0
const GAP_X := 18.0
const GAP_Y := 16.0
const COLS_GRID := 4
## 兼容旧调用（2 列方案已废弃，仅保留常量名以免外部引用报错）
const FACE_DETAIL := 176.0
const COLS_DETAIL := 4

## 背景放大倍率 —— 决定「背景能移动多远」。越大纵深越强，但背景被放得越糊。
const BG_ZOOM := 1.26
## 立绘（近景）位移 = 背景位移 × 这个比例。0 = 角色钉死（旧方案，像贴纸），
## 0.28 是实测「看得出人物和背景是两个空间，又不会晃得晕」的值。
const CHAR_PAR := 0.28
## 海报持有区高度：收起 / 展开两档（补间切换，右栏其余控件被平滑推开）
const PREVIEW_H_GRID := 250.0
const PREVIEW_H_DETAIL := 342.0

const MODE_GRID := 0
const MODE_DETAIL := 1

var sel_chara: String = "chara_小乔儿"
var player_count: int = 2
var ai_level: int = 2
var tutorial_on: bool = true

var _mode: int = MODE_GRID

var _scroll: ScrollContainer
var _board: Control
var _tiles: Dictionary = {}          ## id -> CharTile
var _order: Array = []               ## 显示顺序（id）
var _animating: bool = false
var _in_relayout: bool = false

var _info_box: VBoxContainer
var _name_lbl: Label
var _sub_lbl: Label

# ---- 9:16 预览 ----
var _preview_holder: Control
var _pv_win: Control
var _pv_bg: TextureRect
var _pv_shadow: TextureRect
var _pv_char: TextureRect
var _pv_vig: TextureRect
var _pv_frame: Panel
var _pv_close: Button
var _pv_paths: Dictionary = {}       ## 当前预览的 {bg, scene}，切人时比对，不变就不重设贴图

# ---- 视差状态 ----
var _t := 0.0
var _drag := Vector2.ZERO            ## 鼠标拖动累积（-1..1）
var _gyro := Vector2.ZERO            ## 陀螺仪积分（-1..1）
var _px := Vector2.ZERO              ## 平滑后的最终视差量
var _dragging := false


func _ready() -> void:
	_build()
	_refresh_all()
	_apply_tiles(false)


# ==================================================================== 布局
func _build() -> void:
	add_child(UITheme.bg_rect("bg_hall", 0.10))

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 26
	root.offset_right = -26
	root.offset_top = 12
	root.offset_bottom = -12
	add_child(root)

	# ---- 标题栏 ----
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	root.add_child(head)
	var emblem := TextureRect.new()
	emblem.texture = UITheme.ui_tex("emblem")
	emblem.custom_minimum_size = Vector2(62, 62)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(emblem)
	var tl := VBoxContainer.new()
	tl.add_theme_constant_override("separation", 0)
	var t1 := UITheme.mk_label("摄  伏", 44, UITheme.GOLD, true)
	t1.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.0, 0.9))
	t1.add_theme_constant_override("outline_size", 7)
	t1.add_theme_color_override("font_shadow_color", Color(0.9, 0.7, 0.3, 0.4))
	t1.add_theme_constant_override("shadow_offset_x", 0)
	t1.add_theme_constant_override("shadow_offset_y", 3)
	tl.add_child(t1)
	var t2 := UITheme.mk_label("天 · 地 · 人  三才制衡 ｜ 纯回合制卡牌对战", 14, UITheme.TEXT_DIM)
	tl.add_child(t2)
	head.add_child(tl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)

	var codex_btn := UITheme.mk_button("卡牌图鉴", 16)
	codex_btn.pressed.connect(func(): open_codex.emit())
	head.add_child(codex_btn)

	var tut := CheckButton.new()
	tut.text = "新手提示"
	tut.button_pressed = tutorial_on
	tut.toggled.connect(func(v):
		tutorial_on = v
		Sfx.play("ui_toggle", -10.0))
	UITheme.attach_ui_sfx(tut)
	head.add_child(tut)

	# 设置入口（全屏 / 窗口化 / 音量 / 表现开关）—— 大厅与对局各有一个，面板是同一个
	var set_btn := UITheme.mk_icon_button("gear", "设置：全屏 · 窗口化 · 音量 · 表现", 40)
	set_btn.pressed.connect(func(): SettingsPanel.open(self))
	head.add_child(set_btn)

	# ---- 主体：左（角色网格） 右（预览 + 信息 + 设置） ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# ================= 左：角色网格 =================
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel",
		UITheme.frost_style(Color(0.070, 0.054, 0.105, 0.90), Color(0.91, 0.76, 0.42, 0.30), 14, 1, 0.0))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var lv := UITheme.mk_vbox(8)
	left.add_child(lv)
	lv.add_child(_section_title("选择角色", ""))

	# 【为什么走 ScrollContainer + 手摆位置，而不是 GridContainer】
	# 4 列 ↔ 2 列要「丝滑」——GridContainer 换列数是瞬间重排，补不出动画；
	# 所以格子由 _apply_tiles() 逐帧摆位。滚动条只留纵向，避免横向滚动条挤宽度。
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.connect("resized", _on_layout_resized)
	lv.add_child(_scroll)

	# 【必须给 SIZE_EXPAND_FILL】ScrollContainer 只有在子节点带 EXPAND 标志时才会
	# 把它撑到视口尺寸；否则宽度直接取子节点的最小宽度 —— 而网格板的最小宽度是 0，
	# 于是整块板被压成 0 宽，格子全被裁掉（实测踩到）。
	_board = Control.new()
	_board.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.connect("resized", _on_layout_resized)
	_scroll.add_child(_board)

	for c in CardDB.characters:
		var tile := CharTile.new()
		tile.chara = c
		tile.name = str(c["id"])
		tile.tooltip_text = "%s · %s\n%s" % [c["name"], c.get("title", ""), c.get("identity", "")]
		tile.name_lbl.text = str(c["name"])
		tile.sub_lbl.text = str(c.get("title", ""))
		tile.art.texture = CardView.texture_for(c.get("face", c.get("art", "")))
		tile.pressed.connect(_on_tile_pressed.bind(c))
		tile.mouse_entered.connect(func(): Sfx.hover())
		_board.add_child(tile)
		_tiles[c["id"]] = tile
		_order.append(c["id"])
		if CardView.effects_enabled:
			tile.modulate.a = 0.0
			var tw := tile.create_tween()
			tw.tween_interval(len(_order) * 0.035)
			tw.tween_property(tile, "modulate:a", 1.0, 0.24)

	# ================= 右：预览 + 信息 + 设置 =================
	# 【为什么用 Panel 而不是 PanelContainer】要在同一块底板上叠三层（暗纹 / 顶部金晕 / 内容）。
	var right := Panel.new()
	right.add_theme_stylebox_override("panel",
		UITheme.frost_style(Color(0.062, 0.046, 0.098, 0.94), Color(0.91, 0.76, 0.42, 0.55), 16, 1, 22.0))
	right.custom_minimum_size = Vector2(500, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	var motif := UITheme.motif_overlay()
	motif.set_anchors_preset(Control.PRESET_FULL_RECT)
	right.add_child(motif)
	var gloss := Panel.new()
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gloss.set_anchors_preset(Control.PRESET_TOP_WIDE)
	gloss.offset_top = 2
	gloss.offset_bottom = 4
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.91, 0.76, 0.42, 0.42)
	gloss.add_theme_stylebox_override("panel", gs)
	right.add_child(gloss)

	var rv := UITheme.mk_vbox(10)
	rv.set_anchors_preset(Control.PRESET_FULL_RECT)
	rv.offset_left = 22
	rv.offset_right = -22
	rv.offset_top = 16
	rv.offset_bottom = -16
	right.add_child(rv)

	_build_preview(rv)

	# ---- 角色名 + 称号 ----
	var nv := UITheme.mk_vbox(2)
	rv.add_child(nv)
	_name_lbl = UITheme.mk_label("", 25, UITheme.GOLD, true)
	nv.add_child(_name_lbl)
	_sub_lbl = UITheme.mk_label("", 13, UITheme.TEXT_DIM)
	nv.add_child(_sub_lbl)

	# ---- 技能描述（可滚动） ----
	var info_frame := PanelContainer.new()
	info_frame.add_theme_stylebox_override("panel",
		UITheme.frost_style(Color(0.045, 0.034, 0.070, 0.85), Color(0.91, 0.76, 0.42, 0.22), 10, 1, 0.0))
	info_frame.size_flags_vertical = Control.SIZE_FILL
	rv.add_child(info_frame)
	var info_scr := ScrollContainer.new()
	info_scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_scr.custom_minimum_size = Vector2(0, 172)
	info_frame.add_child(info_scr)
	_info_box = UITheme.mk_vbox(8)
	_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scr.add_child(_info_box)

	# ---- 人数 ----
	var setrow := UITheme.mk_hbox(14)
	rv.add_child(setrow)
	setrow.add_child(UITheme.mk_label("人数", 15, Color(0.91, 0.84, 0.66)))
	var pc := OptionButton.new()
	pc.add_item("2 人", 0)
	pc.add_item("3 人", 1)
	pc.add_item("4 人", 2)
	pc.selected = 0
	pc.item_selected.connect(func(i):
		player_count = 2 + i
		Sfx.play("ui_click", -10.0))
	UITheme.style_option_button(pc, 42.0)
	UITheme.attach_ui_sfx(pc)
	setrow.add_child(pc)

	# ---- 底部按钮组 ----
	var act := UITheme.mk_hbox(12)
	rv.add_child(act)
	var match_btn := UITheme.mk_cta_button("开始匹配", 24, 62.0)
	match_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match_btn.size_flags_stretch_ratio = 1.6
	match_btn.pressed.connect(func(): _start_match())
	act.add_child(match_btn)
	var room_btn := UITheme.mk_ghost_button("开房间", 18, 62.0)
	room_btn.pressed.connect(_open_room)
	act.add_child(room_btn)


# ------------------------------------------------------------------ 9:16 预览
func _build_preview(parent: Control) -> void:
	# 【为什么常驻而不是点开才出现】右侧面板剩余高度全部给预览，
	# 若浏览态把预览藏起来，技能框会被拉成一整块「有框没字」的空面板（像 bug）。
	# 所以预览一直可见：浏览态小一点，聚焦态长大 + 播一次「展开」动画。
	_preview_holder = Control.new()
	_preview_holder.clip_contents = false
	_preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_holder.size_flags_stretch_ratio = 5.0
	_preview_holder.custom_minimum_size = Vector2(0, PREVIEW_H_GRID)
	_preview_holder.connect("resized", _fit_preview)
	parent.add_child(_preview_holder)

	# 窗口本体：严格 9:16，内容裁剪在这块矩形里
	_pv_win = Control.new()
	_pv_win.name = "PreviewWin"
	_pv_win.clip_contents = true
	_pv_win.mouse_filter = Control.MOUSE_FILTER_STOP
	_pv_win.connect("resized", _on_pv_win_resized)
	_pv_win.gui_input.connect(_on_pv_input)
	_preview_holder.add_child(_pv_win)

	# 最远层：背景。放大 BG_ZOOM 倍留出视差余量（永远不露边）。
	# 【为什么不压暗、不偏色】旧版这里挂了 Color(0.80, 0.84, 0.94) 当「大气透视」，
	# 结果整张背景被压掉两成亮度还发蓝，用户反馈「不打光了反而更暗了」。
	# 纵深不靠压暗背景表达 —— 靠的是「位移量的差」和脚下投影，背景保持原色即可，
	# 这样明暗才均匀。
	_pv_bg = TextureRect.new()
	_pv_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pv_bg.modulate = Color.WHITE
	_pv_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_win.add_child(_pv_bg)

	# 中层：地面投影。人物脚下的一枚椭圆暗影，随呼吸缩放 ——
	# 【为什么必须要】没有它，人物就是「贴」在背景上的一张贴纸；
	# 有了它，人物才「落」在某个平面上，伪 3D 的纵深立刻成立。
	_pv_shadow = TextureRect.new()
	_pv_shadow.texture = _radial_tex(Color(0.02, 0.01, 0.04, 0.52), Color(0.02, 0.01, 0.04, 0.0))
	_pv_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_pv_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_win.add_child(_pv_shadow)

	# 近景：对局立绘。只做「小幅度位移 + 极缓呼吸」，角度永不改变。
	_pv_char = TextureRect.new()
	_pv_char.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv_char.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pv_char.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_win.add_child(_pv_char)

	# 【扫光已删除】旧版这里有一层 ADD 混合的径向扫光，跟着拖拽反向跑。
	# 用户反馈「莫名其妙的光效曝光」—— 那种叠加光在静态海报上是对的，
	# 但放在角色立绘上只会把人脸冲白、塑料感很重。海报的纵深现在完全由
	# 「位移量的差」（背景满幅 / 立绘 28%）和地面投影表达，不靠加光。

	# 暗角：把注意力收回人物身上，同时压掉背景四角的杂色。
	# 幅度收得极小（0.18）—— 它只该是「边缘略沉一点」，不该是一圈黑晕。
	# （旧值 0.42 与背景压暗叠加，整块海报就是「发暗」，用户已否。）
	_pv_vig = TextureRect.new()
	_pv_vig.texture = _radial_tex(Color(0, 0, 0, 0.0), Color(0.02, 0.01, 0.04, 0.18))
	_pv_vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv_vig.stretch_mode = TextureRect.STRETCH_SCALE
	_pv_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_win.add_child(_pv_vig)

	# 金框
	_pv_frame = Panel.new()
	_pv_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_frame.add_theme_stylebox_override("panel",
		UITheme.frost_style(Color(0, 0, 0, 0), Color(0.91, 0.76, 0.42, 0.75), 10, 2, 0.0))
	_pv_win.add_child(_pv_frame)

	# 收起按钮（浮在右上角，只在聚焦态出现）
	_pv_close = UITheme.mk_icon_button("exit", "返回浏览（或按 Esc）", 34.0)
	_pv_close.pressed.connect(func(): _set_mode(MODE_GRID))
	_pv_close.visible = false
	_pv_win.add_child(_pv_close)


## 生成一张径向渐变贴图（fill_from = 亮心，fill_to = 暗边）
func _radial_tex(inner: Color, outer: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([inner, inner.lerp(outer, 0.35), outer])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.42)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## 把 9:16 窗口摆进持有区（取能放下的最大 9:16 矩形，居中）
func _fit_preview() -> void:
	if _pv_win == null or _preview_holder == null:
		return
	var a := _preview_holder.size
	if a.x < 24.0 or a.y < 24.0:
		return
	var h := a.y
	var w := h * 9.0 / 16.0
	if w > a.x:
		w = a.x
		h = w * 16.0 / 9.0
	_pv_win.position = Vector2((a.x - w) * 0.5, (a.y - h) * 0.5)
	_pv_win.size = Vector2(w, h)


func _on_pv_win_resized() -> void:
	if _pv_win == null:
		return
	var s := _pv_win.size
	# 缩放动画的轴心必须跟着窗口尺寸走 —— 展开动画期间窗口还在长大，
	# 用旧尺寸算出的轴心会让「弹开」的方向歪掉。
	_pv_win.pivot_offset = s * 0.5
	# 立绘的缩放轴心固定在**脚底中线**：呼吸时人往上「长」，脚不位移，
	# 用默认（左上角）轴心会让人整个人从左上角膨胀开，像被吹气。
	_pv_char.pivot_offset = Vector2(s.x * 0.5, s.y)
	_pv_vig.position = Vector2.ZERO
	_pv_vig.size = s
	_pv_frame.position = Vector2.ZERO
	_pv_frame.size = s
	if _pv_close != null:
		var d := _pv_close.custom_minimum_size.x
		_pv_close.position = Vector2(s.x - d - 8.0, 8.0)
		_pv_close.size = Vector2(d, d)
	_apply_parallax()


# ------------------------------------------------------------------ 视差
func _process(delta: float) -> void:
	if _pv_win == null or not _pv_win.visible or _pv_win.size.x < 8.0:
		return
	_t += delta
	# 空闲微漂：没有输入时背景也在「呼吸」，不至于是一张贴图
	var idle := Vector2(sin(_t * 0.42) * 0.16, cos(_t * 0.31) * 0.10)
	# 陀螺仪（移动端）：角速度积分成倾斜量，停手后缓慢回中。
	# 桌面端 get_gyroscope() 恒为 0，这条分支等于不存在，靠鼠标拖动驱动。
	# 注意它返回的是 Vector3（角速度），不是 Vector2。
	var g := Vector3.ZERO
	if CardView.gyro_enabled:
		g = Input.get_gyroscope()
	if g.length() > 0.0001:
		_gyro = (_gyro + Vector2(g.y, -g.x) * delta * 2.2).limit_length(1.0)
	else:
		_gyro = _gyro.lerp(Vector2.ZERO, clampf(delta * 1.6, 0.0, 1.0))
	var target := (_drag + _gyro + idle).limit_length(1.15)
	_px = _px.lerp(target, clampf(delta * 7.0, 0.0, 1.0))
	_apply_parallax()


## 分层视差（伪 3D 的核心）：
##   背景位移 = 满幅（远景）；立绘位移 = 满幅 × CHAR_PAR（近景）。
##   位移量的差 = 视差量 = 大脑读出的「距离」。这就是 2.5D 立牌的全部秘密。
func _apply_parallax() -> void:
	var s := _pv_win.size
	if s.x < 8.0:
		return
	var amp := Vector2(s.x, s.y) * (BG_ZOOM - 1.0) * 0.5 * 0.92
	var off := Vector2(_px.x * amp.x, _px.y * amp.y)

	# ---- 远景：背景 ----
	_pv_bg.size = s * BG_ZOOM
	_pv_bg.position = -s * (BG_ZOOM - 1.0) * 0.5 + off

	# ---- 近景：立绘（角度恒定，只有轻微位移 + 呼吸） ----
	# 呼吸 ~0.55Hz、0.7% 缩放，轴心在脚底：读起来是「重心微微起伏」，
	# 而不是「整张图在飘」。幅度再大就不是站着了，是在喘。
	var br := sin(_t * 1.05)
	var cs := 1.0 + br * 0.007
	_pv_char.size = s
	_pv_char.pivot_offset = Vector2(s.x * 0.5, s.y)
	_pv_char.scale = Vector2(cs, cs)
	_pv_char.position = off * CHAR_PAR + Vector2(0.0, br * s.y * 0.0022)

	# ---- 地面投影：人物微抬时影子收小变淡（唯一让人「落地」的东西） ----
	var sw := s.x * 0.46 * (1.0 - br * 0.05)
	var sh := s.y * 0.082 * (1.0 - br * 0.05)
	_pv_shadow.size = Vector2(sw, sh)
	_pv_shadow.position = Vector2((s.x - sw) * 0.5 + off.x * CHAR_PAR,
		s.y - sh * 0.70 + off.y * CHAR_PAR)
	_pv_shadow.modulate.a = 0.88 - br * 0.10


## 拖动 = 视差输入。往哪边拖，背景就往哪边走（并带一点阻尼感）
func _on_pv_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_pv_win.mouse_default_cursor_shape = Control.CURSOR_DRAG if mb.pressed else Control.CURSOR_POINTING_HAND
	elif ev is InputEventMouseMotion and _dragging:
		_drag = (_drag + (ev as InputEventMouseMotion).relative * 0.005).limit_length(1.0)


# ==================================================================== 布局重排
func _on_layout_resized() -> void:
	if _animating or _in_relayout:
		return
	_in_relayout = true
	_apply_tiles(false)
	_in_relayout = false


## 摆放所有格子。**列数恒定 4**，所以 mode 与排布无关 ——
## 唯一让布局变化的是窗口尺寸（resize）与角色数量，两者都会走 _on_layout_resized。
func _apply_tiles(animate: bool) -> void:
	if _board == null or _scroll == null:
		return
	var cols := COLS_GRID
	var face := FACE_GRID
	var tw := face + TILE_PAD * 2.0
	var th := tw + NAME_H + SUB_H + 8.0
	var n := _order.size()
	if n == 0:
		return
	var rows := int(ceil(float(n) / float(cols)))
	var grid_w := cols * tw + (cols - 1) * GAP_X
	var grid_h := rows * th + (rows - 1) * GAP_Y
	# 视口尺寸（预留 ~16px 给可能出现的纵向滚动条，避免算出来的居中量左右抖）
	var vw := maxf(_scroll.size.x - 16.0, 200.0)
	var vh := maxf(_scroll.size.y, 200.0)
	_board.custom_minimum_size = Vector2(0, grid_h)
	var bx := maxf(0.0, (vw - grid_w) * 0.5)
	var by := maxf(0.0, (vh - grid_h) * 0.5)

	_animating = animate
	for i in n:
		var tile: CharTile = _tiles[_order[i]]
		var r := i / cols
		var c := i % cols
		var to := Vector2(bx + float(c) * (tw + GAP_X), by + float(r) * (th + GAP_Y))
		var ts := Vector2(tw, th)
		tile.pivot_offset = ts * 0.5
		if animate and CardView.effects_enabled:
			var t := tile.create_tween()
			t.set_parallel(true)
			t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			t.tween_property(tile, "position", to, 0.40).set_delay(float(i) * 0.012)
			t.tween_property(tile, "size", ts, 0.40).set_delay(float(i) * 0.012)
		else:
			tile.position = to
			tile.size = ts
	if CardView.effects_enabled and animate:
		await get_tree().create_timer(0.55).timeout
	_animating = false
	# 聚焦态列表比视口长，滚到当前选中那张
	if _mode == MODE_DETAIL:
		var sel: CharTile = _tiles.get(sel_chara, null)
		if sel != null:
			_scroll.ensure_control_visible(sel)


func _set_mode(m: int) -> void:
	if _mode == m:
		return
	_mode = m
	# 【格子不重排】列数恒定 4，位置与尺寸都不变 —— 展开的只有右侧海报。
	# （旧版这里会调 _apply_tiles(true) 做 4 列→2 列的重排，用户已否掉该设计。）
	var target_h := PREVIEW_H_DETAIL if m == MODE_DETAIL else PREVIEW_H_GRID
	# 海报持有区的高度用**补间 custom_minimum_size** 来改（而不是直接改 offset）：
	# 容器只认最小尺寸，于是右栏其余控件是被平滑推开的，不会「啪」地跳一下。
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_preview_holder, "custom_minimum_size:y", target_h, 0.34)
	_pv_close.visible = m == MODE_DETAIL
	if m == MODE_DETAIL:
		_pv_win.pivot_offset = _pv_win.size * 0.5
		_pv_win.scale = Vector2(0.88, 0.88)
		_pv_win.modulate.a = 0.0
		tw.tween_property(_pv_win, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK)
		tw.tween_property(_pv_win, "modulate:a", 1.0, 0.28)
		Sfx.play("ui_open", -6.0)
	else:
		Sfx.play("ui_close", -8.0)


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == KEY_ESCAPE and _mode == MODE_DETAIL:
		_set_mode(MODE_GRID)
		get_viewport().set_input_as_handled()


# ==================================================================== 角色格子
## 单个角色格子：金框 + 方形头像 + 名字 + 称号。
## 【为什么自绘而不是塞进 GridContainer】见 _build 里的说明：换列数要能补间。
class CharTile extends Button:
	var frame: Panel
	var art: TextureRect
	var name_lbl: Label
	var sub_lbl: Label
	var chara: Dictionary = {}

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_filter = Control.MOUSE_FILTER_STOP
		# 头像框（选中时由 HallScreen._refresh_all 换成金色发光样式）
		frame = Panel.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)
		art = TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(art)
		name_lbl = UITheme.mk_label("", 18, UITheme.TEXT, true)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_lbl)
		sub_lbl = UITheme.mk_label("", 12, UITheme.TEXT_DIM)
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sub_lbl)
		resized.connect(_relayout)

	func _relayout() -> void:
		var w := size.x
		if w < 8.0:
			return
		var pad := HallScreen.TILE_PAD
		frame.position = Vector2.ZERO
		frame.size = Vector2(w, w)
		art.position = Vector2(pad, pad)
		art.size = Vector2(w - pad * 2.0, w - pad * 2.0)
		name_lbl.position = Vector2(0, w + 1.0)
		name_lbl.size = Vector2(w, HallScreen.NAME_H)
		sub_lbl.position = Vector2(0, w + HallScreen.NAME_H - 2.0)
		sub_lbl.size = Vector2(w, HallScreen.SUB_H)


func _section_title(main: String, sub: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(UITheme.mk_label(main, 19, UITheme.GOLD))
	if sub != "":
		h.add_child(UITheme.mk_label(sub, 13, UITheme.TEXT_DIM))
	return h


# ==================================================================== 交互
func _on_tile_pressed(c: Dictionary) -> void:
	var id := str(c["id"])
	# 已在聚焦态点同一张 → 收起预览，回到 4 列浏览
	if id == sel_chara and _mode == MODE_DETAIL:
		_set_mode(MODE_GRID)
		_refresh_all()
		return
	var entering := _mode == MODE_GRID
	sel_chara = id
	if not entering:
		Sfx.play("ui_select", -8.0)
	_set_mode(MODE_DETAIL)
	_refresh_all()


func _refresh_all() -> void:
	var c: Dictionary = CardDB.get_chara(sel_chara)
	for k in _tiles.keys():
		var tile: CharTile = _tiles[k]
		var sel: bool = (k == sel_chara)
		if sel:
			tile.frame.add_theme_stylebox_override("panel", UITheme.selected_tile_style(10))
			tile.name_lbl.add_theme_color_override("font_color", UITheme.GOLD)
			tile.sub_lbl.add_theme_color_override("font_color", Color(0.91, 0.84, 0.66))
			tile.z_index = 2
		else:
			tile.frame.add_theme_stylebox_override("panel",
				UITheme.frost_style(Color(0.09, 0.07, 0.13, 0.95), Color(0.91, 0.76, 0.42, 0.22), 10, 1, 0.0))
			tile.name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
			tile.sub_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
			tile.z_index = 0

	_name_lbl.text = str(c.get("name", ""))
	_sub_lbl.text = str(c.get("title", ""))
	_refresh_preview(c)

	for ch in _info_box.get_children():
		ch.queue_free()
	# ---- 文本层级：标签浅金 / 被动浅灰 / 主动青蓝，字重区分明确 ----
	_info_box.add_child(_tag_row(c))
	var sk: Dictionary = c.get("skill", {})
	_info_box.add_child(UITheme.mk_label("主动 · %s" % sk.get("name", ""), 16, Color(0.42, 0.74, 0.92), true))
	_info_box.add_child(UITheme.mk_label("冷却 %d 回合" % int(sk.get("cd", 0)), 12, Color(0.91, 0.84, 0.66)))
	var d1 := UITheme.mk_label(sk.get("desc", ""), 15, UITheme.TEXT)
	d1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d1.custom_minimum_size = Vector2(400, 0)
	d1.add_theme_constant_override("line_spacing", 6)
	_info_box.add_child(d1)
	if c.get("passive", null) != null:
		_info_box.add_child(UITheme.mk_label("被动 · %s" % c["passive"]["name"], 15,
			Color(0.68, 0.65, 0.72), true))
		var d2 := UITheme.mk_label(c["passive"]["desc"], 14, Color(0.70, 0.68, 0.74))
		d2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d2.custom_minimum_size = Vector2(400, 0)
		d2.add_theme_constant_override("line_spacing", 5)
		_info_box.add_child(d2)


## 换人时刷新 9:16 预览。贴图路径不变就不重设 —— 避免同一个人被点两次时重新解码。
func _refresh_preview(c: Dictionary) -> void:
	var bg_path := str(c.get("bg", ""))
	var sc_path := str(c.get("scene", c.get("art", "")))
	if str(_pv_paths.get("bg", "\u0000")) != bg_path:
		_pv_paths["bg"] = bg_path
		_pv_bg.texture = CardView.texture_for(bg_path)
	if str(_pv_paths.get("scene", "\u0000")) != sc_path:
		_pv_paths["scene"] = sc_path
		_pv_char.texture = CardView.texture_for(sc_path)
	if CardView.effects_enabled:
		# 换人时立绘淡入一档，让「换人」这件事有反馈（角度始终不变）
		_pv_char.modulate.a = 0.0
		var tw := _pv_char.create_tween()
		tw.tween_property(_pv_char, "modulate:a", 1.0, 0.26)


## 标签行：推荐【人】/ 阵营 这类短标签统一走「浅金」色
func _tag_row(c: Dictionary) -> Control:
	var h := UITheme.mk_hbox(8)
	var items := [
		"推荐【%s】" % c.get("renCard", ""),
		"阵营 · %s" % c.get("identity", ""),
	]
	for i in items:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel",
			UITheme.frost_style(Color(0.91, 0.76, 0.42, 0.10), Color(0.91, 0.76, 0.42, 0.35), 8, 1, 0.0))
		var s := p.get_theme_stylebox("panel") as StyleBoxFlat
		s.content_margin_left = 9
		s.content_margin_right = 9
		s.content_margin_top = 2
		s.content_margin_bottom = 2
		p.add_child(UITheme.mk_label(i, 12, Color(0.92, 0.86, 0.68)))
		h.add_child(p)
	return h


# ==================================================================== 开始
func _cfg() -> Dictionary:
	return {
		"chara_id": sel_chara,
		"player_count": player_count,
		"ai_level": ai_level,
		"tutorial": tutorial_on,
	}


## 匹配：直接进入对局，开场在局内选【人】
func _start_match() -> void:
	Sfx.play("ui_confirm", -3.0)
	start_game.emit(_cfg())


## 开房间：进入房间界面，不直接开局
func _open_room() -> void:
	Sfx.play("ui_confirm", -5.0)
	open_room.emit(_cfg())
