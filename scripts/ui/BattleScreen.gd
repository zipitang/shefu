class_name BattleScreen
extends Control
## 战斗界面 —— KARDS 式简洁布局
## ------------------------------------------------------------------
## 顶部：敌方【人】大本营（人卡 + 气条 + 手牌背面），点击设定主目标
## 中部：敌方场面 / 我方场面（场上卡带 祇/点数 徽标 + 主动技能图标 + 冷却转圈）
## 底部：左下【人】升级 + 资源池；中央扇形手牌；右下结束回合
## 右缘：图标操作坞（拜神/敬鬼为回合冷却制卡牌按钮），悬停出文字介绍
## 战报：右缘卷轴图标开启的半透明弹缩面板

signal exit_to_hall
signal rematch(cfg: Dictionary)

const BOARD_W := 132.0
const BOARD_H := 232.0
const HAND_W := 158.0
const HAND_H := 272.0
const DRAFT_W := 152.0
const DRAFT_H := 271.0
## 对手大本营【人】卡尺寸（9:16）——也是对手手牌背面的「横向对齐基线」
const CAMP_CARD_W := 62.0
const CAMP_CARD_H := 110.0
## 对手角色立绘：与【人】卡一样取**半身**（原图顶 50%，720×640 ≈ 9:8），并「稍大一点」。
## 旧版直接塞 62×110 全身 → 人物小、看不清脸；现在 96×86（≈9:8）配合 bust_tex() 只取上半身，
## 头像明显更大、五官清晰。SHRINK_CENTER 垂直居中，行高仍由【人】卡 (110) 决定，不撑高整排。
const CAMP_BUST_W := 96.0
const CAMP_BUST_H := 86.0
## 拜神 / 敬鬼专属卡牌尺寸（9:16）
const WORSHIP_W := 76.0
const WORSHIP_H := 135.0
## ==================== 我方大本营（左下角固定面板） ====================
## 【★ 布局原则：固定区域 + 绝对定位】用户明确要求「位置相互固定、不要脱出这个区域」。
## 流式容器（HBox/VBox）做不到这一点 —— 它的宽度由内容决定：资源池数字从 "0" 变到 "150"、
## 名称从「你 · 东」变成「你 · 东 · 小乔儿」，整块就会被推着走，卡片位置跟着漂。
## 所以这里区域尺寸写死，内部每个元素给固定坐标，数字再怎么变都不挪动一格。
const MY_CAMP_W := 600.0
## 区域高 = 底部行高（HAND_H + 12）。立绘按这个高度取，正好从底边顶到顶边。
const MY_CAMP_H := HAND_H + 12.0
## 底板内边距（立绘左缘距底板左缘）
const CAMP_PAD := 10.0

## 半身立绘：原图**上半边**，按用户指定的 1.5 倍放大（210×187 → 315×281）。
## 比例仍是原图比例（720×640 ≈ 1.125），配合 KEEP_ASPECT_CENTERED 不拉伸、不二次裁边。
const MY_BUST_W := 315.0
const MY_BUST_H := 281.0
## 立绘底边距底板底边的距离（贴底：硬裁切线被底板下边缘吃掉，不会在画面中间横一道）
const BUST_BOTTOM := 2.0
## 人卡咬住立绘右侧的宽度。旧版立绘 210 时是 46（≈22%），放大 1.5 倍后同步为 69，
## 卡片咬住立绘的比例保持不变 —— 人脸仍然完整露在卡片左侧。
const MY_BUST_OVERLAP := 69.0

## 我方【人】卡尺寸（9:16）
const MY_CARD_W := 78.0
const MY_CARD_H := 138.0
## 卡底距底板底边的距离
const CARD_BOTTOM := 2.0
## 【人】卡的半透明黑底框：比卡片每边各外扩这么多（太窄就看不出是「底框」）
const MY_CARD_FRAME := 12.0

## 信息列：卡片右缘 → 信息列左缘
const INFO_GAP := 14.0
## 信息列右缘 → 底板右缘
const INFO_RIGHT := 12.0

var gs: GameState
var human: PlayerState
var cfg: Dictionary = {}
var busy: bool = false
var tutorial: bool = false

var selected_hand: CCard = null
var selected_unit: CCard = null
## 正在拖拽的「指向性道具」。拖拽期间用它驱动：直线瞄准线 / 目标高亮 / 中央判词。
## 旧版的 `targeting`（"vajra" 那种先点按钮再点目标的模式）已经不需要了 ——
## 道具现在就是一张手牌，按下即瞄、松手即放。
var _aim_card: CCard = null
var _aim_from := Vector2.ZERO        ## 瞄准线起点（手牌中心，全局坐标）
var _aim_pos := Vector2.ZERO         ## 瞄准线终点（鼠标，全局坐标）
var _aim_target_uid: int = -1        ## itemTarget=="unit" 时锁定的场上卡
var _aim_target_pid: int = -1        ## itemTarget=="player" 时锁定的玩家
var _aim_reason: String = ""         ## 判词：空串=可放，非空=不可放的原因
var _aim_label: String = ""
var _aim_line: Control               ## 画在拖拽层上的瞄准线

# ---- 节点 ----
var top_round: Label
var top_turn: Label
var enemy_area: HBoxContainer      ## 敌方区：N 列（3人局左上/右上，4人局左上/正中/右上），每列=大本营+该玩家的场面
var my_board_row: HFlowContainer   ## 我方场面（卡多自动换行）
var hand_area: Control              ## 扇形手牌区
var draft_bar: PanelContainer
var draft_row: HBoxContainer
var draft_hint: Label
var log_panel: PanelContainer
var log_box: VBoxContainer
var log_scroll: ScrollContainer
var hint_bar: Label
var banner: Label
var modal_layer: Control
var button_refs: Dictionary = {}
var res_pills: Dictionary = {}
var _camp_by_pid: Dictionary = {}   ## pid -> 大本营控件（含我方）
var _board_flow_by_pid: Dictionary = {}  ## pid -> 该玩家的场面 FlowContainer（卡多自动换行）
var _camps_built := false           ## 敌方列只建一次（详见 _refresh_camps 内注释）
var _camp_refs: Dictionary = {}     ## pid -> 大本营各控件引用（原地更新用，见 _update_enemy_camp）
## 底部行两侧的控件（手牌居中靠左右等宽，宽度在 _sync_side_width 里按实测校正）
var _my_camp_box: Control
var _end_block: Control
var _side_syncing := false           ## _sync_side_width 重入守卫（避免多个协程互相过冲）
var _prev_cd: Dictionary = {}       ## uid -> 上次刷新时的剩余冷却（用于识别「冷却刚结束」）
var _worship_used_prev: bool = false
var _log_open := false
var _guide_shown: bool = false
var _guide_idx: int = 0
## 牌面是否被玩家「收起」了（**只是藏起来，不销毁**）。
## 【★ 为什么必须区分「收起」与「清空」】
##   规则层的 close_draft() 会把 current_draft 清空 —— 那是**回合结束**该做的事。
##   玩家按 ✕ 只是想把这叠牌先收起来，牌本回合内还是他的。旧写法两个语义共用
##   同一个函数，于是「收起 → 再点卡牌商店」时牌面已经没了，只能重摇一批，
##   而重摇就是刷新、就要计价。用户明确要求：卡牌商店只负责**打开那个窗口**，
##   不触发刷新、不消耗财。所以收起改为只翻一个 UI 开关，牌面数据原封不动。
var _draft_hidden := false
# ---- 测试训练场（Dev.enabled 时才创建） ----
var _dev_panel: Node = null

# ---- 特效层 / 视图索引 ----
var fx: FXLayer
var _world: Control
var _view_by_uid: Dictionary = {}
var _hand_seen: Dictionary = {}
var _draft_seen: Array = []
var _hand_cards: Array = []        ## 手牌 CardView 列表（与 hand 顺序一致，悬停邻卡推开用）
var _hover_hand_idx := -1          ## 当前悬停的手牌下标（-1 = 无）
var _hand_spread_tweens: Array = [] ## 邻卡推开 tween（每次刷新统一 kill，防堆积）

# ---- 拖拽上场 ----
var _drag_layer: Control
var _ghost: CardView = null
var _drag_valid := false

# ---- 开场选择（只选【人】大本营；命理系统已移除） ----
var _setup_layer: Control
var _setup_step := 0
var _setup_sel_ren: String = ""
var _setup_grid: GridContainer
var _setup_title: Label
var _setup_sub: Label
var _setup_confirm: Button
var _setup_random: Button

const GUIDE_STEPS: Array = [
	["① 三选一（每回合强制）",
	 "回合开始系统发 3 张牌，必须选 1 张。选之前可点【刷新】换一批 ——
第一次免费，之后依次 1 财、2 财、3 财；也可用 3【财】直接【购买】。
卡池里没有【人】牌，也不含四相与十二生肖。"],
	["② 起乩上场：点击手牌",
	 "点击扇形手牌里的一张卡 → 在弹出的操作条上点【↑】起乩上场。
上场后不可下场，但被动/主动技能才会生效，也可能被对方拔除。
记住：手牌安全，场上危险。"],
	["③ 攻击：选中 → 点目标",
	 "点己方场上【地】卡（选中发光）→ 再点【敌方大本营】= 袭人，直接扣对方【气】；
点己方【天】卡 → 再点对方场上一张【地】卡 = 直接消灭（天↔天则互相制衡）。
卡面右缘的【闪电图标】是主动技能，点击即发，冷却时带转圈。
每回合只有 2 次「主动行动」（袭人 + 主动技能共享）。"],
	["④ 【人】是命根 & 拜神敬鬼",
	 "左下角是你的大本营：点【人卡右上角的升级按钮】（可点时按钮外圈会金光呼吸），
每升一级 +【气】上限，同时加厚场上【天】的【祇】。
右缘两张牌是【拜神】【敬鬼】—— 每回合各一次，掷骰 1-6 点，随机请来对应数量的
天/地卡入手（不消耗，回合冷却制）。"],
	["⑤ 弃置 / 图标坞",
	 "右缘图标坞（悬停有说明）：卡牌商店、弃置换资源、角色专属技能、阴阳师召唤式神（千纸鹤）。
道具是**手牌**：拖到对方场上那张卡上（降魔杵「降」/ 金刚镢「封」），或拖入自己战场（三清铃 / 铜钱剑 / 八卦镜）。
卡牌阶数在卡池里就是固定的（图鉴看到的阶数即最终阶数），没有升阶路径。
右下【▶▶】结束回合。右缘【卷轴】可展开战报。"],
]


## 指向性道具的「直线瞄准线」。
## 【为什么不用 FXLayer 的 Beam】Beam 是一次性演出、到点自毁；
## 瞄准线要跟着鼠标逐帧重画，生命周期与拖拽绑定，且要能在「不可放」时整体转成朱红。
class AimLine extends Control:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var ok := true
	## 【为什么判词要贴在准星旁，而不是只放底部提示条】
	## 拖到目标上时，鼠标（和跟着鼠标的半透明幽灵卡）常常正好压在底部提示条上，
	## 「松手即释放」被盖掉 —— 而那正是玩家唯一需要看到它的一刻。
	## 判词必须出现在眼睛实际所在的位置：准星的右上角（幽灵卡是往右下偏的，不会打架）。
	var verdict: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		z_index = 249
		visible = false
		verdict = UITheme.mk_label("", 15, UITheme.GOLD, true)
		verdict.mouse_filter = Control.MOUSE_FILTER_IGNORE
		verdict.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.03, 0.95))
		verdict.add_theme_constant_override("outline_size", 6)
		verdict.visible = false
		add_child(verdict)

	## good=true 表示落点合法（金），false 给出不可放的原因（朱砂）
	func set_verdict(txt: String, good: bool) -> void:
		verdict.text = txt
		verdict.add_theme_color_override("font_color", UITheme.GOLD if good else UITheme.CINNABAR)
		verdict.visible = txt != ""

	func _process(_d: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		if from == Vector2.ZERO or to == Vector2.ZERO:
			return
		if from.distance_to(to) < 6.0:
			return
		var col: Color = UITheme.GOLD if ok else UITheme.CINNABAR
		var dir := (to - from).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		# 三段式：外层柔光 → 主体 → 内芯白线（读起来才像「一条有能量的直线」）
		draw_line(from, to, Color(col.r, col.g, col.b, 0.16), 11.0, true)
		draw_line(from, to, Color(col.r, col.g, col.b, 0.55), 3.6, true)
		draw_line(from, to, Color(1, 1, 1, 0.80), 1.1, true)
		# 起点短横：告诉玩家这条线是从哪张牌拉出来的
		draw_line(from - nrm * 10.0, from + nrm * 10.0, Color(col.r, col.g, col.b, 0.9), 2.6, true)
		# 末端准星：外圈呼吸 + 内圈十字
		var r := 10.0 + sin(Time.get_ticks_msec() * 0.006) * 2.0
		draw_arc(to, r, 0, TAU, 30, Color(col.r, col.g, col.b, 0.95), 2.2, true)
		draw_arc(to, r * 1.85, 0, TAU, 36, Color(col.r, col.g, col.b, 0.38), 1.2, true)
		draw_line(to - dir * (r + 9.0), to - dir * (r + 2.0), Color(col.r, col.g, col.b, 0.8), 1.8, true)
		draw_line(to + dir * (r + 2.0), to + dir * (r + 9.0), Color(col.r, col.g, col.b, 0.8), 1.8, true)
		draw_line(to - nrm * (r + 2.0), to - nrm * (r + 9.0), Color(col.r, col.g, col.b, 0.8), 1.8, true)
		draw_line(to + nrm * (r + 2.0), to + nrm * (r + 9.0), Color(col.r, col.g, col.b, 0.8), 1.8, true)


# ==================================================================== 启动
func start_battle(p_cfg: Dictionary) -> void:
	cfg = p_cfg
	tutorial = bool(p_cfg.get("tutorial", false))
	_build()
	await get_tree().process_frame
	# 截图 / 测试模式：跳过开场选择，用配置里的默认值直接开局
	if bool(p_cfg.get("auto_setup", false)):
		_begin_game(String(p_cfg.get("ren", "凡人")))
		return
	_show_setup(0)


## 真正开始对局：确定【人】后建 GameState
func _begin_game(ren_name: String) -> void:
	if _setup_layer != null:
		_setup_layer.visible = false
	if gs != null and is_instance_valid(gs):
		return
	gs = GameState.new()
	gs.name = "GameState"
	add_child(gs)
	var n: int = int(cfg.get("player_count", 2))
	var seats_data: Array = []
	seats_data.append({
		"chara_id": cfg.get("chara_id", "chara_小乔儿"),
		"ren": ren_name,
		"is_ai": false,
		"ai_level": 0,
		"name": "你",
	})
	var others := ["chara_马曜", "chara_青蘅", "chara_唐森", "chara_白樰", "chara_孟谢菲", "chara_楚伞"]
	var other_ren := ["凡人", "巫女", "法师", "萨满", "阴阳师"]
	for i in (n - 1):
		seats_data.append({
			"chara_id": others[i % others.size()],
			"ren": other_ren[i % other_ren.size()],
			"is_ai": true,
			"ai_level": int(cfg.get("ai_level", 2)),
			"name": "对手%d" % (i + 1),
		})
	# cfg.seed != 0 时对局完全可复现 —— 开发时截图对比 A/B 效果全靠它，
	# 否则每次随机发牌，两张截图根本没法逐像素比对。
	gs.setup(seats_data, int(cfg.get("seed", 0)))
	human = gs.players[0]
	gs.log_message.connect(_on_log)
	gs.game_over.connect(_on_game_over)
	gs.card_played.connect(_fx_card_played)
	gs.unit_removed.connect(_fx_unit_removed)
	gs.effect_fired.connect(_fx_effect)
	# 牌面被规则层重摇 → 解除「收起」状态（详见 _on_draft_opened 的注释）
	gs.draft_opened.connect(_on_draft_opened)

	_refresh()
	await get_tree().create_timer(0.35).timeout
	_driver()


# ==================================================================== 开场选择层
## 设计文档：对局开始先选【人】大本营（都挪到局内，不占大厅）
func _show_setup(step: int) -> void:
	_setup_step = step
	if not _setup_layer.visible:
		# 首次构建骨架
		for ch in _setup_layer.get_children():
			ch.queue_free()
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.015, 0.04, 0.88)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		_setup_layer.add_child(dim)
		# 用 CenterContainer 保证面板始终居中（直接给 PanelContainer 设 PRESET_CENTER
		# 会在内容填充前就锁定偏移，导致面板跑到右下角）
		var center := CenterContainer.new()
		center.name = "SetupCenter"
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_setup_layer.add_child(center)
		var pnl := UITheme.mk_panel(Color(0.07, 0.06, 0.11, 0.99), UITheme.GOLD)
		pnl.custom_minimum_size = Vector2(1180, 0)
		center.add_child(pnl)
		var v := UITheme.mk_vbox(10)
		pnl.add_child(v)
		_setup_title = UITheme.mk_label("", 32, UITheme.GOLD, true)
		v.add_child(_setup_title)
		_setup_sub = UITheme.mk_label("", 14, UITheme.TEXT_DIM)
		v.add_child(_setup_sub)
		v.add_child(UITheme.mk_divider(560, 14))
		var scr := ScrollContainer.new()
		scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scr.custom_minimum_size = Vector2(0, 400)
		scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(scr)
		_setup_grid = GridContainer.new()
		_setup_grid.add_theme_constant_override("h_separation", 10)
		_setup_grid.add_theme_constant_override("v_separation", 10)
		_setup_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scr.add_child(_setup_grid)
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 10)
		bar.alignment = BoxContainer.ALIGNMENT_END
		v.add_child(bar)
		_setup_random = UITheme.mk_button("随机决定", 17)
		_setup_random.pressed.connect(_on_setup_random)
		bar.add_child(_setup_random)
		_setup_confirm = UITheme.mk_gold_button("确定 ▶", 20)
		_setup_confirm.custom_minimum_size = Vector2(190, 50)
		_setup_confirm.pressed.connect(_on_setup_confirm)
		bar.add_child(_setup_confirm)
		_setup_layer.visible = true
		pnl.reset_size()
	else:
		_setup_layer.visible = true
	_build_setup_content()


func _build_setup_content() -> void:
	for ch in _setup_grid.get_children():
		ch.queue_free()
	_setup_title.text = "选择【人】大本营"
	_setup_sub.text = ""
	_setup_grid.columns = 6
	var idx := 0
	for r in CardDB.ren_cards:
		var cell := _make_setup_ren_tile(r)
		_setup_grid.add_child(cell)
		if CardView.effects_enabled:
			cell.modulate.a = 0.0
			cell.pivot_offset = cell.custom_minimum_size * 0.5
			cell.scale = Vector2(0.85, 0.85)
			var tw := cell.create_tween()
			tw.tween_interval(idx * 0.05)
			tw.set_parallel(true)
			tw.tween_property(cell, "modulate:a", 1.0, 0.22)
			tw.tween_property(cell, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
		idx += 1
	_refresh_setup_selection()
	Sfx.play("draw", -4.0)


func _make_setup_ren_tile(r: Dictionary) -> Control:
	var key := "ren_" + str(r["name"])
	var b := Button.new()
	b.name = key
	b.custom_minimum_size = Vector2(178, 322)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	b.add_child(v)
	var fr := PanelContainer.new()
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.custom_minimum_size = Vector2(172, 254)
	fr.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL_HI, UITheme.PANEL_LINE, 10))
	v.add_child(fr)
	var art := TextureRect.new()
	art.texture = CardView.texture_for(r.get("art", ""))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.custom_minimum_size = Vector2(164, 246)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.add_child(art)
	var nl := UITheme.mk_label(r["name"], 20, UITheme.GOLD, true)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var ql := UITheme.mk_label("起手【气】%d" % int(r.get("qi", 12)), 14, UITheme.QI)
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ql)
	var dl := UITheme.mk_label(str(r.get("note", "")), 11, UITheme.TEXT_DIM)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.custom_minimum_size = Vector2(170, 0)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dl)
	b.pressed.connect(func():
		_setup_sel_ren = str(r["name"])
		_refresh_setup_selection()
		Sfx.play("ui_click", -8.0))
	b.set_meta("tile_kind", "ren")
	b.set_meta("tile_key", str(r["name"]))
	b.set_meta("frame", fr)
	return b


func _refresh_setup_selection() -> void:
	for ch in _setup_grid.get_children():
		if not ch.has_meta("tile_kind"):
			continue
		var kind: String = str(ch.get_meta("tile_kind"))
		var key: String = str(ch.get_meta("tile_key"))
		var fr: PanelContainer = ch.get_meta("frame")
		var sel: bool = (kind == "ren" and key == _setup_sel_ren)
		fr.add_theme_stylebox_override("panel",
			UITheme.glow_style(UITheme.PANEL_HI, UITheme.GOLD if sel else UITheme.PANEL_LINE,
				10, 3 if sel else 1, 12.0 if sel else 0.0))
	var ok := not _setup_sel_ren.is_empty()
	_setup_confirm.text = "确定 ▶  开始对局" if ok else "请先选择【人】"
	_setup_confirm.disabled = not ok


func _on_setup_random() -> void:
	var rs: Array = CardDB.ren_cards
	_setup_sel_ren = str(rs[randi_range(0, rs.size() - 1)]["name"])
	_refresh_setup_selection()
	Sfx.play("dice", -6.0)


func _on_setup_confirm() -> void:
	if _setup_sel_ren.is_empty():
		return
	Sfx.play("turn", -3.0)
	_begin_game(_setup_sel_ren)


# ==================================================================== 构建界面
func _build() -> void:
	add_child(UITheme.bg_rect("bg_battle", 0.18))

	var main := VBoxContainer.new()
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.add_theme_constant_override("separation", 4)
	main.offset_left = 16
	main.offset_right = -16
	main.offset_top = 8
	main.offset_bottom = -8
	add_child(main)
	_world = main

	# ---------- 顶栏 ----------
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	main.add_child(th)
	var gear := UITheme.mk_icon_button("gear", "设置：全屏 · 窗口化 · 音量 · 表现", 34)
	gear.pressed.connect(func(): SettingsPanel.open(self))
	th.add_child(gear)
	# 测试训练场：仅在测试版 exe 里出现的两枚入口（正式版什么都不加）
	if Dev.enabled:
		_build_dev_entries(th)
	th.add_child(UITheme.mk_label("摄伏", 20, UITheme.GOLD, true))
	top_round = UITheme.mk_label("第 0 轮", 14, UITheme.TEXT_DIM)
	th.add_child(top_round)
	var sp0 := Control.new()
	sp0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp0)
	top_turn = UITheme.mk_label("", 17, UITheme.GOLD)
	th.add_child(top_turn)
	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp1)
	var logb := UITheme.mk_icon_button("scroll", "战报（展开 / 收起）", 34)
	logb.pressed.connect(_toggle_log)
	th.add_child(logb)
	button_refs["log_toggle"] = logb
	var help := UITheme.mk_icon_button("help", "新手引导", 34)
	help.pressed.connect(func(): _show_guide(0))
	th.add_child(help)
	var quit := UITheme.mk_icon_button("exit", "认输并返回大厅", 34)
	quit.pressed.connect(func():
		Sfx.play("ui_back", -5.0)
		exit_to_hall.emit())
	th.add_child(quit)

	# ---------- 敌方区（顶部，按座位对称分列） ----------
	# 【为什么不用一行 ScrollContainer】多人局打到后面场上卡一多，横向滚动条出现，
	# 内容从「居中」跳成「左对齐 + 可横向拖动」，整个画面就会左移/跳动 —— 正是用户报的 bug。
	# 改成 N 列（3 人局 2 列 = 左上/右上，4 人局 3 列 = 左上/正中/右上），每列内部用
	# HFlowContainer 让卡牌「太多就换行」，既不再横向溢出，也不会再有滚动重排。
	enemy_area = UITheme.mk_hbox(8)
	enemy_area.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_area.size_flags_stretch_ratio = 1.0
	enemy_area.custom_minimum_size = Vector2(0, 120)
	main.add_child(enemy_area)

	# ---------- 战场中线 ----------
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 10)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(mid)
	var l1 := HSeparator.new()
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.modulate = Color(1, 1, 1, 0.35)
	mid.add_child(l1)
	hint_bar = UITheme.mk_label("", 13, UITheme.GOLD_DIM)
	mid.add_child(hint_bar)
	var l2 := HSeparator.new()
	l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l2.modulate = Color(1, 1, 1, 0.35)
	mid.add_child(l2)

	# ---------- 我方场面 ----------
	# 【为什么不能用 CenterContainer 包 HFlowContainer】CenterContainer 永远把子控件
	# 压到**最小尺寸**——而 FlowContainer 的最小宽度只有一张卡（132px），
	# 结果整列卡竖着堆成 2152px 高、溢出屏幕，正是「画面布局漂移/放大」的元凶之一。
	# 改为 Flow 直接占满整行（EXPAND_FILL），横向居中交给 ALIGNMENT_CENTER 逐行居中。
	my_board_row = HFlowContainer.new()
	my_board_row.add_theme_constant_override("h_separation", 10)
	my_board_row.add_theme_constant_override("v_separation", 8)
	my_board_row.alignment = FlowContainer.ALIGNMENT_CENTER
	my_board_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_board_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	my_board_row.size_flags_stretch_ratio = 1.05
	main.add_child(my_board_row)

	# ---------- 底部：大本营 / 扇形手牌 / 结束回合 ----------
	# 【左右必须等宽，否则手牌一定偏】扇形手牌的中心 = 它左右两侧块的中点。
	# 旧版左边是大本营、右边只有一枚结束回合按钮，中点被推右 ≈ 140px ——
	# 这正是用户报的「自己手牌有点靠右」。
	# 【两侧不再靠常量对齐】大本营现在是固定 520 宽（立绘不再溢出区域，所以不需要
	# 左侧空档），但右块的宽度仍会在 _sync_side_width() 里按**实测**校正，
	# 保证任何情况下手牌区中点都等于屏幕中点。
	var side_w := MY_CAMP_W
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.custom_minimum_size = Vector2(0, HAND_H + 12)
	main.add_child(bottom)

	# 左下：我方大本营（固定尺寸面板）
	var me_camp := _make_my_camp()
	bottom.add_child(me_camp)
	_my_camp_box = me_camp

	# 中央：扇形手牌
	hand_area = Control.new()
	hand_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_area.clip_contents = false
	hand_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(hand_area)

	# 右下：结束回合（与左侧等宽 → 球权对称；按钮靠右缘）
	var end_wrap := VBoxContainer.new()
	end_wrap.alignment = BoxContainer.ALIGNMENT_END
	end_wrap.custom_minimum_size = Vector2(side_w, 0)
	bottom.add_child(end_wrap)
	_end_block = end_wrap
	var end_row := HBoxContainer.new()
	end_row.alignment = BoxContainer.ALIGNMENT_END
	end_wrap.add_child(end_row)
	var endbtn := UITheme.mk_icon_button("endturn", "结束回合（空格）", 68)
	endbtn.pressed.connect(_on_end_turn)
	end_row.add_child(endbtn)
	button_refs["end"] = endbtn

	# ---------- 右缘操作坞 ----------
	var dock := VBoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	dock.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	dock.offset_left = -96
	dock.offset_right = -14
	dock.offset_top = -320
	dock.offset_bottom = 320
	dock.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(dock)
	_make_dock(dock)

	# ---------- 设置弹层已并入 SettingsPanel（大厅 / 对局共用同一个面板） ----------
	# 旧版这里有个只有「陀螺仪 / 特效」两个勾的自制小弹窗；现在统一走
	# SettingsPanel.open(self)，多了全屏/窗口化切换、分辨率、音量，且会持久化。

	# ---------- 战报（半透明弹缩面板） ----------
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.04, 0.03, 0.07, 0.85), Color(1, 1, 1, 0.14), 12, 1, 10, 8))
	log_panel.anchor_left = 1.0
	log_panel.anchor_right = 1.0
	log_panel.offset_left = -360
	log_panel.offset_right = -8
	log_panel.offset_top = 52
	log_panel.offset_bottom = -12
	log_panel.visible = false
	log_panel.z_index = 50
	add_child(log_panel)
	var lv := UITheme.mk_vbox(4)
	log_panel.add_child(lv)
	lv.add_child(UITheme.mk_label("战 报", 14, UITheme.GOLD_DIM))
	log_scroll = ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(log_scroll)
	log_box = UITheme.mk_vbox(1)
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_box)

	# ---------- 三选一浮层 ----------
	draft_bar = UITheme.mk_panel(Color(0.07, 0.06, 0.11, 0.98), UITheme.GOLD_DIM)
	draft_bar.anchor_left = 0.5
	draft_bar.anchor_right = 0.5
	draft_bar.anchor_top = 1.0
	draft_bar.anchor_bottom = 1.0
	draft_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	draft_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	draft_bar.offset_top = -(HAND_H + 46.0 + DRAFT_H + 176.0)
	draft_bar.offset_bottom = -(HAND_H + 46.0)
	draft_bar.offset_left = -460.0
	draft_bar.offset_right = 460.0
	draft_bar.visible = false
	draft_bar.z_index = 55
	add_child(draft_bar)
	var dv := UITheme.mk_vbox(6)
	draft_bar.add_child(dv)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 12)
	dv.add_child(dh)
	dh.add_child(UITheme.mk_label("三 选 一", 20, UITheme.GOLD))
	draft_hint = UITheme.mk_label("", 13, UITheme.TEXT_DIM)
	dh.add_child(draft_hint)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(sp2)
	button_refs["refresh"] = UITheme.mk_icon_button("refresh", "刷新牌面：第一次免费，之后 1/2/3 财", 44)
	dh.add_child(button_refs["refresh"])
	button_refs["refresh"].pressed.connect(_on_refresh)
	button_refs["draft_close"] = UITheme.mk_icon_button("exit", "收起牌面（不取也不消耗）", 44)
	dh.add_child(button_refs["draft_close"])
	button_refs["draft_close"].pressed.connect(_on_close_draft)
	draft_row = UITheme.mk_hbox(14)
	draft_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_child(draft_row)

	# ---------- 模态层 ----------
	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.visible = false
	modal_layer.z_index = 80
	add_child(modal_layer)

	# ---------- 回合横幅 ----------
	banner = UITheme.mk_label("", 60, UITheme.GOLD, true)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.visible = false
	banner.modulate.a = 0.0
	banner.z_index = 100
	banner.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.0, 0.95))
	banner.add_theme_constant_override("outline_size", 8)
	add_child(banner)

	# ---------- 特效层（最顶层，不拦截鼠标） ----------
	fx = FXLayer.new()
	add_child(fx)

	# ---------- 拖拽层（手牌拖入场上） ----------
	_drag_layer = Control.new()
	_drag_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_layer.z_index = 250
	add_child(_drag_layer)

	# ---------- 开场选择层（选【人】大本营） ----------
	_setup_layer = Control.new()
	_setup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_layer.visible = false
	_setup_layer.z_index = 220
	add_child(_setup_layer)

	# 【最后一步】把左右两侧调成等宽 —— 必须等第一帧布局落定后才知道左侧真实宽度
	# （资源池的宽度随数字位数变化）。放在 _build 末尾，await 之后没有别的初始化，
	# 所以即使 _build 因此变成协程也不会打乱任何时序。
	_sync_side_width()


## 让底部行的左右两块**等宽**，扇形手牌才会落在屏幕正中。
## 【为什么要在 _refresh 之后再调一次】资源池的数字（财 "0" → "12"）是**内容宽度**，
## _build 那一帧还是占位符；对局数据刷上去后左侧实际宽度会变，同步必须重做
## （实测：_build 时对齐到 0 偏差，_refresh 后左侧缩了 11px → 手牌又偏 5.5px）。
## 【为什么用迭代而不是一次算准】容器的最小宽度是逐级往上传播的
## （大本营 → bottom → main），一次推导很容易差几像素。这里直接**量**：
## 手牌区左缘是固定的，右缘被右侧块挤着 —— 右侧每加宽 x，中点就左移 x/2，
## 于是「偏差 × 2」就是该补的宽度。通常一次就收敛。
func _sync_side_width() -> void:
	if _side_syncing:
		return
	_side_syncing = true
	var changed := false
	await get_tree().process_frame
	for _i in 3:
		if not is_inside_tree() or hand_area == null or _end_block == null:
			break
		var hb := hand_area.get_parent() as Control
		if hb == null or hb.size.x < 100.0:
			break
		var delta: float = hand_area.get_global_rect().get_center().x \
			- (hb.global_position.x + hb.size.x * 0.5)
		if absf(delta) < 0.5:
			break
		_end_block.custom_minimum_size.x += delta * 2.0
		changed = true
		await get_tree().process_frame
	_side_syncing = false
	# 手牌扇形是按 hand_area 的尺寸算出来的，宽度变了必须重排一次
	if changed and human != null and hand_area != null:
		_refresh_hand()


## 取「半身像」贴图：原图的**上半边**（顶部 50%）。
## 【为什么用 AtlasTexture 而不是重跑资源管线】立绘已经压成 720×1280 的 webp，
## 再生成一套「半身版」等于把包体翻一倍；运行期裁一个矩形就够了，零成本、零维护。
## 裁切只是取原图的一部分，比例天然不变 —— 不存在拉伸问题。
static func bust_tex(path: String) -> Texture2D:
	var t := CardView.texture_for(path)
	if t == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = t
	at.region = Rect2(0.0, 0.0, float(t.get_width()), float(t.get_height()) * 0.5)
	return at


## 我方大本营（左下）：一块**固定尺寸**的信息面板。
##   左：半身立绘（放大 1.5 倍）+ 【人】卡（压在立绘右缘之上，脸完整露出）
##   右：名称 / 气条 / 气数 / 人 / 【财】【法】【源】【行动】
func _make_my_camp() -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(MY_CAMP_W, MY_CAMP_H)
	box.size = Vector2(MY_CAMP_W, MY_CAMP_H)
	box.set_meta("role", "my_camp")

	# ---------- 底板：半透明黑，把这一整块圈成整体 ----------
	# 【为什么挂在最底层】它要垫在立绘与卡片之下：立绘的硬裁切线落在底板内，
	# 人物看起来就「沉」进这块面板里，而不是浮在场上。
	var backdrop := Panel.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.position = Vector2.ZERO
	backdrop.size = Vector2(MY_CAMP_W, MY_CAMP_H)
	backdrop.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0, 0, 0, 0.42), Color(0.91, 0.76, 0.42, 0.16), 12, 1, 0, 0))
	backdrop.set_meta("role", "my_camp_backdrop")
	box.add_child(backdrop)

	var bust_x := CAMP_PAD
	var bust_y := MY_CAMP_H - MY_BUST_H - BUST_BOTTOM
	var card_x := bust_x + MY_BUST_W - MY_BUST_OVERLAP
	var card_y := MY_CAMP_H - MY_CARD_H - CARD_BOTTOM

	# ---------- 半身立绘 ----------
	# 【为什么是 box 的子节点、而不是卡片的孩子】它比卡片大得多，要「压在卡片之下、
	# 从左下角铺开」。同 z_index 下按树序绘制 —— 先 add 的先画，所以它必须
	# **早于 card_wrap** 加进来，天然就在卡片下层。
	# （负 z_index 会被全屏背景整张盖掉，踩过；见常量区注释。）
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(MY_BUST_W, MY_BUST_H)
	portrait.position = Vector2(bust_x, bust_y)
	portrait.size = Vector2(MY_BUST_W, MY_BUST_H)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.tooltip_text = "你的角色立绘"
	portrait.set_meta("role", "my_portrait")
	box.add_child(portrait)
	# ---------- 人卡宿主（黑底框 + 人卡 + 升级按钮 + 辟邪剑都挂在这上面） ----------
	var card_wrap := Control.new()
	card_wrap.position = Vector2(card_x, card_y)
	card_wrap.size = Vector2(MY_CARD_W, MY_CARD_H)
	card_wrap.custom_minimum_size = Vector2(MY_CARD_W, MY_CARD_H)
	card_wrap.set_meta("role", "my_card_wrap")
	box.add_child(card_wrap)

	# ---- 【人】卡的半透明黑底框 ----
	# 人卡图几乎铺满 78×138，直接压在立绘上会「贴死」，完全没有层次。
	# 垫一层外扩 12px 的半透明黑底框：卡片像浮在角色身前，立绘在框内的部分
	# 被压暗一档 —— 这半档明暗差就是「远近」的视觉信号，不需要任何光效。
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(-MY_CARD_FRAME, -MY_CARD_FRAME)
	plate.size = Vector2(MY_CARD_W + MY_CARD_FRAME * 2.0, MY_CARD_H + MY_CARD_FRAME * 2.0)
	plate.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0, 0, 0, 0.52), Color(1, 1, 1, 0.10), 12, 1, 0, 0))
	plate.set_meta("role", "my_card_plate")
	card_wrap.add_child(plate)

	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card_wrap.add_child(art)
	card_wrap.set_meta("art", art)
	# ---- 升级按钮：移到**右上角、角色名牌正上方**（用户要求：不要和名字重叠） ----
	# 旧位置贴在【人】卡右上角（相对卡片 (34,-8)），会压住名牌与立绘的交界；
	# 现在挂到整块面板的右上角，名牌在它正下方，两者完全错开。
	var up := UITheme.mk_icon_button("pui_upgrade", "升级【人】", 42, false)
	up.position = Vector2(MY_CAMP_W - INFO_RIGHT - 42.0, 6.0)
	up.pressed.connect(func(): _on_action("upgrade"))
	box.add_child(up)
	button_refs["upgrade"] = up
	# 升级可用的呼吸提示环（不可用时藏起来，由 _refresh_buttons 控制）
	var up_halo := Panel.new()
	up_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0, 0, 0, 0)
	hs.border_color = Color(1.0, 0.86, 0.45, 0.75)
	hs.set_border_width_all(2)
	hs.set_corner_radius_all(21)
	up_halo.add_theme_stylebox_override("panel", hs)
	up_halo.position = up.position - Vector2(3, 3)
	up_halo.size = Vector2(48, 48)
	up_halo.visible = false
	box.add_child(up_halo)
	button_refs["upgrade_halo"] = up_halo
	_camp_by_pid[-1] = card_wrap  # 我方人卡锚点（飘字用）
	# ---- 我方【辟邪】：横于**人卡上方**（对手的在人卡下方，见 _make_enemy_camp）----
	# 浮动子节点，不占布局空间；可见性由 _update_my_camp 按 ward 层数切换。
	# 宽度收到 100：卡片右侧紧挨着信息列（只隔 INFO_GAP），剑再宽就会压上去。
	var my_ward := TextureRect.new()
	my_ward.texture = UITheme.ui_tex("fx_ward")
	my_ward.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	my_ward.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	my_ward.position = Vector2((MY_CARD_W - 100.0) * 0.5, -46.0)
	my_ward.size = Vector2(100, 42)
	my_ward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	my_ward.visible = false
	my_ward.tooltip_text = "【辟邪】护体中：【地】卡无法袭人"
	card_wrap.add_child(my_ward)
	card_wrap.set_meta("my_ward", my_ward)

	# ---------- 右下信息列（全部绝对坐标，绝不因内容宽度而漂移） ----------
	# 【为什么不再用 VBoxContainer + ALIGNMENT_END】容器宽度由内容决定 ——
	# 资源数字从 "0" 变 "150"、角色名从 2 字变 4 字，整列就会被推着走，
	# 名牌与卡片跟着漂。用户报过「【人】卡片的位置都不对了」就是它。
	# 现在整块面板写死 MY_CAMP_W×MY_CAMP_H，内部每个控件都吃常量坐标。
	var info_x := card_x + MY_CARD_W + INFO_GAP
	var info_w := MY_CAMP_W - info_x - INFO_RIGHT

	# ---- 角色名牌：称号（小）+ 名字（大，楷体，角色专属色） ----
	# 【为什么用楷体】正文是雅黑，名牌用 UITheme.title_font()（楷体/宋体）——
	# 中式志怪的味道全靠这一处字形差异撑起来，且不引入任何字体文件（系统字体）。
	var plate_w := info_w - 42.0 - 12.0        # 右边让出升级按钮那一列
	var nplate := Panel.new()
	nplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nplate.position = Vector2(info_x, 6.0)
	nplate.size = Vector2(plate_w, 74.0)
	nplate.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.03, 0.02, 0.06, 0.46), UITheme.GOLD_DIM, 8, 1, 0, 0))
	nplate.set_meta("role", "my_nameplate")
	box.add_child(nplate)

	var title_lbl := UITheme.mk_label("", 12, UITheme.TEXT_DIM, true)
	title_lbl.position = Vector2(10, 7)
	title_lbl.size = Vector2(plate_w - 20, 16)
	title_lbl.clip_text = true
	title_lbl.set_meta("role", "my_title")
	nplate.add_child(title_lbl)

	var nm := UITheme.mk_label("", 26, UITheme.GOLD, true)
	nm.position = Vector2(9, 24)
	nm.size = Vector2(plate_w - 18, 36)
	nm.clip_text = true
	nm.set_meta("role", "my_name")
	nplate.add_child(nm)

	# 名牌下沿的一道角色专属色细线（深浅由 _update_my_camp 按角色写）
	var rule := ColorRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.position = Vector2(10, 63)
	rule.size = Vector2(plate_w - 20, 2)
	rule.set_meta("role", "my_name_rule")
	nplate.add_child(rule)

	# ---- 角色介绍 ----
	var intro := UITheme.mk_label("", 12, UITheme.TEXT_DIM)
	intro.position = Vector2(info_x, 86.0)
	intro.size = Vector2(info_w, 46.0)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.set_meta("role", "my_intro")
	box.add_child(intro)

	# ---- 气条 ----
	var qi_row := HBoxContainer.new()
	qi_row.position = Vector2(info_x, 136.0)
	qi_row.size = Vector2(info_w, 26.0)
	qi_row.add_theme_constant_override("separation", 5)
	box.add_child(qi_row)
	var qi_icon := TextureRect.new()
	qi_icon.texture = UITheme.icon("pui_qi")
	# 22px 时「祥云」糊成一团绿，26px 才看得出是云 —— 它是气条的唯一图形标识，
	# 不能只当装饰。气条本身只有 14px 高，图标略高一点反而更稳。
	qi_icon.custom_minimum_size = Vector2(26, 26)
	qi_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qi_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qi_row.add_child(qi_icon)
	var qi_bar := ProgressBar.new()
	qi_bar.min_value = 0
	qi_bar.show_percentage = false
	qi_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qi_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qi_bar.add_theme_stylebox_override("background", UITheme.flat_style(Color(0, 0, 0, 0.55), 4))
	var qf := StyleBoxFlat.new()
	qf.bg_color = UITheme.QI
	qf.set_corner_radius_all(4)
	qi_bar.add_theme_stylebox_override("fill", qf)
	qi_row.add_child(qi_bar)
	qi_bar.set_meta("role", "my_qi_bar")

	# ---- 气数 / 人：并排一行（省高度，给介绍腾地方） ----
	var stat_row := HBoxContainer.new()
	stat_row.position = Vector2(info_x, 166.0)
	stat_row.size = Vector2(info_w, 18.0)
	stat_row.add_theme_constant_override("separation", 8)
	box.add_child(stat_row)
	var qi_lbl := UITheme.mk_label("0/0", 13, UITheme.TEXT)
	qi_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_row.add_child(qi_lbl)
	qi_lbl.set_meta("role", "my_qi_lbl")
	var ren_lbl := UITheme.mk_label("", 13, UITheme.TEXT_DIM)
	ren_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_row.add_child(ren_lbl)
	ren_lbl.set_meta("role", "my_ren_lbl")

	# ---- 资源池（财/法/源/行动）—— pUI 彩色立体图标，不染色 ----
	# 【为什么是 2×2 网格而不是横排】横排 4 个会把大本营撑到 700+ 宽（旧版就是），
	# 撇成两行两列后整列宽度收在信息列里，不再往区域外顶。
	var res := GridContainer.new()
	res.position = Vector2(info_x, 190.0)
	res.columns = 2
	res.add_theme_constant_override("h_separation", 6)
	res.add_theme_constant_override("v_separation", 5)
	box.add_child(res)
	res_pills["wealth"] = UITheme.mk_res_pill("pui_wealth", "【财】：购买 / 刷新 / 凡人升级",
		UITheme.GOLD, false)
	res_pills["fa"] = UITheme.mk_res_pill("pui_fa", "【法】：正一道士收徒", UITheme.AZURE, false)
	res_pills["yuan"] = UITheme.mk_res_pill("pui_yuan", "【源】：阴阳师收徒", UITheme.PURPLE, false)
	res_pills["action"] = UITheme.mk_res_pill("pui_action",
		"【主动行动】每回合 2 次：袭人 + 场上主动技能共享", UITheme.JADE, false)
	for k in ["wealth", "fa", "yuan", "action"]:
		res_pills[k].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		res.add_child(res_pills[k])
	# 测试训练场：立绘 → 换角色，人卡 → 换【人】（正式版不接线，鼠标事件照旧穿透）
	if Dev.enabled:
		_wire_dev_probes(portrait, art)
	return box


## 右缘图标操作坞
func _make_dock(dock: VBoxContainer) -> void:
	# 拜神 / 敬鬼：回合冷却制「专属卡牌」（用道具目录里的原画素材 002/003）
	var ws := WorshipCard.new()
	ws.setup("拜神", "请【天】", "res://assets/item/002.webp",
		"【拜神 · 请天】掷骰 1-6 点，随机获得对应数量【天】卡入手\n" +
		"每回合 1 次（不消耗资源，回合冷却制）\n发动后会把这张卡亮给全场看")
	ws.pressed.connect(func(): _on_action("worship_shen"))
	dock.add_child(ws)
	button_refs["worship_shen"] = ws
	var wg := WorshipCard.new()
	wg.setup("敬鬼", "请【地】", "res://assets/item/003.webp",
		"【敬鬼 · 请地】掷骰 1-6 点，随机获得对应数量【地】卡入手\n" +
		"每回合 1 次（不消耗资源，回合冷却制）\n发动后会把这张卡亮给全场看")
	wg.pressed.connect(func(): _on_action("worship_gui"))
	dock.add_child(wg)
	button_refs["worship_gui"] = wg
	dock.add_child(HSeparator.new())
	# 【合成已移除】卡牌的阶数在卡池里就是固定的（图鉴里看到的阶数即最终阶数），
	# 所以「3 张同阶同名 → 升 1 阶」这条路径整条删掉，图标坞不再有合成入口。
	#
	# 【降魔杵按钮已移除】降魔杵现在是**卡池里会刷出来的道具卡**，
	# 用法是「把手上的牌拖到对方场上那张卡上」，不再需要一个右侧计数器按钮。
	var defs: Array = [
		["shop", "ingot", "卡牌商店\n重新打开三选一牌面（只看牌，不刷新、不消耗）", true, 52.0],
		["discard", "exchange", "弃置换资源\n弃 1 张手牌，按阵营换 1 点资源", true, 52.0],
		["chara", "star", "角色专属技能", true, 52.0],
		# 【式神只在阴阳师 / 巫女出现】不是这两个【人】时不创建 ——
		# 按钮的可见性由 _refresh_buttons 按 ren_type 控制（VBox 会自动跳过
		# 隐藏子节点，所以藏起来时它不占位置，图标坞自然收拢）。
		["shikigami", "pui_crane", "召唤式神（阴阳师 / 巫女）\n消耗 1 只千纸鹤，召唤 2 气护盾式神上场", false, 62.0],
	]
	for d in defs:
		var b := UITheme.mk_icon_button(d[1], d[2], float(d[4]), bool(d[3]))
		b.pressed.connect(_on_action.bind(d[0]))
		dock.add_child(b)
		button_refs[d[0]] = b


# ==================================================================== 刷新界面
func _refresh() -> void:
	if gs == null:
		return
	# 兜底：任何一次整屏刷新都不允许把拖拽残影留下
	if CardView.active_drag == null:
		_prune_ghost()
	var p := gs.current_player()
	top_round.text = "第 %d 轮" % gs.round_no
	if p:
		top_turn.text = "%s（%s）的回合" % [p.display_name, p.seat]
		top_turn.add_theme_color_override("font_color", UITheme.GOLD if p.pid == human.pid else UITheme.TEXT_DIM)

	_refresh_camps()
	_refresh_boards()
	_refresh_hand()
	_refresh_resources()
	_refresh_draft()
	_refresh_buttons()
	_update_hint()
	# 资源池里的数字刚刚变过 → 左下大本营的宽度可能变了 → 重新对齐手牌中线
	# （内容宽度一变，"左右等宽"就必须重算，否则手牌会跟着漂）
	_sync_side_width()


func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


# ---------- 大本营（敌方按座位对称分列，我方在左下） ----------
## 【★ 为什么列只建一次、之后原地更新 —— 本函数是「4 人局布局漂移」的根治点】
## 旧实现每次 _refresh() 都 _clear(enemy_area)（queue_free，**帧末**才真正删除）
## 再马上 add 3 个新列 —— 于是有那么一帧，enemy_area 同时装着
## 「3 个待删旧列 + 3 个新列」，最小宽度瞬间翻倍：
##   4 人局 6 列 × ~390px ≈ 2350 > 视口 1888 → 主 VBox 被强行撑宽；
##   帧末旧列删掉、最小宽度回落到 ~1200，但**被撑大的尺寸不会自动缩回**
##   （锚点矩形只在父级变化时重算，强制扩宽写进 offset 后就粘住了）。
## 实测用户截图列距 784px → 主容器 2344px，与「6 列瞬时最小宽」完全吻合。
## 结果：第 3 列被推出屏幕外、右上角 战报/帮助/退出 按钮再也点不到。
## 3 人局只有 4 列（≈1580px < 1888）不触发，所以这个 bug 只在 4 人局现形、
## 且「打到后面才出现」（第一次动作后的刷新就中招）。
## 现在列在首刷建好，之后只原地改数据，彻底消灭「新旧列同帧并存」。
func _refresh_camps() -> void:
	if not _camps_built:
		_camps_built = true
		_board_flow_by_pid.clear()
		# 按座位顺序（东/南/西/北，已按 turn_order 排好）逐个开列。
		# 3 人局 2 个对手 → 左上/右上；4 人局 3 个对手 → 左上/正中/右上。
		for q in gs.players:
			if q.pid == human.pid:
				continue
			enemy_area.add_child(_make_enemy_column(q))
	# 每次刷新只原地更新数据（不增删任何列/面板节点）
	for q in gs.players:
		if q.pid == human.pid:
			continue
		_update_enemy_camp(q)
	# 我方（左下，构建期已建，这里只更新数据）
	_update_my_camp()


## 一个对手 = 一列：顶部大本营（人卡+气条+牌背），下方该玩家的场面（卡多自动换行）。
## 【为什么每列 SIZE_EXPAND_FILL】让 N 列均分整行宽度，自然得到
##   「左上/右上」或「左上/正中/右上」的对称布局，且每位玩家的上场区被隐形划分开。
func _make_enemy_column(q: PlayerState) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 大本营头部（沿用原 _make_enemy_camp，内部会登记 _camp_by_pid[q.pid]）
	var head := _make_enemy_camp(q)
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(head)

	# 该玩家的场面（HFlowContainer：卡太多就换到下一行）
	# 【为什么 EXPAND_FILL】FlowContainer 的最小宽度 = 最宽的一张卡。若给 SHRINK_CENTER，
	# 它的宽度会塌缩到「一张卡」，结果每张卡各占一行全竖着堆叠。占满列宽后
	# 才能一行放多张、放不下再换行；每行内容用 ALIGNMENT_CENTER 居中保持对称。
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(flow)
	_board_flow_by_pid[q.pid] = flow
	return col


func _make_enemy_camp(q: PlayerState) -> Control:
	var wrap := PanelContainer.new()
	var is_target := gs.get_target(human.pid) == q.pid
	wrap.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(0.05, 0.04, 0.09, 0.72),
		UITheme.GOLD if is_target else Color(1, 1, 1, 0.12),
		12, 2 if is_target else 1, 10, 6))
	wrap.tooltip_text = "%s（%s）· %s\n点击设为主目标（袭人 / 掠夺指向）" % [q.display_name, q.seat, q.ren_type]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(h)

	# ---- 对手角色立绘：**半身像**（原图顶 50%）+ 稍大，坐在【人】卡**左方**（用户指定摆位） ----
	# 【为什么改半身】全身立绘塞进 62×110 时人物太小、脸部细节全糊掉。改用 bust_tex()
	# 只取上半身（720×640 ≈ 9:8），并放大到 CAMP_BUST_W×H —— 头像更大、五官清晰，
	# 与左下角「我方大本营半身立绘」视觉语言统一。
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(CAMP_BUST_W, CAMP_BUST_H)
	portrait.size = Vector2(CAMP_BUST_W, CAMP_BUST_H)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 同样不能用负 z_index（会被全屏背景盖掉，见 _make_my_camp 里的说明）。
	# 立绘比【人】卡先 add → 同 z 时先绘制 → 压在人卡之下。
	portrait.z_index = 0
	portrait.tooltip_text = "%s 的角色立绘（半身）" % q.display_name
	h.add_child(portrait)

	# ---- 对手大本营【人】卡：整排的「对齐基线」，高度 = CAMP_CARD_H ----
	var art := TextureRect.new()
	art.texture = CardView.texture_for(q.ren.get("art", ""))
	art.custom_minimum_size = Vector2(CAMP_CARD_W, CAMP_CARD_H)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if q.dead:
		art.modulate = Color(0.35, 0.35, 0.38)
	h.add_child(art)
	# ---- 对手的【辟邪】：横于人卡**下方**（己方的在人卡上方，见 _make_my_camp）----
	# 挂在 art 内部做浮动子节点，不占布局空间 —— 生效/失效切换不会把整排大本营顶来顶去。
	var ward_img := TextureRect.new()
	ward_img.texture = UITheme.ui_tex("fx_ward")
	ward_img.custom_minimum_size = Vector2(140, 44)
	ward_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ward_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ward_img.position = Vector2((CAMP_CARD_W - 140.0) * 0.5, CAMP_CARD_H + 4.0)
	ward_img.size = Vector2(140, 44)
	ward_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ward_img.visible = q.ward > 0
	ward_img.tooltip_text = "【辟邪】护体中：【地】卡无法袭人（余 %d 层）" % q.ward
	art.add_child(ward_img)

	# 名称 + 气条
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(info)
	var nm := UITheme.mk_label("%s · %s%s" % [q.display_name, q.seat, " ✝" if q.dead else ""],
		15, UITheme.seat_color(q.seat))
	info.add_child(nm)
	var qi_row := HBoxContainer.new()
	qi_row.add_theme_constant_override("separation", 5)
	info.add_child(qi_row)
	var qi_icon := TextureRect.new()
	qi_icon.texture = UITheme.icon("pui_qi")
	qi_icon.custom_minimum_size = Vector2(24, 24)
	qi_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qi_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qi_row.add_child(qi_icon)
	var qi_bar := ProgressBar.new()
	qi_bar.min_value = 0
	qi_bar.max_value = maxi(1, q.qi_max)
	qi_bar.value = q.qi
	qi_bar.show_percentage = false
	qi_bar.custom_minimum_size = Vector2(110, 13)
	qi_bar.add_theme_stylebox_override("background", UITheme.flat_style(Color(0, 0, 0, 0.55), 4))
	var qf := StyleBoxFlat.new()
	qf.bg_color = UITheme.QI
	qf.set_corner_radius_all(4)
	qi_bar.add_theme_stylebox_override("fill", qf)
	qi_row.add_child(qi_bar)
	var qi_lbl := UITheme.mk_label("气 %d/%d%s ｜ 人×%d" % [q.qi, q.qi_max,
		" 盾%d" % q.shield_qi if q.shield_qi > 0 else "", q.ren_count], 12, UITheme.TEXT_DIM)
	info.add_child(qi_lbl)

	# ---- 对手手牌背面：缩小 + 与大本营【人】卡「横向对齐」 ----
	# （30×54 封顶 7 张的说明见 _rebuild_enemy_backs；数量变化时才整组重建）
	var backs := Control.new()
	backs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	backs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(backs)
	_rebuild_enemy_backs(q, backs)

	# 点击设主目标
	wrap.gui_input.connect(func(ev):
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not q.dead:
				if selected_unit != null and selected_unit.is_di():
					_do_attack_ren(q.pid)
				else:
					gs.set_target(human.pid, q.pid)
					_refresh())
	_camp_by_pid[q.pid] = wrap
	# 【原地更新用引用】_refresh_camps 不再重建列，改由 _update_enemy_camp
	# 拿这些引用改文字/数值，因此这里必须把所有会变的控件登记起来。
	_camp_refs[q.pid] = {
		"wrap": wrap, "art": art, "nm": nm, "qi_bar": qi_bar, "qi_lbl": qi_lbl,
		"backs": backs, "shown": mini(q.hand.size(), 7), "ward": ward_img,
		"portrait": portrait, "ppath": "",
	}
	return wrap


## 重建某对手的「手牌背面」小子树（≤7 张牌背 + ×N 计数）。
## 只在大本营**原地更新**路径里被调用；这是一个纯展示子树，
## 不在任何信号回调链上，free() 立即删除是安全的。
func _rebuild_enemy_backs(q: PlayerState, backs: Control) -> void:
	for c in backs.get_children():
		backs.remove_child(c)
		c.free()
	var bw := 30.0
	var bh := 54.0
	var gap := 15.0
	var shown: int = mini(q.hand.size(), 7)
	var stack_w: float = 0.0 if shown <= 0 else bw + float(shown - 1) * gap
	var cnt_w: float = 30.0 if q.hand.size() > 0 else 0.0
	backs.custom_minimum_size = Vector2(maxf(38.0, stack_w + cnt_w), CAMP_CARD_H)
	backs.tooltip_text = "%s 的手牌 ×%d" % [q.display_name, q.hand.size()]
	var back_tex: Texture2D = UITheme.ui_tex("cardback_t")
	for i in shown:
		var b := TextureRect.new()
		# 【顺序有讲究】必须先设 expand_mode / stretch_mode / custom_minimum_size，
		# 最后才设 size。
		# Godot 的 Control.set_size() 会把尺寸夹到 get_combined_minimum_size() 以上；
		# TextureRect 在默认的 EXPAND_KEEP_SIZE 下最小尺寸 = 贴图尺寸（cardback_t 是 180×320）。
		# 旧代码先写 size 再改 expand_mode，那一下就被夹成 180×320，
		# 牌背于是比【人】卡还大，横着压过整排大本营 —— 就是「牌背太大遮住信息」的元凶。
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b.texture = back_tex
		b.custom_minimum_size = Vector2(bw, bh)
		b.position = Vector2(float(i) * gap, (CAMP_CARD_H - bh) * 0.5)
		b.size = Vector2(bw, bh)
		backs.add_child(b)
	if q.hand.size() > 0:
		var cnt := UITheme.mk_label("×%d" % q.hand.size(), 12, UITheme.TEXT_DIM)
		cnt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		cnt.add_theme_constant_override("shadow_offset_x", 1)
		cnt.add_theme_constant_override("shadow_offset_y", 1)
		# 摆在整叠牌背的**右侧**，不压在牌背上面
		cnt.position = Vector2(stack_w + 4.0, CAMP_CARD_H * 0.5 - 10.0)
		cnt.z_index = 2
		backs.add_child(cnt)


## 原地更新某对手的大本营数据（不增删任何列/面板节点 —— 见 _refresh_camps 说明）。
func _update_enemy_camp(q: PlayerState) -> void:
	var r: Dictionary = _camp_refs.get(q.pid, {})
	if r.is_empty():
		return
	var wrap: PanelContainer = r["wrap"]
	var is_target: bool = gs.get_target(human.pid) == q.pid
	wrap.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(0.05, 0.04, 0.09, 0.72),
		UITheme.GOLD if is_target else Color(1, 1, 1, 0.12),
		12, 2 if is_target else 1, 10, 6))
	wrap.tooltip_text = "%s（%s）· %s\n点击设为主目标（袭人 / 掠夺指向）" % [q.display_name, q.seat, q.ren_type]
	var art: TextureRect = r["art"]
	art.texture = CardView.texture_for(q.ren.get("art", ""))
	art.modulate = Color(0.35, 0.35, 0.38) if q.dead else Color.WHITE
	# 角色立绘：**半身像**（顶 50%），居【人】卡左方；阵亡同样置灰
	var portrait: TextureRect = r["portrait"]
	var spath := str(q.chara.get("scene", ""))
	if str(r["ppath"]) != spath:
		r["ppath"] = spath
		portrait.texture = bust_tex(spath)
	portrait.modulate = Color(0.35, 0.35, 0.38) if q.dead else Color.WHITE
	var nm: Label = r["nm"]
	nm.text = "%s · %s%s" % [q.display_name, q.seat, " ✝" if q.dead else ""]
	nm.add_theme_color_override("font_color", UITheme.seat_color(q.seat))
	var qi_bar: ProgressBar = r["qi_bar"]
	qi_bar.max_value = maxi(1, q.qi_max)
	qi_bar.value = q.qi
	var qi_lbl: Label = r["qi_lbl"]
	qi_lbl.text = "气 %d/%d%s ｜ 人×%d" % [q.qi, q.qi_max,
		" 盾%d" % q.shield_qi if q.shield_qi > 0 else "", q.ren_count]
	var backs: Control = r["backs"]
	if mini(q.hand.size(), 7) != int(r["shown"]):
		# 手牌数跨过了封顶档位（≤7）→ 整组牌背重建；否则只改 tooltip
		r["shown"] = mini(q.hand.size(), 7)
		_rebuild_enemy_backs(q, backs)
	else:
		backs.tooltip_text = "%s 的手牌 ×%d" % [q.display_name, q.hand.size()]
	var ward_img: TextureRect = r["ward"]
	ward_img.visible = q.ward > 0
	ward_img.tooltip_text = "【辟邪】护体中：【地】卡无法袭人（余 %d 层）" % q.ward


func _update_my_camp() -> void:
	# 左下大本营数据更新（按 meta role 查找）
	var camp := _find_by_role(self, "my_camp")
	if camp == null:
		return
	var nm := _find_by_role(self, "my_name") as Label
	# 名牌只写角色名 —— 「你 · 东」这种座位标签对玩家没有信息量，
	# 座位已经由整块面板的位置（左下角）表达。
	nm.text = str(human.chara.get("name", "?"))
	var cc := UITheme.chara_color(str(human.chara.get("color", "")))
	nm.add_theme_color_override("font_color", cc)
	var tl := _find_by_role(self, "my_title") as Label
	if tl != null:
		tl.text = "%s · %s" % [human.chara.get("identity", "?"), human.chara.get("title", "")]
		tl.add_theme_color_override("font_color", Color(cc.r, cc.g, cc.b, 0.88))
	var rl := _find_by_role(self, "my_name_rule") as ColorRect
	if rl != null:
		rl.color = Color(cc.r, cc.g, cc.b, 0.75)
	var pl := _find_by_role(self, "my_nameplate") as Panel
	if pl != null:
		pl.add_theme_stylebox_override("panel",
			UITheme.panel_style(Color(0.03, 0.02, 0.06, 0.46),
				Color(cc.r, cc.g, cc.b, 0.5), 8, 1, 0, 0))
	var it := _find_by_role(self, "my_intro") as Label
	if it != null:
		it.text = str(human.chara.get("intro", ""))
	var bar := _find_by_role(self, "my_qi_bar") as ProgressBar
	bar.max_value = maxi(1, human.qi_max)
	bar.value = human.qi
	var lbl := _find_by_role(self, "my_qi_lbl") as Label
	lbl.text = "气 %d/%d%s" % [human.qi, human.qi_max,
		" 盾%d" % human.shield_qi if human.shield_qi > 0 else ""]
	lbl.add_theme_color_override("font_color",
		UITheme.CINNABAR if human.qi <= human.qi_max * 0.3 else UITheme.TEXT)
	var ren := _find_by_role(self, "my_ren_lbl") as Label
	ren.text = "%s ×%d" % [human.ren_type, human.ren_count]
	# 左下角角色立绘：只换人时重设贴图（同路径重复设 texture 虽幂等，
	# 但每次 _refresh 都做一遍属于白费；比对路径最省）
	var pt := _find_by_role(self, "my_portrait") as TextureRect
	if pt != null:
		var spath := str(human.chara.get("scene", ""))
		if str(pt.get_meta("path", "\u0000")) != spath:
			pt.set_meta("path", spath)
			pt.texture = bust_tex(spath)
	var wrap: Control = _camp_by_pid.get(-1)
	if wrap:
		var art := wrap.get_meta("art") as TextureRect
		art.texture = CardView.texture_for(human.ren.get("art", ""))
		# 【辟邪】剑：ward > 0 时横在人卡上方（层数写进 tooltip）
		var my_ward := wrap.get_meta("my_ward") as TextureRect
		my_ward.visible = human.ward > 0
		my_ward.tooltip_text = "【辟邪】护体中：【地】卡无法袭人（余 %d 层）" % human.ward
	_camp_by_pid[human.pid] = wrap


func _find_by_role(root: Node, role: String) -> Control:
	if root is Control and root.has_meta("role") and root.get_meta("role") == role:
		return root
	for c in root.get_children():
		var r := _find_by_role(c, role)
		if r != null:
			return r
	return null


# ---------- 场面 ----------
func _refresh_boards() -> void:
	_view_by_uid.clear()
	# 敌方：每位玩家的卡牌进各自那一列（列头部已标注名字/座位，卡牌上不再重复挂 tag）
	# 【为什么 4 人局要缩小敌卡】3 列时每列只有 ~630px 宽。7 张常规 + 3 僵尸 = 10 张，
	# 132px 的卡 3 行就 ~800px 高，会把整屏撑爆。缩到 110×194 后 5 张一行，
	# 10 张也只要 2 行，稳稳放下。3 人局每列 ~950px，保持全尺寸。
	var opp_cnt := gs.players.size() - 1
	var ew := BOARD_W
	var eh := BOARD_H
	if opp_cnt >= 3:
		ew = BOARD_W * 0.84
		eh = BOARD_H * 0.84
	for q in gs.players:
		if q.pid == human.pid:
			continue
		var flow: Control = _board_flow_by_pid.get(q.pid)
		if flow == null or not is_instance_valid(flow):
			continue
		_clear(flow)
		for u in q.board:
			var cv := CardView.new()
			cv.set_card(u)
			cv.set_size_px(ew, eh)
			cv.set_board_mode(true)
			cv.card_pressed.connect(_on_enemy_card_click)
			cv.card_right_pressed.connect(_show_detail)
			flow.add_child(cv)
			_view_by_uid[u.uid] = cv
			_note_cd(u.uid, cv)

	_clear(my_board_row)
	if human.board.is_empty():
		my_board_row.add_child(UITheme.mk_label("· 点击手牌起乩上场 ·", 14, UITheme.TEXT_DIM))
	for u in human.board:
		var cv2 := CardView.new()
		cv2.set_card(u)
		cv2.set_size_px(BOARD_W, BOARD_H)
		cv2.set_board_mode(true)
		cv2.set_selected(selected_unit != null and selected_unit.uid == u.uid)
		cv2.card_pressed.connect(_on_unit_click)
		cv2.card_right_pressed.connect(_show_detail)
		cv2.skill_pressed.connect(_on_unit_skill)
		my_board_row.add_child(cv2)
		_view_by_uid[u.uid] = cv2
		_note_cd(u.uid, cv2)


## 冷却回合数变化检测：cd 从 >0 掉到 0 的那一刻，让卡牌四边向外发光。
## 数值由核心层 start_turn() 在自己的回合开始时统一递减，这里只做「读 + 比对」。
func _note_cd(uid: int, cv: CardView) -> void:
	var cur: int = cv.cd_cur
	var prev: int = int(_prev_cd.get(uid, cur))
	cv.note_cooldown(prev)
	_prev_cd[uid] = cur
	if prev > 0 and cur <= 0 and cv.cd_max > 0:
		Sfx.play("buff", -8.0)


# ---------- 扇形手牌 ----------
func _refresh_hand() -> void:
	if OS.get_environment("SF_HDBG") == "1":
		print("   [HDBG] _refresh_hand @%.3f frame=%d busy=%s" % [
			Time.get_ticks_msec() / 1000.0, Engine.get_frames_drawn(), str(busy)])
	# 清掉上一批手牌的邻卡推开 tween（目标对象即将被 free，避免悬空 tween）
	_kill_hand_spread()
	_clear(hand_area)
	_hand_cards.clear()
	_hover_hand_idx = -1
	var cards := human.hand.duplicate()
	cards.sort_custom(func(a, b):
		if a.faction == b.faction:
			return a.sub < b.sub
		return a.faction < b.faction)
	var n := cards.size()
	if n == 0:
		return
	var area_w := hand_area.size.x
	if area_w < 100:
		area_w = 1200.0
	var area_h := hand_area.size.y
	if area_h < 100:
		area_h = HAND_H + 10
	# 扇形参数：围绕手牌区下方的虚拟圆心
	var pivot := Vector2(area_w * 0.5, area_h + 460.0)
	var radius := 460.0 + HAND_H * 0.5
	var step := clampf(0.66 / float(n), 0.05, 0.088)
	var mid := float(n - 1) * 0.5
	var my := gs.is_my_turn(human) and not busy
	for i in n:
		var c: CCard = cards[i]
		var ang := (float(i) - mid) * step
		var center := pivot + Vector2(0, -radius).rotated(ang)
		center.y -= cos(ang) * 8.0
		# ---- 透视（Y 轴向心倾斜）：离中心越远，横向压缩越多 ----
		# 模拟真实扇形里两侧卡牌「侧对镜头」的透视缩短，让手牌「立在桌面」而非平铺。
		# （Control 无 skew 属性，用 scale.x 压缩等效实现 Y 轴向内旋转的透视缩短）
		var rel := (float(i) - mid) / maxf(1.0, mid)   # -1..1 归一化离中心距离
		var squeeze := 1.0 - absf(rel) * 0.10          # 两侧最多压窄 10%
		var sc := Vector2(squeeze, 1.0)
		var zi := n - int(roundf(absf(float(i) - mid))) # 中间在最上，两侧依次压下去
		var cv := CardView.new()
		cv.set_card(c)
		cv.foil = c.tier >= 3
		cv.idle_float = true
		cv.hover_lift = true          ## 悬停抬升 + 置顶（KARDS 手感）
		cv.selectable = my
		cv.draggable = my
		cv.card_pressed.connect(_on_hand_click)
		cv.card_right_pressed.connect(_show_detail)
		cv.card_hovered.connect(_on_hand_hover)
		cv.card_unhovered.connect(_on_hand_unhover)
		cv.drag_started.connect(_on_card_drag_start)
		cv.drag_moved.connect(_on_card_drag_move)
		cv.drag_dropped.connect(_on_card_drag_drop)
		cv.drag_cancelled.connect(_on_card_drag_cancel)
		hand_area.add_child(cv)
		cv.set_size_px(HAND_W, HAND_H)
		var pos := center - Vector2(HAND_W, HAND_H) * 0.5
		cv.position = pos
		cv.rotation = ang
		cv.scale = sc
		cv.z_index = zi
		# 记录原位：悬停结束时必须精确还原，否则扇形会越抬越乱
		cv.set_home(pos, ang, zi, sc)
		_hand_cards.append(cv)
		_view_by_uid[c.uid] = cv
		if not _hand_seen.has(c.uid):
			_hand_seen[c.uid] = true
			cv.anim_enter(minf(i * 0.06, 0.5), ang)


# ---------- 手牌悬停邻卡推开（KARDS 手感：让位 + 选中上浮） ----------
func _on_hand_hover(c: CCard) -> void:
	if c == null:
		return
	var idx := _hand_index_of(c)
	if idx < 0 or idx == _hover_hand_idx:
		return
	_hover_hand_idx = idx
	_apply_hand_spread(idx)


func _on_hand_unhover(c: CCard) -> void:
	if c == null:
		return
	var idx := _hand_index_of(c)
	if idx < 0 or idx != _hover_hand_idx:
		return
	# 刚离开悬停的卡，落回动画由 CardView 自己的弹簧接管（_process 手牌分支），
	# 这里再 tween 它的 position 会和弹簧打架（每帧互相覆盖 → 横向抖动）。
	var skip: CardView = _hand_cards[idx] if idx < _hand_cards.size() else null
	_hover_hand_idx = -1
	_reset_hand_spread(skip)


func _hand_index_of(c: CCard) -> int:
	for j in _hand_cards.size():
		var cv: CardView = _hand_cards[j]
		if is_instance_valid(cv) and cv.card == c:
			return j
	return -1


## 悬停第 idx 张时，把它左右两边的邻卡向外推开（距离越近推得越多），模拟「让位」。
## 选中卡自身由 CardView 沿 Y 上浮 + 摆正 + 置顶，这里只管邻卡的横向让位。
func _apply_hand_spread(idx: int) -> void:
	_kill_hand_spread()
	for j in _hand_cards.size():
		if j == idx:
			continue
		var cv: CardView = _hand_cards[j]
		if not is_instance_valid(cv):
			continue
		var d := absf(float(j - idx))
		if d > 2.0:
			continue   # 只推近邻（隔两张以上不推，避免整片晃动）
		var push := (1.0 - (d - 1.0) * 0.45) * 40.0   # 最近邻 40px，次邻 22px
		var dir := -1.0 if j < idx else 1.0
		var tw := create_tween()
		tw.tween_property(cv, "position", cv.home_pos + Vector2(dir * push, 0.0), 0.16) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_hand_spread_tweens.append(tw)


## 全部邻卡推回原位。skip = 刚离开悬停的卡（落回由 CardView 自己的弹簧管理）。
func _reset_hand_spread(skip: CardView = null) -> void:
	_kill_hand_spread()
	for cv0 in _hand_cards:
		var cv: CardView = cv0
		if cv == skip or not is_instance_valid(cv):
			continue
		var tw := create_tween()
		tw.tween_property(cv, "position", cv.home_pos, 0.16) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_hand_spread_tweens.append(tw)


func _kill_hand_spread() -> void:
	for t in _hand_spread_tweens:
		var tw: Tween = t
		if tw != null and tw.is_valid():
			tw.kill()
	_hand_spread_tweens.clear()


# ---------- 资源 ----------
func _refresh_resources() -> void:
	# 测试训练场：无限资源直接画 ∞ —— 数字仍停在原值（因为根本没扣），
	# 只显示数字会让测试者以为开关没生效。
	UITheme.pill_value(res_pills["wealth"]).text = \
		"∞" if Dev.res_infinite("wealth") else str(human.wealth)
	UITheme.pill_value(res_pills["fa"]).text = \
		"∞" if Dev.res_infinite("fa") else str(human.fa)
	UITheme.pill_value(res_pills["yuan"]).text = \
		"∞" if Dev.res_infinite("yuan") else str(human.yuan)
	var av := UITheme.pill_value(res_pills["action"])
	av.text = "%d/%d" % [human.actions_left(), human.action_limit()]
	av.add_theme_color_override("font_color",
		UITheme.TEXT_DIM if human.actions_left() <= 0 else UITheme.JADE)
	res_pills["fa"].visible = human.ren_type == "正一道士" or human.fa > 0 \
		or Dev.res_infinite("fa")
	res_pills["yuan"].visible = human.ren_type == "阴阳师" or human.yuan > 0 \
		or Dev.res_infinite("yuan")


# ---------- 三选一 ----------
func _refresh_draft() -> void:
	# 牌面显示条件：轮到自己 & 牌面非空 & 没被玩家收起
	# （牌面在回合内一直开着，直到玩家按 ✕ 收起 —— 收起只是 _draft_hidden，
	#  再点「卡牌商店」会把它原样摊开，不重摇、不计价）
	var show := gs.is_my_turn(human) and not busy \
		and not gs.current_draft.is_empty() and not _draft_hidden
	if show and not draft_bar.visible and CardView.effects_enabled:
		draft_bar.pivot_offset = Vector2(460, DRAFT_H + 176)
		draft_bar.scale = Vector2(0.94, 0.55)
		draft_bar.modulate.a = 0.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(draft_bar, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(draft_bar, "modulate:a", 1.0, 0.18)
	draft_bar.visible = show
	if not show:
		_draft_seen = []
		return
	_clear(draft_row)
	var new_batch := false
	var uids: Array = []
	for c0 in gs.current_draft:
		uids.append(c0.uid)
	if uids != _draft_seen:
		_draft_seen = uids
		new_batch = true
	var cost := gs.draft_take_cost(human)
	var can := gs.can_take_draft(human)
	for i in gs.current_draft.size():
		var c: CCard = gs.current_draft[i]
		# 每张卡配一条「技能描述」，直接摆在卡面正下方
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.custom_minimum_size = Vector2(DRAFT_W + 60.0, 0)
		var cv := CardView.new()
		cv.set_card(c)
		cv.set_size_px(DRAFT_W, DRAFT_H)
		cv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.foil = c.tier >= 3
		cv.card_pressed.connect(func(_x): _take_draft(i))
		cv.card_right_pressed.connect(_show_detail)
		cell.add_child(cv)
		var sk := _draft_skill_lines(c)
		var l1 := UITheme.mk_label(sk[0], 13, UITheme.JADE)
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l1.custom_minimum_size = Vector2(DRAFT_W + 60.0, 0)
		cell.add_child(l1)
		var l2 := UITheme.mk_label(sk[1], 11, UITheme.TEXT_DIM)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l2.custom_minimum_size = Vector2(DRAFT_W + 60.0, 58)
		cell.add_child(l2)
		# 免费额度用完时，付不起的卡整体压暗
		if cost > 0 and not can:
			cell.modulate = Color(0.62, 0.60, 0.66)
		draft_row.add_child(cell)
		if new_batch:
			cv.anim_enter(i * 0.09)
	var rc := gs.refresh_cost(human)
	button_refs["refresh"].tooltip_text = "刷新牌面（%s）" % ("本次免费" if rc == 0 else "%d 财" % rc)
	button_refs["refresh"].disabled = not gs.can_refresh(human) or busy
	button_refs["draft_close"].disabled = busy
	if cost <= 0:
		draft_hint.text = "点卡牌直接取走 ｜ 本回合还剩 %d 次免费" % human.draft_free_left
		draft_hint.add_theme_color_override("font_color", UITheme.JADE)
	elif can:
		draft_hint.text = "免费额度已用完 ｜ 每张需 %d【财】（当前 %d）" % [cost, human.wealth]
		draft_hint.add_theme_color_override("font_color", UITheme.GOLD)
	else:
		draft_hint.text = "免费额度已用完 ｜ 需要 %d【财】，当前只有 %d" % [cost, human.wealth]
		draft_hint.add_theme_color_override("font_color", UITheme.CINNABAR)


## 三选一卡面下方的技能摘要 → [标题行, 描述行]
func _draft_skill_lines(c: CCard) -> Array:
	var pick: String = ""
	for key in ["active", "on_play", "passive", "on_remove"]:
		if not c.skill_name(key).is_empty():
			pick = key
			break
	if pick.is_empty():
		return ["— 无技能 —", ""]
	var tag: String = {"on_play": "上场", "on_remove": "下场",
			  "passive": "被动", "active": "主动"}.get(pick, "")
	var head := "%s技能：%s" % [tag, c.skill_name(pick)]
	if pick == "active":
		head += "（冷却 %d 回合）" % c.active_cd()
	return [head, c.skill_desc(pick)]


## 点击三选一里的卡牌 → 直接取走（免费额度内不花【财】，用完后按 buyCost 扣）
func _take_draft(i: int) -> void:
	if i < 0 or i >= gs.current_draft.size():
		return
	if not gs.can_take_draft(human):
		if human.draft_free_left <= 0:
			_show_toast("免费次数已用完，【财】不足（需 %d）" % gs.draft_take_cost(human), true)
		return
	var free_before := human.draft_free_left
	var cost := gs.draft_take_cost(human)
	if gs.do_take_draft(i):
		if fx != null and i < draft_row.get_child_count():
			var pos := (draft_row.get_child(i) as Control).get_global_rect().get_center()
			fx.ring(pos, UITheme.GOLD, 60.0)
			fx.burst(pos, UITheme.GOLD, 14, 180.0)
		if cost > 0:
			Sfx.play("coin", -4.0)
			_show_toast("花费 %d【财】购入" % cost)
		else:
			Sfx.play("draw", -4.0)
			_show_toast("免费取牌（剩余免费 %d 次）" % human.draft_free_left)
		# 免费额度刚好用完 → 提示下次要花钱
		if free_before > 0 and human.draft_free_left <= 0:
			_show_toast("免费次数已用完，之后每张 %d【财】" % gs.buy_cost())
	_refresh_draft()
	_refresh_resources()
	_refresh_hand()
	_refresh_buttons()
	if gs.finished:
		_on_game_over(gs.winner_pid)


## 收起牌面 = **只把它藏起来**，本回合的牌一张不丢。
## 规则层真正的清空发生在 end_turn() → gs.close_draft()（回合结束，没取走的牌不带入下一回合）。
## 用户要的「卡牌商店只开窗、不刷新」能成立，全靠这里不清数据。
func _on_close_draft() -> void:
	_draft_hidden = true
	Sfx.play("ui_click", -8.0)
	_after_action()


## 规则层真正重摇了牌面（回合开始 / 刷新按钮 / 取牌补位）→ 收起状态必须解除。
## 【★ 为什么必须挂信号、而不是在 _refresh_draft 里顺手清】
##   收起时 _refresh_draft 会在 show=false 分支直接 return，
##   根本走不到「比对 uid 发现是新一批」那一步 —— 于是上一回合的「收起」
##   会一直盖着下一回合的新牌，玩家会以为回合没开始。
func _on_draft_opened(_options: Array) -> void:
	_draft_hidden = false


# ---------- 按钮可用态 ----------
func _refresh_buttons() -> void:
	var my := gs.is_my_turn(human) and not busy
	var p := human
	# 拜神/敬鬼：本回合用过就压暗；冷却解除（进入自己回合）时四边发光
	var wp_used := not my or not gs.can_worship(p)
	var just_ready := _worship_used_prev and not wp_used
	(button_refs["worship_shen"] as WorshipCard).set_used(wp_used, just_ready)
	(button_refs["worship_gui"] as WorshipCard).set_used(wp_used, just_ready)
	_worship_used_prev = wp_used
	var ui := gs.upgrade_info(p)
	button_refs["upgrade"].tooltip_text = "升级【人】\n" + ui.get("desc", "")
	button_refs["upgrade"].disabled = not my or not gs.can_upgrade(p)
	# 可升级时给按钮套一圈呼吸金光（pUI 图标本身是静态的，需要额外一层「可以点」的暗示）
	if button_refs.has("upgrade_halo"):
		var halo: Panel = button_refs["upgrade_halo"]
		halo.visible = not button_refs["upgrade"].disabled
		if halo.visible:
			halo.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005))
	button_refs["discard"].disabled = not my or not gs.can_discard(p)
	var cs: Dictionary = p.chara.get("skill", {})
	button_refs["chara"].tooltip_text = "【%s】%s\n%s" % [
		cs.get("name", ""), "（冷却中 ⟳%d）" % p.chara_cd if p.chara_cd > 0 else "（可用）",
		cs.get("desc", "")]
	button_refs["chara"].disabled = not my or p.chara_cd > 0
	button_refs["shop"].disabled = not my
	# 【式神按钮只给阴阳师 / 巫女】其他【人】直接把它从图标坞里藏掉 ——
	# VBoxContainer 会跳过不可见子节点，所以收起来后不会留一个空洞。
	var can_shiki: bool = human.ren_type == "阴阳师" or human.ren_type == "巫女"
	button_refs["shikigami"].visible = can_shiki
	button_refs["shikigami"].disabled = not my or human.paper_cranes <= 0
	button_refs["shikigami"].tooltip_text = "召唤式神（千纸鹤 ×%d）\n消耗 1 只千纸鹤，召唤 2 气护盾式神" % p.paper_cranes
	button_refs["end"].disabled = not my


# ---------- 中央提示 ----------
func _update_hint() -> void:
	# 正在拖一张「指向性道具」：把规则层的判词原样搬上来，
	# 玩家松手前就知道这一下算不算数。
	if _aim_card != null and _aim_card.is_item():
		var why := String(_aim_reason)
		if why == "":
			hint_bar.text = "%s → 松手即释放" % _aim_label
			hint_bar.add_theme_color_override("font_color", UITheme.GOLD)
		else:
			hint_bar.text = why
			hint_bar.add_theme_color_override("font_color", UITheme.CINNABAR)
		return
	if selected_unit != null:
		var u := selected_unit
		if u.is_di():
			hint_bar.text = "已选 %s → 点击【敌方大本营】袭人（%d 气伤）" % [u.name, human.effective_atk_qi(u)]
		else:
			hint_bar.text = "已选 %s → 点击对方场上目标：地=消灭 / 天=制衡" % u.name
		hint_bar.add_theme_color_override("font_color", UITheme.GOLD)
		return
	if selected_hand != null:
		hint_bar.text = "手牌 %s：↑ 起乩上场" % selected_hand.name
		hint_bar.add_theme_color_override("font_color", UITheme.GOLD_DIM)
		return
	# 空闲态：常驻显示「场位占用 / 本轮上限」——上场上限与轮数挂钩，
	# 玩家必须随时能看到现在还能上几张，否则那条规则等于隐形。
	var cap := gs.board_cap(human)
	var used := human.board.size()
	hint_bar.text = "场位 %d/%d" % [used, cap]
	hint_bar.add_theme_color_override("font_color",
		UITheme.CINNABAR if used >= cap else UITheme.GOLD_DIM)


# ==================================================================== 日志
func _on_log(t: String) -> void:
	var lbl := UITheme.mk_label(t, 12, UITheme.TEXT_DIM)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(300, 0)
	if t.begins_with("★") or t.begins_with("✦"):
		lbl.add_theme_color_override("font_color", UITheme.GOLD)
	elif t.begins_with("⚑") or t.begins_with("✗"):
		lbl.add_theme_color_override("font_color", UITheme.CINNABAR)
	elif t.begins_with("—") or t.begins_with("==="):
		lbl.add_theme_color_override("font_color", UITheme.TEXT)
	log_box.add_child(lbl)
	if log_box.get_child_count() > 400:
		log_box.get_child(0).queue_free()
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func _toggle_log() -> void:
	_log_open = not _log_open
	if _log_open:
		log_panel.visible = true
		log_panel.modulate.a = 0.0
		log_panel.offset_left = -300
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(log_panel, "offset_left", -360.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(log_panel, "modulate:a", 1.0, 0.2)
	else:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(log_panel, "offset_left", -300.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(log_panel, "modulate:a", 0.0, 0.2)
		tw.set_parallel(false)
		tw.tween_callback(func(): log_panel.visible = false)


func _toggle_settings() -> void:
	SettingsPanel.open(self)


# ==================================================================== 动作
## 点击手牌 —— 直接弹出卡牌详情（KARDS 式），详情面板里再决定是否起乩上场。
## 起乩的主路径是「把卡拖到场上」；弃置走右缘图标坞。
func _on_hand_click(c: CCard) -> void:
	if gs.is_my_turn(human) and not busy:
		selected_hand = c
		selected_unit = null
	_show_detail(c)


# ==================================================================== 拖拽上场
func _on_card_drag_start(c: CCard) -> void:
	if gs == null or not gs.is_my_turn(human) or busy or c == null:
		return
	if c.sealed > 0:
		_show_toast("该手牌被封锁，本回合无法起乩", true)
		return
	selected_hand = c
	selected_unit = null
	_prune_ghost()
	_ghost = CardView.new()
	_ghost.set_card(c)
	_ghost.selectable = false
	_ghost.foil = c.tier >= 2
	_drag_layer.add_child(_ghost)
	_ghost.set_size_px(HAND_W, HAND_H)
	_ghost.pivot_offset = Vector2(HAND_W, HAND_H) * 0.5
	# 指向性道具（降魔杵 / 金刚镢 / 金刚钺）：起一条直线瞄准线
	if c.is_item() and c.item_target != "self":
		_begin_aim(c)
	Sfx.play("draw", -8.0)


## 瞄准线起点取「这张手牌在扇形里的静止中心」。
## 【为什么不取 get_global_rect().get_center()】拖拽起手的那一瞬鼠标必然还压在牌上，
## 卡牌正处于悬停抬升状态（已上浮 LIFT_PX），用它会在画面上拉出一条偏移 76px 的线。
func _aim_anchor(c: CCard) -> Vector2:
	var cv: CardView = _view_by_uid.get(c.uid)
	if cv != null and is_instance_valid(cv):
		return hand_area.get_global_transform() * (cv.home_pos + Vector2(HAND_W, HAND_H) * 0.5)
	return hand_area.get_global_rect().get_center()


func _begin_aim(c: CCard) -> void:
	_aim_card = c
	_aim_target_uid = -1
	_aim_target_pid = -1
	_aim_reason = ""
	_aim_label = "%s → %s" % [c.name, _item_verb(c.item_func)]
	_aim_from = _aim_anchor(c)
	_aim_pos = _aim_from
	if _aim_line == null:
		_aim_line = AimLine.new()
		_drag_layer.add_child(_aim_line)
	_aim_line.visible = true
	_aim_line.from = _drag_layer.get_global_transform().affine_inverse() * _aim_from


func _end_aim() -> void:
	if _aim_line != null and is_instance_valid(_aim_line):
		_aim_line.visible = false
	if _aim_card != null:
		_clear_target_glow()
	_aim_card = null
	_aim_target_uid = -1
	_aim_target_pid = -1
	_aim_reason = ""
	_aim_label = ""
	# 判词清空：AimLine 整体隐藏时子 Label 也会被藏起来，但留着旧文字
	# 会在下一次瞄准的第一帧闪一下上一次的结论。
	if _aim_line != null and is_instance_valid(_aim_line):
		_aim_line.set_verdict("", true)


func _item_verb(func_key: String) -> String:
	match func_key:
		"purge": return "指向对方场上一张卡，直接拔除"
		"seal": return "指向对方场上一张卡，封印其下回合的行动与被动"
		"axe": return "指向一位对手，巨钺砸落"
		_: return "拖入释放"


## 逐帧重算瞄准：找落点 → 问规则层 → 高亮目标 → 更新判词
func _update_aim(gpos: Vector2) -> void:
	var c := _aim_card
	if c == null:
		return
	_aim_pos = gpos
	_aim_target_uid = -1
	_aim_target_pid = -1
	var ctx: Dictionary = {}
	if c.item_target == "unit":
		_aim_target_uid = _nearest_enemy_uid(gpos, 170.0)
		ctx = {"target_uid": _aim_target_uid}
	elif c.item_target == "player":
		_aim_target_pid = _nearest_enemy_pid(gpos, 140.0)
		ctx = {"target_pid": _aim_target_pid}
	var chk := gs.can_use_item(human, c, ctx)
	var ok := bool(chk.get("ok", false))
	_aim_reason = "" if ok else String(chk.get("reason", "无法使用"))
	_apply_target_glow(_aim_target_uid if ok else -1)
	if _aim_line != null and is_instance_valid(_aim_line):
		var t := _drag_layer.get_global_transform().affine_inverse()
		_aim_line.from = t * _aim_from
		_aim_line.to = t * gpos
		_aim_line.ok = ok
		_aim_line.queue_redraw()
		# 判词：合法给「松手即释放」，不合法给规则层原文（玩家看得懂的那种）
		_aim_line.set_verdict("松手即释放" if ok else _aim_reason, ok)
		_aim_line.verdict.position = (t * gpos) + Vector2(20.0, -40.0)
	_update_hint()


## 找离鼠标最近的一张「对方场上卡」。
## 【为什么带容差】要求像素级压在某张卡上太苛刻了，尤其 4 人局场面很窄；
## 容差 170px 大约是「卡宽 + 一个身位」，指哪打哪，不会误指到更远的卡。
func _nearest_enemy_uid(gpos: Vector2, tol: float) -> int:
	var best := -1
	var bd := 1e9
	for q in gs.players:
		if q.pid == human.pid:
			continue
		for u in q.board:
			if not _view_by_uid.has(u.uid):
				continue
			var cv: Control = _view_by_uid[u.uid]
			if not is_instance_valid(cv):
				continue
			var d := gpos.distance_to(cv.get_global_rect().get_center())
			if d <= tol + cv.size.x * 0.5 and d < bd:
				bd = d
				best = u.uid
	return best


func _nearest_enemy_pid(gpos: Vector2, tol: float) -> int:
	var best := -1
	var bd := 1e9
	for q in gs.players:
		if q.pid == human.pid or not _camp_by_pid.has(q.pid):
			continue
		var ctl: Control = _camp_by_pid[q.pid]
		if not is_instance_valid(ctl):
			continue
		var r: Rect2 = ctl.get_global_rect().grow(tol)
		if r.has_point(gpos):
			var d := gpos.distance_to(r.get_center())
			if d < bd:
				bd = d
				best = q.pid
	# 只有一个对手时，鼠标落在战场任何位置都算指向他 ——
	# 双人局是主玩法，不该让玩家为「对准」较劲。
	if best < 0:
		var ops: Array = []
		for q in gs.players:
			if q.pid != human.pid:
				ops.append(q)
		if ops.size() == 1:
			return int((ops[0] as PlayerState).pid)
	return best


func _apply_target_glow(uid: int) -> void:
	for u in _view_by_uid.keys():
		var cv: CardView = _view_by_uid[u]
		if is_instance_valid(cv):
			cv.set_target_glow(int(u) == uid and uid >= 0)


func _clear_target_glow() -> void:
	for u in _view_by_uid.keys():
		var cv: CardView = _view_by_uid[u]
		if is_instance_valid(cv):
			cv.set_target_glow(false)


func _on_card_drag_move(c: CCard, gpos: Vector2) -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	var lp := _drag_layer.get_global_transform().affine_inverse() * gpos
	# 指向性道具：幽灵卡跟着鼠标走，但**不遮住落点**——
	# 把它缩到 0.6 并往右下偏一点，玩家才看得见自己正瞄着哪张卡。
	var aiming := c.is_item() and c.item_target != "self"
	if aiming:
		_ghost.position = lp - Vector2(HAND_W, HAND_H) * 0.5 + Vector2(HAND_W * 0.42, HAND_H * 0.34)
		_ghost.rotation = 0.0
		_ghost.scale = Vector2(0.58, 0.58)
		_update_aim(gpos)
		_drag_valid = _aim_reason == ""
	else:
		_ghost.position = lp - Vector2(HAND_W, HAND_H) * 0.5
		_ghost.rotation = 0.0
		_ghost.scale = Vector2(0.94, 0.94)
		_drag_valid = _drop_ok(gpos, c)
	_ghost.modulate = Color.WHITE if _drag_valid else Color(0.85, 0.72, 0.72)


func _on_card_drag_drop(c: CCard, gpos: Vector2) -> void:
	# 【必须先清残影】不管这次投放有效与否，拖拽残影都在这一帧结束生命。
	_prune_ghost()
	if c == null:
		_end_aim()
		return
	var ctx := {"target_uid": _aim_target_uid, "target_pid": _aim_target_pid}
	var valid := _drag_valid and _drop_ok(gpos, c)
	_drag_valid = false
	_end_aim()
	if valid:
		if c.is_item():
			_use_item_card(c, ctx)
			return
		_play_card(c)
		return
	_refresh()


## 拖拽被强制取消（源卡在拖拽途中被 _refresh() 销毁）。
## 这里**不能**落牌，也不能立刻 _refresh()：调用栈此时正处于节点销毁过程中，
## 任何 add_child 都会失败。只需延迟清掉拖拽层残留即可。
func _on_card_drag_cancel(_c: CCard) -> void:
	_drag_valid = false
	_end_aim()
	_prune_ghost.call_deferred()


## 清掉拖拽层上所有残留卡面。
## 拖拽中途任何一次 _refresh() 都会重建手牌节点，源卡被销毁时释放事件可能丢失，
## 于是上一张 _ghost 会永远留在 _drag_layer 上（就是那个「残留卡牌」bug）。
## 所以这里不信任 _ghost 这个单变量，直接把拖拽层扫干净，
## 并且只在「当前没有卡处于拖拽态」时才动手，避免误杀正在拖的那张。
func _prune_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if _drag_layer == null:
		return
	var active := CardView.active_drag
	if active != null and is_instance_valid(active) and active.dragging:
		return
	for ch in _drag_layer.get_children():
		if ch == _aim_line:
			continue
		ch.queue_free()


## 投放判定，分三条完全不同的路径：
##   ① 指向性道具（unit / player）——合法性由「瞄准判定」给出（_aim_reason），落点是某张卡 / 某个人；
##   ② 自身道具（三清铃 / 铜钱剑 / 八卦镜）——拖入战场即释放，与普通上场同一套区域判定；
##   ③ 普通卡——落在「手牌区上方」的战场范围内，且规则层允许上场。
## （同名牌不能重复上场 / 场位已达本轮上限时，指示器直接变红，不让玩家白拖一趟）
func _drop_ok(gpos: Vector2, c: CCard = null) -> bool:
	if gs == null or busy or not gs.is_my_turn(human):
		return false
	if not get_global_rect().has_point(gpos):
		return false
	if c != null and c.is_item():
		if c.item_target == "unit" or c.item_target == "player":
			return _aim_reason == ""
		return gpos.y < hand_area.get_global_rect().position.y - 4.0
	if c != null and not gs.can_play(human, c.uid):
		return false
	var ha := hand_area.get_global_rect()
	return gpos.y < ha.position.y - 4.0


## 起乩（点击流程与拖拽流程共用）
func _play_card(c: CCard) -> void:
	if gs == null or c == null:
		return
	if not gs.do_play(c.uid):
		# 把**具体原因**告诉玩家：同名重复 / 场位已满 / 被封锁，各不相同
		var why := gs.play_block_reason(human, c.uid)
		_show_toast(why if why != "" else "无法起乩：本回合不能打出该牌", true)
		_refresh()
		return
	Sfx.play("play", -3.0)
	selected_hand = null
	_after_action()
	var cv: CardView = _view_by_uid.get(c.uid)
	if cv != null and is_instance_valid(cv):
		cv.anim_cast(UITheme.faction_color(c.faction))


## 道具卡释放（拖拽流程专用入口）。
## 【为什么不走 _play_card】道具不占场位、不给面板数值、不走 on_play 技能，
## 它要做的是「把落点交给规则层的 use_item」，走 do_play 会把落点丢掉。
func _use_item_card(c: CCard, ctx: Dictionary) -> void:
	if gs == null or c == null:
		return
	# 先把落点上的视觉打出去（规则层随后就把它拔掉了，锚点会取不到）
	_fx_item_use(human, c, int(ctx.get("target_uid", -1)), int(ctx.get("target_pid", -1)))
	if not gs.use_item(human, c, ctx):
		_show_toast("【%s】无法使用" % c.name, true)
		_refresh()
		return
	selected_hand = null
	_after_action()


## 道具释放前的「落点视觉」：瞄准线收束 + 目标点爆闪。
## 真正的重头戏（书法字 / 巨钺 / 八卦镜读数）由 _fx_effect 在规则层发信号后播。
func _fx_item_use(p: PlayerState, c: CCard, uid: int, tpid: int) -> void:
	if fx == null:
		return
	Sfx.play("seal", -4.0)
	var from := _aim_from if _aim_from != Vector2.ZERO else _player_anchor(p.pid)
	var to := Vector2.ZERO
	if uid >= 0:
		to = _card_anchor(uid)
	elif tpid >= 0:
		to = _player_anchor(tpid)
	if to == Vector2.ZERO:
		to = _player_anchor(p.pid)
	match c.item_func:
		"purge", "seal":
			if to != Vector2.ZERO:
				fx.beam(from, to, UITheme.CINNABAR if c.item_func == "purge" else UITheme.GOLD)
		"axe":
			fx.beam(from, to, UITheme.GOLD)
		_:
			fx.ring(to, UITheme.GOLD, 110.0)


func _on_unit_click(c: CCard) -> void:
	if not gs.is_my_turn(human) or busy:
		return
	selected_unit = (null if (selected_unit != null and selected_unit.uid == c.uid) else c)
	selected_hand = null
	_refresh()


func _on_unit_skill(c: CCard) -> void:
	## 点击场上卡的技能图标：直接发动主动技能
	if not gs.is_my_turn(human) or busy or c == null:
		return
	if c.cooldown > 0 or c.frozen > 0:
		_show_toast("冷却中（剩 %d 回合）" % c.cooldown, true)
		return
	if not human.has_action():
		_show_toast("本回合主动行动已用完", true)
		return
	if fx != null:
		fx.play_fx(c.skill_fx("active"), _card_anchor(c.uid),
			UITheme.faction_color(c.faction))
	Sfx.play_fx(c.skill_fx("active"))
	gs.do_active(c.uid)
	selected_unit = null
	_after_action()
	var cv: CardView = _view_by_uid.get(c.uid)
	if cv != null and is_instance_valid(cv):
		cv.anim_cast(UITheme.faction_color(c.faction))


func _on_enemy_card_click(c: CCard) -> void:
	if not gs.is_my_turn(human) or busy:
		return
	if selected_unit != null:
		var u := selected_unit
		var chk := gs.can_attack(human, u, "unit", c)
		if chk["ok"]:
			selected_unit = null
			_fx_attack_visual(u.uid, "unit", c.uid)
			gs.do_attack(u.uid, "unit", c.uid)
			_after_action()
		else:
			_show_toast(chk.get("reason", "无法攻击"), true)
		return
	_show_detail(c)


func _do_attack_ren(target_pid: int = -1) -> void:
	if selected_unit == null:
		return
	if target_pid >= 0:
		gs.set_target(human.pid, target_pid)
	var u := selected_unit
	selected_unit = null
	_fx_attack_visual(u.uid, "ren", -1)
	gs.do_attack(u.uid, "ren")
	_after_action()


func _on_end_turn() -> void:
	if not gs.is_my_turn(human) or busy:
		return
	selected_unit = null
	selected_hand = null
	_end_aim()
	Sfx.play("turn", -6.0)
	gs.end_turn()
	_driver()


## 是否正压着一个「要求你先做选择」的层。空格跳过回合必须避开这些，
## 否则玩家正开着详情 / 弃置 / 三选一 / 开场选择，一按空格回合就没了。
func _modal_open() -> bool:
	if modal_layer != null and modal_layer.visible:
		return true
	if _setup_layer != null and is_instance_valid(_setup_layer) and _setup_layer.visible:
		return true
	if draft_bar != null and draft_bar.visible:
		return true
	return false


## 键盘快捷键：**空格 = 结束回合并跳过**。
## 【为什么用 _unhandled_key_input 而不是 _input】
##   _input 会抢在 UI 控件之前拿到事件 —— 玩家在下拉框 / 详情面板里按空格
##   也会被判成「跳过回合」。_unhandled 只在没人消费事件时触发，天然安全。
func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey):
		return
	var k := ev as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode != KEY_SPACE:
		return
	if gs == null or human == null or _modal_open():
		return
	if not gs.is_my_turn(human) or busy:
		return
	_on_end_turn()
	get_viewport().set_input_as_handled()


func _on_action(key: String) -> void:
	if not gs.is_my_turn(human) or busy:
		return
	match key:
		"worship_shen":
			var r := gs.do_worship("shen")
			if r.get("ok", false):
				busy = true
				Sfx.play("dice", -4.0)
				_show_worship_reveal("shen", int(r.get("dice", 1)))
				fx.dice_roll(int(r.get("dice", 1)), func():
					busy = false
					_show_toast("请神成功 · %d 点" % int(r.get("dice", 0)))
					Sfx.play("draw", -5.0)
					_after_action())
			else:
				_after_action()
		"worship_gui":
			var r2 := gs.do_worship("gui")
			if r2.get("ok", false):
				busy = true
				Sfx.play("dice", -4.0)
				_show_worship_reveal("gui", int(r2.get("dice", 1)))
				fx.dice_roll(int(r2.get("dice", 1)), func():
					busy = false
					_show_toast("敬鬼成功 · %d 点" % int(r2.get("dice", 0)))
					# 【★ 2026-10 用户要求】敬鬼的音效**播一次就够了，不要连着响**。
					# 原来这条 `soul`(2.84s) 紧跟在揭晓音 worship_gui(2.4s) 之后，
					# 两段长音首尾相接 ≈ 5 秒连绵不断，听感上就像在循环播放。
					# 现在整条链路只留揭晓那一次。
					_after_action())
			else:
				_after_action()
		"upgrade":
			# 【升级特效】升级是最贵的一次投入（财/法/源），必须有明确回报感：
			# 金色光柱 + 「升」字 + 气上限飘字，一次看不完说明演出太短。
			var anchor := _player_anchor(human.pid)
			if gs.do_upgrade():
				Sfx.play("buff", -2.0)
				if fx != null and anchor != Vector2.ZERO:
					fx.upgrade_burst(anchor, human.qi_max)
			_after_action()
		"discard":
			_open_discard()
		"shop":
			_open_shop()
		"chara":
			# 【★ 2026-10 用户要求】角色专属技能**暂时不放音效** ——
			# 后面会为每个角色的技能单独制作特效与音效，届时按角色分别接。
			# 这里只执行规则与刷新，不出声（特效由 _fx_effect 走通用技能反馈）。
			gs.do_chara_skill()
			_after_action()
		"shikigami":
			if gs.do_summon_shikigami():
				Sfx.play("summon", -4.0)
			_after_action()


func _on_refresh() -> void:
	_draft_hidden = false
	if gs.do_refresh():
		Sfx.play("draw", -6.0)
	_after_action()


## 卡牌商店：把「三选一」牌面重新打开（**不刷新、不消耗任何资源**）。
## 【★ 用户要求】
##   ①「打开三选一商店的时候不会触发刷新，只是打开那个窗口而已，不消耗财。」
##     所以这里既不调 do_refresh()，也不看 can_open_draft() 的计价 —— 它就是一个
##     「把收起来的牌面再摊开」的动作。牌面的**内容**永远由规则层决定：
##       · 回合开始 open_draft() 发的那一批，取走一张自动补一张，本回合内一直在；
##       · 玩家按 ✕ 只是 _draft_hidden = true，牌还在 current_draft 里；
##       · 真正清空只发生在 end_turn() → gs.close_draft()。
##     唯一「无牌可开」的情形是回合还没开始（开局第一帧）或牌面已被回合结束清掉，
##     此时给一句提示，绝不偷偷重摇一批 —— 那才是「无限免费换牌」的漏洞。
##   ②「点击卡牌商店按钮后，再次点击按钮可以关闭。」→ 同一枚按钮就是个开关：
##     面板开着时再点 = 收起（等价于点 ✕），面板关着时再点 = 摊开。
func _open_shop() -> void:
	if not gs.is_my_turn(human) or busy:
		_show_toast("现在不是你的回合", true)
		return
	if not _draft_hidden and not gs.current_draft.is_empty():
		# 面板正开着 → 再点一次即收起（与 ✕ 同一条路径，牌一张不丢）
		_on_close_draft()
		return
	if gs.current_draft.is_empty():
		_show_toast("牌面已收起（本回合的牌已结算），下回合开新的一批", true)
		return
	_draft_hidden = false
	Sfx.play("ui_open", -6.0)
	_after_action()


func _after_action() -> void:
	_refresh()
	if gs.finished:
		_on_game_over(gs.winner_pid)


# ==================================================================== 特效钩子
func _player_anchor(pid: int) -> Vector2:
	if _camp_by_pid.has(pid):
		var pnl: Control = _camp_by_pid[pid]
		if is_instance_valid(pnl):
			return pnl.get_global_rect().get_center()
	if pid == human.pid and _camp_by_pid.has(-1):
		var mine: Control = _camp_by_pid[-1]
		if is_instance_valid(mine):
			return mine.get_global_rect().get_center()
	return get_rect().get_center()


func _card_anchor(uid: int) -> Vector2:
	if _view_by_uid.has(uid):
		var cv: Control = _view_by_uid[uid]
		if is_instance_valid(cv):
			return cv.get_global_rect().get_center()
	return Vector2.ZERO


func _owner_of_unit(uid: int) -> PlayerState:
	for p in gs.players:
		for u in p.board:
			if u.uid == uid:
				return p
	return null


func _fx_attack_visual(attacker_uid: int, target_kind: String, target_uid: int) -> void:
	if fx == null:
		return
	var from := _card_anchor(attacker_uid)
	var to := Vector2.ZERO
	if target_kind == "ren":
		var owner := _owner_of_unit(attacker_uid)
		if owner != null:
			to = _player_anchor(gs.opponent_of(owner).pid)
	else:
		to = _card_anchor(target_uid)
	if from == Vector2.ZERO or to == Vector2.ZERO:
		return
	var av: CardView = _view_by_uid.get(attacker_uid)
	if av != null and is_instance_valid(av):
		av.anim_lunge(to - from)
		av.anim_cast(UITheme.QI)
	fx.beam(from, to, UITheme.QI)
	Sfx.play("attack", -4.0)


func _fx_card_played(pid: int, c: CCard) -> void:
	if fx == null:
		return
	var pos := _player_anchor(pid)
	var col := UITheme.faction_color(c.faction)
	fx.ring(pos, col, 90.0)
	fx.burst(pos, col, 18, 200.0)
	fx.float_text(pos + Vector2(0, -30), "起乩 · " + c.name, UITheme.GOLD, 22)
	_land_sfx(c)


## 【★ 2026-10 用户要求】一般卡牌**不再有上场 / 下场音效**，只保留三类神兽的：
##     龙（辰龙 / 青龙 / 亢金龙 / 金龙 / 黄龙）→ 龙吟
##     虎（寅虎 / 白虎 / 煞面虎-虎爷 / 虎神 / 虎妖）→ 虎啸
##     犬（犬神）→ 猛兽吼
##   其余一律静音。判据是**卡名包含关键字**，不是 sub —— 因为这几类神兽在数据里
##   分属「神 / 妖」两个 sub，用 sub 分派会把它们漏掉。
## 【为什么抽成独立函数】测试训练场的「试听音效」复用同一条分派 ——
##   复制一份出去的那一刻，两边就会开始漂。
const BEAST_SFX := {"龙": "dragon", "虎": "roar", "犬": "beast"}


## 这张卡有没有专属吼声？没有就返回 ""（调用方据此决定要不要出声）。
func beast_sfx_key(c: CCard) -> String:
	if c == null:
		return ""
	for k in BEAST_SFX.keys():
		if c.name.contains(str(k)):
			return str(BEAST_SFX[k])
	return ""


func _land_sfx(c: CCard) -> void:
	var s := beast_sfx_key(c)
	if s != "":
		Sfx.play(s, -5.0)


func _fx_unit_removed(pid: int, c: CCard) -> void:
	if fx == null:
		return
	# 下场音效同样只给龙 / 虎 / 犬
	var s := beast_sfx_key(c)
	if s != "":
		Sfx.play(s, -7.0)
	var pos := _card_anchor(c.uid)
	if pos == Vector2.ZERO:
		pos = _player_anchor(pid)
	fx.burst(pos, UITheme.PURPLE, 20, 230.0, 3.6)
	fx.float_text(pos, "拔除", UITheme.PURPLE, 26)


func _fx_effect(info: Dictionary) -> void:
	if fx == null:
		return
	match String(info.get("kind", "")):
		"qi_damage":
			var pid := int(info.get("pid", -1))
			var v := int(info.get("value", 0))
			var pos := _player_anchor(pid)
			if v <= 0:
				fx.float_text(pos, "护盾吸收", UITheme.AZURE, 18)
				return
			fx.float_text(pos, "-%d 气" % v, UITheme.QI, 30)
			fx.burst(pos, UITheme.QI, 12, 150.0)
			Sfx.play("hit", -4.0)
			if pid == human.pid:
				fx.shake(_world, 7.0)
				fx.flash_screen(Color(0.8, 0.15, 0.1, 0.14))
		"unit_damage":
			var uid := int(info.get("uid", -1))
			var v2 := int(info.get("value", 0))
			var pos2 := _card_anchor(uid)
			if pos2 != Vector2.ZERO:
				fx.float_text(pos2, "-%d" % v2, Color("ff9d6b"), 24)
				var cv: CardView = _view_by_uid.get(uid)
				if cv != null and is_instance_valid(cv):
					cv.anim_shake()
		# ---------------- 道具特效 ----------------
		# 降「降」/ 金刚镢「封」：朱砂 / 金的书法单字
		"item_calligraphy":
			var uid3 := int(info.get("uid", -1))
			var p3 := _card_anchor(uid3)
			if p3 == Vector2.ZERO:
				p3 = _player_anchor(int(info.get("pid", -1)))
			var tone := String(info.get("tone", "cinnabar"))
			var col3: Color = UITheme.CINNABAR if tone == "cinnabar" else UITheme.GOLD
			fx.calligraphy(String(info.get("text", "降")), p3, col3, 300.0)
			Sfx.play("purge" if tone == "cinnabar" else "seal", -2.0)
			fx.float_text(p3 + Vector2(0, 96), "%s · %s" % [info.get("name", ""), info.get("sub", "")],
				col3, 20)
		# 金刚钺
		"item_axe":
			var tp := _player_anchor(int(info.get("target_pid", -1)))
			fx.axe_smash(tp)
			Sfx.play("quake", -2.0)
			fx.float_text(tp + Vector2(0, -70), "金刚钺 · 巨钺降世", UITheme.GOLD, 26)
		# 三清铃：三张临时【僵尸】各起一座法阵
		"item_zombies":
			var zc := int(info.get("count", 0))
			for zu in (info.get("uids", []) as Array):
				var zp := _card_anchor(int(zu))
				if zp != Vector2.ZERO:
					fx.sigil(zp, Color("9bbf6a"), 86.0)
					fx.burst(zp, Color("9bbf6a"), 16, 170.0, 3.2)
			fx.ring(_player_anchor(int(info.get("pid", -1))), Color("9bbf6a"), 150.0)
			Sfx.play("summon", -2.0)
			fx.float_text(_player_anchor(int(info.get("pid", -1))), "三清铃 · 召 %d 僵" % zc,
				Color("9bbf6a"), 24)
		"item_ward":
			var wp := _player_anchor(int(info.get("pid", -1)))
			fx.sigil(wp, Color("d8c070"), 110.0)
			fx.ring(wp, UITheme.GOLD, 150.0)
			for i in int(info.get("value", 3)):
				fx.burst(wp + Vector2(0, -10 - i * 16), Color("ffe6a8"), 12, 130.0, 3.0)
			Sfx.play("shield", -3.0)
			fx.float_text(wp, "铜钱剑 · 辟邪 ×%d" % int(info.get("value", 3)), UITheme.GOLD, 24)
		# 八卦镜：只向「照镜子的人」显示读数
		"reveal_di":
			var rp := int(info.get("pid", -1))
			if rp != human.pid:
				return
			var arr: Array = []
			for it in (info.get("info", []) as Array):
				var d := it as Dictionary
				arr.append({"pos": _player_anchor(int(d.get("pid", -1))),
					"count": int(d.get("count", 0)), "name": d.get("name", "")})
			fx.reveal_marks(arr)
			Sfx.play("moon", -4.0)


# ==================================================================== AI 驱动
func _driver() -> void:
	var guard := 0
	while not gs.finished and guard < 5000:
		guard += 1
		if not gs.start_turn():
			continue
		var p := gs.current_player()
		if p == null:
			break
		if p.is_ai:
			await _play_ai_turn(p)
			if gs.finished:
				break
			gs.end_turn()
			_refresh()
			await get_tree().create_timer(0.2).timeout
		else:
			busy = false
			_show_banner("你的回合 · %s" % human.seat)
			_refresh()
			if tutorial and not _guide_shown:
				_guide_shown = true
				_show_guide(0)
			return
	_refresh()


func _play_ai_turn(p: PlayerState) -> void:
	busy = true
	_show_banner("%s 的回合 · %s" % [p.display_name, p.seat])
	_refresh()
	await get_tree().create_timer(0.6).timeout
	var ai := AIBrain.new()
	ai.setup(gs, p)
	var acts := ai.plan_turn()
	for a in acts:
		if gs.finished:
			break
		await get_tree().create_timer(0.42).timeout
		_apply_ai_action(p, a)
		_refresh()
	busy = false


func _apply_ai_action(p: PlayerState, a: Dictionary) -> void:
	match a.get("type", ""):
		"draft": gs.pick_draft(int(a.get("idx", 0)))
		"refresh": gs.do_refresh()
		"buy": gs.do_buy(int(a.get("idx", 0)))
		"worship": gs.do_worship(a.get("kind", "shen"))
		"discard": gs.do_discard(int(a.get("uid", -1)))
		"upgrade": gs.do_upgrade()
		"play": gs.do_play(int(a.get("uid", -1)))
		"item":
			var cur := gs.current_player()
			var ic := cur.find_hand(int(a.get("uid", -1)))
			if ic != null:
				_fx_item_use(cur, ic, int(a.get("target_uid", -1)), int(a.get("target_pid", -1)))
				gs.use_item(cur, ic, {"target_uid": int(a.get("target_uid", -1)),
					"target_pid": int(a.get("target_pid", -1))})
		"attack":
			_fx_attack_visual(int(a.get("uid", -1)), a.get("target_kind", "ren"), int(a.get("target", -1)))
			gs.do_attack(int(a.get("uid", -1)), a.get("target_kind", "ren"), int(a.get("target", -1)))
		"active": gs.do_active(int(a.get("uid", -1)))
		"chara": gs.do_chara_skill()
		"shikigami": gs.do_summon_shikigami()


# ==================================================================== 模态面板
## 模态面板。actions = [[按钮文字, Callable], …]，摆在「关闭」左边。
## 测试训练场用它给弹窗插入额外操作；正式版永远传空数组，
## 所以这条参数对 SheFu.exe 完全没有可见影响。
func _modal(title: String, body: Control, w: float = 900.0, actions: Array = []) -> void:
	_clear(modal_layer)
	modal_layer.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close_modal())
	modal_layer.add_child(dim)
	var pnl := UITheme.mk_panel(Color(0.07, 0.06, 0.11, 0.98), UITheme.GOLD_DIM)
	pnl.set_meta("role", "modal_panel")
	pnl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pnl.custom_minimum_size = Vector2(w, 0)
	modal_layer.add_child(pnl)
	var v := UITheme.mk_vbox(10)
	pnl.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(UITheme.mk_label(title, 22, UITheme.GOLD, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	for a in actions:
		var extra := UITheme.mk_button(str(a[0]), 15)
		extra.pressed.connect(a[1])
		h.add_child(extra)
	var cb := UITheme.mk_icon_button("exit", "关闭", 34)
	cb.name = "ModalClose"
	cb.pressed.connect(_close_modal)
	h.add_child(cb)
	v.add_child(HSeparator.new())
	v.add_child(body)
	pnl.reset_size()
	# 【★ 为什么最后要手摆一次，而不是再调 PRESET_CENTER】
	# 上面那次 PRESET_CENTER 是在「还没塞内容」的时候算 offsets 的：offsets 一旦写死，
	# 之后 reset_size() 把面板撑到 980×406，anchors 还在 0.5 而 offsets 没跟着改 ——
	# 面板就变成「左上角钉在屏幕正中心、向右下长出去」。
	# 试过"reset_size() 之后再调一次 PRESET_CENTER"：它的 offsets 仍是按**调用当时**的
	# 尺寸算的，实测 980 宽的面板被摆到 x=815（父级 1954 → 应该 x=487），右边差 328px。
	# 所以直接按父级尺寸手摆 —— 这才是唯一确定的行为。
	pnl.position = ((modal_layer.size - pnl.size) * 0.5).floor()
	if CardView.effects_enabled:
		dim.modulate.a = 0.0
		pnl.pivot_offset = pnl.size * 0.5
		pnl.scale = Vector2(0.9, 0.9)
		pnl.modulate.a = 0.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(dim, "modulate:a", 1.0, 0.18)
		tw.tween_property(pnl, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(pnl, "modulate:a", 1.0, 0.16)


func _close_modal() -> void:
	modal_layer.visible = false
	_clear(modal_layer)


func _open_discard() -> void:
	# 【★ 2026-10 用户要求】点一张**不关窗**，可以接着弃下一张，直到手牌清空；
	# 而且允许把牌全部弃光（规则层 can_discard 已不再要求保底 1 张）。
	# 做法：每弃一张就原地重建这份列表 —— 弃掉的那张立刻消失，窗口留在原地。
	var v := UITheme.mk_vbox(8)
	var res := gs.discard_res(human)
	var gain: int = int(CardDB.rules.get("discardGain", {}).get(res, 1))
	v.add_child(UITheme.mk_label(
		"按阵营换 1 点资源：天→法　地→财　道具→源　（右键查看卡牌详情）",
		15, UITheme.TEXT_DIM))
	v.add_child(UITheme.mk_label(
		"你弃一张 → 【%s】+%d　·　手牌 %d 张（可以全部弃完；弃置不消耗行动数）"
			% [gs.res_cn(res), gain, human.hand.size()],
		14, UITheme.GOLD))
	var scr := ScrollContainer.new()
	scr.custom_minimum_size = Vector2(0, 290)
	scr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scr)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	scr.add_child(grid)
	if human.hand.is_empty():
		v.add_child(UITheme.mk_label("手牌已空 —— 已经没有可以弃置的牌了。", 15, UITheme.TEXT_DIM))
	for c in human.hand:
		var cv := CardView.new()
		cv.set_card(c)
		cv.set_size_px(126, 224)
		cv.card_pressed.connect(func(_x): _do_discard_one(c.uid))
		# 右键 = 看详细（与手牌 / 场上卡一致的操作习惯）
		cv.card_right_pressed.connect(_show_detail)
		grid.add_child(cv)
	_modal("弃 置 换 资 源", v)


## 弃掉一张：点击音 + 换到【财】时补一声铜钱（用户要求「弃置换资源也有点击音效，
## 还有财的相关音效」）→ 原地重建列表，窗口**不关闭**。
func _do_discard_one(uid: int) -> void:
	if gs == null or not gs.can_discard(human):
		return
	var res := gs.discard_res(human)
	Sfx.play("ui_click", -8.0)
	if not gs.do_discard(uid):
		Sfx.play("ui_error", -14.0)
		return
	if res == "wealth":
		Sfx.play("coin", -5.0)
	else:
		Sfx.play("ui_select", -7.0)
	_refresh()
	_open_discard()


func _show_detail(c: CCard) -> void:
	if c == null:
		return
	var v := UITheme.mk_vbox(8)
	var top := UITheme.mk_hbox(14)
	v.add_child(top)
	var cv := CardView.new()
	cv.set_card(c)
	cv.set_size_px(210, 372)
	cv.selectable = false
	top.add_child(cv)
	var info := UITheme.mk_vbox(5)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(UITheme.mk_label("%s" % c.name, 30, UITheme.GOLD, true))
	info.add_child(UITheme.mk_label("%s · %s ｜ %d 阶 ｜ %s" % [c.faction, c.sub, c.tier, c.group],
		15, UITheme.TEXT_DIM))
	if c.is_tian():
		info.add_child(UITheme.mk_label("【祇】%d / %d　【击】%d　（【祇】= 阶数 + 己方【人】数量）" % [
			c.cur_hp, c.max_hp, c.atk], 15, UITheme.TEXT))
	else:
		info.add_child(UITheme.mk_label("【体】%d / %d　【击】%d　【气伤】%d（对【人】的伤害）" % [
			c.cur_hp, c.max_hp, c.atk, c.atk_qi], 15, UITheme.TEXT))
	if not c.tags.is_empty():
		info.add_child(UITheme.mk_label("标签：" + ", ".join(c.tags), 14, UITheme.PURPLE))
	info.add_child(HSeparator.new())
	for key in ["on_play", "on_remove", "passive", "active"]:
		var s := c.skill(key)
		if s.is_empty():
			continue
		var label: String = {"on_play": "上场技能", "on_remove": "下场技能",
				  "passive": "被动技能", "active": "主动技能"}[key]
		var col: Color = {"on_play": UITheme.JADE, "on_remove": UITheme.CINNABAR,
				"passive": UITheme.PURPLE, "active": UITheme.AZURE}[key]
		var cd_txt := "（冷却 %d 回合）" % int(s.get("cd", 0)) if key == "active" else ""
		info.add_child(UITheme.mk_label("【%s】%s%s" % [label, s.get("name", ""), cd_txt], 16, col))
		info.add_child(UITheme.mk_label(c.skill_desc(key), 14, UITheme.TEXT))
	# 手牌里且轮到自己 → 详情内直接给一个「起乩上场」入口
	if human.find_hand(c.uid) != null:
		info.add_child(HSeparator.new())
		var row := UITheme.mk_hbox(8)
		info.add_child(row)
		var play := UITheme.mk_gold_button("起乩上场", 17)
		play.custom_minimum_size = Vector2(150, 42)
		play.disabled = not gs.is_my_turn(human) or busy or not gs.can_play(human, c.uid)
		play.tooltip_text = "把手牌打到场上（也可以直接把卡拖到场地里）"
		play.pressed.connect(func():
			_close_modal()
			_play_card(c))
		row.add_child(play)
	_modal("卡 牌 详 情", v, 980.0)


# ==================================================================== 拜神 / 敬鬼 全场揭晓
## 点击拜神/敬鬼后，把这张「专属卡牌」放大亮在屏幕正中，
## 让所有玩家都看到这一手拜的是【神】还是【鬼】。
func _show_worship_reveal(kind: String, dice: int) -> void:
	var is_shen := kind == "shen"
	var title := "拜 神 · 请【天】" if is_shen else "敬 鬼 · 请【地】"
	var accent := UITheme.GOLD if is_shen else UITheme.PURPLE
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 150
	add_child(layer)
	# 压暗全场：不让手牌/场面跟这张「全场可见」的牌抢注意力
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.035, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	if fx != null:
		var c := size * 0.5
		fx.ring(c, accent, 240.0)
		fx.burst(c, accent, 30, 280.0, 3.6)
	# 揭晓音：请天用「钟声泛音的空旷感」、请地用「呼啸里的鬼怪喘气」——
	# 两条都取自环境音效库，各只有一次、固定不变（不做随机变体）。
	Sfx.play("worship_shen" if is_shen else "worship_gui", -6.0)

	# 【居中只能靠 CenterContainer 铺满全屏】
	# 不要给还处于 0 尺寸的容器用 PRESET_CENTER —— 那会把「左上角那个点」
	# 钉在屏幕中心，整块内容直接从中心往下挂，牌面会掉到屏幕下缘（踩过）。
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	var box := UITheme.mk_vbox(10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	var tl := UITheme.mk_label("%s（%s）" % [title, human.display_name], 26, accent, true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tl)
	var wrap := CenterContainer.new()
	box.add_child(wrap)
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(0.05, 0.04, 0.08, 0.94), accent, 12, 2, 10, 10))
	wrap.add_child(holder)
	var card := WorshipCard.new()
	card.setup("拜神" if is_shen else "敬鬼",
		"请【天】" if is_shen else "请【地】",
		"res://assets/item/002.webp" if is_shen else "res://assets/item/003.webp",
		"")
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(240, 426)
	card.size = Vector2(240, 426)
	card.scale = Vector2(0.6, 0.6)
	card.pivot_offset = Vector2(120, 213)
	holder.add_child(card)
	var dl := UITheme.mk_label("掷骰：%d 点 → 获得 %d 张【%s】牌入手" % [
		dice, dice, "天" if is_shen else "地"], 20, UITheme.TEXT)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(dl)
	var sl := UITheme.mk_label("全场可见", 14, UITheme.TEXT_DIM)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sl)

	if not CardView.effects_enabled:
		var tw0 := create_tween()
		tw0.tween_interval(1.1)
		tw0.tween_callback(layer.queue_free)
		return
	layer.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(layer, "modulate:a", 1.0, 0.16)
	tw.tween_property(card, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(1.1)
	tw.tween_property(layer, "modulate:a", 0.0, 0.30)
	tw.tween_callback(layer.queue_free)


func _show_guide(step: int) -> void:
	_guide_idx = clampi(step, 0, GUIDE_STEPS.size() - 1)
	var v := UITheme.mk_vbox(10)
	var prog := HBoxContainer.new()
	prog.add_theme_constant_override("separation", 6)
	v.add_child(prog)
	for i in GUIDE_STEPS.size():
		var dot := UITheme.mk_label("●" if i == _guide_idx else "○", 16,
			UITheme.GOLD if i == _guide_idx else UITheme.PANEL_LINE)
		prog.add_child(dot)
	var st: Array = GUIDE_STEPS[_guide_idx]
	v.add_child(UITheme.mk_label(str(st[0]), 26, UITheme.GOLD, true))
	var body := UITheme.mk_label(str(st[1]), 16, UITheme.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(720, 0)
	v.add_child(body)
	v.add_child(HSeparator.new())
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	v.add_child(btns)
	var prev := UITheme.mk_button("← 上一步", 17)
	prev.disabled = _guide_idx == 0
	prev.pressed.connect(func(): _show_guide(_guide_idx - 1))
	btns.add_child(prev)
	var next := UITheme.mk_button(
		"开始游戏 ▶" if _guide_idx == GUIDE_STEPS.size() - 1 else "下一步 →", 17)
	next.custom_minimum_size = Vector2(180, 44)
	next.add_theme_color_override("font_color", UITheme.GOLD)
	next.pressed.connect(func():
		if _guide_idx >= GUIDE_STEPS.size() - 1:
			_close_modal()
		else:
			_show_guide(_guide_idx + 1))
	btns.add_child(next)
	var skip := UITheme.mk_button("跳过引导", 15)
	skip.pressed.connect(_close_modal)
	btns.add_child(skip)
	_modal("新 手 引 导 · 第 %d / %d 步" % [_guide_idx + 1, GUIDE_STEPS.size()], v, 820.0)


## 屏幕中央的即时提示。
## bad=true 时补一记极轻的否定音 —— 视觉上有字、听觉上有「不行」，
## 玩家不必盯着文字也知道这一下没生效。
## 【为什么不默认播】这个函数同时也报成功（购牌 / 请神），
## 那些场景旁边已经有掷骰、铜钱音了，再来一记否定音就自相矛盾。
func _show_toast(text: String, bad: bool = false) -> void:
	if bad:
		Sfx.play("ui_error", -20.0)
	var l := UITheme.mk_label(text, 30, UITheme.GOLD, true)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 200
	l.modulate.a = 0.0
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.18)
	tw.tween_interval(0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func _show_banner(text: String) -> void:
	banner.text = text
	banner.visible = true
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.85, 0.85)
	banner.pivot_offset = banner.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.22)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	tw.set_parallel(false)
	tw.tween_interval(0.8)
	tw.tween_property(banner, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): banner.visible = false)


# ==================================================================== 结算
func _on_game_over(winner_pid: int) -> void:
	if modal_layer.visible:
		return
	busy = true
	var win := winner_pid == human.pid
	if win:
		Sfx.play("win", -2.0)
	else:
		Sfx.play("lose", -2.0)
	if fx != null:
		if win:
			fx.flash_screen(Color(1.0, 0.85, 0.4, 0.22), 0.6)
			fx.burst(get_rect().get_center(), UITheme.GOLD, 40, 320.0, 4.2)
		else:
			fx.flash_screen(Color(0.5, 0.1, 0.15, 0.25), 0.6)

	var v := UITheme.mk_vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var em := TextureRect.new()
	em.texture = UITheme.ui_tex("emblem")
	em.custom_minimum_size = Vector2(0, 120)
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not win:
		em.modulate = Color(0.4, 0.36, 0.4)
	v.add_child(em)
	var title := "摄 伏 成 功" if win else "气 尽 而 伏"
	var col := UITheme.GOLD if win else UITheme.CINNABAR
	var tl := UITheme.mk_label(title, 46, col, true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	var wname := "无人生还"
	if winner_pid >= 0:
		var w := gs.get_player(winner_pid)
		wname = "%s（%s）" % [w.display_name, w.seat] if w else "?"
	var wl2 := UITheme.mk_label("胜者：%s ｜ 共 %d 轮" % [wname, gs.round_no], 18, UITheme.TEXT)
	wl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wl2)
	v.add_child(HSeparator.new())
	var stat := UITheme.mk_vbox(3)
	v.add_child(stat)
	for p in gs.players:
		var sl := UITheme.mk_label(
			"%s【%s】 气 %d/%d ｜ 人×%d ｜ 手牌 %d ｜ 场面 %d ｜ 财 %d" % [
				p.display_name, p.seat, p.qi, p.qi_max, p.ren_count, p.hand.size(),
				p.board.size(), p.wealth], 15,
			UITheme.GOLD if p.pid == winner_pid else UITheme.TEXT_DIM)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat.add_child(sl)
	v.add_child(HSeparator.new())
	var btns := UITheme.mk_hbox(12)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	var rb := UITheme.mk_gold_button("再来一局", 20)
	rb.custom_minimum_size = Vector2(200, 52)
	rb.pressed.connect(func():
		_close_modal()
		rematch.emit(cfg))
	btns.add_child(rb)
	var hb := UITheme.mk_button("返回大厅", 20)
	hb.custom_minimum_size = Vector2(200, 52)
	hb.pressed.connect(func():
		_close_modal()
		exit_to_hall.emit())
	btns.add_child(hb)
	_modal("对 局 结 算", v, 820.0)


# ==================================================================== 测试训练场（Dev）
## 【★ 整段只在 Dev.enabled == true 时可达】
##   正式版 SheFu.exe 里 Dev.enabled 恒为 false：
##     · 顶栏不会多出「开发者设置 / 卡牌库」两枚按钮
##     · 左下立绘与【人】卡不会被接上点击（鼠标事件原样穿透，行为与从前一致）
##     · 规则层所有作弊钩子全部短路
##   代码刻意留在同一份工程里 —— 拆成两份分支才是真正的维护灾难。
func _dev() -> Node:
	if _dev_panel == null or not is_instance_valid(_dev_panel):
		var p := DevPanel.new()
		p.battle = self
		p.name = "DevPanel"
		add_child(p)
		_dev_panel = p
	return _dev_panel


## 顶栏的两枚测试入口（_build 里仅 Dev.enabled 时调用）
func _build_dev_entries(th: BoxContainer) -> void:
	var devb := UITheme.mk_icon_button("taiji",
		"【测试】开发者设置\n对局人数 / 不掉气 / 无冷却 / 无限财·法·源·千纸鹤", 34)
	devb.pressed.connect(func(): _dev().open_menu())
	th.add_child(devb)
	button_refs["dev"] = devb
	var libb := UITheme.mk_icon_button("book",
		"【测试】卡牌库\n拉出任意图鉴卡牌：入手 / 直接上场 / 看特效 / 听音效", 34)
	libb.pressed.connect(func(): _dev().open_library())
	th.add_child(libb)
	button_refs["dev_lib"] = libb


## 左下大本营的两处点击入口：立绘 → 换角色，人卡 → 换【人】
func _wire_dev_probes(portrait: Control, ren_art: Control) -> void:
	var wire := func(c: Control, tip: String, cb: Callable) -> void:
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		c.tooltip_text = tip
		c.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb := ev as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					cb.call())
	wire.call(portrait, "【测试】点击切换角色（12 位）", func(): _dev().open_chara())
	wire.call(ren_art, "【测试】点击切换【人】卡（6 种）", func(): _dev().open_ren())


# ---------------------------------------------------------------- 测试：改配置
## 换角色 —— 只改 PlayerState 里的 chara 字段，然后整体刷新。
## 名牌（名字 / 称号 / 专属色 / 介绍）与左下立绘都从 human.chara 现取，
## 所以这一处赋值就把大本营全部联动更新了，不需要逐个控件去改。
func dev_set_chara(cid: String) -> void:
	var c := CardDB.get_chara(cid)
	if c.is_empty():
		return
	human.chara = c
	human.chara_id = cid
	human.display_name = str(c.get("name", human.display_name))
	cfg["chara_id"] = cid
	_close_modal()
	_refresh()
	Sfx.play("ui_confirm", -4.0)
	_show_toast("测试：角色 → %s" % str(c.get("name", "?")))


## 换【人】大本营
func dev_set_ren(name: String) -> void:
	var r := CardDB.get_ren(name)
	if r.is_empty():
		return
	human.ren = r
	human.ren_type = str(r.get("name", human.ren_type))
	# 起手【气】跟着换（与开局一致）。当前气超过新上限就压回上限，
	# 已经掉到 0（角色刚被打死）则回到满值 —— 测试工具不该因为换个人就卡在死亡状态。
	human.qi_max = maxi(1, int(r.get("qi", human.qi_max)))
	human.qi = clampi(human.qi, 1, human.qi_max)
	# 阴阳师 / 巫女是千纸鹤机制的唯一入口，换过去时先给几只用起来
	if GameState.is_shikigami_ren(human.ren_type):
		human.paper_cranes = maxi(human.paper_cranes, 5)
	cfg["ren"] = name
	_close_modal()
	_refresh()
	Sfx.play("ui_confirm", -4.0)
	_show_toast("测试：【人】→ %s（气上限 %d）" % [human.ren_type, human.qi_max])


## 重开一局（改玩家人数靠它 —— 人数是开局参数，中途改不了）
func dev_restart(n: int) -> void:
	_close_modal()
	var c := cfg.duplicate(true)
	c["player_count"] = clampi(n, 2, 4)
	c["auto_setup"] = true
	c["tutorial"] = false
	c["dev"] = true
	Sfx.play("ui_confirm", -3.0)
	rematch.emit(c)


# ---------------------------------------------------------------- 测试：拉卡
## 从卡池直接取一张卡：入手 / 直接上场。
## 【为什么走 gs.summon() 而不是 do_play()】do_play 要求「轮到自己 + 在场上限内 +
## 场上没有同名卡」，测试工具要的恰恰是绕开这三条（否则想把某张卡拉出来看效果，
## 还得先把对面清干净）。summon() 是规则层自带的「不消耗手牌直接上场」入口，
## 三清铃召唤僵尸走的就是它，所以技能 / 被动 / 光环该触发的都会触发。
## 唯一缺的是**落场演出**（card_played 信号由 do_play 发），这里显式补发一次，
## 于是特效 / 音效 / 飘字与正常上场完全一致。
func dev_give(cid: String, n: int, to_board: bool) -> void:
	var def: Dictionary = CardDB.card_index.get(cid, {})
	if def.is_empty():
		return
	var is_item: bool = str(def.get("faction", "")) == "道具"
	var on_board := to_board and not is_item
	var placed := 0
	for i in maxi(1, n):
		var c := CardDB.instantiate_card(cid)
		if c == null:
			continue
		c.owner_id = human.pid
		c.set_cooldown(0)
		if on_board:
			gs.summon(human, c, true)
			gs.card_played.emit(human.pid, c)
		else:
			human.hand.append(c)
			gs._note_item_obtained(human, c)
		placed += 1
	_refresh()
	Sfx.play("ui_confirm", -6.0)
	_show_toast("测试：%s ×%d → %s" % [str(def.get("name", "?")), placed,
		"上场" if on_board else "手牌"])


## 单独试这张卡的「特效 + 音效」而不真正上场 ——
## 一局只能上一张（同名限制），但演出得能反复看，所以拆出这条预览路径。
## 【★ 注意】「一般卡牌没有上场音效」之后，试听要如实告诉测试者：
##   有专属吼声（龙/虎/犬）就放它；没有就放通用出牌音并**在提示里写明**，
##   否则测试者会以为「这张卡本来就有声音」。
func dev_preview(cid: String, with_sfx: bool) -> void:
	var def: Dictionary = CardDB.card_index.get(cid, {})
	if def.is_empty():
		return
	var c := CardDB.instantiate_card(cid)
	if c == null:
		return
	var at := size * 0.5
	if fx != null:
		var k := c.skill_fx("on_play")
		if k == "":
			k = "buff"
		fx.play_fx(k, at + Vector2(0, -40))
		fx.float_text(at + Vector2(0, -150), "%s · %s" % [c.name, k], UITheme.GOLD, 22)
	var note := "（未放音效）"
	if with_sfx:
		var bk := beast_sfx_key(c)
		if bk != "":
			Sfx.play(bk, -5.0)
			note = "+ 吼声「%s」" % bk
		else:
			Sfx.play("play", -6.0)
			note = "+ 通用出牌音（该卡无专属吼声）"
	else:
		Sfx.play("hit", -8.0)
	_show_toast("测试：%s 特效「%s」%s" % [c.name, c.skill_fx("on_play"), note])


# ==================================================================== 内部类
## 拜神 / 敬鬼：回合冷却制的「专属卡牌」。
## 卡面直接用道具目录里的原画（assets/item/002.webp = 拜神，003 = 敬鬼），
## 用完后整张压暗并自下而上褪去；冷却结束时四边向外发光。
class WorshipCard:
	extends Control
	signal pressed
	var title := "拜神"
	var subtitle := "请【天】"
	var art_path := ""
	var _used := false
	var _hover := false
	var _t := 0.0
	var _glow := 0.0
	var _tex: Texture2D = null

	func _init() -> void:
		custom_minimum_size = Vector2(76, 135)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# 注意：这里**不能**开 clip_contents —— 冷却结束的「四边向外发光」需要溢到按钮之外。
		# 卡面溢出已由 _draw() 里的源图裁剪解决，不需要靠裁剪兜底。
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func setup(p_title: String, p_sub: String, p_art: String, tip: String) -> void:
		title = p_title
		subtitle = p_sub
		art_path = p_art
		tooltip_text = tip
		custom_minimum_size = Vector2(76, 135)

	func _ready() -> void:
		size = Vector2(76, 135)
		custom_minimum_size = size
		if art_path != "":
			_tex = CardView.texture_for(art_path)

	## v = true 表示本回合已用；just_ready 为 true 时补一段「冷却结束四边发光」
	func set_used(v: bool, just_ready: bool = false) -> void:
		if _used and not v and just_ready:
			_glow = 1.0
		_used = v
		set_process(true)
		queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not _used:
				pressed.emit()
				accept_event()

	func _process(delta: float) -> void:
		_t += delta
		if _glow > 0.0:
			_glow = maxf(0.0, _glow - delta * 1.5)
			queue_redraw()
		elif _hover or _used:
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# ---- 卡面（等比居中铺满） ----
		if _tex == null and art_path != "":
			_tex = CardView.texture_for(art_path)
		if _tex != null:
			# 等比「cover」铺满 + 从**源图**里裁掉溢出部分。
			# 不能反过来让它溢出再指望被裁：WorshipCard 没有 clip_contents，
			# 多出来的那 5px 会直接糊到按钮上下两侧，变成两条白杠（就是之前那个白条）。
			var ts := _tex.get_size()
			var k: float = maxf(w / maxf(ts.x, 1.0), h / maxf(ts.y, 1.0))
			var src_w: float = w / k
			var src_h: float = h / k
			var src := Rect2((ts.x - src_w) * 0.5, (ts.y - src_h) * 0.5, src_w, src_h)
			draw_texture_rect_region(_tex, Rect2(Vector2.ZERO, size), src, Color.WHITE)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.09, 0.14), true)
		# ---- 底部题名条 ----
		# 【★ 修「条形码阴影」】旧版用 22 条 1.6px 半透明横条拼顶部渐隐，
		# 条高非整数 + y 是小数 → 摩尔纹条带。改用真渐变纹理一次绘制。
		var band := 30.0
		draw_texture_rect(UITheme.vgrad(Color(0.02, 0.015, 0.04), 0.0, 0.86),
			Rect2(0.0, floorf(h - band - 9.0), w, 9.0), false)
		draw_rect(Rect2(0, floorf(h - band), w, band), Color(0.02, 0.015, 0.04, 0.86), true)
		# 字体必须走缓存：在 _draw() 里 SystemFont.new() 会让中文变成豆腐块
		var f := UITheme.font()
		draw_string(f, Vector2(0, h - band + 15.0), title,
			HORIZONTAL_ALIGNMENT_CENTER, w, 16, UITheme.GOLD)
		draw_string(f, Vector2(0, h - 7.0), subtitle,
			HORIZONTAL_ALIGNMENT_CENTER, w, 11, UITheme.TEXT_DIM)
		# ---- 边框 ----
		var edge := UITheme.GOLD if (_hover and not _used) else Color(0.5, 0.45, 0.55, 0.85)
		if _hover and not _used:
			var pulse := 0.5 + 0.3 * sin(_t * 5.0)
			edge = UITheme.GOLD.lerp(Color.WHITE, pulse * 0.4)
		_outline(Rect2(Vector2(1, 1), size - Vector2(2, 2)), edge, 2.0 if _hover else 1.4, 8.0)
		# ---- 已用：半透明黑压住整张卡 ----
		if _used:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.04, 0.60), true)
			draw_string(f, Vector2(0, h * 0.58), "本回合已用",
				HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(0.82, 0.80, 0.88))
		# ---- 冷却结束的四边外发光（用屏幕像素，不随卡尺寸缩放） ----
		if _glow > 0.0:
			var t: float = clampf(_glow, 0.0, 1.0)
			var g := t * t
			var reach := 5.0 + 18.0 * (1.0 - t)
			# 外层泛光：由外向内叠，做出"光溢出去"的感觉
			for i in 8:
				var u := float(i + 1) / 8.0
				var a2 := Color(1.0, 0.90, 0.60, 0.15 * g * (1.0 - u) * (1.0 - u))
				if a2.a <= 0.004:
					continue
				var o := reach * u
				draw_rect(Rect2(-o, -o, w + o * 2.0, h + o * 2.0), a2, true)
			var gc := Color(1.0, 0.97, 0.86, g)
			draw_line(Vector2(-1, 0), Vector2(w + 1, 0), gc, 2.6, true)
			draw_line(Vector2(-1, h), Vector2(w + 1, h), gc, 2.6, true)
			draw_line(Vector2(0, -1), Vector2(0, h + 1), gc, 2.6, true)
			draw_line(Vector2(w, -1), Vector2(w, h + 1), gc, 2.6, true)

	## 【★ 修「毛刺边缘」】旧版圆角只用 6 段 draw_arc、直边没开 AA → 圆角处是六边形折角、
	## 直边端点硬切。现在：段数按半径自适应（10~24），直边与圆弧全部打开抗锯齿。
	func _outline(rect: Rect2, col: Color, width: float, r: float) -> void:
		var x0 := rect.position.x
		var y0 := rect.position.y
		var x1 := rect.end.x
		var y1 := rect.end.y
		var seg := clampi(int(r * 1.6) + 8, 10, 24)
		draw_line(Vector2(x0 + r, y0), Vector2(x1 - r, y0), col, width, true)
		draw_line(Vector2(x0 + r, y1), Vector2(x1 - r, y1), col, width, true)
		draw_line(Vector2(x0, y0 + r), Vector2(x0, y1 - r), col, width, true)
		draw_line(Vector2(x1, y0 + r), Vector2(x1, y1 - r), col, width, true)
		draw_arc(Vector2(x0 + r, y0 + r), r, PI, PI * 1.5, seg, col, width, true)
		draw_arc(Vector2(x1 - r, y0 + r), r, PI * 1.5, TAU, seg, col, width, true)
		draw_arc(Vector2(x1 - r, y1 - r), r, 0, PI * 0.5, seg, col, width, true)
		draw_arc(Vector2(x0 + r, y1 - r), r, PI * 0.5, PI, seg, col, width, true)
