class_name CodexScreen
extends Control
## 图鉴：卡池浏览 / 角色档案 / 规则速查

signal closed

var _tabs: TabContainer
var _filter_faction := "全部"
var _filter_sub := "全部"
var _filter_tier := 0
var _grid: GridContainer
var _count_lbl: Label
var _detail_layer: Control
var _search := ""


func _ready() -> void:
	_build()
	_build_tree()
	_rebuild_grid()


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(UITheme.mk_label("《摄伏》图 鉴", 34, UITheme.GOLD, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := UITheme.mk_button("← 返回大厅", 18)
	back.pressed.connect(func():
		Sfx.play("ui_back", -6.0)
		closed.emit())
	head.add_child(back)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 18)
	root.add_child(_tabs)

	_tabs.add_child(_make_card_tab())
	_tabs.add_child(_make_chara_tab())
	_tabs.add_child(_make_rules_tab())

	_detail_layer = Control.new()
	_detail_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_layer.visible = false
	add_child(_detail_layer)


# ==================================================================== 卡池
var _tree: Tree
var _grid_scr: ScrollContainer
var _search_edit: LineEdit
var _sel_top := ""                    ## "" = 全部
var _sel_path: Array = []             ## 原始 PNG 目录层级前缀
var _top_cn := {"tian": "天", "di": "地", "item": "道具", "ren": "人"}


func _make_card_tab() -> Control:
	var wrap := UITheme.mk_vbox(8)
	wrap.name = "卡池（%d 张）" % CardDB.draft_pool.size()

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 250
	wrap.add_child(split)

	# ---------- 左：目录树（按原始 PNG 存储层级） ----------
	var left := UITheme.mk_panel(UITheme.PANEL, UITheme.PANEL_LINE)
	left.custom_minimum_size = Vector2(240, 0)
	split.add_child(left)
	var lv := UITheme.mk_vbox(4)
	left.add_child(lv)
	lv.add_child(UITheme.mk_label("目录（按图片层级）", 15, UITheme.GOLD_DIM))
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.allow_reselect = true
	_tree.add_theme_font_size_override("font_size", 14)
	_tree.item_selected.connect(_on_tree_selected)
	lv.add_child(_tree)

	# ---------- 右：搜索 + 筛选 + 网格 ----------
	var right := UITheme.mk_vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	# 搜索行
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	right.add_child(srow)
	srow.add_child(UITheme.mk_label("搜索", 14, UITheme.TEXT_DIM))
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "输入卡名 / 目录 / 标签 / 技能描述…"
	_search_edit.custom_minimum_size = Vector2(340, 34)
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(func(_t):
		_search = _search_edit.text.strip_edges()
		_rebuild_grid())
	srow.add_child(_search_edit)
	_count_lbl = UITheme.mk_label("", 13, UITheme.TEXT_DIM)
	srow.add_child(_count_lbl)

	# 筛选行：阵营 + 类别 + 阶数
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 6)
	right.add_child(frow)
	frow.add_child(UITheme.mk_label("阵营", 14, UITheme.TEXT_DIM))
	for f in ["全部", "天", "地", "道具"]:
		frow.add_child(_chip(f, func():
			_filter_faction = f
			_sel_top = {"天": "tian", "地": "di", "道具": "item"}.get(f, "")
			_sel_path = []
			_sync_tree_sel()
			_rebuild_grid()))
	frow.add_child(UITheme.mk_label("  类别", 14, UITheme.TEXT_DIM))
	for s in ["全部", "佛", "神", "妖", "鬼", "魔", "奇兽", "道具"]:
		frow.add_child(_chip(s, func():
			_filter_sub = s
			if s == "全部":
				_sel_path = []
			else:
				_sel_top = ""
				_sel_path = ["道具"] if s == "道具" else [s]
			_sync_tree_sel()
			_rebuild_grid()))

	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 6)
	right.add_child(orow)
	orow.add_child(UITheme.mk_label("阶数", 14, UITheme.TEXT_DIM))
	for t in [0, 1, 2, 3]:
		var lbl := "全部" if t == 0 else "%d 阶" % t
		orow.add_child(_chip(lbl, func():
			_filter_tier = t
			_rebuild_grid()))
	var clr := UITheme.mk_button("清空筛选", 13)
	clr.pressed.connect(func():
		_search = ""
		if _search_edit: _search_edit.text = ""
		_filter_faction = "全部"
		_filter_sub = "全部"
		_filter_tier = 0
		_sel_top = ""
		_sel_path = []
		_sync_tree_sel()
		_rebuild_grid())
	orow.add_child(clr)

	var scr := ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scr)
	_grid_scr = scr
	_grid = GridContainer.new()
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scr.add_child(_grid)
	return wrap


func _chip(txt: String, cb: Callable) -> Button:
	var b := UITheme.mk_button(txt, 13)
	b.pressed.connect(cb)
	return b


# ---------------- 目录树 ----------------
func _build_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var all := _tree.create_item(root)
	all.set_text(0, "全部卡牌（%d）" % CardDB.cards.size())
	all.set_metadata(0, {"top": "", "path": []})
	# 按 topKey 分组
	var tops_order := ["tian", "di", "item"]
	for tk in tops_order:
		var pool: Array = CardDB.cards.filter(func(d): return str(d.get("topKey", "")) == tk)
		if pool.is_empty():
			continue
		var tnode := _tree.create_item(root)
		tnode.set_text(0, "%s（%d）" % [_top_cn.get(tk, tk), pool.size()])
		tnode.set_metadata(0, {"top": tk, "path": []})
		# 用 path 数组建子层级
		_add_path_children(tnode, pool, [], tk)


## 递归按 path 数组建树
func _add_path_children(parent: TreeItem, pool: Array, prefix: Array, tk: String) -> void:
	# 收集当前层级下所有直接子目录名
	var children := {}
	for d in pool:
		var p: Array = d.get("path", [])
		if p.size() <= prefix.size():
			continue
		var ok := true
		for i in prefix.size():
			if str(p[i]) != str(prefix[i]):
				ok = false
				break
		if not ok:
			continue
		var nm := str(p[prefix.size()])
		children[nm] = true
	for nm in children.keys():
		var sub_prefix := prefix + [nm]
		var cnt := 0
		for d in pool:
			var p2: Array = d.get("path", [])
			if p2.size() < sub_prefix.size():
				continue
			var ok2 := true
			for i in sub_prefix.size():
				if str(p2[i]) != str(sub_prefix[i]):
					ok2 = false
					break
			if ok2:
				cnt += 1
		var node := _tree.create_item(parent)
		var direct := 0
		for d in pool:
			var p3: Array = d.get("path", [])
			if p3.size() == sub_prefix.size():
				var ok3 := true
				for i in sub_prefix.size():
					if str(p3[i]) != str(sub_prefix[i]):
						ok3 = false
						break
				if ok3: direct += 1
		node.set_text(0, "%s（%d）" % [nm, cnt])
		node.set_metadata(0, {"top": tk, "path": sub_prefix.duplicate()})
		_add_path_children(node, pool, sub_prefix, tk)


func _on_tree_selected() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var md: Dictionary = it.get_metadata(0)
	_sel_top = str(md.get("top", ""))
	_sel_path = (md.get("path", []) as Array).duplicate()
	_filter_faction = "全部"
	_filter_sub = "全部"
	_rebuild_grid()


## 筛选变化后同步树的选中态（尽量定位到对应节点）
func _sync_tree_sel() -> void:
	if _tree == null:
		return
	var want_top := _sel_top
	var want_path := _sel_path
	var hit := _find_tree_item(want_top, want_path)
	if hit != null:
		hit.select(0)
		return
	var root := _tree.get_root()
	if root != null and root.get_child_count() > 0:
		root.get_child(0).select(0)


func _find_tree_item(want_top: String, want_path: Array) -> TreeItem:
	var root := _tree.get_root()
	if root == null:
		return null
	for i in root.get_child_count():
		var n := root.get_child(i)
		if _item_matches(n, want_top, want_path):
			return n
		var r := _find_in(n, want_top, want_path)
		if r != null:
			return r
	return null


func _find_in(node: TreeItem, want_top: String, want_path: Array) -> TreeItem:
	for i in node.get_child_count():
		var n := node.get_child(i)
		if _item_matches(n, want_top, want_path):
			return n
		var r := _find_in(n, want_top, want_path)
		if r != null:
			return r
	return null


func _item_matches(n: TreeItem, want_top: String, want_path: Array) -> bool:
	var md: Dictionary = n.get_metadata(0)
	if str(md.get("top", "")) != want_top:
		return false
	var p: Array = md.get("path", [])
	if p.size() != want_path.size():
		return false
	for i in p.size():
		if str(p[i]) != str(want_path[i]):
			return false
	return true


func _path_prefix_ok(d: Dictionary) -> bool:
	if not _sel_path.is_empty():
		var p: Array = d.get("path", [])
		if p.size() < _sel_path.size():
			return false
		for i in _sel_path.size():
			if str(p[i]) != str(_sel_path[i]):
				return false
	return true


func _search_ok(d: Dictionary) -> bool:
	if _search.is_empty():
		return true
	var q := _search.to_lower()
	var parts: Array = [
		str(d.get("name", "")),
		str(d.get("group", "")),
		str(d.get("faction", "")),
		str(d.get("sub", "")),
		" ".join(PackedStringArray(d.get("tags", []))),
		" ".join(PackedStringArray(d.get("path", []))),
		str(d.get("desc", "")),
	]
	# 注意：道具卡的 skills.active 显式为 null，.get(key, {}) 会拿到 null 而非默认值
	var skills: Variant = d.get("skills", null)
	if skills is Dictionary:
		for key in ["on_play", "on_remove", "passive", "active"]:
			var sv: Variant = (skills as Dictionary).get(key, null)
			if not (sv is Dictionary) or (sv as Dictionary).is_empty():
				continue
			parts.append(str((sv as Dictionary).get("name", "")))
			parts.append(str((sv as Dictionary).get("desc", "")))
	var hay := " ".join(PackedStringArray(parts)).to_lower()
	return hay.findn(q) >= 0


func _rebuild_grid() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	var n := 0
	var all: Array = CardDB.cards.duplicate()
	all.sort_custom(func(a, b):
		if a["faction"] != b["faction"]:
			return a["faction"] < b["faction"]
		if a["sub"] != b["sub"]:
			return a["sub"] < b["sub"]
		if a["tier"] != b["tier"]:
			return a["tier"] < b["tier"]
		return a["name"] < b["name"])
	for d in all:
		# 目录树筛选（优先）
		if not _sel_top.is_empty() and str(d.get("topKey", "")) != _sel_top:
			continue
		if not _path_prefix_ok(d):
			continue
		# 快捷筛选（阵营 / 类别 / 阶数）
		if _filter_faction != "全部" and d["faction"] != _filter_faction:
			continue
		if _filter_sub != "全部" and d["sub"] != _filter_sub:
			continue
		if _filter_tier > 0 and int(d.get("tier", 1)) != _filter_tier:
			continue
		if not _search_ok(d):
			continue
		n += 1
		var cv := CardView.new()
		var inst := CardDB.instantiate_card(d["id"])
		cv.set_card(inst)
		cv.set_size_px(112, 199)
		cv.foil = int(d["tier"]) >= 3
		cv.card_pressed.connect(_show_card_detail)
		_grid.add_child(cv)
	if _count_lbl:
		var where := "全部"
		if not _sel_path.is_empty():
			where = " / ".join(PackedStringArray(_sel_path))
		elif not _sel_top.is_empty():
			where = _top_cn.get(_sel_top, _sel_top)
		_count_lbl.text = "　%s ｜ 共 %d 张" % [where, n]


func _show_card_detail(c: CCard) -> void:
	if c == null:
		return
	for ch in _detail_layer.get_children():
		ch.queue_free()
	_detail_layer.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_layer.add_child(dim)
	var pnl := UITheme.mk_panel(UITheme.PANEL, UITheme.GOLD)
	pnl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_detail_layer.add_child(pnl)
	var v := UITheme.mk_vbox(8)
	pnl.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(UITheme.mk_label(c.name + "  详情", 24, UITheme.GOLD, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var cb := UITheme.mk_button("关闭", 15)
	cb.pressed.connect(func():
		_detail_layer.visible = false
		for ch in _detail_layer.get_children():
			ch.queue_free())
	h.add_child(cb)
	v.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)
	var cv := CardView.new()
	body.add_child(cv)
	cv.set_card(c)
	cv.set_size_px(210, 372)
	cv.foil = true
	cv.selectable = false
	var info := UITheme.mk_vbox(5)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(info)
	info.add_child(UITheme.mk_label("%s · %s ｜ %d 阶 ｜ %s" % [c.faction, c.sub, c.tier, c.group],
		16, UITheme.TEXT_DIM))
	if c.is_tian():
		info.add_child(UITheme.mk_label("【祇】%d 　【击】%d 　（祇 = 阶数 + 己方【人】数量）" % [c.max_hp, c.atk],
			15, UITheme.TEXT))
	else:
		info.add_child(UITheme.mk_label("【体】%d 　【击】%d 　【气伤】%d" % [c.max_hp, c.atk, c.atk_qi],
			15, UITheme.TEXT))
	if not c.tags.is_empty():
		info.add_child(UITheme.mk_label("标签：" + ", ".join(c.tags), 14, UITheme.PURPLE))
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
		info.add_child(UITheme.mk_label(s.get("desc", ""), 14, UITheme.TEXT))
	pnl.reset_size()


# ==================================================================== 角色
func _make_chara_tab() -> Control:
	var wrap := UITheme.mk_vbox(8)
	wrap.name = "角色（12）"
	var scr := ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.add_child(scr)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scr.add_child(grid)
	for c in CardDB.characters:
		var pnl := UITheme.mk_panel(UITheme.PANEL_HI, UITheme.PANEL_LINE)
		pnl.custom_minimum_size = Vector2(560, 210)
		grid.add_child(pnl)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		pnl.add_child(h)
		var art := TextureRect.new()
		art.texture = CardView.texture_for(c.get("art", ""))
		art.custom_minimum_size = Vector2(118, 190)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		h.add_child(art)
		var v := UITheme.mk_vbox(3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UITheme.mk_label(c["name"], 24, UITheme.GOLD, true))
		v.add_child(UITheme.mk_label("%s ｜ %s ｜ 【人】%s" % [c["identity"], c["title"], c["renCard"]],
			13, UITheme.TEXT_DIM))
		var sk: Dictionary = c["skill"]
		v.add_child(UITheme.mk_label("专属【%s】CD%d" % [sk.get("name", ""), int(sk.get("cd", 0))],
			15, UITheme.GOLD_DIM))
		var dl := UITheme.mk_label(sk.get("desc", ""), 13, UITheme.TEXT)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(390, 0)
		v.add_child(dl)
		v.add_child(UITheme.mk_label("视觉核心：%s" % c.get("visual", ""), 12, UITheme.TEXT_DIM))
	return wrap


# ==================================================================== 规则
func _make_rules_tab() -> Control:
	var scr := ScrollContainer.new()
	scr.name = "规则速查"
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(1100, 0)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scr.add_child(rt)
	rt.text = _rules_bbcode()
	return scr


func _rules_bbcode() -> String:
	return """
[color=#e8c36a][font_size=26]《摄伏》核心规则速查[/font_size][/color]

[color=#e8c36a][font_size=20]一、一句话概括[/font_size][/color]
《摄伏》= 天地人三才 + 纯回合制手动操控 + 卡牌技能系统 + 财/升级/弃置。
【天】做护法，【地】做刀，【人】是大本营。耗尽对方【气】，最后活下来的玩家获胜。

[color=#e8c36a][font_size=20]二、回合循环（东南西北轮流）[/font_size][/color]
 1. 结算【财】（凡人阵营累加：3、3、4、4、5、5……）
 2. 免费三选一（强制，卡池不含【人】牌）
 3. 可刷新（免费 1 次 → 1 财 → 2 财 → 3 财，每回合重置）
 4. 可购买（3 财买一张，购买后仅刷新购买位）
 5. 拜神 / 敬鬼（每回合 1 次，掷骰得 1–6 张天地牌）
 6. 弃置换资源（弃 1 张牌换 1 点财 / 法 / 源）
 7. 升级【人】（左下角按钮，增加【人】数量）
 8. 起乩（上场，上场后不可下场）
 9. 使用主动技能（点击场上卡牌触发，内置冷却 N 回合）
10. 结束 → 下一位

[color=#e8c36a][font_size=20]三、克制关系[/font_size][/color]
[table=4]
[cell][b]攻击方 / 防守方[/b][/cell][cell][b]【天】[/b][/cell][cell][b]【地】[/b][/cell][cell][b]【人】[/b][/cell]
[cell][b]【天】[/b][/cell][cell]互相制衡[/cell][cell]克制 · 消灭[/cell][cell]无法造成伤害[/cell]
[cell][b]【地】[/b][/cell][cell]被克制[/cell][cell]【鬼】不能打【鬼】[/cell][cell]扣【气】[/cell]
[cell][b]【人】[/b][/cell][cell]不主动攻击[/cell][cell]不主动攻击[/cell][cell]—[/cell]
[/table]

[color=#e8c36a][font_size=20]四、【天】的【祇】[/font_size][/color]
上场【神】【佛】的生命值叫【祇】，与己方【人】数量挂钩：
初始 1 张【人】时，上场【天】的【祇】为 1；每增加 1 张【人】，【祇】+1。

[color=#e8c36a][font_size=20]五、【人】的升级（六种大本营）[/font_size][/color]
 · [color=#4fb286]凡人[/color]：花【财】买人，+2 气
 · [color=#4a90d9]正一道士[/color]：消耗【法】收【徒】，+5 气；对方单位被拔除 / 钉死时获得【法】
 · [color=#8e6fd0]阴阳师[/color]：消耗【源】收【阴阳师】，+2 气；1 个【千纸鹤】召唤 1 个【式神】，2 个【式神】提供 2 点护盾【气】（被拔除后消失，不追伤）
 · [color=#4fb286]巫女[/color]：和凡人一样靠【财】买，+2 气
 · [color=#e8c36a]法师（佛）[/color]：无法获得【财】；每回合免费三选一【护法金刚】；降伏【地】单位获得 1【信众】，+3 气并 +1【阿弥陀佛】；不能被萨满抢牌
 · [color=#c0392b]萨满[/color]：不能升级【人】；无法使用【财】；每回合从各玩家手中随机抢 1 张手牌

[color=#e8c36a][font_size=20]六、卡牌阶数与技能数量[/font_size][/color]
 卡牌的阶数在卡池里就是固定的 —— 图鉴里看到的阶数就是最终阶数，没有升阶路径。
 每张卡（除道具）都有一条【被动】，被动不占技能位、永远生效。
 被动之外还有三个技能位：【上场】（起乩时触发）、【下场】（被拔除时触发）、【主动】（消耗行动次数，带冷却）。
 · 1 阶：只有其中 1 个技能位（要么上场、要么下场、要么主动）
 · 2 阶：有其中 2 个技能位
 · 3 阶：三个技能位全开
 所以看到一张卡有几个技能，就知道它是几阶。

[color=#e8c36a][font_size=20]七、道具卡（无技能，只有功能）[/font_size][/color]
 道具卡不带任何技能，只带一个功能，用完即弃（进弃置区）。
 · 降魔杵：拖到对方场上某张卡上 → 直接拔除该卡
 · 金刚镢：拖到对方场上某张卡上 → 该卡下回合无法行动，被动也被封印
 · 三清铃：拖入场上直接释放 → 召唤 3 张临时【僵尸】（可用），3 回合后全体退场
 · 铜钱剑：拖入场上直接释放 → 己方【人】获得 3 层【辟邪】，每回合消 1 层；
   持有【辟邪】期间，其他玩家无法用【地】卡攻击该【人】
 · 八卦镜：拖入场上直接释放 → 只向自己提示：各方手牌里各有几张【地】卡
 · 金刚钺：拖入对方方向（多人局指向具体玩家）→ 巨钺砸下，对该玩家所有上场卡
   造成 3 点伤害，【地】单位额外受伤
 道具的刷出概率低于其他卡牌，且每一种道具一局最多获得 2 次；
 【拜神】【敬鬼】是开局自带的专属卡，不会出现在三选一里。

[color=#e8c36a][font_size=20]八、护法金刚羁绊[/font_size][/color]
 同时起乩 4 张及以上【护法金刚】→ 获得 1 张【降魔杵】。
 降魔杵拿在手里，拖到对方场上卡牌上即可直接拔除。

[color=#e8c36a][font_size=20]九、多余卡牌的三条出路[/font_size][/color]
 弃置换资源（换财 / 法 / 源）｜ 喂给【人】升级（长期投资）｜ 当消耗品（道具）
 [color=#c0392b]关键：多余卡牌不是废牌，是资源。[/color]

[color=#e8c36a][font_size=20]十、关键心法[/font_size][/color]
 · 手牌安全，场上危险。上场才可能被拔除。
 · 被拔除不是白死，有【下场技能】。
 · 不上场【天】，【人】就是直接被攻击的对象。
 · 【神】【佛】无法对【人】造成伤害，所以【地】才是刀。
"""
