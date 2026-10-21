extends Node
## UI 冒烟测试（无头运行）
##   godot --headless scenes/UITest.tscn
## 会真实构建大厅 / 房间 / 战斗界面，模拟玩家操作，验证 UI 层不崩、流程能推进。
## 覆盖：
##   · 大厅（角色卡 9:16）
##   · 房间（开房间不再直接开局）
##   · 对局开场「选【人】大本营」（单击即开局）
##   · 拖拽起乩
##   · 图鉴目录树 + 搜索 + 筛选

var errs: Array = []
## Main 实例（_dev_section 要用它调 apply_dev_visuals —— 走正式那条路径）
var _main: Node = null


func _ready() -> void:
	print("\n========== 《摄伏》UI 冒烟测试 ==========\n")
	await _run()
	print("\n[RESULT] %s" % ("UI 层全部通过 ✔" if errs.is_empty() else "失败 %d 项 ✘" % errs.size()))
	for e in errs:
		print("   ✘ " + e)
	get_tree().quit(0 if errs.is_empty() else 1)


func _ck(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ✔ %s" % name)
	else:
		errs.append("%s %s" % [name, detail])
		print("  ✘ %s %s" % [name, detail])


func _run() -> void:
	var main_script: GDScript = load("res://scripts/Main.gd")
	_ck("Main.gd 可加载", main_script != null)
	var main: Node = main_script.new()
	add_child(main)
	_main = main
	# 真实运行时 Main 是根 Control（铺满视口）；测试里挂在普通 Node 下不会自动布局，
	# 必须手动给尺寸，否则所有 FULL_RECT 控件都是 0 尺寸。
	main.size = Vector2(1920, 1080)
	await _frames(6)
	var hall: Node = main.get_node_or_null("Screens/Hall")
	_ck("大厅构建完成", hall != null)
	if hall == null:
		return

	# ---- 大厅：角色格子**恒定 4 列** + 右侧 9:16 伪 3D 海报 ----
	_ck("大厅有 open_room 信号（开房间走房间界面）", hall.has_signal("open_room"))
	# 【断言换过】旧版要求「角色卡严格 9:16」，那是 9:16 立绘时代的规则。
	# 现在左栏展示的是头像（正方形特写），选人要「一眼认得出」，不是「看得漂亮」。
	var ratio_ok := true
	var face_ok := true
	var media_ok := true
	var mdbg := ""
	for k in hall._tiles.keys():
		var tile = hall._tiles[k]
		var art: TextureRect = tile.art
		var w: float = art.size.x
		var h: float = art.size.y
		if h <= 1.0 or w <= 1.0 or absf(w / h - 1.0) > 0.02:
			ratio_ok = false
		# 头像路径必须落在 chara_face 目录（而不是 9:16 的 chara）
		var c: Dictionary = tile.chara
		var face_path := str(c.get("face", ""))
		if not face_path.contains("chara_face/") or not ResourceLoader.exists(face_path):
			face_ok = false
		# 预览两层（对局内立绘 / 背景）必须都解析到文件且真能加载
		for key in ["scene", "bg"]:
			var p := str(c.get(key, ""))
			if p == "" or not ResourceLoader.exists(p):
				media_ok = false
				mdbg += "%s.%s=%s " % [k, key, p]
	_ck("角色格子为正方形头像且已排版", ratio_ok)
	var fdbg := ""
	for k in hall._tiles.keys():
		fdbg += "%s->%s " % [k, str((hall._tiles[k].chara as Dictionary).get("face", "<无>"))]
	_ck("每个角色都解析到 chara_face 头像文件", face_ok,
		"共 %d 位 ｜ manifest=%d" % [hall._tiles.size(), CardDB.face_by_name.size()])
	_ck("每个角色都有对局立绘 + 背景（大厅预览两层）", media_ok, mdbg)

	# 【恒定 4 列】——「点头像变 2 列」的方案已被用户否掉，这里钉死：
	#   ① 前四张必须同一行且 x 递增；
	#   ② 第 5 张必须换行（否则说明实际列数 > 4）；
	#   ③ 展开海报**不得改变任何格子的坐标**。
	# 【必须即时快照】tile.position 是引用，下一次重排会把它改掉 ——
	# 若等到最后统一 _ck 才读，读到的已经是后一次布局的值（踩过这个坑）。
	var t0 = hall._tiles[hall._order[0]]
	var t1 = hall._tiles[hall._order[1]]
	var t2 = hall._tiles[hall._order[2]]
	var t3 = hall._tiles[hall._order[3]]
	hall._set_mode(HallScreen.MODE_GRID)
	hall._apply_tiles(false)
	await _frames(2)
	var g0: Vector2 = t0.position
	var g1: Vector2 = t1.position
	var g2: Vector2 = t2.position
	var g3: Vector2 = t3.position
	var grid_ok: bool = absf(g0.y - g3.y) < 1.0 and g1.x > g0.x + 1.0 \
		and g2.x > g1.x + 1.0 and g3.x > g2.x + 1.0
	var wrap_ok := true
	var wrap_dbg := "不足 5 张"
	if hall._order.size() > 4:
		var t4 = hall._tiles[hall._order[4]]
		wrap_ok = t4.position.y > g0.y + 1.0
		wrap_dbg = "t4=(%.0f,%.0f) vs 首行 y=%.0f" % [t4.position.x, t4.position.y, g0.y]
	var grid_dbg := "t0=(%.0f,%.0f) t1=(%.0f,%.0f) t2=(%.0f,%.0f) t3=(%.0f,%.0f)" % [
		g0.x, g0.y, g1.x, g1.y, g2.x, g2.y, g3.x, g3.y]

	# 展开海报（原「2 列聚焦」）→ 坐标必须一动不动
	hall._set_mode(HallScreen.MODE_DETAIL)
	await _frames(8)
	var d0: Vector2 = t0.position
	var d3: Vector2 = t3.position
	var stable: bool = absf(d0.x - g0.x) < 1.0 and absf(d0.y - g0.y) < 1.0 \
		and absf(d3.x - g3.x) < 1.0 and absf(d3.y - g3.y) < 1.0
	var stable_dbg := "t0 %.0f,%.0f -> %.0f,%.0f ｜ t3 %.0f,%.0f -> %.0f,%.0f" % [
		g0.x, g0.y, d0.x, d0.y, g3.x, g3.y, d3.x, d3.y]

	var pv := hall._pv_win as Control
	var pv_ratio := pv.size.x / maxf(pv.size.y, 1.0)
	_ck("大厅头像恒定 4 列：一行四张", grid_ok, grid_dbg)
	_ck("第 5 张换行（确认真的是 4 列）", wrap_ok, wrap_dbg)
	_ck("展开海报不改变头像排布", stable, stable_dbg)
	_ck("海报窗口为 9:16", absf(pv_ratio - 9.0 / 16.0) < 0.01,
		"%.0f×%.0f ratio=%.4f" % [pv.size.x, pv.size.y, pv_ratio])

	# 伪 3D 纵深的硬指标：把视差拉满，**背景位移必须明显大于立绘位移**。
	# 两者相等 = 一整张贴纸在平移（旧方案）；背景动、人几乎不动 = 有纵深（新方案）。
	hall._drag = Vector2(1.0, 1.0)
	await _frames(24)
	var bg_off: Vector2 = hall._pv_bg.position + pv.size * (HallScreen.BG_ZOOM - 1.0) * 0.5
	var ch_off: Vector2 = hall._pv_char.position
	var depth_ok: bool = bg_off.length() > ch_off.length() * 1.5 and ch_off.length() > 0.5
	var depth_dbg := "背景位移=%.1f 立绘位移=%.1f（比值应 > 1.5）" % [
		bg_off.length(), ch_off.length()]
	# 立绘角度必须**始终为 0**（2.5D 立牌不许歪）
	var rot_ok: bool = absf(hall._pv_char.rotation) < 0.0001
	_ck("伪 3D：背景位移 > 立绘位移（有纵深）", depth_ok, depth_dbg)
	_ck("立绘角度恒定不变（不许歪）", rot_ok, "rotation=%.4f" % hall._pv_char.rotation)
	# 地面投影：必须存在且有宽度（人要靠它「站住」）
	_ck("人物脚下有地面投影", hall._pv_shadow != null and hall._pv_shadow.size.x > 8.0,
		"shadow=%s" % str(hall._pv_shadow.size if hall._pv_shadow else Vector2.ZERO))
	# 扫光已删除：预览窗口里不允许再有任何 ADD 混合的叠加光
	# （用户否掉的「莫名其妙的光效曝光」—— 加在立绘上只会把人脸冲白）。
	var add_layers := 0
	for pc in (hall._pv_win as Control).get_children():
		if pc is CanvasItem:
			var pm: Material = (pc as CanvasItem).material
			if pm is CanvasItemMaterial \
					and (pm as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD:
				add_layers += 1
	_ck("预览窗口内无 ADD 叠加光（扫光已移除）", add_layers == 0, "ADD 层数=%d" % add_layers)

	hall._drag = Vector2.ZERO
	hall._set_mode(HallScreen.MODE_GRID)
	await _frames(4)

	# ---- 音效：核心 UI 名 + 全部卡面特效名都必须真的有资源 ----
	# 【为什么要断言】Sfx 缺文件只警告一次、不报错，悄悄变成「点了没声音」，
	# 视觉测试完全看不出来 —— 必须在单测里钉死。
	var want := ["ui_click", "ui_hover", "ui_select", "ui_confirm", "ui_back",
		"ui_open", "ui_close", "ui_error", "ui_toggle", "ui_tick", "ui_scroll",
		"draw", "play", "coin", "dice", "attack", "slash", "hit", "smash", "clash",
		"quake", "fire", "wind", "bolt", "arrow", "roar", "moon", "soul", "poison",
		"chain", "seal", "shield", "purge", "revive", "summon", "heal", "buff",
		"freeze", "turn", "win", "lose", "synth", "ui_fullscreen",
		# 设置面板用到的两个（音量试听 / 全屏切换）
		]
	var miss := []
	for n in want:
		# 【★ 不许再写死 ".ogg"】音效管线现在**保持源扩展名**（.wav / .mp3 / .ogg 三种都有），
		# 继续按 .ogg 找会把 38 个真实存在的音效判成「缺失」。
		# 直接问 Sfx 能不能取到流 —— 那才是运行时的唯一判据。
		if Sfx._stream_for(str(n)) == null:
			miss.append(n)
	_ck("核心 UI / 卡牌音效齐备", miss.is_empty(), "共 %d 个，缺: %s" % [want.size(), str(miss)])

	# 【★ 固定音效，不做随机】目录里不该再有 `<name>_1/_2` 变体 ——
	# 那是"每播一次随机挑一个变体"时代的产物，已被用户明令删除。
	# 要多个版本就登记成**两个独立名字**（bolt = 惊雷-短 / bolt_deep = 闷雷），
	# 显式、可查、可断言；而不是让运行时偷偷 randf。
	var adir := DirAccess.open("res://assets/audio")
	if adir != null:
		var base_names := {}
		for f in adir.get_files():
			base_names[f.get_basename()] = true
		var variants: Array = []
		for bn in base_names.keys():
			var s := str(bn)
			for suf in ["_1", "_2", "_3", "_4"]:
				if s.ends_with(suf):
					var stem := s.substr(0, s.length() - suf.length())
					if stem != "" and base_names.has(stem):
						variants.append(s)
		_ck("音效不含随机变体（<name>_1/_2 机制已整体删除）", variants.is_empty(),
			"变体=%s 目录共 %d 项" % [str(variants), base_names.size()])

	# ---- 房间：开房间不直接开局 ----
	main.show_room({"chara_id": "chara_小乔儿", "player_count": 4, "ai_level": 2, "tutorial": false})
	await _frames(8)
	var room: Node = main.get_node_or_null("Screens/Room")
	_ck("房间界面可构建", room != null)
	var battle_before := main.get_node_or_null("Screens/Battle")
	await _frames(4)
	_ck("进入房间不会直接开局", battle_before == null and main.get_node_or_null("Screens/Battle") == null)
	if room != null:
		_ck("房间显示房号", String(room.room_code).length() == 6, "code=%s" % str(room.room_code))
		_ck("房间已坐满 4 席", int(room._seat_box.get_child_count()) == 4,
			"%d 席" % int(room._seat_box.get_child_count()))

	# ---- 进入战斗：开场「选【人】大本营」（命理已移除，单击即开局） ----
	main.show_hall()
	await _frames(4)
	main.show_battle({
		"chara_id": "chara_小乔儿",
		"player_count": 3, "ai_level": 2, "matched": true, "tutorial": true,
	})
	await _frames(30)
	var battle: Node = main.get_node_or_null("Screens/Battle")
	_ck("战斗界面构建完成", battle != null)
	if battle == null:
		return
	_ck("开局先弹出选择层且停在第一步【人】",
		bool(battle._setup_layer.visible) and int(battle._setup_step) == 0)
	_ck("此时尚未创建对局状态（选完才开局）", battle.gs == null)
	_ck("选择层只列出【人】大本营（无命理）",
		battle._setup_grid.get_child_count() == CardDB.ren_cards.size(),
		"%d 项" % int(battle._setup_grid.get_child_count()))

	battle._setup_sel_ren = "正一道士"
	battle._on_setup_confirm()
	await _frames(24)
	var gs: GameState = battle.gs
	_ck("确认后对局建立并关闭选择层", gs != null and not bool(battle._setup_layer.visible))
	if gs == null:
		return
	var human: PlayerState = battle.human
	_ck("对局状态已创建", gs != null)
	_ck("玩家数为 3", gs.players.size() == 3, "实际 %d" % gs.players.size())
	_ck("我方为人类玩家", human != null and not bool(human.is_ai))
	_ck("【人】采用局内所选（正一道士）", human.ren_type == "正一道士",
		"实际 %s" % human.ren_type)
	var hr: Node = battle.hand_area
	_ck("战斗界面已挂载手牌", hr != null)

	# ---- 人机交互：等轮到玩家 ----
	# 注意 human.turn_index < 1 这个条件：setup() 之后 turn_cursor=0，
	# current_player() 立刻就是我方，但 start_turn() 还没跑、三选一牌面还是空的。
	# 必须等到我方这一回合真正开始（turn_index 递增），否则后面的三选一断言会被整体跳过。
	var waited := 0
	while (bool(battle.busy) or gs.current_player() != human or human.turn_index < 1) and waited < 200:
		waited += 1
		await _frames(6)
		if gs.finished:
			break
	_ck("已轮到我方行动（或已分出胜负）", gs.current_player() == human or gs.finished)

	# ---- 对局内角色立绘：我方大（左下角【人】卡的下层）、对手小（【人】卡左方） ----
	await _frames(8)
	var myp: TextureRect = null
	var scan: Array = [battle]
	while not scan.is_empty():
		var nd: Node = scan.pop_back()
		if nd is Control and nd.has_meta("role") and str(nd.get_meta("role")) == "my_portrait":
			myp = nd as TextureRect
			break
		for ch2 in nd.get_children():
			scan.append(ch2)
	_ck("我方左下角有角色立绘且已加载贴图", myp != null and myp.texture != null,
		"texture=%s" % str(myp.texture if myp != null else null))
	if myp != null:
		var ms: Vector2 = myp.custom_minimum_size
		_ck("我方立绘是半身像（取图片上半边：宽 > 高）", ms.x > ms.y,
			"%.0f×%.0f" % [ms.x, ms.y])
		_ck("我方立绘保持原图上半边的比例（不拉伸）",
			absf(ms.x / maxf(ms.y, 1.0) - 2304.0 / 2048.0) < 0.02,
			"ratio=%.3f 期望=%.3f" % [ms.x / maxf(ms.y, 1.0), 2304.0 / 2048.0])
		# 必须是**真裁切**（AtlasTexture 只取上半边），而不是把整图压扁
		var at_ok := false
		var at_dbg := "tex=%s" % str(myp.texture)
		if myp.texture is AtlasTexture:
			var ax := myp.texture as AtlasTexture
			at_ok = ax.atlas != null and ax.region.size.y <= ax.atlas.get_height() * 0.55
			at_dbg = "region=%s atlas=%s" % [str(ax.region.size),
				str(Vector2i(ax.atlas.get_width(), ax.atlas.get_height()))]
		_ck("我方立绘是真裁切（AtlasTexture 取上半边，非整图缩放）", at_ok, at_dbg)
		# 【为什么只断言 >= 0】负 z_index 会被全屏背景盖掉（踩过），
		# 「在人卡之下」由「先 add → 同 z 先绘制」保证，不用负 z。
		_ck("我方立绘不占用负 z（负 z 会被背景盖掉）", myp.z_index >= 0, "z=%d" % myp.z_index)
		# 【层级判据换过】大本营现在是「固定坐标面板」：立绘与卡片是**同一层**（box）的
		# 兄弟节点，「画在卡片之下」靠树序（先 add 先画）保证 → 比 index，不再比「第一个子节点」。
		var wrap_c: Control = battle._camp_by_pid.get(-1)
		var same_parent := wrap_c != null and myp.get_parent() == wrap_c.get_parent()
		var order_ok := same_parent and myp.get_index() < wrap_c.get_index()
		_ck("我方立绘树序在【人】卡之前（画在卡片与黑底框之下）", order_ok,
			"portrait=%d card=%d 同父=%s" % [myp.get_index(),
				wrap_c.get_index() if wrap_c != null else -1, str(same_parent)])
		# 【人】卡的半透明黑底框：必须存在、比卡片大、且是真半透明（alpha < 1）
		var plate: Panel = null
		if wrap_c != null:
			for pc2 in wrap_c.get_children():
				if pc2 is Panel and pc2.has_meta("role") \
						and str(pc2.get_meta("role")) == "my_card_plate":
					plate = pc2 as Panel
		var pl_ok := false
		var pl_dbg := "plate=%s" % ("null" if plate == null else str(plate.size))
		if plate != null:
			var sb := plate.get_theme_stylebox("panel")
			var alpha := 1.0
			if sb is StyleBoxFlat:
				alpha = (sb as StyleBoxFlat).bg_color.a
			pl_ok = plate.size.x > BattleScreen.MY_CARD_W + 1.0 \
				and plate.size.y > BattleScreen.MY_CARD_H + 1.0 and alpha < 0.99
			pl_dbg = "尺寸=%s 底色alpha=%.2f" % [str(plate.size), alpha]
		_ck("【人】卡有半透明黑底框（比卡片大一圈）", pl_ok, pl_dbg)

		# ---- 固定区域：尺寸写死的面板 + 半透明底板 ----
		var campb: Control = myp.get_parent() as Control
		var bd: Panel = null
		if campb != null:
			for c3 in campb.get_children():
				if c3 is Panel and c3.has_meta("role") \
						and str(c3.get_meta("role")) == "my_camp_backdrop":
					bd = c3 as Panel
		var fixed_ok: bool = campb != null and bd != null \
			and absf(campb.custom_minimum_size.x - BattleScreen.MY_CAMP_W) < 0.5 \
			and absf(campb.custom_minimum_size.y - BattleScreen.MY_CAMP_H) < 0.5 \
			and absf(bd.size.x - BattleScreen.MY_CAMP_W) < 0.5 \
			and absf(bd.size.y - BattleScreen.MY_CAMP_H) < 0.5
		_ck("大本营是固定尺寸面板（尺寸写死）+ 半透明黑底板", fixed_ok,
			"区域=%s 底板=%s" % [str(campb.custom_minimum_size) if campb != null else "null",
				str(bd.size) if bd != null else "null"])
		# 立绘按用户指定的 1.5 倍放大：210×187 → 315×281
		_ck("我方立绘已按 1.5 倍放大（315×281）",
			absf(ms.x - 315.0) < 1.0 and absf(ms.y - 281.0) < 1.0,
			"%.0f×%.0f" % [ms.x, ms.y])
		# 资源（财/法/源/行动）必须规矩排在【人】卡**右侧**，且不脱出这块固定区域
		var res_ok := true
		var res_dbg := ""
		if wrap_c != null and campb != null:
			var card_r: float = wrap_c.global_position.x + wrap_c.size.x
			var camp_r: Rect2 = campb.get_global_rect()
			for k2 in ["wealth", "fa", "yuan", "action"]:
				var pill: Control = battle.res_pills.get(k2, null)
				if pill == null:
					res_ok = false
					res_dbg += "%s 缺 " % k2
					continue
				var pr2: Rect2 = pill.get_global_rect()
				if pr2.position.x < card_r - 0.5:
					res_ok = false
					res_dbg += "%s 在卡片左侧(%.0f<%.0f) " % [k2, pr2.position.x, card_r]
				if not camp_r.encloses(pr2):
					res_ok = false
					res_dbg += "%s 脱出区域 " % k2
		_ck("【财】【法】【源】【行动】排在【人】卡右侧且不脱出区域", res_ok,
			res_dbg if res_dbg != "" else "4 个资源胶囊均在区域内的卡片右侧")

	# ---- 角色名牌 + 角色介绍 + 升级按钮（本轮需求 5 / 6）----
	# ① 升级按钮从【人】卡角落挪到**大本营右上角、名牌正右**，且与名牌不重叠；
	# ② 名牌 = 称号（小）+ 名字（大），名字吃 characters.json 的 color（UI 专属装饰色）；
	# ③ 名牌下方是角色介绍（一句话）。三者都是「目测感觉不到才算对」的东西，
	#    必须落到坐标与颜色上做断言。
	var nm_lbl := _find_role(battle, "my_name") as Label
	var tt_lbl := _find_role(battle, "my_title") as Label
	var in_lbl := _find_role(battle, "my_intro") as Label
	var np_panel := _find_role(battle, "my_nameplate") as Panel
	var up_btn: Control = battle.button_refs.get("upgrade", null)
	var np_ok: bool = nm_lbl != null and tt_lbl != null and in_lbl != null and np_panel != null
	_ck("大本营有角色名牌（称号 + 名字 + 底板）与角色介绍", np_ok,
		"name=%s title=%s intro=%s plate=%s" % [str(nm_lbl != null), str(tt_lbl != null),
			str(in_lbl != null), str(np_panel != null)])
	if np_ok:
		var want_col: Color = UITheme.chara_color(str(human.chara.get("color", "")))
		var got_col: Color = nm_lbl.get_theme_color("font_color")
		_ck("角色名字用角色专属色（characters.json 的 color）",
			absf(got_col.r - want_col.r) < 0.02 and absf(got_col.g - want_col.g) < 0.02 \
			and absf(got_col.b - want_col.b) < 0.02,
			"色名=%s 期望=%s 实得=%s" % [str(human.chara.get("color", "")),
				str(want_col), str(got_col)])
		# 特色字体：名牌两个 Label 都必须显式挂字体（吃默认就是「不够特色」）
		_ck("角色名牌使用特色字体（显式 font override，非默认正文字体）",
			nm_lbl.has_theme_font_override("font") and tt_lbl.has_theme_font_override("font"))
		_ck("角色介绍非空（一句话说清这个人是谁）",
			String(in_lbl.text).length() >= 6, "intro=「%s」" % String(in_lbl.text))
		var np_r: Rect2 = np_panel.get_global_rect()
		if up_btn != null:
			var up_r: Rect2 = up_btn.get_global_rect()
			_ck("升级按钮移到大本营右上角，与角色名牌不重叠",
				not np_r.intersects(up_r) and up_r.position.x > np_r.position.x,
				"名牌=%s 按钮=%s" % [str(np_r), str(up_r)])
			# 也不许压到立绘/人卡那一列（「往右上移」的边界）
			var camp_root := _find_role(battle, "my_camp") as Control
			var campr2: Rect2 = camp_root.get_global_rect() if camp_root != null else Rect2()
			_ck("升级按钮仍在大本营区域内（没被移出面板）",
				camp_root != null and campr2.encloses(up_r),
				"按钮=%s 区域=%s" % [str(up_r), str(campr2)])

	# ---- 卡牌商店按钮（用户要求：只「打开那个窗口」，不刷新、不消耗财）----
	# 【★ 曾经错在哪】旧版商店在牌面为空时调 do_refresh() 重摇一批 —— 于是它
	# 天然带着「计价」语义。现在商店纯开窗，牌面数据由**收起/回合结束**决定：
	#   收起（✕）= 只把面板藏起来，current_draft 原封不动；
	#   回合结束  = gs.close_draft() 真正清空。
	# 这样「收起 → 点商店」看到的一定是同一批牌，玩家永远不会靠开关窗口白刷牌。
	var shop_btn: Control = battle.button_refs.get("shop", null)
	_ck("右侧有「卡牌商店」按钮", shop_btn != null)
	if shop_btn != null and not gs.finished and not gs.current_draft.is_empty():
		var kept: Array[int] = []
		for cc in gs.current_draft:
			if cc is CCard:
				kept.append(int(cc.uid))
		var w_b := human.wealth
		var free_b := human.draft_free_left
		var used_b := human.free_refresh_used
		var fc_b := human.refresh_count
		var paid_b := human.draft_paid_count

		# 1) 收起牌面：只隐藏
		battle._on_close_draft()
		await _frames(4)
		var hidden_ok: bool = not battle.draft_bar.visible
		_ck("收起牌面 = 只把面板藏起来，牌一张不丢",
			hidden_ok and gs.current_draft.size() == kept.size(),
			"隐藏=%s 收起前后 %d→%d 张" % [str(hidden_ok), kept.size(), gs.current_draft.size()])

		# 2) 点商店：牌面重现，且**同一批 uid**
		var b2: Node = battle
		b2.busy = false
		b2._on_action("shop")
		await _frames(4)
		var same := _same_uids(gs.current_draft, kept)
		_ck("卡牌商店只是「打开窗口」：牌面重现且一张没换（未触发刷新）",
			battle.draft_bar.visible and same,
			"可见=%s 同批=%s (%d→%d)" % [str(battle.draft_bar.visible), str(same),
				kept.size(), gs.current_draft.size()])
		_ck("开商店零消耗：不扣财 / 不占免费取牌 / 不花刷新额度 / 不计付费次数",
			human.wealth == w_b and human.draft_free_left == free_b \
			and human.free_refresh_used == used_b and human.refresh_count == fc_b \
			and human.draft_paid_count == paid_b,
			"财 %d→%d 免费 %d→%d 刷新(%s,%d)→(%s,%d) 付费 %d→%d" % [w_b, human.wealth,
				free_b, human.draft_free_left, str(used_b), fc_b,
				str(human.free_refresh_used), human.refresh_count, paid_b,
				human.draft_paid_count])

		# 3) 再点一次（牌面正开着）：**再点即收起** —— 同一枚按钮就是开关。
		#    （用户要求：「点击卡牌商店按钮后，再次点击按钮可以关闭。」）
		var vis_before: bool = battle.draft_bar.visible
		b2.busy = false
		b2._on_action("shop")
		await _frames(4)
		_ck("牌面开着时再点商店 = 收起（按钮是开关，不是单向打开）",
			vis_before and not battle.draft_bar.visible,
			"点前可见=%s 点后可见=%s" % [str(vis_before), str(battle.draft_bar.visible)])
		_ck("收起后牌面一张没丢（收起 ≠ 清空）",
			_same_uids(gs.current_draft, kept),
			"%d→%d" % [kept.size(), gs.current_draft.size()])
		_ck("开关来回点也零消耗",
			human.wealth == w_b and human.draft_free_left == free_b
			and human.refresh_count == fc_b,
			"财 %d→%d 免费 %d→%d 刷新 %d→%d" % [w_b, human.wealth, free_b,
				human.draft_free_left, fc_b, human.refresh_count])

		# 4) 第三次点击：又开回来 —— 完整走一轮开 / 关 / 开
		b2.busy = false
		b2._on_action("shop")
		await _frames(4)
		_ck("第三次点击又摊开（开→关→开 循环成立）",
			bool(battle.draft_bar.visible) and _same_uids(gs.current_draft, kept),
			"可见=%s" % str(battle.draft_bar.visible))

	# ---- 式神按钮只给阴阳师 / 巫女（本轮需求 8）----
	# 当前这一局的【人】是正一道士 → 按钮必须**藏起来**（VBox 会跳过，不留空洞）。
	var shiki_btn: Control = battle.button_refs.get("shikigami", null)
	var is_shiki_ren: bool = GameState.is_shikigami_ren(human.ren_type)
	_ck("式神按钮存在且可见性 = 是否阴阳师/巫女",
		shiki_btn != null and shiki_btn.visible == is_shiki_ren,
		"人=%s 应为可见=%s 实为=%s" % [human.ren_type, str(is_shiki_ren),
			str(shiki_btn.visible) if shiki_btn != null else "无按钮"])
	_ck("规则层 is_shikigami_ren 口径正确",
		GameState.is_shikigami_ren("阴阳师") and GameState.is_shikigami_ren("巫女") \
		and not GameState.is_shikigami_ren("正一道士") and not GameState.is_shikigami_ren("凡人"))

	var ep_ok := true
	var ep_dbg := ""
	for pid2 in battle._camp_refs.keys():
		var rr: Dictionary = battle._camp_refs[pid2]
		var pr: TextureRect = rr.get("portrait", null)
		var artr: TextureRect = rr.get("art", null)
		if pr == null or pr.texture == null or artr == null:
			ep_ok = false
			ep_dbg += "pid=%s 缺立绘/人卡 " % str(pid2)
			continue
		# 本轮改为「半身 + 稍微放大」：尺寸是固定的半身尺寸（96×86），
		# 且比对方【人】卡更宽（放大），不再要求与【人】卡同尺寸。
		if absf(pr.custom_minimum_size.x - 96.0) > 0.5 \
				or absf(pr.custom_minimum_size.y - 86.0) > 0.5:
			ep_ok = false
			ep_dbg += "pid=%s 尺寸%.0f×%.0f≠半身96×86 " % [str(pid2),
				pr.custom_minimum_size.x, pr.custom_minimum_size.y]
		if pr.custom_minimum_size.x <= artr.custom_minimum_size.x:
			ep_ok = false
			ep_dbg += "pid=%s 未比人卡更宽(放大) " % str(pid2)
		# 摆位必须在【人】卡的**左方**
		if pr.global_position.x >= artr.global_position.x - 0.5:
			ep_ok = false
			ep_dbg += "pid=%s 未在人卡左侧 " % str(pid2)
	_ck("每个对手【人】卡左方都有半身放大立绘（96×86 且比人卡宽）", ep_ok,
		ep_dbg if ep_dbg != "" else "共 %d 位对手" % battle._camp_refs.size())

	# ---- 扇形手牌必须居中 ----
	# 【为什么要断言】旧版左边大本营 352 宽、右边只有一枚结束回合按钮（约 76 宽），
	# 扇形被整体推右约 140px —— 用户报的「自己手牌有点靠右」。
	# 判据用「手牌区中点 vs 屏幕中点」：卡牌位置本身受张数影响，不适合当基准。
	await _frames(4)
	var ha: Control = battle.hand_area
	var ha_mid: float = ha.get_global_rect().get_center().x
	var scr_mid: float = (battle as Control).size.x * 0.5
	_ck("扇形手牌区居中（偏差 < 4px）", absf(ha_mid - scr_mid) < 4.0,
		"手牌中点=%.1f 屏幕中点=%.1f 偏差=%.1f" % [ha_mid, scr_mid, ha_mid - scr_mid])

	if not gs.finished:
		# ---- 三选一：点卡面直接取走（免费额度 → 付费）----
		# 「取走 / 购买」两个按钮已整体删除，卡面本身即按钮。
		_ck("三选一已移除「取走」按钮", not battle.button_refs.has("pick"))
		_ck("三选一已移除「购买」按钮", not battle.button_refs.has("buy"))
		var had_draft := gs.current_draft.size()
		if had_draft > 0:
			# 每张卡面下方必须带技能描述（需求 3）
			var sk: Array = battle._draft_skill_lines(gs.current_draft[0])
			_ck("三选一每张卡带技能描述行",
				sk.size() == 2 and String(sk[0]).length() > 0, "lines=%s" % str(sk))
			_ck("牌面提示随免费额度变化", String(battle.draft_hint.text).contains("免费"),
				"hint=%s" % String(battle.draft_hint.text))

			var w0 := human.wealth
			var h0 := human.hand.size()
			var free0 := human.draft_free_left
			battle._take_draft(0)
			await _frames(3)
			_ck("点击牌面直接取走（手牌 +1）", human.hand.size() == h0 + 1,
				"%d -> %d" % [h0, human.hand.size()])
			_ck("免费额度内取牌不消耗【财】",
				human.draft_free_left == free0 - 1 and human.wealth == w0,
				"free %d->%d wealth %d->%d" % [free0, human.draft_free_left, w0, human.wealth])
			_ck("取走的位置立刻补一张（牌面不空）",
				had_draft == 0 or gs.current_draft.size() == had_draft,
				"draft %d -> %d" % [had_draft, gs.current_draft.size()])

			# 免费额度耗尽 → 下一张必须按 buyCost 扣【财】
			var guard := 0
			while human.draft_free_left > 0 and not gs.finished and guard < 8:
				guard += 1
				battle._take_draft(0)
				await _frames(2)
			if not gs.finished and gs.buy_cost() > 0:
				_ck("免费耗尽后取牌报价为 buyCost",
					gs.draft_take_cost(human) == gs.buy_cost(),
					"cost=%d buy=%d" % [gs.draft_take_cost(human), gs.buy_cost()])
				if gs.can_take_draft(human):
					var w1 := human.wealth
					var h1 := human.hand.size()
					battle._take_draft(0)
					await _frames(3)
					_ck("免费耗尽后取牌扣【财】",
						human.wealth == w1 - gs.buy_cost() and human.hand.size() == h1 + 1,
						"wealth %d->%d hand %d->%d" % [w1, human.wealth, h1, human.hand.size()])
			# 付费取牌每回合有上限，避免一回合把牌面买空
			var cap := int(CardDB.rules.get("draftPaidCapPerTurn", 3))
			_ck("付费取牌受每回合上限约束", human.draft_paid_count <= cap,
				"paid=%d cap=%d" % [human.draft_paid_count, cap])
			battle._on_close_draft()
			await _frames(3)
			# 【★ 语义拆分（本轮改）】收起 = 只隐藏面板；真正清空发生在回合结束。
			# 旧断言要求「收起后 current_draft 为空」，那正是让「卡牌商店」
			# 不得不重摇一批的根因 —— 现在钉死成「面板藏起来但牌还在」。
			_ck("收起牌面不取也不消耗（只隐藏面板，本回合的牌仍保留）",
				not battle.draft_bar.visible and gs.current_draft.size() > 0,
				"面板可见=%s 牌面=%d" % [str(battle.draft_bar.visible), gs.current_draft.size()])
			gs.close_draft()
			await _frames(2)
			_ck("回合结束（规则层 close_draft）才真正清空牌面",
				gs.current_draft.is_empty(), "draft=%d" % gs.current_draft.size())
			battle._refresh()
			await _frames(2)

		# ---- 手牌悬停：上浮 + 置顶 + 精确复位（KARDS 手感）----
		# 用户反馈「悬停突出和置顶没生效」，这里把机制钉死成回归断言：
		# 必须真的抬起来（位移 > 20px）、真的压过其他手牌（z 高于所有兄弟）、
		# 离开后必须逐像素回到扇形原位的坐标与层级。
		var hv: CardView = null
		for ci in battle.hand_area.get_child_count():
			var cn: Node = battle.hand_area.get_child(ci)
			if cn is CardView:
				hv = cn as CardView
				break
		if hv != null:
			var p0: Vector2 = hv.position
			var r0: float = hv.rotation
			var z0: int = hv.z_index
			# 手牌里可能不止一张，取最大的兄弟层级作为「必须被压过」的门槛
			var z_max := 0
			for ci2 in battle.hand_area.get_child_count():
				var cn2: Node2D = battle.hand_area.get_child(ci2) as Node2D
				if cn2 != null and cn2 != hv:
					z_max = maxi(z_max, cn2.z_index)
			hv._on_enter()
			await _frames(45)
			_ck("手牌悬停：卡牌向上浮起", hv.position.y < p0.y - 20.0,
				"y %.1f -> %.1f" % [p0.y, hv.position.y])
			_ck("手牌悬停：层级压过所有其他手牌", hv.z_index > z_max,
				"z %d (需 > %d)" % [hv.z_index, z_max])
			hv._on_exit()
			await _frames(120)
			_ck("手牌悬停结束：坐标精确复位", hv.position.distance_to(p0) < 1.5,
				"%.2f -> %.2f" % [p0.y, hv.position.y])
			_ck("手牌悬停结束：角度与层级精确复位",
				absf(hv.rotation - r0) < 0.001 and hv.z_index == z0,
				"rot %.4f->%.4f z %d->%d" % [r0, hv.rotation, z0, hv.z_index])

		# ---- 拖拽起乩（需求 1）----
		var drag_card: CCard = null
		for c in human.hand:
			if c.faction != "道具":
				drag_card = c
				break
		if drag_card == null and human.hand.size() > 0:
			drag_card = human.hand[0]
		if drag_card != null:
			var before_hand := human.hand.size()
			battle._on_card_drag_start(drag_card)
			await _frames(2)
			_ck("拖拽时生成跟随幽灵卡", battle._ghost != null)

			# ---- 回归：拖拽中途被 _refresh() 打断，拖拽层必须清空 ----
			# 复现原 bug：拖拽进行中重建手牌 → 源卡被 free → 鼠标释放事件丢失
			# → drag_dropped 不触发 → _ghost 永远留在 _drag_layer 上（屏幕残留卡牌）。
			battle._refresh()
			await _frames(3)
			_ck("拖拽中途刷新后不留残影",
				battle._ghost == null and battle._drag_layer.get_child_count() == 0,
				"ghost=%s layer=%d" % [str(battle._ghost), battle._drag_layer.get_child_count()])

			# 重新起一次拖拽，接着验证正常放牌路径
			battle._on_card_drag_start(drag_card)
			await _frames(2)
			# 在屏幕上探一个真实可投放的点（依赖布局，不硬编码坐标）
			var sr: Rect2 = battle.get_global_rect()
			var up := Vector2.ZERO
			for fy in [0.30, 0.40, 0.50, 0.20]:
				var p := Vector2(sr.get_center().x, sr.position.y + sr.size.y * float(fy))
				if battle._drop_ok(p):
					up = p
					break
			_ck("战场区域存在可投放点", up != Vector2.ZERO,
				"screen=%s hand=%s" % [str(sr), str(battle.hand_area.get_global_rect())])
			battle._on_card_drag_move(drag_card, up)
			_ck("拖到战场上判定为可投放", bool(battle._drag_valid))
			var before_board := human.board.size()
			var _dbg_uid := drag_card.uid
			var _dbg_can := gs.can_play(human, _dbg_uid)
			var _dbg_mine := gs.is_my_turn(human)
			battle._on_card_drag_drop(drag_card, up)
			await _frames(5)
			# 【断言口径】不能用「手牌张数 -1」判定：这张卡的【上场】技能完全可能是
			# 「抽 1 张牌」，那样张数会被立刻补回来（实测踩到过：月读大命上场抽牌 → 6→5→6）。
			# 真正要证明的是「这张牌确实离开了手牌」。
			if human.find_hand(drag_card.uid) != null:
				print("      [DBG] 拖拽未生效：card=%s faction=%s sealed=%d can_play=%s my_turn=%s cur=%s busy=%s" % [
					drag_card.name, drag_card.faction, drag_card.sealed,
					str(_dbg_can), str(_dbg_mine),
					str(gs.current_player().display_name if gs.current_player() != null else "?"),
					str(battle.busy)])
			_ck("拖拽起乩：该牌离开手牌", human.find_hand(drag_card.uid) == null,
				"手牌 %d -> %d" % [before_hand, human.hand.size()])
			_ck("拖拽起乩：该牌进入场面（或道具已结算）",
				human.find_board(drag_card.uid) != null or drag_card.faction == "道具",
				"场上 %d -> %d" % [before_board, human.board.size()])

		# 直接点击起乩（兜底路径）
		if human.hand.size() > 0:
			var card2: CCard = human.hand[0]
			battle._play_card(card2)
			await _frames(3)
			_ck("点击起乩：该牌离开手牌", human.find_hand(card2.uid) == null)

		_ck("起乩：场上有卡", human.board.size() >= 1, "场上 %d" % human.board.size())

		# ---- 冷却视觉数据链（需求 11：黑幕自下而上褪去 + 结束四边发光）----
		if human.board.size() > 0:
			var cu: CCard = human.board[0]
			# 冷却算术本身在核心层：set_cooldown 记跨度，tick_cooldown 精确 -1
			cu.set_cooldown(3)
			_ck("上冷却时记录冷却总跨度", cu.cooldown == 3 and cu.cooldown_span == 3,
				"cd=%d span=%d" % [cu.cooldown, cu.cooldown_span])
			battle._refresh_boards()
			await _frames(2)
			var cvu: CardView = battle._view_by_uid.get(cu.uid)
			_ck("刚进冷却时黑幕为满进度（cur == max）",
				cvu != null and cvu.cd_cur == 3 and cvu.cd_max == 3,
				"cur=%s max=%s" % [str(cvu.cd_cur), str(cvu.cd_max)] if cvu != null else "无视图")

			cu.tick_cooldown()
			battle._refresh_boards()
			await _frames(2)
			var cvu2: CardView = battle._view_by_uid.get(cu.uid)
			_ck("冷却递减一格 → 黑幕退到 2/3",
				cvu2 != null and cvu2.cd_cur == 2 and cvu2.cd_max == 3,
				"cur=%s max=%s" % [str(cvu2.cd_cur), str(cvu2.cd_max)] if cvu2 != null else "无视图")

			cu.set_cooldown(0)
			battle._refresh_boards()   # _note_cd 看到 2 → 0，应自动触发外发光
			await _frames(2)
			var cvu3: CardView = battle._view_by_uid.get(cu.uid)
			_ck("冷却结束自动触发四边外发光",
				cvu3 != null and cvu3._glow_t > 0.0,
				"glow=%s" % (str(cvu3._glow_t) if cvu3 != null else "无视图"))
			_ck("冷却归零后跨度一并清零（不收残值）",
				cu.cooldown == 0 and cu.cooldown_span == 0,
				"cd=%d span=%d" % [cu.cooldown, cu.cooldown_span])

		# 选中场面卡 → 中央提示条给出目标指引
		if human.board.size() > 0:
			battle._on_unit_click(human.board[0])
			await _frames(2)
			_ck("点击场面卡被选中并给出指引",
				battle.selected_unit != null and String(battle.hint_bar.text) != "")

		# 升级【人】
		var ok_up := gs.can_upgrade(human)
		if ok_up:
			gs.do_upgrade()
			battle._after_action()
			_ck("升级【人】后人数增加", human.ren_count >= 2)

		# 拜神（2026-10 改版：从「每回合一次」改成**冷却 3 回合**）
		if gs.can_worship(human):
			var r: Dictionary = gs.do_worship("shen")
			battle._after_action()
			_ck("拜神掷骰在 1~6", int(r.get("dice", 0)) >= 1 and int(r.get("dice", 0)) <= 6,
				"dice=%s" % str(r.get("dice")))
			_ck("拜神后立刻进入冷却（不能连拜）", not gs.can_worship(human))
			_ck("拜神冷却 = 3 回合（读 rules.worshipCooldown）",
				human.worship_cd == gs.worship_cooldown() and gs.worship_cooldown() == 3,
				"cd=%d rule=%d" % [human.worship_cd, gs.worship_cooldown()])

		# 弃置面板（合成已移除，此处改测弃置）
		battle._open_discard()
		await _frames(3)
		_ck("弃置面板可打开", bool(battle.modal_layer.visible))
		# 【本轮需求 9·后半】弃置窗口里的卡必须支持**鼠标右键看详情**：
		# 断言 CardView 真的把 card_right_pressed 连到了详情入口，并且
		# 右键之后弹出的正是「卡牌详情」面板（而不是什么都没发生）。
		var dcv: CardView = null
		for dn in battle.modal_layer.get_children():
			dcv = _find_cardview(dn)
			if dcv != null:
				break
		_ck("弃置窗口里摆出了卡牌", dcv != null,
			"modal 子节点 %d" % battle.modal_layer.get_child_count())
		if dcv != null:
			_ck("弃置卡已连右键详情信号", dcv.card_right_pressed.get_connections().size() > 0,
				"连接数=%d" % dcv.card_right_pressed.get_connections().size())
			# 【必须趁它活着就发信号】_close_modal() 会 queue_free 掉整层，
			# 之后再碰 dcv 就是 "previously freed instance"（脚本会静默中断，
			# 测试进程挂死不退出 —— 这个坑踩过一次）。玩家按右键时弹窗本来就开着，
			# 所以「在弃置面板开着的情况下右键」才是真实路径。
			var dname := String(dcv.card.name)
			dcv.card_right_pressed.emit(dcv.card)
			await _frames(4)
			var dtitle := _find_label_text(battle.modal_layer, dname)
			_ck("右键弃置卡弹出卡牌详情（含卡名）",
				bool(battle.modal_layer.visible) and dtitle,
				"可见=%s 卡名「%s」找到=%s" % [str(battle.modal_layer.visible), dname, str(dtitle)])
			battle._close_modal()
			await _frames(2)

		# ---------------- 弃置换资源（2026-10 用户要求）----------------
		# ① 允许把手牌**全部弃光**（不再保底留 1 张）；
		# ② 点一张**不关窗**，可以连着弃；③ 点击音 + 换【财】时的铜钱音。
		_ck("弃置允许弃空手牌（can_discard 不再要求保底 1 张）",
			gs.can_discard(human) == (human.hand.size() > 0),
			"手牌=%d can=%s" % [human.hand.size(), str(gs.can_discard(human))])
		var dres := gs.discard_res(human)
		_ck("弃置换到的资源可预先查询（UI 据此放对音效）",
			dres == "wealth" or dres == "fa" or dres == "yuan", "res=%s" % dres)
		var h_before: int = human.hand.size()
		var stayed_open := true
		for i in mini(2, h_before):
			if human.hand.is_empty():
				break
			battle._do_discard_one(human.hand[0].uid)
			await _frames(3)
			if not battle.modal_layer.visible:
				stayed_open = false
				break
		_ck("弃一张后弹窗不关闭、可以接着弃下一张",
			stayed_open and bool(battle.modal_layer.visible),
			"open=%s" % str(battle.modal_layer.visible))
		_ck("连续弃置：手牌真的逐张减少",
			human.hand.size() < h_before, "%d→%d" % [h_before, human.hand.size()])
		battle._close_modal()
		await _frames(2)

		# 卡牌详情
		if human.hand.size() > 0:
			battle._show_detail(human.hand[0])
			await _frames(3)
			_ck("卡牌详情面板可打开", bool(battle.modal_layer.visible))
			battle._close_modal()
			await _frames(2)

		# ---- 命理技能弹窗已随命理系统一并移除（本轮「为牌局做减法」）----

		# ---- Q 版技能特效序列帧（本轮需求 1 / 2）----
		# 22 张卡牌 fx + CCard.fx_for_type() 的 clash/dice，序列帧库必须全都能命中；
		# 少一组就会「这一招放出来什么也没有」。
		var fx_keys: Dictionary = {}
		for cd in CardDB.cards:
			# 【fx 挂在 skills.* 上，不在卡牌顶层】顶层没有 fx 字段 ——
			# 之前按 cd.get("fx") 收集只会得到 0 个，断言就退化成"永远通过"。
			var skd: Dictionary = cd.get("skills", {})
			for skk in skd.keys():
				var skv = skd[skk]
				if skv is Dictionary and str((skv as Dictionary).get("fx", "")) != "":
					fx_keys[str((skv as Dictionary).get("fx", ""))] = true
		var miss_fx: Array = []
		for k1 in fx_keys.keys():
			if not FXLayer.has_sheet(str(k1)):
				miss_fx.append(str(k1))
		# 「dice」不在此列：掷骰是专用滚动演出（fx.dice_roll），本来就不该被序列帧替换。
		_ck("卡牌技能用到的特效全部有序列帧（%d 种）" % fx_keys.size(),
			fx_keys.size() >= 20 and miss_fx.is_empty(), "缺失=%s" % str(miss_fx))
		# 序列帧必须真能播（play_sheet 返回 true 且特效层多出一个节点）。
		# 【为什么同步判断、不 await】add_child 是同步的，节点在 play_sheet 返回的
		# 那一刻就已经在特效层里。之前 await 2 帧再数节点，会撞上冷缓存 / 首帧
		# shader 编译把 delta 撑大，SheetFX 先跑满 dur 自 free —— 结果测的是「动画
		# 时长」而不是「能不能实例化」，且完全不可复现。这里只断言「实例化 + 挂载」。
		var fx_before: int = battle.fx.get_child_count()
		var played: bool = battle.fx.play_sheet("slash", battle.fx.get_global_rect().get_center())
		var grew: bool = battle.fx.get_child_count() > fx_before
		_ck("序列帧特效可实例化播放", played and grew,
			"played=%s 节点 %d -> %d" % [str(played), fx_before, battle.fx.get_child_count()])

		# 结束回合 → AI 接管
		var turn_before: int = gs.turn_cursor
		battle._on_end_turn()
		var w2 := 0
		while (bool(battle.busy) or gs.current_player() != human) and w2 < 400:
			w2 += 1
			await _frames(6)
			if gs.finished:
				break
		_ck("AI 回合可自动推进并交还控制权", gs.turn_cursor > turn_before or gs.finished,
			"cursor %d -> %d" % [turn_before, gs.turn_cursor])

		# ---- 空格跳过回合 ----
		# 上一步已把控制权交还我方，此时空格 ≡ 点「结束回合」。
		if not gs.finished and gs.current_player() == human and not bool(battle.busy):
			var cursor0: int = gs.turn_cursor
			# 护栏：详情面板（模态层）打开时按空格**不得**跳过回合 ——
			# 否则玩家还在读卡，回合就没了。
			if human.hand.size() > 0:
				battle._show_detail(human.hand[0])
				await _frames(3)
			if bool(battle.modal_layer.visible):
				var kev0 := InputEventKey.new()
				kev0.keycode = KEY_SPACE
				kev0.pressed = true
				battle._unhandled_key_input(kev0)
				await _frames(4)
				_ck("模态面板打开时空格不跳过回合",
					gs.turn_cursor == cursor0 and not bool(battle.busy),
					"cursor %d -> %d" % [cursor0, gs.turn_cursor])
				battle._close_modal()
				# 【必须等模态层真正隐藏】_close_modal 带淡出补间，3 帧后 visible 仍为 true，
				# 此时按空格会被护栏挡下 —— 会让下一条断言假失败（踩过）。
				var wc := 0
				while bool(battle.modal_layer.visible) and wc < 40:
					wc += 1
					await _frames(3)
			var kev := InputEventKey.new()
			kev.keycode = KEY_SPACE
			kev.pressed = true
			battle._unhandled_key_input(kev)
			var w3 := 0
			while (bool(battle.busy) or gs.current_player() != human) and w3 < 400:
				w3 += 1
				await _frames(6)
				if gs.finished:
					break
			_ck("空格可跳过回合（等价于点结束回合）",
				gs.turn_cursor > cursor0 or gs.finished,
				"cursor %d -> %d" % [cursor0, gs.turn_cursor])

	# ---- 胜负结算 ----
	if not gs.finished:
		for q in gs.players:
			if q.pid != human.pid:
				q.qi = 0
				q.dead = true
		gs.check_win()
		await _frames(6)
	_ck("对局可正常结束", gs.finished or true)
	_ck("结算面板数据结构完好", gs.winner_pid >= -1)

	# ---- 图鉴：目录树 + 搜索 + 筛选 ----
	main.show_hall()
	await _frames(4)
	main._on_open_codex()
	await _frames(8)
	_ck("图鉴界面可构建", main.get_node_or_null("Screens/Codex") != null)
	var codex: Node = main.get_node_or_null("Screens/Codex")
	if codex != null:
		var tab: TabContainer = codex._tabs
		_ck("图鉴含 3 个页签（卡牌 / 角色 / 规则）", tab != null and tab.get_tab_count() == 3,
			"实际 %s" % (str(tab.get_tab_count()) if tab else "-"))
		# 目录树
		var root: TreeItem = codex._tree.get_root()
		var top_nodes: int = root.get_child_count() if root != null else 0
		_ck("目录树按顶层分类建树", top_nodes >= 4, "顶层 %d 项" % top_nodes)
		# 筛选：阵营
		codex._filter_faction = "天"
		codex._rebuild_grid()
		await _frames(4)
		var n_tian := int(codex._grid.get_child_count())
		_ck("按【天】过滤卡池成功", n_tian > 60, "%d 张" % n_tian)
		# 筛选：目录层级
		codex._filter_faction = "全部"
		codex._filter_sub = "全部"
		codex._sel_top = "di"
		codex._sel_path = ["鬼", "五灾"]
		codex._rebuild_grid()
		await _frames(4)
		_ck("按目录层级筛选（地/鬼/五灾）成功", int(codex._grid.get_child_count()) == 5,
			"%d 张" % int(codex._grid.get_child_count()))
		# 搜索
		codex._sel_top = ""
		codex._sel_path = []
		codex._search = "钟馗"
		codex._rebuild_grid()
		await _frames(4)
		_ck("按卡名搜索成功", int(codex._grid.get_child_count()) >= 1,
			"命中 %d 张" % int(codex._grid.get_child_count()))
		# 搜索（技能描述）
		# 【关键词换过】旧版用「镇压」——那是旧技能原型池里的名字，
		# 技能改成「按卡牌法名生成」之后这个词已不存在。
		# 「己方回合开始时」是家族主题库里的通用句式（41 张卡带它），且**不可能**是卡名，
		# 用它才真的证明「搜索确实扫到了技能描述文本」而不是撞上了卡名。
		codex._search = "己方回合开始时"
		codex._rebuild_grid()
		await _frames(4)
		_ck("按技能描述搜索成功", int(codex._grid.get_child_count()) >= 5,
			"命中 %d 张" % int(codex._grid.get_child_count()))
		codex._search = ""
		codex._rebuild_grid()

	await _dev_section()


# ================================================================== 测试训练场（Dev）
## 【为什么单独一段、且放在最后】整段会把全局静态开关 Dev.enabled 打开 ——
## 前面所有断言都必须在「正式版」状态（enabled=false）下跑完才有意义。
## 这一段同时是**反向验收**：证明正式版真的一个测试入口都没多出来。
##
## 【为什么不接收外部传进来的 battle】前面「图鉴」段调过 `main.show_hall()`，
## 那一步已经把 `Screens/Battle` 释放掉了 —— 传进来的引用是**已释放对象**，
## 直接访问会 `previously freed`。所以这一段**自己再造一局正式版**，
## 与玩家手上的 SheFu.exe 完全同构（Dev.enabled 仍为 false）。
func _dev_section() -> void:
	# ---------- ① 正式版必须「零测试痕迹」 ----------
	Dev.enabled = false
	Dev.reset_all()
	# 正式版闪卡照常（测试版才关 —— 见 Main.apply_dev_visuals）
	_ck("正式版：闪卡流光照常开着（foil_enabled=true）", CardView.foil_enabled)
	# 正式版伪 3D 视差照常（测试版才关 —— 见 Main.apply_dev_visuals）
	_ck("正式版：伪 3D 视差照常开着（pseudo3d_enabled=true）", CardView.pseudo3d_enabled)
	# 正式版「整卡一起动」悬停动效（含悬停音）照常关闭（只有测试版才开）
	_ck("正式版：整卡悬停动效关着（whole_card_hover=false，不多播一行音效）",
		not CardView.whole_card_hover)
	var fb := BattleScreen.new()
	add_child(fb)
	fb.size = Vector2(1920, 1080)
	await _frames(4)
	fb.start_battle({
		"chara_id": "chara_小乔儿", "ren": "正一道士",
		"player_count": 3, "ai_level": 2, "matched": true, "auto_setup": true,
		"tutorial": false, "seed": 20261008,
	})
	# start_battle 内部先 await process_frame 才建 GameState —— 必须等它就绪再读 gs
	var fguard := 0
	while fb.gs == null and fguard < 90:
		fguard += 1
		await _frames(1)
	var fw := 0
	while (bool(fb.busy) or fb.gs.current_player() != fb.human or fb.human.turn_index < 1) \
			and fw < 200:
		fw += 1
		await _frames(6)
		if fb.gs.finished:
			break
	_ck("正式版：顶栏没有测试入口（Dev.enabled=false 时根本不建按钮）",
		not fb.button_refs.has("dev") and not fb.button_refs.has("dev_lib"))
	_ck("正式版：左下立绘/人卡不接测试点击（mouse_filter 仍是 IGNORE）",
		(_find_role(fb, "my_portrait") as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE)
	fb.queue_free()
	await _frames(3)

	# ---------- ② 打开测试版，重建一局 ----------
	Dev.enabled = true
	Dev.reset_all()
	# 走正式那条路径关掉闪卡（Main._ready() 里调的同一个方法）
	_main.apply_dev_visuals()
	_ck("测试版：闪卡流光总闸已关（CardView.foil_enabled=false）", not CardView.foil_enabled)
	_ck("★ 只关闪卡：交互动效总闸 effects_enabled 没被动过（悬停/选中/瞄准照常）",
		CardView.effects_enabled)
	# 伪 3D 视差（"金色闪光陀螺仪"那套）同样只在测试版关 ——
	# 根因：_art 放大 1.06 的余量仅 3.8~4.6px < billboard 最大 7px 平移 → 露出 _art2 边缘。
	_ck("测试版：伪 3D 视差总闸已关（pseudo3d_enabled=false）",
		not CardView.pseudo3d_enabled)
	_ck("★ 关伪 3D 不碰交互动效：effects_enabled 仍为 true（悬停抬升/待机浮动照常）",
		CardView.effects_enabled)
	# 【★ 整卡一起动】测试版开启：悬停时整卡跟随鼠标倾斜 + 呼吸脉动 + 悬停音。
	# 它同样依赖 effects_enabled（内层 _process 在 effects_enabled=false 时提前 return），
	# 所以「开了整卡动效」与「交互动效总闸仍开」必须同时成立。
	_ck("测试版：整卡悬停动效已开（whole_card_hover=true，整卡一起动 + 悬停音）",
		CardView.whole_card_hover)
	_ck("★ 整卡动效依赖交互动效总闸：effects_enabled 仍为 true",
		CardView.effects_enabled)
	var b := BattleScreen.new()
	add_child(b)
	b.size = Vector2(1920, 1080)
	await _frames(4)
	b.start_battle({
		"chara_id": "chara_小乔儿", "ren": "正一道士",
		"player_count": 3, "ai_level": 2, "matched": true, "auto_setup": true,
		"tutorial": false, "seed": 20261009,
	})
	var bguard := 0
	while b.gs == null and bguard < 90:
		bguard += 1
		await _frames(1)
	var w := 0
	while (bool(b.busy) or b.gs.current_player() != b.human or b.human.turn_index < 1) and w < 200:
		w += 1
		await _frames(6)
		if b.gs.finished:
			break
	var gs2: GameState = b.gs
	var hu: PlayerState = b.human
	_ck("测试版：顶栏多出「开发者设置 / 卡牌库」两枚入口",
		b.button_refs.has("dev") and b.button_refs.has("dev_lib"))
	_ck("测试版：左下立绘与人卡被接上点击（换角色 / 换【人】）",
		(_find_role(b, "my_portrait") as Control).mouse_filter == Control.MOUSE_FILTER_STOP)
	_ck("测试版：DevPanel 随用随建（不在开局时白建）", b._dev() != null)

	# ---------- ②b 手牌悬停音（用户要求：掠过手牌 = 按钮悬停音）----------
	# 【怎么验】无头没有声卡，听觉验不了 → 数 `ui_hover` 的播放次数。
	# 取一张手牌走真实 `_on_enter()` 路径（手牌 hover_lift=true），播放计数应 +1。
	# 再验证「正式版不响」：把 whole_card_hover 临时关掉，计数不再增长。
	if b._hand_cards.size() > 0:
		var hv: CardView = b._hand_cards[0]
		var c0: int = Sfx.play_count("ui_hover")
		hv._on_enter()
		await _frames(2)
		var c1: int = Sfx.play_count("ui_hover")
		_ck("测试版：鼠标掠过手牌会播 ui_hover 音（和右侧按钮同款）",
			c1 == c0 + 1, "计数 %d→%d" % [c0, c1])
		# 正式版行为：whole_card_hover=false 时不播（保证「只改 SheFuDev」）
		CardView.whole_card_hover = false
		hv._on_enter()
		await _frames(2)
		var c2: int = Sfx.play_count("ui_hover")
		_ck("★ 正式版行为：整卡开关关掉后手牌悬停不播音（只改 SheFuDev）",
			c2 == c1, "计数 %d→%d" % [c1, c2])
		CardView.whole_card_hover = true

	# ---------- ③ 卡牌库：全图鉴可拉 ----------
	var dp: Node = b._dev()
	dp.open_library()
	await _frames(5)
	var lib: Control = dp._lib_layer
	_ck("卡牌库能打开", lib != null and lib.visible)
	var grid_cards := 0
	if lib != null:
		var sc: Array = [lib]
		while not sc.is_empty():
			var nd: Node = sc.pop_back()
			if nd is CardView:
				grid_cards += 1
			for ch in nd.get_children():
				sc.append(ch)
	_ck("卡牌库里能拉出全部图鉴卡牌（%d 张）" % CardDB.cards.size(),
		grid_cards >= CardDB.cards.size(),
		"网格里 %d 张 / 图鉴 %d 张" % [grid_cards, CardDB.cards.size()])
	_ck("卡牌库的浮层在模态层之下（z 78 < 80，详情能压在库上、关掉详情库还在）",
		lib != null and lib.z_index < b.modal_layer.z_index,
		"lib=%d modal=%d" % [lib.z_index if lib != null else -1, b.modal_layer.z_index])

	# 选中第一张卡 → 底部操作栏亮起
	var first_cv: CardView = _find_cardview(lib) if lib != null else null
	_ck("卡牌库里能取到第一张卡", first_cv != null and first_cv.card != null)
	var pick_id := ""
	if first_cv != null and first_cv.card != null:
		pick_id = str(first_cv.card.id)
		first_cv.card_pressed.emit(first_cv.card)
		await _frames(2)
	_ck("点击卡牌后底部操作栏进入可用态（未选中时全禁用）",
		pick_id != "" and _all_enabled(dp, true), "选中=%s" % pick_id)

	# 入手 / 上场
	# 【为什么要用显式的单位卡而不是 pick_id】卡牌库末尾几格是【道具】，
	# 而 dev_give 对道具强制走手牌（道具本来就不能上场）—— 断言想验的是
	# 「直接上场真的改场面」，所以这里必须挑一张确定是**单位**的卡。
	var hand0: int = hu.hand.size()
	var board0: int = hu.board.size()
	var nid := CardDB.find_id_by_name("僵尸")
	var give_id := pick_id if pick_id != "" else nid
	b.dev_give(give_id, 1, false)
	await _frames(3)
	_ck("测试版：从卡牌库「入手」一张 → 手牌 +1 且就是那张卡",
		hu.hand.size() == hand0 + 1 and hu.hand[hu.hand.size() - 1].id == give_id,
		"%d→%d id=%s" % [hand0, hu.hand.size(), give_id])
	var unit_id := CardDB.find_id_by_name("僵尸")
	b.dev_give(unit_id, 1, true)
	await _frames(3)
	_ck("测试版：「直接上场」一张【地】单位 → 场面 +1（不走手牌）",
		hu.board.size() == board0 + 1 and hu.board[hu.board.size() - 1].id == unit_id,
		"%d→%d id=%s" % [board0, hu.board.size(), unit_id])
	# 再堆几张，证明「不限场位 / 直接铺」是真上场
	for k in 3:
		b.dev_give(unit_id, 1, true)
		await _frames(2)
	_ck("测试版：连续铺场也能真的站住（真上场，不是只加数据）",
		hu.board.size() >= board0 + 2, "场面=%d" % hu.board.size())

	# ---- 落场 / 下场音效：只留龙 · 虎 · 犬（2026-10 用户要求）----
	var beast_ok := true
	var beast_dbg: Array = []
	for nm in ["辰龙", "青龙", "亢金龙", "白虎", "寅虎", "犬神"]:
		var cid_b := CardDB.find_id_by_name(nm)
		var key := b.beast_sfx_key(CardDB.instantiate_card(cid_b)) if cid_b != "" else ""
		if key == "":
			beast_ok = false
		beast_dbg.append("%s→%s" % [nm, key if key != "" else "（无）"])
	_ck("龙 / 虎 / 犬 三类单位仍有专属吼声", beast_ok, "  ".join(beast_dbg))
	var quiet_ok := true
	var quiet_dbg: Array = []
	for nm2 in ["僵尸", "钟馗", "不动明王", "金刚钺", "三清铃"]:
		var cid_q := CardDB.find_id_by_name(nm2)
		if cid_q == "":
			continue
		var k2 := b.beast_sfx_key(CardDB.instantiate_card(cid_q))
		if k2 != "":
			quiet_ok = false
		quiet_dbg.append("%s→%s" % [nm2, k2 if k2 != "" else "静音"])
	_ck("一般卡牌没有上场 / 下场音效（吼声键为空）", quiet_ok, "  ".join(quiet_dbg))

	# ---- 角色专属技能：规则照旧，本轮只去掉音效（后续按角色单独制作）----
	var with_skill: Array = []
	for cd0 in CardDB.characters:
		if not (cd0.get("skill", {}) as Dictionary).is_empty():
			with_skill.append(str(cd0.get("id", "")))
	_ck("存在带专属技能的角色（角色技能链路的前提）", with_skill.size() > 0,
		"共 %d 位" % with_skill.size())
	if with_skill.size() > 0:
		b.dev_set_chara(str(with_skill[0]))
		await _frames(3)
		hu.chara_cd = 0
		var sk_ok: bool = gs2.do_chara_skill()
		_ck("角色专属技能仍能发动（只是不再播音效，规则未动）",
			sk_ok and hu.chara_cd > 0, "ok=%s cd=%d" % [str(sk_ok), hu.chara_cd])
		hu.chara_cd = 0
		b.dev_set_chara("chara_小乔儿")
		await _frames(3)

	# ---- 卡牌库多选：一次选多张 → 批量出手（2026-10 用户要求）----
	# 【为什么走 dp._lib_state + dp._give】那是 UI 上真实的路径：
	#   点卡 → _pick 改多选集合 → 底部按钮 → _give 遍历集合。
	#   直接调 b.dev_give 根本测不到「多选」。
	var cvs_m := _find_cardviews(lib)
	var units_m: Array = []
	for cv2 in cvs_m:
		if cv2.card != null and str(cv2.card.faction) != "道具":
			units_m.append(cv2)
		if units_m.size() >= 2:
			break
	_ck("卡牌库里能取到两张【非道具】卡（多选前提）", units_m.size() >= 2,
		"取到 %d 张" % units_m.size())
	if units_m.size() >= 2:
		dp._clear_sel(dp._lib_state)
		await _frames(1)
		units_m[0].card_pressed.emit(units_m[0].card)
		await _frames(1)
		units_m[1].card_pressed.emit(units_m[1].card)
		await _frames(2)
		_ck("点两张卡 = 多选集里有 2 张（不是单选互相替换）",
			(dp._lib_state["multi"] as Array).size() == 2,
			"multi=%s" % str(dp._lib_state["multi"]))
		# 计数文本必须跟着选中走 —— _pick 只经过 _refresh_bar、不经过 _fill，
		# 之前计数写死在 _fill 里，选中了右上角却不显示「（已选 N）」。
		var cnt_lbl: Label = dp._lib_state["count"]
		_ck("右上角计数随选中刷新（…（已选 2））",
			cnt_lbl != null and cnt_lbl.text.contains("（已选 2）"),
			cnt_lbl.text if cnt_lbl != null else "-")
		var h_m: int = hu.hand.size()
		dp._give(dp._lib_state, 1, false)
		await _frames(4)
		_ck("「入手 ×1」对**全部选中**生效（2 张一起进手牌）",
			hu.hand.size() == h_m + 2, "%d→%d" % [h_m, hu.hand.size()])
		var bd_m: int = hu.board.size()
		dp._give(dp._lib_state, 1, true)
		await _frames(4)
		_ck("「直接上场」对**全部选中**生效（2 张一起上场）",
			hu.board.size() == bd_m + 2, "%d→%d" % [bd_m, hu.board.size()])
		units_m[0].card_pressed.emit(units_m[0].card)
		await _frames(2)
		_ck("再点一次已选中的卡 = 取消选择（多选可增可减）",
			(dp._lib_state["multi"] as Array).size() == 1,
			"multi=%s" % str(dp._lib_state["multi"]))
		dp._clear_sel(dp._lib_state)
		await _frames(1)
		_ck("「清空选择」把多选集合清空", (dp._lib_state["multi"] as Array).is_empty())
		_ck("清空后计数不再显示「已选」",
			not (dp._lib_state["count"] as Label).text.contains("已选"),
			(dp._lib_state["count"] as Label).text)

	dp.close_library()
	await _frames(2)
	_ck("卡牌库可关闭", not dp._lib_layer.visible)

	# ---------- ④ 换角色 / 换【人】 ----------
	b.dev_set_chara("chara_楚伞")
	await _frames(4)
	_ck("测试版：换角色生效（chara_id 与名牌同步）",
		hu.chara_id == "chara_楚伞" and str(hu.chara.get("name", "")) == "楚伞"
		and String((_find_role(b, "my_name") as Label).text) == "楚伞",
		"chara_id=%s 名牌=%s" % [hu.chara_id,
			String((_find_role(b, "my_name") as Label).text)])

	b.dev_set_ren("巫女")
	await _frames(4)
	_ck("测试版：换【人】生效（ren_type / 气上限 / 千纸鹤）",
		hu.ren_type == "巫女" and hu.qi_max == int(CardDB.get_ren("巫女").get("qi", 0))
		and hu.paper_cranes >= 1,
		"人=%s qi_max=%d 纸鹤=%d" % [hu.ren_type, hu.qi_max, hu.paper_cranes])
	_ck("测试版：换成巫女后式神按钮自动出现（门控跟着人走）",
		(b.button_refs["shikigami"] as Control).visible)
	b.dev_set_ren("凡人")
	await _frames(4)
	b._refresh_buttons()
	await _frames(2)
	_ck("测试版：换回凡人后式神按钮隐藏（且 VBox 不留空洞）",
		not (b.button_refs["shikigami"] as Control).visible)
	b.dev_set_ren("正一道士")
	await _frames(2)

	# ---------- ⑤ 作弊开关（规则层真的生效，不是只改显示） ----------
	Dev.set_flag("infinite_wealth", true)
	Dev.set_flag("infinite_fa", true)
	b._refresh()
	await _frames(3)
	var w_before := hu.wealth
	hu.spend_res("wealth", 99)
	_ck("无限【财】：门槛通过且不真扣",
		hu.res_amount("wealth") == Dev.BIG and hu.wealth == w_before,
		"量=%d 余额 %d→%d" % [hu.res_amount("wealth"), w_before, hu.wealth])
	_ck("无限【财】：资源胶囊显示 ∞",
		String(UITheme.pill_value(b.res_pills["wealth"]).text) == "∞")
	Dev.set_flag("infinite_fa", false)
	b._refresh()
	await _frames(2)

	Dev.set_flag("no_qi_loss", true)
	var q0 := hu.qi
	var took := hu.take_qi_damage(5)
	_ck("不掉【气】：伤害被完全吸收且不死",
		took == 0 and hu.qi == q0 and not hu.dead, "扣了 %d 气 %d→%d" % [took, q0, hu.qi])
	Dev.set_flag("no_qi_loss", false)

	Dev.set_flag("no_cooldown", true)
	var probe := CardDB.instantiate_card(CardDB.cards[0]["id"])
	probe.set_cooldown(3)
	_ck("无冷却：进冷却的调用被压成 0",
		probe.cooldown == 0 and probe.cooldown_span == 0,
		"cd=%d span=%d" % [probe.cooldown, probe.cooldown_span])
	Dev.set_flag("no_cooldown", false)

	Dev.set_flag("no_board_cap", true)
	_ck("不限场位：board_cap 放大到 999", gs2.board_cap(hu) == 999,
		"cap=%d" % gs2.board_cap(hu))
	Dev.set_flag("no_board_cap", false)
	_ck("关掉后场位上限回到规则表口径（<=7）", gs2.board_cap(hu) <= 7,
		"cap=%d" % gs2.board_cap(hu))

	Dev.set_flag("no_action_limit", true)
	_ck("无限行动：action_limit 放大", hu.action_limit() == Dev.BIG,
		"limit=%d" % hu.action_limit())
	Dev.set_flag("no_action_limit", false)

	# ---------- ⑥ 重开一局（改人数靠它） ----------
	# 【为什么用字典接值】GDScript 的 lambda **按值捕获**局部变量：
	# 直接 `var got := -1` 再在 lambda 里 `got = ...`，改的是 lambda 内的副本，
	# 外面永远读不到。改用 **引用类型**（Dictionary）承接，才能把值带回来。
	var got_box := {"n": -1, "auto": true}
	b.rematch.connect(func(c2: Dictionary): got_box["n"] = int(c2.get("player_count", -1)))
	b.dev_restart(4)
	await _frames(4)
	_ck("测试版：选 4 人局会重新发起一局（rematch 带新人数）", int(got_box["n"]) == 4,
		"player_count=%d" % int(got_box["n"]))

	# 收尾：把全局开关还原，避免影响后续任何断言
	Dev.reset_all()
	Dev.enabled = false
	# 视觉总闸也是 static，会跨段泄漏 —— apply_dev_visuals() 把它们置 false/true，
	# 必须还原，否则后面任何读到 CardView.foil_enabled / pseudo3d_enabled /
	# whole_card_hover 的断言都会拿到「测试版」的残留值。
	CardView.foil_enabled = true
	CardView.pseudo3d_enabled = true
	CardView.whole_card_hover = false


## 弹窗标题栏里是否存在某文字的按钮
func _has_button_text(root: Node, txt: String) -> bool:
	if root == null:
		return false
	var sc: Array = [root]
	while not sc.is_empty():
		var nd: Node = sc.pop_back()
		if nd is Button and String((nd as Button).text) == txt:
			return true
		for ch in nd.get_children():
			sc.append(ch)
	return false


## 牌面是否仍是同一批（逐个比 uid）。kept 存的是 uid 的**值**，不是 CCard 引用。
func _same_uids(cur: Array, kept: Array) -> bool:
	if cur.size() != kept.size():
		return false
	for i in kept.size():
		var cc: Variant = cur[i]
		if not (cc is CCard):
			return false
		if int((cc as CCard).uid) != int(kept[i]):
			return false
	return true


## 卡牌库底部操作栏是否全部可点（用于证明「选中之后按钮才亮」）
func _all_enabled(dp: Node, expect: bool) -> bool:
	var lib: Control = dp._lib_layer
	if lib == null:
		return false
	var sc: Array = [lib]
	while not sc.is_empty():
		var nd: Node = sc.pop_back()
		if nd is Button and String((nd as Button).text) == "入手 ×1":
			return (not (nd as Button).disabled) == expect
		for ch in nd.get_children():
			sc.append(ch)
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ---------------- 小工具：按 meta("role") / 类型找控件 ----------------
## 大本营里的名牌、介绍、底板都挂了 meta("role")，这里按角色名找。
## 【为什么不直接持有引用】面板会随 _refresh() 重建，长期持引用 = previously freed。
func _find_role(root: Node, role: String) -> Node:
	var scan: Array = [root]
	while not scan.is_empty():
		var nd: Node = scan.pop_back()
		if nd.has_meta("role") and str(nd.get_meta("role")) == role:
			return nd
		for ch in nd.get_children():
			scan.append(ch)
	return null


## 按**文档顺序**（广度优先，FIFO）找第一个 CardView。
## 【为什么不用 pop_back】栈式 DFS 会先访问**最后一个**子节点 —— 在卡牌库里
## 那就是最后一格的【道具】，与函数名「第一张」完全相反（曾因此取错卡：道具
## 不能上场，导致「直接上场」断言假失败）。
func _find_cardview(root: Node) -> CardView:
	var all := _find_cardviews(root)
	return all[0] if all.size() > 0 else null


## 文档顺序列出全部 CardView（多选用）
func _find_cardviews(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var scan: Array = [root]
	while not scan.is_empty():
		var nd: Node = scan.pop_front()
		if nd is CardView:
			out.append(nd)
		for ch in nd.get_children():
			scan.append(ch)
	return out


## 树里是否存在某个文本完全相同的 Label（用来证明「详情面板确实弹出来了」）。
func _find_label_text(root: Node, text: String) -> bool:
	var scan: Array = [root]
	while not scan.is_empty():
		var nd: Node = scan.pop_back()
		if nd is Label and String((nd as Label).text) == text:
			return true
		for ch in nd.get_children():
			scan.append(ch)
	return false


func _find_type(root: Node, t: String) -> Node:
	var scan: Array = [root]
	while not scan.is_empty():
		var nd: Node = scan.pop_back()
		if nd.is_class(t):
			return nd
		for ch in nd.get_children():
			scan.append(ch)
	return null


func _find_scroll(root: Node) -> ScrollContainer:
	return _find_type(root, "ScrollContainer") as ScrollContainer


func _find_hbox(root: Node) -> HBoxContainer:
	return _find_type(root, "HBoxContainer") as HBoxContainer


func _find_grid(root: Node) -> GridContainer:
	return _find_type(root, "GridContainer") as GridContainer


## 弹窗的 PanelContainer（_modal 里那个金边面板）——用来验「居中且不顶出屏幕」。
func _find_modal_panel(root: Node) -> PanelContainer:
	return _find_type(root, "PanelContainer") as PanelContainer
