class_name DevPanel
extends Node
## 测试训练场的弹窗集合（★ 只有测试版 exe 会创建它）
## ------------------------------------------------------------------
## 提供四件事：
##   open_menu()       开发者设置：对局人数 / 不掉气 / 无冷却 / 无限资源 …
##   open_library()    卡牌库：拉出任意图鉴卡牌（入手 / 直接上场 / 试特效 / 试音效）
##   open_chara()      换角色（点左下角立绘进入）
##   open_ren()        换【人】卡（点左下角【人】卡进入）
##
## 【★ 为什么 battle 不加类型标注】
##   标成 BattleScreen 就会形成 BattleScreen ↔ DevPanel 的循环 class_name 引用，
##   GDScript 解析器会直接报 "Could not resolve class"。用 Variant 动态调用即可 ——
##   本文件只调 battle 的公开/约定方法，参数对错在运行期一眼可见（测试工具，够用）。
##
## 【★ 为什么卡牌库是「自带浮层」而不是复用 battle._modal】
##   库里的卡要能点开「卡牌详情」，而详情走的正是 battle._modal —— 它会 _clear()
##   整个 modal_layer。若库也住在 modal_layer 里，点一次详情库就没了。
##   所以库单独挂在 z_index=78（低于 modal_layer 的 80）：详情弹在上面，
##   关掉详情后库**原样还在**，可以继续拉卡。

var battle   ## BattleScreen（Variant，见上）

var _lib_layer: Control = null
## 卡牌库的会话状态（筛选 / 搜索 / 多选集合 …）。
## 【为什么提成成员】UITest 要能以**真实路径**驱动多选与批量上场，
## 而不是在测试里另建一份字典 —— 那种测法测的是测试自己。
var _lib_state: Dictionary = {}


# ================================================================== 开发者设置
func open_menu() -> void:
	var gs: GameState = battle.gs
	var v := UITheme.mk_vbox(10)
	v.add_child(UITheme.mk_label("这些开关只存在于测试版 exe，正式版 SheFu.exe 里没有它们。",
		12, UITheme.TEXT_DIM))
	v.add_child(UITheme.mk_divider(620, 10))
	# ---------------- 对局 ----------------
	v.add_child(_sec("对 局"))
	var row := UITheme.mk_hbox(8)
	row.add_child(UITheme.mk_label("玩家人数", 15, UITheme.TEXT))
	var cur_n: int = gs.players.size()
	for n in [2, 3, 4]:
		var b := UITheme.mk_button("%d 人局" % int(n), 15)
		if cur_n == int(n):
			b.disabled = true          # 当前人数压暗，一眼看出现在是几人局
		b.pressed.connect(func(): battle.dev_restart(int(n)))
		row.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var rb := UITheme.mk_button("重开一局（沿用当前人数）", 15)
	rb.pressed.connect(func(): battle.dev_restart(cur_n))
	row.add_child(rb)
	v.add_child(row)

	v.add_child(UITheme.mk_divider(620, 10))

	# ---------------- 作弊 ----------------
	v.add_child(_sec("作 弊"))
	var flags: Array = [
		{"t": "不掉【气】",
		 "s": "全场（含对手）都不会因掉气而死亡，力竭也不例外。想测胜负条件时关掉它。",
		 "g": func() -> bool: return Dev.no_qi_loss,
		 "w": func(x: bool) -> void: Dev.no_qi_loss = x},
		{"t": "无冷却",
		 "s": "场上主动技能 / 角色专属技能 / 拜神敬鬼 的冷却恒为 0，可以连续发动看演出。",
		 "g": func() -> bool: return Dev.no_cooldown,
		 "w": func(x: bool) -> void: Dev.no_cooldown = x},
		{"t": "无限【财】",
		 "s": "刷新牌面 / 付费取牌 / 凡人阵营升级都不再扣【财】（左下角显示 ∞）。",
		 "g": func() -> bool: return Dev.infinite_wealth,
		 "w": func(x: bool) -> void: Dev.infinite_wealth = x},
		{"t": "无限【法】",
		 "s": "正一道士收徒不再扣【法】。",
		 "g": func() -> bool: return Dev.infinite_fa,
		 "w": func(x: bool) -> void: Dev.infinite_fa = x},
		{"t": "无限【源】",
		 "s": "阴阳师收徒不再扣【源】。",
		 "g": func() -> bool: return Dev.infinite_yuan,
		 "w": func(x: bool) -> void: Dev.infinite_yuan = x},
		{"t": "无限【千纸鹤】",
		 "s": "阴阳师 / 巫女召唤式神不再消耗千纸鹤。",
		 "g": func() -> bool: return Dev.infinite_crane,
		 "w": func(x: bool) -> void: Dev.infinite_crane = x},
		{"t": "不限场位",
		 "s": "解除场上单位数量上限（默认随轮数增长、封顶 7 张）。",
		 "g": func() -> bool: return Dev.no_board_cap,
		 "w": func(x: bool) -> void: Dev.no_board_cap = x},
		{"t": "无限行动",
		 "s": "每回合「主动行动」次数不限（默认 2 次：袭人 + 主动技能共享）。",
		 "g": func() -> bool: return Dev.no_action_limit,
		 "w": func(x: bool) -> void: Dev.no_action_limit = x},
	]
	for f in flags:
		v.add_child(_flag_row(f))

	v.add_child(UITheme.mk_divider(620, 10))
	var tail := UITheme.mk_hbox(8)
	var all_on := UITheme.mk_gold_button("全部开启", 15)
	all_on.custom_minimum_size = Vector2(140, 40)
	all_on.pressed.connect(func():
		Dev.set_all(true)
		battle._close_modal()
		battle._refresh()
		Sfx.play("ui_confirm", -4.0)
		battle._show_toast("测试：作弊全开"))
	tail.add_child(all_on)
	var all_off := UITheme.mk_button("全部关闭", 15)
	all_off.custom_minimum_size = Vector2(140, 40)
	all_off.pressed.connect(func():
		Dev.set_all(false)
		battle._close_modal()
		battle._refresh()
		Sfx.play("ui_back", -4.0)
		battle._show_toast("测试：作弊全关"))
	tail.add_child(all_off)
	var hint := UITheme.mk_label("当前：%s" % Dev.profile(), 11, UITheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tail.add_child(hint)
	v.add_child(tail)

	battle._modal("测 试 训 练 场 · 开发者设置", v, 760.0)


func _sec(t: String) -> Control:
	var h := UITheme.mk_hbox(10)
	h.add_child(UITheme.mk_label(t, 16, UITheme.GOLD))
	h.add_child(UITheme.mk_divider(360, 12))
	return h


## 一行开关：左标题 + 说明，右一个 CheckButton
func _flag_row(f: Dictionary) -> Control:
	var row := UITheme.mk_hbox(12)
	var col := UITheme.mk_vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UITheme.mk_label(str(f["t"]), 16, UITheme.TEXT))
	var sub := UITheme.mk_label(str(f["s"]), 12, UITheme.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(540, 0)
	col.add_child(sub)
	row.add_child(col)
	var cb := CheckButton.new()
	cb.text = "开启"
	cb.button_pressed = bool((f["g"] as Callable).call())
	cb.toggled.connect(func(x: bool):
		(f["w"] as Callable).call(x)
		Sfx.play("ui_toggle", -8.0)
		# 立刻刷新一次：无限财 / 不限场位这类开关会直接改变本屏可见状态，
		# 不刷的话要等下一次动作才看到效果，测试者会以为没生效。
		battle._refresh())
	UITheme.attach_ui_sfx(cb)
	row.add_child(cb)
	return row


# ================================================================== 卡牌库
func open_library() -> void:
	if _lib_layer != null and is_instance_valid(_lib_layer) and _lib_layer.visible:
		return
	if _lib_layer == null or not is_instance_valid(_lib_layer):
		_lib_layer = Control.new()
		_lib_layer.name = "DevLibrary"
		_lib_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# 78 < modal_layer(80)：详情弹窗压在库之上，关掉详情后库还在
		_lib_layer.z_index = 78
		battle.add_child(_lib_layer)
	_lib_layer.visible = true
	_clear(_lib_layer)

	var st := {
		"filter": "全部", "search": "", "sel": "",
		"multi": [],          # 【多选】已选中的卡 id（按点击顺序）
		"grid": null, "cells": {}, "info": null, "acts": null, "count": null,
	}
	# 【★ fill 必须在使用它的 lambda 之前声明】GDScript 的 lambda 捕获的是
	# 声明处可见的名字，写在使用点后面会直接报「Identifier not declared」。
	var fill := func() -> void: _fill(st)
	_lib_state = st

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lib_layer.add_child(dim)

	var pnl := UITheme.mk_panel(Color(0.07, 0.06, 0.11, 0.99), UITheme.GOLD_DIM)
	pnl.position = Vector2(96, 34)
	pnl.custom_minimum_size = Vector2(1728, 0)
	_lib_layer.add_child(pnl)
	var v := UITheme.mk_vbox(8)
	pnl.add_child(v)

	# ---------------- 标题行 ----------------
	var head := UITheme.mk_hbox(12)
	v.add_child(head)
	head.add_child(UITheme.mk_label("卡 牌 库", 22, UITheme.GOLD, true))
	head.add_child(UITheme.mk_label("拉出任意图鉴卡牌来测：技能 / 特效 / 音效 / 布局", 13, UITheme.TEXT_DIM))
	var sp0 := Control.new()
	sp0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp0)
	var cnt := UITheme.mk_label("", 13, UITheme.TEXT_DIM)
	head.add_child(cnt)
	st["count"] = cnt
	var xb := UITheme.mk_icon_button("exit", "关闭卡牌库", 36)
	xb.pressed.connect(close_library)
	head.add_child(xb)

	# ---------------- 筛选行 ----------------
	var chips := UITheme.mk_hbox(8)
	v.add_child(chips)
	chips.add_child(UITheme.mk_label("阵营", 14, UITheme.TEXT_DIM))
	for fac in ["全部", "天", "地", "道具"]:
		var c := UITheme.mk_button(str(fac), 14)
		c.custom_minimum_size = Vector2(88, 36)
		c.pressed.connect(func():
			st["filter"] = str(fac)
			fill.call())
		chips.add_child(c)
	chips.add_child(UITheme.mk_label("　名字", 14, UITheme.TEXT_DIM))
	var le := LineEdit.new()
	le.placeholder_text = "输入卡名筛选，例如「龙」"
	le.custom_minimum_size = Vector2(300, 36)
	le.text_changed.connect(func(t: String):
		st["search"] = t
		fill.call())
	UITheme.attach_ui_sfx(le)
	chips.add_child(le)

	# ---------------- 卡牌网格 ----------------
	var scr := ScrollContainer.new()
	scr.custom_minimum_size = Vector2(0, 620)
	scr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scr)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scr.add_child(grid)
	st["grid"] = grid

	# ---------------- 操作栏 ----------------
	var bar := UITheme.mk_hbox(8)
	v.add_child(bar)
	var info := UITheme.mk_label("点上方任意一张卡加入选择（可多选）→ 在这里批量操作", 14, UITheme.TEXT)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.clip_text = true
	bar.add_child(info)
	st["info"] = info
	var acts := UITheme.mk_hbox(6)
	bar.add_child(acts)
	st["acts"] = acts
	var mk := func(t: String, cb: Callable, gold: bool = false) -> void:
		var b: Button = UITheme.mk_gold_button(t, 15) if gold else UITheme.mk_button(t, 15)
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(cb)
		acts.add_child(b)
	# 【★ 多选】这些动作全都作用于**当前选中的全部卡牌**（见 _give / _selected_ids）
	mk.call("入手 ×1", func(): _give(st, 1, false), true)
	mk.call("入手 ×3", func(): _give(st, 3, false))
	mk.call("直接上场", func(): _give(st, 1, true), true)
	mk.call("铺满 ×6", func(): _give(st, 6, true))
	mk.call("清空选择", func(): _clear_sel(st))
	mk.call("试特效", func(): _preview(st, false))
	mk.call("试特效+音效", func(): _preview(st, true))
	mk.call("详情", func(): _detail(st))

	fill.call()
	_refresh_bar(st)


func close_library() -> void:
	if _lib_layer != null and is_instance_valid(_lib_layer):
		_lib_layer.visible = false
		_clear(_lib_layer)
	Sfx.play("ui_close", -6.0)


## 按当前筛选条件重建网格
func _fill(st: Dictionary) -> void:
	var grid: GridContainer = st["grid"]
	if grid == null:
		return
	_clear(grid)
	var cells: Dictionary = st["cells"]
	cells.clear()
	var fac := str(st["filter"])
	var q := str(st["search"])
	var n := 0
	var all: Array = CardDB.cards.duplicate()
	all.sort_custom(func(a, b):
		if a["faction"] != b["faction"]:
			return a["faction"] < b["faction"]
		if a["sub"] != b["sub"]:
			return a["sub"] < b["sub"]
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) < int(b["tier"])
		return str(a["name"]) < str(b["name"]))
	for d in all:
		if fac != "全部" and str(d.get("faction", "")) != fac:
			continue
		if q != "" and not str(d.get("name", "")).contains(q):
			continue
		n += 1
		var cid := str(d["id"])
		var cell := PanelContainer.new()
		# 切换筛选后，已选中的卡如果还在列表里，边框要保持亮着
		cell.add_theme_stylebox_override("panel", _cell_style(_is_sel(st, cid)))
		grid.add_child(cell)
		cells[cid] = cell
		var cv := CardView.new()
		cv.set_card(CardDB.instantiate_card(cid))
		cv.set_size_px(116, 206)
		cv.foil = int(d.get("tier", 1)) >= 3
		cv.card_pressed.connect(func(_x): _pick(st, cid))
		cv.card_right_pressed.connect(func(_x):
			battle._show_detail(CardDB.instantiate_card(cid)))
		cell.add_child(cv)
	# 【★ 计数文本统一由 _refresh_bar 渲染】这里只负责把「当前筛选出的张数」
	# 存进会话状态。之前计数写死在 _fill 里，导致「点选卡牌」时（只走
	# _refresh_bar、不走 _fill）右上角的「（已选 N）」不刷新 —— 选中了却显示没选。
	st["total"] = n
	# 筛选变化后底部操作栏也要跟着重算（选中集合可能已不在列表里）
	if st.get("info") != null:
		_refresh_bar(st)


## 这张卡现在是否被选中（多选集合里有没有它）
func _is_sel(st: Dictionary, cid: String) -> bool:
	return (st["multi"] as Array).has(cid)


## 选中的卡牌 id 列表（按点击顺序）
func _selected_ids(st: Dictionary) -> Array:
	return (st["multi"] as Array).duplicate()


## 点一张卡 = 加入 / 移出多选集合（再点一次取消）
func _pick(st: Dictionary, cid: String) -> void:
	var multi: Array = st["multi"]
	if multi.has(cid):
		multi.erase(cid)
	else:
		multi.append(cid)
	st["sel"] = cid if multi.has(cid) else (str(multi[multi.size() - 1]) if multi.size() > 0 else "")
	_repaint_cells(st)
	_refresh_bar(st)
	Sfx.play("ui_click", -10.0)


## 清空选择
func _clear_sel(st: Dictionary) -> void:
	(st["multi"] as Array).clear()
	st["sel"] = ""
	_repaint_cells(st)
	_refresh_bar(st)
	Sfx.play("ui_back", -8.0)


## 按当前 multi 集合重刷所有格子的选中边框
func _repaint_cells(st: Dictionary) -> void:
	var cells: Dictionary = st["cells"]
	for cid in cells.keys():
		if is_instance_valid(cells[cid]):
			(cells[cid] as PanelContainer).add_theme_stylebox_override(
				"panel", _cell_style(_is_sel(st, str(cid))))


func _refresh_bar(st: Dictionary) -> void:
	var ids := _selected_ids(st)
	var info: Label = st["info"]
	var acts: HBoxContainer = st["acts"]
	var has := ids.size() > 0
	# 右上角计数：总数 + （已选 N）。★ 必须在这里渲染 —— _pick / _clear_sel
	# 都只经过 _refresh_bar，不经过 _fill。
	var cl: Label = st["count"]
	if cl != null:
		var suffix := ("（已选 %d）" % ids.size()) if has else ""
		cl.text = "共 %d 张%s" % [int(st.get("total", 0)), suffix]
	if ids.size() == 1:
		var cid := str(ids[0])
		var def: Dictionary = CardDB.card_index.get(cid, {})
		var c := CardDB.instantiate_card(cid)
		var sk := "—"
		for key in ["on_play", "active", "passive", "on_remove"]:
			if c != null and not c.skill_name(key).is_empty():
				sk = "%s：%s" % [key, c.skill_name(key)]
				break
		info.text = "%s ｜ %s·%s ｜ %d 阶 ｜ 祇/体 %d ｜ 攻 %d ｜ 气伤 %d ｜ %s" % [
			cid, def.get("faction", ""), def.get("sub", ""), int(def.get("tier", 1)),
			int(def.get("hp", 0)), int(def.get("atk", 0)), int(def.get("atkQi", 0)), sk]
	elif ids.size() > 1:
		var names: Array = []
		for i in mini(ids.size(), 8):
			names.append(str((CardDB.card_index.get(str(ids[i]), {}) as Dictionary).get("name", ids[i])))
		info.text = "已选 %d 张：%s%s　（「直接上场 / 铺满 / 入手」会对**全部选中**生效）" % [
			ids.size(), "、".join(names), " …" if ids.size() > 8 else ""]
	else:
		info.text = "点上方任意一张卡加入选择（可多选）→ 在这里批量操作"
	info.add_theme_color_override("font_color", UITheme.GOLD if has else UITheme.TEXT_DIM)
	for b in acts.get_children():
		var btn := b as Button
		# 「清空选择」在没选中时也该能点（无害）；其余需要至少选一张
		if btn.text != "清空选择":
			btn.disabled = not has


## 批量入手 / 批量上场：作用于**全部选中的卡**
func _give(st: Dictionary, n: int, to_board: bool) -> void:
	var ids := _selected_ids(st)
	if ids.is_empty():
		return
	for cid in ids:
		battle.dev_give(str(cid), n, to_board)


## 试特效只能一张一张看（否则叠在一起分不清），取最后点的那张
func _preview(st: Dictionary, with_sfx: bool) -> void:
	var ids := _selected_ids(st)
	if ids.is_empty():
		return
	if ids.size() > 1:
		battle._show_toast("试特效一次只看一张 —— 已取最后点中的那张", false)
	battle.dev_preview(str(ids[ids.size() - 1]), with_sfx)


## 详情：单选看该卡；多选时按顺序看第一张
func _detail(st: Dictionary) -> void:
	var ids := _selected_ids(st)
	if ids.is_empty():
		return
	if ids.size() > 1:
		battle._show_toast("详情一次只看一张 —— 已取选中的第一张", false)
	battle._show_detail(CardDB.instantiate_card(str(ids[0])))


static func _cell_style(sel: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = UITheme.GOLD if sel else Color(1, 1, 1, 0.07)
	s.set_border_width_all(2 if sel else 1)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(3)
	return s


# ================================================================== 换角色
func open_chara() -> void:
	var v := UITheme.mk_vbox(8)
	v.add_child(UITheme.mk_label("只改「你」的角色（名字 / 称号 / 专属色 / 介绍 / 立绘 / 专属技能）。",
		12, UITheme.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var cur := str(battle.human.chara_id)
	for cd in CardDB.characters:
		var cid := str(cd.get("id", ""))
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(190, 300)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "%s · %s\n%s" % [cd.get("identity", ""), cd.get("title", ""),
			cd.get("intro", "")]
		var cell := UITheme.mk_vbox(3)
		cell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cell)
		var fr := PanelContainer.new()
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.custom_minimum_size = Vector2(184, 246)
		fr.add_theme_stylebox_override("panel",
			UITheme.glow_style(UITheme.PANEL_HI,
				UITheme.GOLD if cid == cur else UITheme.PANEL_LINE, 10, 3 if cid == cur else 1,
				12.0 if cid == cur else 0.0))
		cell.add_child(fr)
		var art := TextureRect.new()
		art.texture = CardView.texture_for(cd.get("face", ""))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.custom_minimum_size = Vector2(176, 238)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.add_child(art)
		var cc := UITheme.chara_color(str(cd.get("color", "")))
		var nl := UITheme.mk_label(str(cd.get("name", "")), 20, cc, true)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(nl)
		var il := UITheme.mk_label("%s · %s" % [cd.get("identity", ""), cd.get("title", "")],
			11, UITheme.TEXT_DIM)
		il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		il.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(il)
		b.pressed.connect(func(): battle.dev_set_chara(cid))
		grid.add_child(b)
	battle._modal("测 试 · 切 换 角 色", v, 1280.0)


# ================================================================== 换【人】卡
func open_ren() -> void:
	var v := UITheme.mk_vbox(8)
	v.add_child(UITheme.mk_label("换的是左下角那张【人】大本营卡：起手【气】上限与每回合的资源机制都跟着换。",
		12, UITheme.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var cur := str(battle.human.ren_type)
	for r in CardDB.ren_cards:
		var nm := str(r.get("name", ""))
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(178, 322)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = str(r.get("note", ""))
		var cell := UITheme.mk_vbox(3)
		cell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cell)
		var fr := PanelContainer.new()
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.custom_minimum_size = Vector2(172, 254)
		fr.add_theme_stylebox_override("panel",
			UITheme.glow_style(UITheme.PANEL_HI,
				UITheme.GOLD if nm == cur else UITheme.PANEL_LINE, 10, 3 if nm == cur else 1,
				12.0 if nm == cur else 0.0))
		cell.add_child(fr)
		var art := TextureRect.new()
		art.texture = CardView.texture_for(r.get("art", ""))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.custom_minimum_size = Vector2(164, 246)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.add_child(art)
		var nl := UITheme.mk_label(nm, 20, UITheme.GOLD, true)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(nl)
		var ql := UITheme.mk_label("起手【气】%d" % int(r.get("qi", 12)), 14, UITheme.QI)
		ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(ql)
		var dl := UITheme.mk_label(str(r.get("note", "")), 11, UITheme.TEXT_DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(170, 0)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(dl)
		b.pressed.connect(func(): battle.dev_set_ren(nm))
		grid.add_child(b)
	battle._modal("测 试 · 切 换 【人】 卡", v, 1280.0)


# ================================================================== 小工具
func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()
