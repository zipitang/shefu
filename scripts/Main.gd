extends Control
## 《摄伏》入口 —— 屏幕管理器
## Hall（大厅）→ Battle（对局）→ Codex（图鉴）
##
## 【★ 同一份代码出两个 exe】
##   SheFu.exe    —— 正式版，一切从这里进大厅。
##   SheFuDev.exe —— 测试训练场，直接开局并挂上开发者工具（详见 scripts/core/Dev.gd）。
##   两者的唯一差别是启动时 Dev.enabled 的取值，代码里所有测试功能都挂在那个开关下。

var screens_root: Control
var _current: Control
var theme_res: Theme
var current_config: Dictionary = {}


func _ready() -> void:
	Dev.enabled = _detect_dev()
	if Dev.enabled:
		Dev.reset_all()
		apply_dev_visuals()
	theme_res = UITheme.build()
	screens_root = Control.new()
	screens_root.name = "Screens"
	screens_root.theme = theme_res
	screens_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screens_root)
	# --windowinfo <path>：把真实窗口模式与尺寸写到文件后退出。
	# 【为什么不用 stdout】Windows Desktop 的 release 导出默认不挂控制台，
	# print 出来的东西看不到；写文件是唯一能跨导出形态取证的通道。
	# 用来验收「设置里的全屏 / 窗口化」是否真的作用到了 DisplayServer。
	if _arg_value("--windowinfo") != "":
		_window_info_flow()
		return
	# --devinfo <path>：把「这次的 exe 是不是测试版」写出来。
	# 测试版 exe 里没有控制台，只能靠文件取证 —— 否则无法证明特性标签生效了。
	if _arg_value("--devinfo") != "":
		var df := FileAccess.open(_arg_value("--devinfo"), FileAccess.WRITE)
		if df != null:
			df.store_string("enabled=%s\nexe=%s\nfeature=%s\narg=%s\nprofile=%s\n" % [
				str(Dev.enabled), OS.get_executable_path(),
				str(OS.has_feature("devtest")), str(_has_arg("--dev")), Dev.profile()])
			df.close()
		get_tree().quit()
		return
	if _has_arg("--shot"):
		_shot_flow()
		return
	if Dev.enabled:
		show_dev_battle()
		return
	show_hall()


## 【★ 测试训练场：视觉总闸】在 SheFuDev 上的卡牌视觉/手感开关，三条：
##   ① `foil_enabled = false` —— 关掉全部卡牌的闪卡流光；
##   ② `pseudo3d_enabled = false` —— 关掉伪 3D 视差（倾斜 / 视差 / billboard 平移）。
##      【为什么必须关它】用户反馈「选中时金色特效和底层卡面图层重叠，像两张卡叠
##      在一起」。根因就是 `_art` 放大 1.06（余量仅 3.8~4.6px）盖不住 billboard
##      最多 7px 的平移，漏出底层 `_art2` 的边缘。详见 CardView.pseudo3d_enabled。
##   ③ `whole_card_hover = true` —— 【Dev 新增】悬停手牌时**整张卡一起动**
##      （整卡跟随鼠标倾斜 + 呼吸脉动），并且鼠标掠过手牌会播 `ui_hover` 音。
##      用户要求「这次是这张卡的全部都动」。详见 CardView.whole_card_hover。
## ★ 三条只影响 SheFuDev；正式版 ①② 保持 true、③ 保持 false —— 一行都不变。
## 【为什么抽成方法】UITest 需要以**同一条路径**验证，而不是在测试里复制一份赋值 ——
## 复制出去的那一刻两边就会开始漂。
func apply_dev_visuals() -> void:
	CardView.foil_enabled = false
	CardView.pseudo3d_enabled = false
	CardView.whole_card_hover = true


## 是不是测试版？三个信号任一命中即可（详见 Dev.gd 文件头）：
##   ① 导出预设的 custom_features 里带 "devtest"
##   ② 命令行 ++ --dev
##   ③ 可执行文件名里含 "dev"（SheFuDev.exe）—— 兜底
## 【为什么第 ③ 条要排除 editor】源码运行时 OS.get_executable_path() 返回的是
## 引擎本体（Godot_v4.7.2-stable_win64_console.exe），万一某天路径里带了 "dev"
## 就会在编辑器里误判成测试版。
func _detect_dev() -> bool:
	if OS.has_feature("devtest"):
		return true
	if _has_arg("--dev"):
		return true
	if not OS.has_feature("editor"):
		var exe := OS.get_executable_path().get_file().to_lower()
		if exe.contains("dev"):
			return true
	return false


## 测试训练场的开局：跳过大厅与选【人】，直接进对局。
## 人数 / 角色 / 【人】都可以从命令行指定，方便截图脚本固定住场景。
func show_dev_battle() -> void:
	var pcount := 3
	if _arg_value("--players") != "":
		pcount = clampi(int(_arg_value("--players")), 2, 4)
	var cid := _arg_value("--chara")
	var ren := _arg_value("--ren")
	show_battle({
		"chara_id": ("chara_" + cid) if cid != "" else "chara_小乔儿",
		"ren": ren if ren != "" else "正一道士",
		"player_count": pcount, "ai_level": 2, "matched": true,
		"auto_setup": true, "tutorial": false, "dev": true,
		"seed": int(_arg_value("--seed") if _arg_value("--seed") != "" else "20261009"),
	})


func _window_info_flow() -> void:
	await get_tree().create_timer(0.9).timeout
	# --fullscreen / --windowed：顺带验证设置面板里的切换真的作用到了 DisplayServer
	# （走的就是面板里那两个按钮调用的同一个函数）。
	if _has_arg("--fullscreen"):
		Settings.set_fullscreen(true)
		await get_tree().create_timer(0.6).timeout
	elif _has_arg("--windowed"):
		Settings.set_fullscreen(false)
		await get_tree().create_timer(0.6).timeout
	var f := FileAccess.open(_arg_value("--windowinfo"), FileAccess.WRITE)
	if f != null:
		var scr := DisplayServer.screen_get_size()
		f.store_string("mode=%d\nsize=%s\nscreen=%s\nusable=%s\ndpi=%d\nfullscreen_cfg=%s\nwindow_cfg=%dx%d\n" % [
			DisplayServer.window_get_mode(),
			str(DisplayServer.window_get_size()),
			str(scr),
			str(DisplayServer.screen_get_usable_rect()),
			DisplayServer.screen_get_dpi(),
			str(Settings.fullscreen),
			Settings.window_w, Settings.window_h])
		f.close()
	print("[WINDOWINFO] 已写出窗口信息")
	get_tree().quit()


func _has_arg(flag: String) -> bool:	return OS.get_cmdline_user_args().has(flag)


func _arg_value(flag: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == flag and i + 1 < a.size():
			return a[i + 1]
	return ""


## 自动截图流程（用于开发时视觉校验）
##   godot --resolution 1920x1080 ++ --shot D:/x/hall.png
##   godot --resolution 1920x1080 ++ --shot D:/x/room.png   --room
##   godot --resolution 1920x1080 ++ --shot D:/x/setup.png  --setup
##   godot --resolution 1920x1080 ++ --shot D:/x/battle.png --battle
##   godot --resolution 1920x1080 ++ --shot D:/x/codex.png  --codex
func _shot_flow() -> void:
	var path := _arg_value("--shot")
	var is_battle := _has_arg("--battle")
	var is_codex := _has_arg("--codex")
	var is_room := _has_arg("--room")
	var is_setup := _has_arg("--setup")
	# ---------- 闪卡专项：完全确定，不经对战流程 ----------
	# 用**同一张卡**渲染多个相位 + 一个无闪卡对照，差异只可能来自流光本身。
	# 之前想用真实对局截图比对，但截图流程与 AI 驱动存在竞态，每次手牌都不一样，
	# 比对结果全是噪声（踩过），所以专门做这个独立场景。
	if _has_arg("--foiltest"):
		add_child(UITheme.bg_rect("bg_foiltest", 1.0))
		var a_def := ""
		for d0 in CardDB.cards:
			if str(d0.get("art", "")) != "":
				a_def = str(d0.get("id", ""))
				break
		var rowf := HBoxContainer.new()
		rowf.add_theme_constant_override("separation", 30)
		rowf.position = Vector2(150, 250)
		add_child(rowf)
		var cases := [
			{"p": -1.0, "t": "对照（无闪卡）"},
			{"p": 0.72, "t": "相位 0.72"},
			{"p": 1.20, "t": "相位 1.20"},
			{"p": 1.68, "t": "相位 1.68"},
		]
		for cs0 in cases:
			var colf := VBoxContainer.new()
			colf.add_theme_constant_override("separation", 10)
			rowf.add_child(colf)
			var cvf := CardView.new()
			cvf.set_card(CardDB.instantiate_card(a_def))
			colf.add_child(cvf)
			cvf.set_size_px(170.0, 292.0)
			if float(cs0["p"]) >= 0.0:
				cvf.foil = true
				cvf._foil_t = float(cs0["p"])
			cvf.set_process(false)          # 冻结：截图与相位严格一一对应
			cvf.queue_redraw()
			if cvf._overlay != null:
				cvf._overlay.queue_redraw()
			colf.add_child(UITheme.mk_label(str(cs0["t"]), 18, UITheme.GOLD, true))
		await get_tree().create_timer(0.5).timeout
		if _has_arg("--dump"):
			_dump_node(rowf)
	elif is_battle:
		await get_tree().process_frame
		var pcount := 3
		if _arg_value("--players") != "":
			pcount = clampi(int(_arg_value("--players")), 2, 4)
		# --chara <id 后缀> / --ren <人卡>：换角色与【人】，用于验收
		# 「式神按钮只给阴阳师 / 巫女」这类按角色变化的分支。
		var cid := _arg_value("--chara")
		var ren := _arg_value("--ren")
		show_battle({
			"chara_id": ("chara_" + cid) if cid != "" else "chara_小乔儿",
			"ren": ren if ren != "" else "正一道士",
			"player_count": pcount, "ai_level": 2, "matched": true, "auto_setup": true,
			"tutorial": not _has_arg("--noguide"),
			"seed": int(_arg_value("--seed") if _arg_value("--seed") != "" else "20261007"),
		})
		await get_tree().create_timer(1.2).timeout
		var battle: Node = _current
		var gs: GameState = battle.gs
		var human: PlayerState = battle.human
		# 演示：三选一 + 起乩 + 拜神，制造有内容的画面
		if gs.current_draft.size() > 0 and not _has_arg("--draft"):
			gs.do_take_draft(0)
		for i in mini(3, human.hand.size()):
			gs.do_play(human.hand[0].uid)
		if gs.can_worship(human):
			gs.do_worship("shen")
		human.add_res("wealth", 9)
		battle.busy = false
		# --fill N：给所有玩家（含我方）召唤 N 张上场卡，压测「卡多换行 / 布局不漂移」
		var fill_n := 0
		if _arg_value("--fill") != "":
			fill_n = clampi(int(_arg_value("--fill")), 1, 12)
		if fill_n > 0:
			for q in gs.players:
				for k in fill_n:
					var fc := CardDB.random_card(gs.rng)
					if fc != null and not fc.is_item():
						fc.owner_id = q.pid
						gs.summon(q, fc, true)
		else:
			for q in gs.players:
				if q.pid != human.pid:
					for k in 2:
						var c := CardDB.random_card(gs.rng)
						if c:
							c.owner_id = q.pid
							gs.summon(q, c, true)
		battle.busy = false
		# --cd：把场上卡依次摆成「同一段 3 回合冷却里的第 3/2/1 回合」，
		# 这样截图能直接对比黑幕进度：第一张盖满、第二张退到 2/3、第三张只剩 1/3。
		# 注意别用 set_cooldown()——那是「重新上冷却」，会把 span 也重置成同一个值。
		if _has_arg("--cd"):
			var n := 0
			for u in human.board:
				u.cooldown_span = 3
				u.cooldown = clampi(3 - n, 1, 3)
				n += 1
		# --rounds N：让 AI 真实对打 N 轮（同步执行、不等动画），用于复现
		# 「多人局打到后面布局漂移」——只有真实推进若干回合才会出现的重建/状态类问题。
		if _arg_value("--rounds") != "":
			var rn := clampi(int(_arg_value("--rounds")), 1, 40)
			var turns := rn * gs.players.size()
			for t_i in turns:
				if gs.finished:
					break
				if not gs.start_turn():
					print("[RT] t=%d start_turn=false（跳过）" % t_i)
					continue
				var cp := gs.current_player()
				if cp == null:
					break
				if cp.pid != human.pid:
					var ai := AIBrain.new()
					ai.setup(gs, cp)
					for a in ai.plan_turn():
						if gs.finished:
							break
						battle._apply_ai_action(cp, a)
				gs.end_turn()
				battle._refresh()
				print("[RT] t=%d round=%d 当前=%s 手=%d 场=%d" % [t_i, gs.round_no,
					cp.display_name, cp.hand.size(), cp.board.size()])
			print("[ROUNDS] 推进 %d 轮完成：round=%d finished=%s" % [rn, gs.round_no, str(gs.finished)])
		# --autoplay N：走真实 _driver 流程（带帧推进、AI 动画等待），逐轮打印
		# 主容器宽度，验证「刷新时 queue_free 列累积」是否在真实帧循环里也会让布局膨胀。
		if _arg_value("--autoplay") != "":
			var apn := clampi(int(_arg_value("--autoplay")), 1, 40)
			for r in apn:
				var b2: Node = _current
				var g2: GameState = b2.gs
				if g2.finished:
					break
				await b2._driver()
				if g2.finished:
					break
				g2.end_turn()
				b2._refresh()
				await get_tree().create_timer(0.2).timeout
				var w := (b2._world as Control).size.x if b2._world != null else 0.0
				var ec: int = b2.enemy_area.get_child_count() if b2.enemy_area != null else -1
				print("[AP] round=%d main_w=%.0f enemy_cols=%d" % [g2.round_no, w, ec])
		# --hands N：给所有玩家抽到 N 张手牌（压测「手牌背面一行」会不会撑爆顶部布局）
		if _arg_value("--hands") != "":
			var hn := clampi(int(_arg_value("--hands")), 1, 30)
			for q in gs.players:
				if q.hand.size() < hn:
					gs.draw_cards(q, hn - q.hand.size())
		# --nodraft：收起取牌台，露出完整场面（牌面是常驻的，不会自己关）
		if _has_arg("--nodraft"):
			gs.close_draft()
		# --ward N：给己方与一个对手挂 N 层【辟邪】，验证铜钱剑特效图（己方在
		# 人卡上方、对手在人卡下方）的摆位与大小。
		if _arg_value("--ward") != "":
			var wn := clampi(int(_arg_value("--ward")), 1, 3)
			human.ward = wn
			for q in gs.players:
				if q.pid != human.pid:
					q.ward = wn
					break
		battle._refresh()
		await get_tree().create_timer(1.6).timeout
		# --glow：让场上卡播放「冷却结束 → 四边向外发光」那一瞬（发光约 0.85s）
		if _has_arg("--glow"):
			for u in human.board:
				var gv: CardView = battle._view_by_uid.get(u.uid)
				if gv != null:
					gv.play_cd_ready()
			await get_tree().create_timer(0.22).timeout
		# --open <key>：以我方身份点开操作坞里的某个按钮（shop / discard / chara），
		# 停在弹窗打开的那一帧 —— 验收「卡牌商店能开三选一」
		# 「弃置窗口右键能看详情」这类**必须真点一下才知道**的分支。
		if _arg_value("--open") != "":
			battle.busy = false
			battle._on_action(_arg_value("--open"))
			await get_tree().create_timer(0.6).timeout
		# ---- 测试训练场专用的截图钩子（Dev.enabled 才有意义）----
		await _dev_shot_hooks(battle)
		# --sheet a,b,c：在屏幕中央依次播放指定的 Q 版序列帧特效并停在中段，
		# 一行一张图就能核对「素材接进来了 / 尺寸归一化没让某个特效看不见」。
		if _arg_value("--sheet") != "":
			var keys := _arg_value("--sheet").split(",")
			var cx := (battle as Control).size.x * 0.5
			var cy := (battle as Control).size.y * 0.5
			var step := 240.0
			var start := cx - step * float(keys.size() - 1) * 0.5
			for si in keys.size():
				battle.fx.play_sheet(str(keys[si]).strip_edges(),
					Vector2(start + step * float(si), cy))
			await get_tree().create_timer(0.26).timeout
		# --nofx：截图前清空特效层（飘字 / 粒子 / 序列帧）。
		# 【为什么需要】截图流程在 1.2s 处同步连播 3 张牌，「起乩 · XX」飘字要 ~1.8s
		# 才渐隐自灭，而截图正好落在它渐隐的中段 —— 名牌/介绍上会叠一层半透明金字，
		# 目检时会误判成「布局重叠」。验收静态布局时先用它清干净。
		if _has_arg("--nofx"):
			for c in battle.fx.get_children():
				c.free()
		# --dump：打印操作坞控件树（布局靠截图目测坐标太不可靠）
		# --dumpall：打印整棵战斗界面树（布局调试用）
		if _has_arg("--dumpall"):
			_dump_node(battle)
		elif _has_arg("--dump"):
			var ws: Node = battle.button_refs.get("worship_shen")
			if ws != null and ws.get_parent() != null:
				_dump_node(ws.get_parent())
		# --worship：停住「拜神/敬鬼全场揭晓」那一帧
		if _has_arg("--worship"):
			battle._show_worship_reveal("shen", 5)
			await get_tree().create_timer(0.9).timeout
		# --foil：强制手牌全部开闪卡；配合 --foilphase 把光带**冻结**在指定相位，
		# 便于逐相位截图做定量比对（判断「竖直金带是否真的在横向移动」）。
		if _has_arg("--foil"):
			var ph := 2.4 * 0.5
			var pv := _arg_value("--foilphase")
			if pv != "":
				ph = float(pv)
			for chf in battle.hand_area.get_children():
				var cf := chf as CardView
				if cf != null:
					cf.foil = true
					cf._foil_t = ph
					cf.set_process(false)       # 冻结，保证截图与相位一一对应
					cf.queue_redraw()
					if cf._overlay != null:
						cf._overlay.queue_redraw()
					print("[FOIL] 手牌 rect=%s rot=%.3f foil_t=%.2f" % [
						str(cf.get_global_rect()), cf.rotation, cf._foil_t])
			await get_tree().process_frame
			await get_tree().process_frame
		# --hoverprobe：注入**真实鼠标移动事件**（而不是直接调 _on_enter），
		# 验证「悬停上浮 + 置顶」在真实事件链路上是否真的生效。
		# 直接调 _on_enter 只能证明函数本身没错，证明不了 mouse_entered 有被派发过。
		if _has_arg("--hoverprobe"):
			var vp0 := get_viewport()
			# 手牌可能被 _refresh() 重建，所以任何一步之前都重新扫描一次，
			# 绝不长期持有 Node 引用（否则就是 "previously freed"）。
			var hv := _front_hand_card(battle)
			if hv == null:
				print("[HOVERPROBE] 手牌区没有 CardView")
			else:
				var gr: Rect2 = hv.get_global_rect()
				# 瞄准该卡靠下的位置（下方 65% 处）—— 旧版正是这里最容易被
				# 「抬起时抽走命中区」害得 enter/exit 反复横跳。
				var gp := Vector2(gr.get_center().x, gr.position.y + gr.size.y * 0.65)
				var ev := InputEventMouseMotion.new()
				ev.position = gp
				ev.global_position = gp
				Input.parse_input_event(ev)
				await get_tree().create_timer(0.9).timeout
				var after := _front_hand_card(battle)
				if after == null:
					print("[HOVERPROBE] 等待期间手牌被整片重建（手牌区为空）")
				else:
					var hov: Node = vp0.gui_get_hovered_control() if vp0.has_method("gui_get_hovered_control") else null
					print("[HOVERPROBE] 瞄点=%s\n             被悬停的就是它: %s\n             _hover=%s  lift_t=%.3f  enter=%d exit=%d  z=%d" % [
						str(gp), str(hov == after),
						str(after._hover), after._lift_t,
						after._dbg_enter, after._dbg_exit, after.z_index])
					# 再取一张「未被悬停」的卡做对照，确认它确实没被抬起
					for chx in battle.hand_area.get_children():
						var ox := chx as CardView
						if ox != null and ox != after:
							print("             [对照] 另一张卡的 _hover=%s lift_t=%.3f z=%d" % [
								str(ox._hover), ox._lift_t, ox.z_index])
							break
		# --hover N：强制第 N 张手牌进入悬停态，停在「邻卡让位 + 选中上浮摆正 + 阴影放大」那一帧，
		# 验收 KARDS 式手牌动效。走真实 _on_enter 链路（emit card_hovered → _on_hand_hover 推开邻卡）。
		if _arg_value("--hover") != "":
			var hn2 := clampi(int(_arg_value("--hover")), 0, 30)
			if hn2 < battle._hand_cards.size():
				var hcv: CardView = battle._hand_cards[hn2]
				if hcv.card != null:
					hcv._on_enter()
					var hw := 0.3
					if _arg_value("--hoverat") != "":
						hw = float(_arg_value("--hoverat"))
					await get_tree().create_timer(hw).timeout
					# 【整卡一起动取证】整卡模式看 self.rotation / self.scale 是否被鼠标倾角驱动
					# （rotation != home_rot、scale 与 home_scale 不等），并对比 _face 是否归位
					# （整卡模式内层不倾斜）。真机鼠标位置会变，所以这里只证明「整卡确实在动」。
					print("[HOVER] 第 %d 张「%s」：lift_t=%.2f z=%d 邻卡已让位 | 整卡 rot=%.4f(基准%.4f) scale=%s(基准%s) | 卡面 rot=%.4f" % [
						hn2, hcv.card.name, hcv._lift_t, hcv.z_index,
						hcv.rotation, hcv.home_rot, str(hcv.scale), str(hcv.home_scale),
						hcv._face.rotation if hcv._face != null else 0.0])
			else:
				print("[HOVER] 手牌第 %d 张不存在（共 %d 张）" % [hn2, battle._hand_cards.size()])
		# --handsel N：把第 N 张手牌置为选中态（selected_hand + 悬浮抬起），
		# 停在「选中呼吸光圈 + 悬停上浮」那一帧 —— 用于目检「选中特效层与
		# 卡面本体是否重影」。--selat <秒> 可调等待时长（默认 0.45s，够弹簧收敛）。
		if _arg_value("--handsel") != "":
			var sn: int = clampi(int(_arg_value("--handsel")), 0, 30)
			if sn < battle._hand_cards.size():
				var scv: CardView = battle._hand_cards[sn]
				if scv.card != null:
					battle.selected_hand = scv.card
					battle.selected_unit = null
					scv._on_enter()
					var st := 0.45
					if _arg_value("--selat") != "":
						st = float(_arg_value("--selat"))
					await get_tree().create_timer(st).timeout
					print("[HANDSEL] 第 %d 张「%s」 selected=%s lift_t=%.2f face_pos=%s z=%d" % [
						sn, scv.card.name, str(scv.selected), scv._lift_t,
						str(scv._face.position), scv.z_index])
			else:
				print("[HANDSEL] 手牌第 %d 张不存在（共 %d 张）" % [sn, battle._hand_cards.size()])
		# --aim <道具名>：把一张指定道具塞进手牌并**按住拖到对方场上**，
		# 停在半途截图 —— 用来验收「直线瞄准线 + 目标青蓝准星 + 中央判词」。
		# 直接调 CardView._input 而不是 Input.parse_input_event：
		# 这里要验的是**瞄准表现**，注入真实事件链只会引入时序抖动（悬停探针那边已经
		# 单独验过事件派发本身），确定性优先。
		if _has_arg("--aim"):
			var want := _arg_value("--aim")
			var ic := _give_item_to_hand(battle, human, want)
			if ic == null:
				print("[AIM] 手牌塞入失败，找不到道具「%s」" % want)
			else:
				await get_tree().create_timer(0.30).timeout
				var cv: CardView = battle._view_by_uid.get(ic.uid)
				var tgt := _pick_enemy_board_card(gs, human)
				if cv == null:
					print("[AIM] 手牌里没找到 %s 的 CardView" % want)
				elif tgt == null:
					print("[AIM] 对方场上没有卡，无法演示指向")
				else:
					var tcv: CardView = battle._view_by_uid.get(tgt.uid)
					if tcv == null:
						print("[AIM] 目标卡没有 CardView")
					else:
						var src: Vector2 = cv.get_global_rect().get_center()
						var dst: Vector2 = tcv.get_global_rect().get_center()
						_drag_probe(cv, src, dst)
						await get_tree().create_timer(0.45).timeout
						print("[AIM] %s -> 目标 %s  判词=「%s」 合法=%s" % [
							want, tgt.name, battle._aim_reason, str(battle._aim_reason == "")])
		# --itemfx <道具名>：走真实结算入口释放一次道具，停在特效进行到一半的那一帧。
		# 六种道具的演出全部是「时间驱动」的，光看代码看不出节奏对不对。
		if _has_arg("--itemfx"):
			var wantf := _arg_value("--itemfx")
			var icf := _give_item_to_hand(battle, human, wantf)
			if icf == null:
				print("[ITEMFX] 找不到道具「%s」" % wantf)
			else:
				var ctx: Dictionary = {}
				if icf.item_target == "unit":
					var t := _pick_enemy_board_card(gs, human)
					ctx["target_uid"] = t.uid if t != null else -1
				elif icf.item_target == "player":
					var op := gs.opponent_of(human)
					ctx["target_pid"] = op.pid if op != null else -1
				var okf := gs.use_item(human, icf, ctx)
				battle._refresh()
				# --fxat <秒>：演出都是时间驱动的，不同道具的「好看那一帧」不在同一时刻
				# （金刚钺要等它砸到底，书法字要趁它刚印上）。默认 0.24s。
				var at := 0.24
				if _arg_value("--fxat") != "":
					at = float(_arg_value("--fxat"))
				await get_tree().create_timer(at).timeout
				print("[ITEMFX] %s 使用=%s（target=%s ctx=%s t=%.2f）" % [
					wantf, str(okf), icf.item_target, str(ctx), at])
		# --settings：在对局内打开设置面板（验证「局内也能改全屏/音量」）
		if _has_arg("--settings"):
			SettingsPanel.open(battle)
			await get_tree().create_timer(0.7).timeout
	elif is_setup:
		await get_tree().process_frame
		show_battle({
			"chara_id": "chara_小乔儿", "player_count": 3, "ai_level": 2,
			"matched": true, "tutorial": false,
		})
		await get_tree().create_timer(1.3).timeout
		if _has_arg("--setup2"):
			var b2: Node = _current
			b2._setup_sel_ren = "凡人"
			b2._show_setup(1)
			await get_tree().create_timer(1.0).timeout
	elif is_room:
		await get_tree().process_frame
		show_room({"chara_id": "chara_小乔儿", "player_count": 4, "ai_level": 2, "tutorial": true})
		await get_tree().create_timer(1.0).timeout
	elif is_codex:
		await get_tree().process_frame
		_on_open_codex()
		await get_tree().create_timer(2.0).timeout
	elif Dev.enabled:
		# 测试版：不给任何场景参数就直接进对局（这就是测试训练场的主界面）
		show_dev_battle()
		await get_tree().create_timer(1.6).timeout
		await _dev_shot_hooks(_current)
	else:
		show_hall()
		await get_tree().create_timer(1.5).timeout
		# --focus N：点开第 N 张角色头像，验收「4 列浏览 → 2 列聚焦 + 9:16 预览」
		if _arg_value("--focus") != "":
			var hall: Node = _current
			var fi: int = clampi(int(_arg_value("--focus")), 0, hall._order.size() - 1)
			hall._on_tile_pressed(CardDB.get_chara(str(hall._order[fi])))
			# --focusat <秒>：不等重排动画跑完就截图，用来验收「4 列 → 2 列」的中段是否顺滑
			var fw := 1.3
			if _arg_value("--focusat") != "":
				fw = float(_arg_value("--focusat"))
			await get_tree().create_timer(fw).timeout
			# --pvdrag x,y：把预览视差拉到指定位置并等它收敛，用于截图比对
			# 「背景会不会跟着动」（-1..1，负=左下，正=右上）
			if _arg_value("--pvdrag") != "":
				var pp := _arg_value("--pvdrag").split(",")
				if pp.size() == 2:
					hall._drag = Vector2(float(pp[0]), float(pp[1]))
					await get_tree().create_timer(1.0).timeout
		# --settings：打开设置面板（验收全屏 / 窗口化 / 音量 的界面与摆位）
		if _has_arg("--settings"):
			SettingsPanel.open(_current)
			await get_tree().create_timer(0.7).timeout
		# --dump：打印大厅控件树。头像格子被压小这类问题，目测像素不可信，
		# 直接看 grect / min 才知道是谁把谁挤扁了。
		if _has_arg("--dump"):
			_dump_node(_current)
	# 截图前把指针挪出控件区：否则截图里会挂着一条 tooltip（悬停在某个按钮上时），
	# 会干扰像素比对（实测把一次视差比对弄出 690 个「幽灵差异像素」）。
	Input.warp_mouse(Vector2(1900, 1050))
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[SHOT] %s -> %s (err=%d) size=%s ui=%s screen=%s" % [
		path, "OK" if err == OK else "FAIL", err, str(img.get_size()),
		str(_current.size) if _current else "-", str(screens_root.size)])
	get_tree().quit()


## 测试训练场的截图钩子 —— 抽成独立函数是为了让「--battle」与「测试版直接开局」
## 两条路径都能用同一套参数（否则只有前者认 --devopen，很容易被自己坑一次）。
##   --devopen <menu|lib|chara|ren>         打开对应的测试弹窗
##   --devflag  a,b,c                       打开指定的作弊开关（验收 ∞ 显示等）
##   --devboard <卡名>                      直接把一张卡召唤上场
##   --devhand  <卡名>                      塞一张卡进手牌
func _dev_shot_hooks(battle: Node) -> void:
	if not Dev.enabled:
		return
	battle.busy = false
	if _arg_value("--devopen") != "":
		match _arg_value("--devopen"):
			"menu": battle._dev().open_menu()
			"lib": battle._dev().open_library()
			"chara": battle._dev().open_chara()
			"ren": battle._dev().open_ren()
		await get_tree().create_timer(0.7).timeout
	if _arg_value("--devflag") != "":
		for f in _arg_value("--devflag").split(","):
			Dev.set_flag(str(f), true)
		battle._refresh()
		await get_tree().create_timer(0.3).timeout
	if _arg_value("--devboard") != "":
		var bid := CardDB.find_id_by_name(_arg_value("--devboard"))
		if bid != "":
			battle.dev_give(bid, 1, true)
			await get_tree().create_timer(0.6).timeout
	if _arg_value("--devhand") != "":
		var hid := CardDB.find_id_by_name(_arg_value("--devhand"))
		if hid != "":
			battle.dev_give(hid, 1, false)
			await get_tree().create_timer(0.4).timeout
	# --devpick a,b,c：在卡牌库里按**卡名**多选（验收「一次选多张」）。
	# 走的是与鼠标点击**同一条** _pick 路径（增/减 + 重刷边框 + 改计数），
	# 不在钩子里另写一份选中判定 —— 复制出去的那一刻两边就开始漂。
	if _arg_value("--devpick") != "":
		var dp: Node = battle._dev()
		dp.open_library()
		var st: Dictionary = dp._lib_state
		for nm in _arg_value("--devpick").split(","):
			var pid := CardDB.find_id_by_name(str(nm).strip_edges())
			if pid != "":
				dp._pick(st, pid)
		await get_tree().create_timer(0.5).timeout
	# --devgive N [--devtoboard]：把**当前多选**一次性入手（或直接上场）。
	# 与操作栏上那两个按钮调用的是同一个 _give()。
	if _arg_value("--devgive") != "":
		var dp2: Node = battle._dev()
		dp2._give(dp2._lib_state, clampi(int(_arg_value("--devgive")), 1, 6),
			_has_arg("--devtoboard"))
		await get_tree().create_timer(0.7).timeout
	# --devdiscard N：打开「弃置换资源」并连弃 N 张，验收
	# 「点一张不关窗、可以一直弃到全部弃完」。
	if _arg_value("--devdiscard") != "":
		var dn := clampi(int(_arg_value("--devdiscard")), 1, 12)
		battle._open_discard()
		await get_tree().create_timer(0.5).timeout
		for _i in dn:
			if not battle.gs.can_discard(battle.human):
				break
			battle._do_discard_one(battle.human.hand[0].uid)
			await get_tree().create_timer(0.3).timeout
		print("[DEVDISCARD] 连弃 %d 次后手牌=%d 张" % [
			dn, battle.human.hand.size()])
	# --devclose：收起卡牌库 + 三选一牌面，回到干净的对局画面
	# （验收「批量上场」的结果时用 —— 不收牌面的话它会挡住场上）。
	if _has_arg("--devclose"):
		battle._dev().close_library()
		if not battle._draft_hidden:
			battle._on_close_draft()
		await get_tree().create_timer(0.5).timeout


## 递归打印控件树（含全局矩形），用于排查布局问题。
## 靠截图目测坐标效率极低，而且坐标系会骗人 —— 打印才是唯一可信来源。
func _dump_node(n: Node, depth: int = 0) -> void:
	var line := ""
	if n is Control:
		var c := n as Control
		line = "%s%s [%s] grect=%s min=%s cmin=%s" % [
			"  ".repeat(depth), n.get_class(), n.name,
			str(c.get_global_rect()), str(c.custom_minimum_size),
			str(c.get_combined_minimum_size())]
		if n is Label:
			line += ' text="%s"' % (n as Label).text.replace("\n", "⏎")
		elif n is TextureRect:
			line += " tex=%s stretch=%d" % [str((n as TextureRect).texture),
				int((n as TextureRect).stretch_mode)]
	else:
		line = "%s%s [%s]" % ["  ".repeat(depth), n.get_class(), n.name]
	print("[DUMP] " + line)
	for ch in n.get_children():
		_dump_node(ch, depth + 1)


## 取手牌区里「最靠前」的那张卡（z_index 最大）。
## 每次调用都重新扫描，绝不缓存引用 —— 手牌随时可能被 _refresh() 整片重建。
func _front_hand_card(battle: Node) -> CardView:
	var best: CardView = null
	var bz := -99999
	for ch in battle.hand_area.get_children():
		var cv := ch as CardView
		if cv != null and cv.z_index > bz:
			bz = cv.z_index
			best = cv
	return best


## 把一张指定名字的【道具】直接塞进手牌（仅供截图流程演示，不改规则层）。
## 名字 -> 定义 id 走 CardDB.find_id_by_name，避免在这里写死 chara_/item_ 前缀。
func _give_item_to_hand(battle: Node, human: PlayerState, item_name: String) -> CCard:
	var iid := CardDB.find_id_by_name(item_name)
	if iid == "":
		return null
	var defn: Dictionary = CardDB.card_index.get(iid, {})
	if defn.is_empty() or str(defn.get("faction", "")) != "道具":
		return null
	var c := CardDB.instantiate_card(iid)
	c.owner_id = human.pid
	c.set_cooldown(0)
	human.hand.append(c)
	battle._refresh()
	return c


## 挑一张对方场上、攻击最高的卡 —— 指向性道具最有说服力的演示目标。
func _pick_enemy_board_card(gs: GameState, human: PlayerState) -> CCard:
	var best: CCard = null
	for q in gs.players:
		if q.pid == human.pid:
			continue
		for u in q.board:
			if best == null or u.atk > best.atk or (u.atk == best.atk and u.cur_hp > best.cur_hp):
				best = u
	return best


## 走 CardView 自己的 _input 完成「按下 → 越过 12px 阈值 → 移动到目标」三步。
## CardView 里那条 12px 阈值不能省：低于它不会被判定为拖拽，也就不会发 drag_started。
func _drag_probe(cv: CardView, src: Vector2, dst: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = src
	down.global_position = src
	cv._input(down)
	var steps := [0.25, 0.55, 0.80, 1.0]
	for t in steps:
		var mv := InputEventMouseMotion.new()
		var p := src.lerp(dst, float(t))
		mv.position = p
		mv.global_position = p
		cv._input(mv)


func make_backdrop() -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var g := ColorRect.new()
	g.color = UITheme.BG
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(g)
	var glow := Control.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.draw.connect(func():
		var s: Vector2 = glow.size
		for i in 28:
			var t := float(i) / 28.0
			var r: float = s.y * (0.25 + t * 0.85)
			var a: float = 0.055 * (1.0 - t)
			glow.draw_arc(Vector2(s.x * 0.5, s.y * 0.42), r, 0, TAU, 96,
				Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, a), 2.0, true)
	)
	holder.add_child(glow)
	return holder


func _swap(new_screen: Control) -> void:
	if _current and is_instance_valid(_current):
		_current.queue_free()
	_current = new_screen
	screens_root.add_child(_current)


func _prep(screen: Control, name_str: String) -> Control:
	screen.name = name_str
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bd := make_backdrop()
	screen.add_child(bd)
	screen.move_child(bd, 0)
	return screen


# ------------------------------------------------------------------ 大厅
func show_hall() -> void:
	var hall := HallScreen.new()
	hall.start_game.connect(_on_start_game)
	hall.open_codex.connect(_on_open_codex)
	hall.open_room.connect(_on_open_room)
	_swap(_prep(hall, "Hall"))


func _on_start_game(cfg: Dictionary) -> void:
	current_config = cfg
	show_battle(cfg)


func _on_open_room(cfg: Dictionary) -> void:
	# 开房间：进入等待厅，不直接开局
	show_room(cfg)


func _on_open_codex() -> void:
	Sfx.play("ui_open", -4.0)
	var codex := CodexScreen.new()
	codex.closed.connect(show_hall)
	_swap(_prep(codex, "Codex"))


# ------------------------------------------------------------------ 房间
func show_room(cfg: Dictionary) -> void:
	var room := RoomScreen.new()
	room.setup(cfg)
	room.back_to_hall.connect(show_hall)
	room.start_game.connect(_on_start_game)
	_swap(_prep(room, "Room"))


# ------------------------------------------------------------------ 对局
func show_battle(cfg: Dictionary) -> void:
	var battle := BattleScreen.new()
	# 测试训练场没有大厅可回 —— 顶栏那枚【退出】直接结束程序，
	# 否则点下去会退到一个玩家根本没进过的大厅，比不退更让人困惑。
	if Dev.enabled:
		battle.exit_to_hall.connect(func():
			Sfx.play("ui_back", -5.0)
			get_tree().quit())
	else:
		battle.exit_to_hall.connect(show_hall)
	battle.rematch.connect(func(c): show_battle(c))
	_swap(_prep(battle, "Battle"))
	battle.start_battle(cfg)
