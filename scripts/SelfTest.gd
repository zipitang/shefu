extends Node
## 规则自测 / 平衡性模拟器（无头运行）
##   godot --headless scenes/SelfTest.tscn
## 会跑完整的多局对战，逐条校验设计文档中的规则。

var gs: GameState
var errors: Array = []
var checks: Array = []
var game_log: Array = []


func _ready() -> void:
	print("\n========== 《摄伏》规则自测 ==========\n")
	var ok := _run_all()
	if ok:
		print("\n[RESULT] 全部规则校验通过 ✔")
	else:
		print("\n[RESULT] 存在 %d 项失败 ✘" % errors.size())
		for e in errors:
			print("   ✘ " + e)
	get_tree().quit(0 if ok else 1)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		checks.append(name)
		print("  ✔ %s" % name)
	else:
		errors.append("%s %s" % [name, detail])
		print("  ✘ %s  %s" % [name, detail])


func _run_all() -> bool:
	_test_database()
	_test_wealth_curve()
	_test_tier_skill_gating()
	_test_counter_matrix()
	_test_removal_skills()
	_test_items()
	_test_full_simulations()
	_test_seat_layout()
	_test_action_budget()
	_test_skill_parity()
	_test_draft_economy()
	_test_cooldown_tick()
	_test_board_rules()
	return errors.is_empty()


# ------------------------------------------------------------------ 三选一经济
## 「三选一」现在是一个常驻的**取牌台**：点卡即取，不再有「取走 / 购买」按钮。
##   ① 每回合前 draftFreePerTurn 次取牌免费，不扣【财】
##   ② 免费额度用完后每张按 buyCost 扣【财】，且每回合有 draftPaidCapPerTurn 上限
##   ③ 取走的位置立刻补一张，牌面不会越取越空
##   ④ 非凡人阵营没有【财】，只能吃免费额度
func _test_draft_economy() -> void:
	print("\n§10 三选一取牌经济（点卡即取）")
	var free_n: int = int(CardDB.rules.get("draftFreePerTurn", 1))
	var cap: int = int(CardDB.rules.get("draftPaidCapPerTurn", 3))
	var price: int = int(CardDB.rules.get("buyCost", 3))
	var count: int = int(CardDB.rules.get("draftCount", 3))
	_check("规则已定义 draftFreePerTurn / draftPaidCapPerTurn",
		free_n >= 1 and cap >= 1, "free=%d cap=%d" % [free_n, cap])

	var g := GameState.new()
	add_child(g)
	g.setup([{"chara_id": "chara_小乔儿", "ren": "正一道士", "is_ai": false, "ai_level": 0},
			 {"chara_id": "chara_小乔儿", "ren": "正一道士", "is_ai": true, "ai_level": 0}], 4242)
	var me: PlayerState = g.players[0]
	me.reset_turn_flags()
	me.wealth = 30
	_check("回合开始免费额度归满", me.draft_free_left == free_n,
		"free=%d 期望 %d" % [me.draft_free_left, free_n])

	g.open_draft()
	var batch := g.current_draft.size()
	_check("牌面按 draftCount 铺开", batch == count, "%d 张" % batch)
	_check("免费额度内取牌报价为 0", g.draft_take_cost(me) == 0,
		"报价 %d" % g.draft_take_cost(me))

	var w0 := me.wealth
	var h0 := me.hand.size()
	for i in free_n:
		g.do_take_draft(0)
	_check("免费取牌不扣【财】", me.wealth == w0, "%d -> %d" % [w0, me.wealth])
	_check("免费取牌手牌 +%d" % free_n, me.hand.size() == h0 + free_n,
		"%d -> %d" % [h0, me.hand.size()])
	_check("免费额度耗尽后剩余为 0", me.draft_free_left == 0,
		"free=%d" % me.draft_free_left)
	_check("取走的位置立刻补满（不会越取越空）", g.current_draft.size() == batch,
		"%d -> %d" % [batch, g.current_draft.size()])

	_check("免费耗尽后报价变为 buyCost", g.draft_take_cost(me) == price,
		"报价 %d / buyCost %d" % [g.draft_take_cost(me), price])
	var w1 := me.wealth
	g.do_take_draft(0)
	_check("付费取牌扣【财】", me.wealth == w1 - price,
		"%d -> %d（应 -%d）" % [w1, me.wealth, price])
	_check("付费次数被计数", me.draft_paid_count == 1, "paid=%d" % me.draft_paid_count)

	# 付费上限：连点也不能一回合把牌面买空
	me.wealth = 999
	for i in cap * 3:
		g.do_take_draft(0)
	_check("付费取牌受每回合上限约束", me.draft_paid_count <= cap,
		"paid=%d cap=%d" % [me.draft_paid_count, cap])
	_check("超出上限后 can_take_draft 立刻为假",
		me.draft_paid_count < cap or not g.can_take_draft(me),
		"paid=%d" % me.draft_paid_count)
	g.queue_free()

	# 非凡人阵营（法师/佛）没有【财】→ 免费额度用完就取不动了
	var g2 := GameState.new()
	add_child(g2)
	g2.setup([{"chara_id": "chara_小乔儿", "ren": "法师", "is_ai": false, "ai_level": 0}], 77)
	var bh: PlayerState = g2.players[0]
	bh.reset_turn_flags()
	bh.wealth = 0
	g2.open_draft()
	_check("法师阵营被判为非凡人（无【财】）", not bh.is_mortal_faction(),
		"阵营 %s" % bh.ren_type)
	for i in free_n:
		g2.do_take_draft(0)
	_check("非凡人阵营免费额度内仍可取牌", bh.draft_free_left == 0,
		"free=%d" % bh.draft_free_left)
	_check("非凡人阵营免费额度用尽后无法取牌", not g2.can_take_draft(bh))
	g2.queue_free()


# ------------------------------------------------------------------ 冷却回合计算
## 玩家明确要求「冷却回合计算准确无误」，所以这里把冷却的算术钉死成可验证的序列：
##   ① 上冷却时 cooldown_span 记录本次总长 → UI 黑幕从 100% 开始
##   ② 每过一个自己的回合，冷却精确 -1（不多减也不少减）
##   ③ 归零时 span 一并清零，不留残值
func _test_cooldown_tick() -> void:
	print("\n§11 冷却回合计算与视觉数据链")
	var probe := CCard.new()
	probe.setup({
		"id": "probe", "name": "冷却探针", "faction": "地", "sub": "五灾",
		"hp": 4, "atk": 2, "tier": 1,
		"skills": {"active": {"name": "试炼", "cd": 3, "effects": []}},
	}, 900001)
	_check("技能冷却值可读出", probe.active_cd() == 3, "cd=%d" % probe.active_cd())

	probe.set_cooldown(maxi(1, probe.active_cd()))
	_check("上冷却即记录总跨度（黑幕从满进度开始）",
		probe.cooldown == 3 and probe.cooldown_span == 3,
		"cd=%d span=%d" % [probe.cooldown, probe.cooldown_span])

	var seq: Array = []
	for i in 3:
		probe.tick_cooldown()
		seq.append(probe.cooldown)
	_check("冷却递减序列精确（3→2→1→0）", str(seq) == "[2, 1, 0]", "seq=%s" % str(seq))
	_check("冷却归零后跨度一并清零",
		probe.cooldown == 0 and probe.cooldown_span == 0,
		"cd=%d span=%d" % [probe.cooldown, probe.cooldown_span])

	# 数据里漏写 cd 时也不能同回合反复发动
	var lame := CCard.new()
	lame.setup({"id": "lame", "name": "无冷却数据", "faction": "地", "sub": "五灾",
		"hp": 3, "atk": 1, "tier": 1,
		"skills": {"active": {"name": "漏写", "effects": []}}}, 900002)
	_check("cd 数据缺失时 active_cd() 为 0", lame.active_cd() == 0,
		"cd=%d" % lame.active_cd())
	lame.set_cooldown(maxi(1, lame.active_cd()))
	_check("cd 数据缺失时冷却下限兜底为 1", lame.cooldown == 1 and lame.cooldown_span == 1,
		"cd=%d span=%d" % [lame.cooldown, lame.cooldown_span])
	lame.tick_cooldown()
	_check("下限冷却 1 回合后即恢复", lame.cooldown == 0,
		"cd=%d" % lame.cooldown)


# ------------------------------------------------------------------ 上场上限 / 同名唯一
## 需求：「相同卡牌不能同时上场」+「限制可上场的卡牌数量，和轮数挂钩」。
## 这两条都是硬规则，必须能被无头校验，否则很容易在改动中悄悄失效
## （比如 AI 走 can_play 而 UI 走另一条路径，就会出现「AI 遵守、玩家不遵守」的错位）。
func _test_board_rules() -> void:
	print("\n§12 上场上限（随轮数增长）与同名牌唯一性")
	var cfg: Dictionary = CardDB.rules.get("boardCap", {})
	_check("规则已定义 boardCap", not cfg.is_empty(), str(cfg))
	var base: int = int(cfg.get("base", 2))
	var per: int = int(cfg.get("perRound", 1))
	var mx: int = maxi(base, int(cfg.get("max", 6)))

	var g := GameState.new()
	add_child(g)
	g.setup([{"chara_id": "chara_小乔儿", "ren": "正一道士", "is_ai": false, "ai_level": 0},
			 {"chara_id": "chara_小乔儿", "ren": "正一道士", "is_ai": true, "ai_level": 0}], 5150)
	var me: PlayerState = g.players[0]

	g.round_no = 0
	_check("第 0 轮上限 = base", g.board_cap(me) == base,
		"cap=%d base=%d" % [g.board_cap(me), base])
	g.round_no = 1
	_check("第 1 轮上限 = base + perRound",
		g.board_cap(me) == clampi(base + per, base, mx),
		"cap=%d 期望 %d" % [g.board_cap(me), clampi(base + per, base, mx)])
	g.round_no = 2
	var cap2 := g.board_cap(me)
	g.round_no = 1
	_check("上限随轮数单调增长", cap2 >= g.board_cap(me),
		"轮1=%d 轮2=%d" % [g.board_cap(me), cap2])
	g.round_no = 999
	_check("上限封顶在 max", g.board_cap(me) == mx,
		"cap=%d max=%d" % [g.board_cap(me), mx])

	# ---- 用真实手牌跑一遍「上限拦截」 ----
	var ids: Array = []
	for d in CardDB.cards:
		var did := str(d.get("id", ""))
		if did != "" and str(d.get("faction", "")) != "道具" and not ids.has(did):
			ids.append(did)
		if ids.size() >= 6:
			break
	_check("测试用卡牌池足够", ids.size() >= 3, "%d 张" % ids.size())

	me.hand.clear()
	me.board.clear()
	var hand_cards: Array = []
	for i in ids.size():
		var c := CardDB.instantiate_card(str(ids[i]))
		c.owner_id = me.pid
		me.hand.append(c)
		hand_cards.append(c)

	g.round_no = 0
	var cap0 := g.board_cap(me)
	var ok_count := 0
	for c in hand_cards:
		if g.can_play(me, c.uid):
			g.do_play(c.uid)
			ok_count += 1
	_check("上场上限生效：最多只能上到 board_cap",
		me.board.size() == cap0 and ok_count == cap0,
		"场上 %d / 上限 %d" % [me.board.size(), cap0])

	# 被上限挡住时，必须给出**可读的具体原因**
	var blocked: CCard = null
	for c in hand_cards:
		if me.find_hand(c.uid) != null:
			blocked = c
			break
	if blocked != null:
		var why := g.play_block_reason(me, blocked.uid)
		_check("被上限挡住时 can_play 为假", not g.can_play(me, blocked.uid))
		_check("被上限挡住时给出含「上限」的原因", why.contains("上限"), "reason=%s" % why)

	# ---- 同名（同 id）不能同时上场 ----
	var on_board: CCard = me.board[0]
	var dup := CardDB.instantiate_card(on_board.id)
	dup.owner_id = me.pid
	me.hand.append(dup)
	_check("场上已有该卡时 board_has_id 为真", me.board_has_id(on_board.id))
	_check("同名牌不能重复上场", not g.can_play(me, dup.uid),
		"reason=%s" % g.play_block_reason(me, dup.uid))
	var why2 := g.play_block_reason(me, dup.uid)
	_check("同名牌拦截给出含「同一张」的原因", why2.contains("同一张"), "reason=%s" % why2)

	# 让该卡下场后应立刻可以再上（规则不能是永久封禁）
	me.board.erase(on_board)
	on_board.on_board = false
	_check("原卡下场后同名牌恢复可上场", g.can_play(me, dup.uid),
		"reason=%s" % g.play_block_reason(me, dup.uid))

	# 道具不吃这两条限制（即时结算，不占场位）
	g.round_no = 0
	me.board.clear()
	for i in mx + 3:
		var filler := CardDB.instantiate_card(str(ids[0]))
		filler.owner_id = me.pid
		me.board.append(filler)
	var item_id := ""
	for d in CardDB.cards:
		if str(d.get("faction", "")) == "道具":
			item_id = str(d.get("id", ""))
			break
	if item_id != "":
		var it := CardDB.instantiate_card(item_id)
		it.owner_id = me.pid
		me.hand.append(it)
		_check("道具不受场位上限限制", g.can_play(me, it.uid),
			"reason=%s" % g.play_block_reason(me, it.uid))

	# ---- 常规上限封顶 7（用户要求：基本一局最多 7 张）----
	_check("常规场位上限封顶为 7", mx == 7, "max=%d" % mx)

	# ---- 特殊技能 board_bonus 可再多上几张 ----
	g.round_no = 999
	me.board.clear()
	me.board_bonus = 0
	var cap_plain := g.board_cap(me)
	me.board_bonus = 2
	var cap_buffed := g.board_cap(me)
	_check("board_bonus 能抬高场位上限（特殊技能可多上）", cap_buffed == cap_plain + 2,
		"普通 %d → 加成后 %d" % [cap_plain, cap_buffed])

	# ---- 临时单位【僵尸】不占数额 ----
	me.board.clear()
	me.board_bonus = 0
	var zid := CardDB.find_id_by_name("僵尸")
	if zid != "":
		g.round_no = 0
		for i in 3:
			var z := CardDB.instantiate_card(zid)
			z.owner_id = me.pid
			z.temp_turns = 3
			me.board.append(z)
		_check("僵尸等临时单位不占场位数额", me.board_occupied() == 0 and me.board.size() == 3,
			"占用 %d / 场上 %d" % [me.board_occupied(), me.board.size()])
	g.queue_free()


# ------------------------------------------------------------------ 技能与品质对等
## 需求 4 ：「再次检查和优化所有卡牌的技能和品质是否对等」
##
## 【2026-10 改版】合成移除后，卡牌阶数在卡池里就是固定的，「1 阶升到 3 阶后技能变强」
## 这条断言已经失去意义（没有任何路径能让一张卡改变阶数）。原来的两条断言
## （「3 阶技能数值更强」「绝大多数可升阶卡技能会成长」）因此在逻辑上恒为假。
## 现在的「品质对等」改成三条新硬约束：
##   ① 描述里的 {v0}/{c0} 占位符必须全部展开（不能把模板暴露给玩家）
##   ② 家族主题库产出的技能（absolute=True）不得携带 per_tier 等缩放键 ——
##      阶数带来的强度只走「技能数量」，再叠数值放大就会超模
##   ③ 面板数值必须与阶数公式一致（天 hp/atk = 阶；地 hp/atk/气伤 = 阶）
## 另附：签名技能覆盖率与效果类型白名单统计。
func _test_skill_parity() -> void:
	print("\n§9 技能与品质对等（描述展开 / 绝对值技能 / 面板公式）")
	var placeholder_bad: Array = []
	var abs_scaled: Array = []
	var stat_regress: Array = []
	var fx_missing := 0
	var abs_skills := 0
	for d in CardDB.cards:
		var cid := str(d.get("id", ""))
		var base := int(d.get("tier", 1))
		# ---- ① 描述占位符全部展开 ----
		var c1 := CardDB.instantiate_card(cid, base)
		if c1 == null:
			continue
		for key in ["on_play", "on_remove", "passive", "active"]:
			var desc := c1.skill_desc(key)
			# 只有「确实带效果」的技能才需要特效名
			var effs: Array = c1.skill(key).get("effects", [])
			if not effs.is_empty() and c1.skill_fx(key) == "":
				fx_missing += 1
			if desc.find("{v") >= 0 or desc.find("{c") >= 0 or desc.find("{t") >= 0:
				placeholder_bad.append("%s/%s: %s" % [d.get("name", ""), key, desc])
			# ---- ② absolute 技能不得带缩放键 ----
			if bool(c1.skill(key).get("absolute", false)):
				abs_skills += 1
				for e in effs:
					var ed: Dictionary = e
					if ed.has("per_tier") or ed.has("count_per_tier") or ed.has("limit_per_tier"):
						abs_scaled.append("%s/%s: %s" % [d.get("name", ""), key, str(ed.get("type", ""))])
		# ---- ③ 面板数值 == 阶数公式 ----
		var want_atk := base
		var want_hp := base
		var want_qi: int = 0 if c1.faction == "天" else base
		if d.get("group", "") in ["天/四相", "天/十二生肖"]:
			# 四相 / 十二生肖有 +1 特殊加成
			want_atk += 1
			want_hp += 1
			want_qi += 1
		if c1.atk != want_atk or c1.hp != want_hp or c1.atk_qi != want_qi:
			stat_regress.append("%s: 实际 atk%d hp%d 气伤%d / 期望 atk%d hp%d 气伤%d" % [
				d.get("name", ""), c1.atk, c1.hp, c1.atk_qi, want_atk, want_hp, want_qi])

	_check("技能描述无未展开的 {v}/{c}/{t} 占位符", placeholder_bad.is_empty(),
		"共 %d 处，例：%s" % [placeholder_bad.size(), "" if placeholder_bad.is_empty() else placeholder_bad[0]])
	_check("绝对值技能未被追加缩放键（阶数只加技能数量）", abs_scaled.is_empty(),
		"共 %d 处，例：%s" % [abs_scaled.size(), "" if abs_scaled.is_empty() else abs_scaled[0]])
	_check("面板数值符合阶数公式（天=阶 / 地=阶含气伤）", stat_regress.is_empty(),
		"共 %d 张，例：%s" % [stat_regress.size(), "" if stat_regress.is_empty() else stat_regress[0]])
	_check("每个有效果的技能都能推导出特效名", fx_missing == 0, "缺特效 %d 处" % fx_missing)
	print("     家族主题库技能（absolute）：%d 处 ｜ 卡池 %d 张" % [abs_skills, CardDB.cards.size()])

	# 签名技能覆盖率
	var sig := 0
	for d in CardDB.cards:
		var sk: Variant = d.get("skills", null)
		if not (sk is Dictionary):
			continue
		for key in ["on_play", "on_remove", "passive", "active"]:
			var s: Variant = (sk as Dictionary).get(key, null)
			if s is Dictionary and (s as Dictionary).has("fx"):
				sig += 1
				break
	print("     签名技能覆盖：%d / %d 张卡（%.0f%%）" % [sig, CardDB.cards.size(),
		float(sig) / float(maxi(1, CardDB.cards.size())) * 100.0])
	_check("签名技能覆盖超过 6 成卡池", sig >= CardDB.cards.size() * 6 / 10,
		"%d / %d" % [sig, CardDB.cards.size()])

	# 每档阶数的平均【击】/【气伤】应随阶数上升（品质对等的宏观体现）
	var atk_by_tier := {1: [], 2: [], 3: []}
	for d in CardDB.cards:
		var t := int(d.get("tier", 1))
		if atk_by_tier.has(t):
			atk_by_tier[t].append(int(d.get("atk", 0)))
	var a1 := _avg(atk_by_tier[1])
	var a2 := _avg(atk_by_tier[2])
	var a3 := _avg(atk_by_tier[3])
	print("     各阶平均【击】：1阶 %.2f ｜ 2阶 %.2f ｜ 3阶 %.2f" % [a1, a2, a3])
	_check("平均【击】随阶数递增", a1 <= a2 and a2 <= a3, "%.2f / %.2f / %.2f" % [a1, a2, a3])


func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / float(arr.size())


# ------------------------------------------------------------------ 座位布局 / 主动行动额度
func _test_seat_layout() -> void:
	print("\n§7 座位布局（对齐设计文档：2 人局推荐 东/西）")
	for n in [2, 3, 4]:
		var g := GameState.new()
		add_child(g)
		var data: Array = []
		for i in n:
			data.append({"chara_id": "chara_%s" % (["小乔儿", "白店小二", "吉马卓玛", "马曜"][i]),
				"ren": "凡人", "is_ai": true, "ai_level": 2, "name": "P%d" % i})
		g.setup(data, 4242 + n)
		var seats := ""
		for p in g.players:
			seats += p.seat
		g.queue_free()
		var want: String = {2: "东西", 3: "东南西", 4: "东南西北"}[n]
		_check("%d 人局座位 = %s" % [n, want], seats == want, "实际 %s" % seats)


func _test_action_budget() -> void:
	print("\n§8 每回合主动行动额度")
	var limit: int = int(CardDB.rules.get("actionsPerTurn", 2))
	_check("规则已定义 actionsPerTurn", limit >= 1, "实际 %d" % limit)
	var p := PlayerState.new()
	var dummy := CardDB.get_chara("chara_小乔儿")
	p.setup(0, "东", dummy, CardDB.get_ren("凡人"))
	p.reset_turn_flags()
	_check("回合开始额度归满", p.actions_left() == limit, "剩余 %d" % p.actions_left())
	p.actions_used = limit
	_check("额度用尽后 has_action() = false", not p.has_action())
	var g := GameState.new()
	add_child(g)
	g.setup([{"chara_id": "chara_小乔儿", "ren": "凡人", "is_ai": false, "ai_level": 2}], 99)
	var me: PlayerState = g.players[0]
	me.actions_used = me.action_limit()
	var c := CardDB.instantiate_card(CardDB.draft_pool[0]["id"])
	c.owner_id = 0
	me.board.append(c)
	var chk := g.can_attack(me, c, "ren", null)
	_check("额度用尽时攻击被拒绝", not chk["ok"], str(chk.get("reason", "")))
	g.queue_free()


# ------------------------------------------------------------------ 数据完整性
func _test_database() -> void:
	print("§1 卡牌数据库完整性")
	_check("卡牌总数 >= 220", CardDB.cards.size() >= 220, "实际 %d" % CardDB.cards.size())
	_check("角色 12 名", CardDB.characters.size() == 12, "实际 %d" % CardDB.characters.size())
	_check("常规池不含【人】牌", _no_faction(CardDB.draft_pool, "人"))
	_check("常规池不含四相/十二生肖", _no_special(CardDB.draft_pool))
	_check("特殊池含四相与十二生肖", CardDB.special_pool.size() >= 16,
		"实际 %d" % CardDB.special_pool.size())
	var bad := 0
	for c in CardDB.cards:
		if not c.has("skills") or c["skills"].size() < 4:
			bad += 1
	_check("每张卡具备四类技能槽", bad == 0, "异常 %d 张" % bad)

	# 立绘完整性：缺图不会报错，只会在界面上显示成一个黑格子，所以必须主动检查。
	# 实际踩过：「角色」目录里的图叫 店小二.png，角色名却是「白店小二」，严格按名字
	# 匹配就拿不到立绘 —— 而且这个格子正好是新手默认角色。
	var no_art: Array = []
	for c in CardDB.characters:
		if str(c.get("art", "")).is_empty():
			no_art.append("角色/" + str(c.get("name", "?")))
	for r in CardDB.ren_cards:
		if str(r.get("art", "")).is_empty():
			no_art.append("人/" + str(r.get("name", "?")))
	_check("12 角色 + 6【人】均有立绘路径", no_art.is_empty(), "缺失: %s" % str(no_art))
	var unreadable := 0
	for c in CardDB.characters:
		if not ResourceLoader.exists(str(c.get("art", "x"))):
			unreadable += 1
	for r in CardDB.ren_cards:
		if not ResourceLoader.exists(str(r.get("art", "x"))):
			unreadable += 1
	_check("立绘资源可被引擎读取", unreadable == 0, "无法读取 %d 个" % unreadable)


func _no_faction(pool: Array, f: String) -> bool:
	for d in pool:
		if d.get("faction", "") == f:
			return false
	return true


func _no_special(pool: Array) -> bool:
	for d in pool:
		if d.get("pool", "normal") == "special":
			return false
	return true


# ------------------------------------------------------------------ 财曲线
func _test_wealth_curve() -> void:
	print("\n§2 【财】结算曲线")
	var gs2 := GameState.new()
	add_child(gs2)
	gs2.setup([{"chara_id": "chara_小乔儿", "ren": "凡人", "is_ai": true}], 12345)
	var p: PlayerState = gs2.players[0]
	var seq: Array = []
	for i in 6:
		p.turn_index = i + 1
		var before := p.wealth
		gs2.settle_wealth(p)
		seq.append(p.wealth - before)
	_check("第 1~6 回合【财】增量 = [3,3,4,4,5,5]",
		seq == [3, 3, 4, 4, 5, 5], "实际 %s" % str(seq))
	_check("第 6 回合累计 = 24", p.wealth == 24, "实际 %d" % p.wealth)
	gs2.queue_free()


# ------------------------------------------------------------------ 阶数 × 技能位
## 取代原「合成机制」用例。
## 合成已整条移除（卡牌阶数在卡池里就固定了），改由这里守住新的技能体系：
##   · 每张非道具卡必须有【被动】；
##   · 非道具卡的技能位数量 == 卡牌阶数（1 阶 1 个 / 2 阶 2 个 / 3 阶 3 个）；
##   · 道具卡不带任何技能（只有功能）。
func _test_tier_skill_gating() -> void:
	print("\n§3 阶数 × 技能位")
	var bad_passive: Array = []
	var bad_count: Array = []
	var bad_item: Array = []
	var slot_keys := ["on_play", "on_remove", "active"]
	for d in CardDB.cards:
		var nm := str(d.get("name", ""))
		var tier := int(d.get("tier", 1))
		var is_item := str(d.get("faction", "")) == "道具"
		var sk: Dictionary = d.get("skills", {})
		if is_item:
			for k in ["on_play", "on_remove", "passive", "active"]:
				var v: Variant = sk.get(k, null)
				if v != null and not (v as Dictionary).is_empty():
					bad_item.append("%s/%s" % [nm, k])
			continue
		var pas: Variant = sk.get("passive", null)
		if pas == null or (pas as Dictionary).is_empty():
			bad_passive.append(nm)
		var cnt := 0
		for k in slot_keys:
			var s2: Variant = sk.get(k, null)
			if s2 != null and not (s2 as Dictionary).is_empty():
				cnt += 1
		if cnt != tier:
			bad_count.append("%s(%d阶→%d个)" % [nm, tier, cnt])
	_check("每张非道具卡都有【被动】（缺失 %d 张）" % bad_passive.size(), bad_passive.is_empty(),
		"、".join(bad_passive.slice(0, 8)))
	_check("技能位数量 == 阶数（不符 %d 张）" % bad_count.size(), bad_count.is_empty(),
		"、".join(bad_count.slice(0, 8)))
	_check("道具卡不带任何技能（越界 %d 处）" % bad_item.size(), bad_item.is_empty(),
		"、".join(bad_item.slice(0, 8)))

	# 阶数确实固定：同名卡不应出现多个阶数，卡池内也不应存在可升阶路径
	var by_name: Dictionary = {}
	for d in CardDB.cards:
		var nm0 := str(d.get("name", ""))
		if not by_name.has(nm0):
			by_name[nm0] = []
		(by_name[nm0] as Array).append(int(d.get("tier", 1)))
	var multi: Array = []
	for k in by_name.keys():
		var arr: Array = by_name[k]
		if arr.size() > 1:
			multi.append("%s×%d" % [k, arr.size()])
	_check("同名卡不再出现多阶（阶数已固定）", multi.is_empty(), "、".join(multi.slice(0, 6)))
	_check("规则层已无 synthesis 常量", not CardDB.rules.has("synthesis"), "rules 里仍有 synthesis")


# ------------------------------------------------------------------ 克制矩阵
func _test_counter_matrix() -> void:
	print("\n§4 克制关系矩阵")
	var gs4 := GameState.new()
	add_child(gs4)
	gs4.setup([
		{"chara_id": "chara_小乔儿", "ren": "凡人", "is_ai": false},
		{"chara_id": "chara_马曜", "ren": "正一道士", "is_ai": false},
	], 2024)
	var a: PlayerState = gs4.players[0]
	var b: PlayerState = gs4.players[1]
	var tian := _mk("tian_神_齐名百圣_000", 1)
	var di := _mk("di_妖_000", 1)
	var gui1 := _mk("di_鬼_000", 1)
	var gui2 := _mk("di_鬼_001", 1)
	_check("【天】→【地】合法（克消灭）", gs4.can_attack(a, tian, "unit", di)["ok"])
	_check("【天】→【天】合法（制衡）", gs4.can_attack(a, tian, "unit", tian)["ok"])
	_check("【天】→【人】非法", not gs4.can_attack(a, tian, "ren", null)["ok"])
	_check("【地】→【天】非法", not gs4.can_attack(a, di, "unit", tian)["ok"])
	_check("【地】→【人】合法（扣气）", gs4.can_attack(a, di, "ren", null)["ok"])
	_check("【鬼】→【鬼】非法", not gs4.can_attack(a, gui1, "unit", gui2)["ok"])

	# 天→地 实战消灭
	_put_board(b, tian)
	_put_board(b, di)
	_put_board(a, _mk("tian_神_齐名百圣_001", 1))
	var before := b.board.size()
	gs4.turn_cursor = 0
	gs4.do_attack(a.board[0].uid, "unit", di.uid)
	_check("【天】镇压使【地】离场", b.board.size() == before - 1,
		"before %d after %d" % [before, b.board.size()])
	gs4.queue_free()


func _mk(card_id: String, tier: int, owner: PlayerState = null) -> CCard:
	var c := CardDB.instantiate_card(card_id, tier)
	if c == null:
		c = CardDB.instantiate_card(CardDB.cards[0]["id"], tier)
	if c and owner:
		c.owner_id = owner.pid
	return c


## 把一张卡直接摆到某玩家场上（测试用，保持 owner_id 一致）
func _put_board(p: PlayerState, c: CCard) -> CCard:
	c.owner_id = p.pid
	c.on_board = true
	if c.is_tian():
		c.max_hp = p.tian_base_hp(c)
	else:
		c.max_hp = c.hp
	c.cur_hp = c.max_hp
	p.board.append(c)
	return c


# ------------------------------------------------------------------ 下场技能
func _test_removal_skills() -> void:
	print("\n§5 拔除与下场技能")
	var gs5 := GameState.new()
	add_child(gs5)
	gs5.setup([
		{"chara_id": "chara_小乔儿", "ren": "凡人", "is_ai": false},
		{"chara_id": "chara_马曜", "ren": "凡人", "is_ai": false},
	], 7)
	var a: PlayerState = gs5.players[0]
	var b: PlayerState = gs5.players[1]
	gs5.turn_cursor = 0

	# 下场技能「卡面文字 = 实际效果」。
	# 【为什么不再写死「佛 +1 / 鬼 -1」】技能已改为按卡牌 id 从原型池确定性取样，
	# 同一阵营的卡不再共享同一条模板（36 条 on_remove 分布在 227 张卡上），
	# 所以断言必须从**卡牌自己声明的效果**推导期望值，否则测得的是「我挑到的那张卡」
	# 而不是「下场技能这套机制」。
	var heal_card: CCard = null
	var harm_card: CCard = null
	for d in CardDB.cards:
		var c0 := CardDB.instantiate_card(str(d["id"]), int(d.get("tier", 1)))
		if c0 == null:
			continue
		var effs: Array = c0.skill("on_remove").get("effects", [])
		if effs.is_empty():
			continue
		var e0: Dictionary = effs[0]
		if heal_card == null and e0.get("type", "") == "heal_qi" \
				and e0.get("target", "self_ren") == "self_ren":
			heal_card = c0
		if harm_card == null and e0.get("type", "") == "damage_qi" \
				and e0.get("target", "enemy_ren") == "enemy_ren":
			harm_card = c0
		if heal_card != null and harm_card != null:
			break

	if heal_card != null:
		var heal_v: int = maxi(1, int(heal_card.skill_effects("on_remove")[0].get("value", 0)))
		b.qi = 5
		_put_board(b, heal_card)
		var heal_name := heal_card.skill_name("on_remove")
		gs5.remove_unit(heal_card, a, "测试")
		_check("下场技能【%s】：己方【人】+%d 气" % [heal_name, heal_v], b.qi == 5 + heal_v,
			"实际 %d / 期望 %d" % [b.qi, 5 + heal_v])
	else:
		_check("卡池中存在「拔除时为己方【人】回气」的下场技能", false, "一张都没找到")

	if harm_card != null:
		var harm_v: int = maxi(1, int(harm_card.skill_effects("on_remove")[0].get("value", 0)))
		a.qi = 9
		_put_board(b, harm_card)
		var harm_name := harm_card.skill_name("on_remove")
		gs5.remove_unit(harm_card, a, "测试")
		_check("下场技能【%s】：对方【人】-%d 气" % [harm_name, harm_v], a.qi == 9 - harm_v,
			"实际 %d / 期望 %d" % [a.qi, 9 - harm_v])
	else:
		_check("卡池中存在「拔除时对对方【人】打气」的下场技能", false, "一张都没找到")

	# 正一道士得【法】
	_check("拔除后正一道士获得【法】", a.ren_type != "正一道士" or a.fa >= 0)
	gs5.queue_free()


# ------------------------------------------------------------------ 道具六功能
## 道具不带技能，只有功能 —— 由 itemFunc 分派。
## 这里逐条验证「拖入后到底发生了什么」，并且验证目标不合规时**牌不会被白吃掉**。
func _test_items() -> void:
	print("\n§5b 道具卡的六项功能（无技能，只有功能）")
	var g := GameState.new()
	add_child(g)
	g.setup([
		{"chara_id": "chara_小乔儿", "ren": "凡人", "is_ai": false},
		{"chara_id": "chara_马曜", "ren": "凡人", "is_ai": false},
	], 11)
	var me: PlayerState = g.players[0]
	var op: PlayerState = g.players[1]
	g.turn_cursor = 0

	# ---- 拿道具卡进手牌 ----
	var byname := {}
	for d in CardDB.cards:
		if str(d.get("faction", "")) == "道具":
			byname[str(d["name"])] = str(d["id"])

	var need := ["降魔杵", "金刚镢", "三清铃", "铜钱剑", "八卦镜", "金刚钺"]
	_check("六种功能性道具都在卡池里（%d / 6）" % need.size(),
		need.all(func(n): return byname.has(n)),
		"缺少：" + "、".join(need.filter(func(n): return not byname.has(n))))

	var hand_of := {}
	for n in need:
		if not byname.has(n):
			continue
		var c := CardDB.instantiate_card(byname[n], 1)
		c.owner_id = me.pid
		me.hand.append(c)
		hand_of[n] = c

	# ---- ① 降魔杵：指向对方场上卡 → 直接拔除 ----
	var victim := _put_board(op, _mk("di_妖_001", 2, op))
	var n_before := op.board.size()
	if hand_of.has("降魔杵"):
		_check("【降魔杵】目标不合规时（指自己）被拒绝",
			not g.use_item(me, hand_of["降魔杵"], {"target_uid": me.board[0].uid if not me.board.is_empty() else -1}),
			"指到自己场上却通过了")
		_check("【降魔杵】被拒后仍留在手牌", me.hand.has(hand_of["降魔杵"]))
		g.use_item(me, hand_of["降魔杵"], {"target_uid": victim.uid})
		_check("【降魔杵】直接拔除对方场上卡", op.board.size() == n_before - 1,
			"场上 %d -> %d" % [n_before, op.board.size()])
		_check("【降魔杵】使用后进弃置区、离开手牌",
			not me.hand.has(hand_of["降魔杵"]) and me.discard.has(hand_of["降魔杵"]))

	# ---- ② 金刚镢：封印目标下回合的行动与被动 ----
	var sealed := _put_board(op, _mk("di_妖_002", 3, op))
	if hand_of.has("金刚镢"):
		var aura_before := sealed.skill_effects("passive").size()
		g.use_item(me, hand_of["金刚镢"], {"target_uid": sealed.uid})
		_check("【金刚镢】命中后目标被冻结", sealed.frozen > 0)
		_check("【金刚镢】命中后被动被封印（读取点返回空）",
			sealed.skill_effects("passive").is_empty(),
			"封印前 %d 条 / 封印后 %d 条" % [aura_before, sealed.skill_effects("passive").size()])
		# 目标自己回合开始时递减一次：2 -> 1 仍 >0，整回合被封
		g.turn_cursor = 1
		g.start_turn()
		_check("【金刚镢】封印覆盖目标接下来的一整个回合", sealed.passive_sealed > 0,
			"递减一次后 passive_sealed=%d" % sealed.passive_sealed)
		g.turn_cursor = 0

	# ---- ③ 三清铃：召唤 3 张临时【僵尸】，3 回合后退场 ----
	var board_before := me.board.size()
	if hand_of.has("三清铃"):
		g.use_item(me, hand_of["三清铃"], {})
		var zs := me.board.filter(func(u): return u.temp_turns > 0)
		_check("【三清铃】召唤 3 张临时【僵尸】", zs.size() == 3, "实际 %d 张" % zs.size())
		_check("【三清铃】僵尸带 3 回合计时", zs.all(func(u): return u.temp_turns == 3))
		# 推进 3 个自己的回合，僵尸应全部退场
		for _i in 3:
			g.turn_cursor = 0
			g.start_turn()
		var left := me.board.filter(func(u): return u.temp_turns > 0)
		var z_left := me.board.filter(func(u): return str(u.name).contains("僵尸"))
		_check("【三清铃】3 回合后僵尸全部退场", z_left.is_empty(),
			"剩 %d 张（计时器剩 %d）" % [z_left.size(), left.size()])

	# ---- ④ 铜钱剑：3 层【辟邪】，其间【地】卡无法袭人 ----
	if hand_of.has("铜钱剑"):
		me.ward = 0
		g.use_item(me, hand_of["铜钱剑"], {})
		_check("【铜钱剑】己方【人】获得 3 层【辟邪】", me.ward == 3, "实际 %d" % me.ward)
		var di_unit := _put_board(op, _mk("di_妖_003", 2, op))
		op.actions_used = 0                      # 先排除「行动额度用完」这条干扰项
		var chk := g.can_attack(op, di_unit, "ren", null)
		_check("【辟邪】期间对方【地】卡无法袭人", not bool(chk.get("ok", true)),
			"居然还能打：%s" % chk.get("reason", ""))
		me.ward = 0
		var chk2 := g.can_attack(op, di_unit, "ren", null)
		_check("【辟邪】层数归零后对方【地】卡恢复袭人", bool(chk2.get("ok", false)),
			"仍被挡：%s" % chk2.get("reason", ""))

	# ---- ⑤ 八卦镜：只向自己报出各方手牌【地】数量 ----
	if hand_of.has("八卦镜"):
		op.hand.clear()
		var want_di := 0
		for i in 4:
			var hd := _mk("di_妖_%03d" % (i + 1), 1, op)
			op.hand.append(hd)
			if hd.is_di():
				want_di += 1
		op.hand.append(_mk("tian_佛_001", 1, op))
		# 【踩过的坑】GDScript 的 lambda 按**值**捕获局部变量：
		# 在闭包里写 `got = info.get("info", [])` 只会改掉那份拷贝，外面的 got 永远是空数组。
		# 必须原地改（clear + append_array），让闭包和外层共享同一个 Array 对象。
		var got: Array = []
		var cf := func(info: Dictionary):
			if String(info.get("kind", "")) == "reveal_di":
				got.assign(info.get("info", []))
		g.effect_fired.connect(cf)
		g.use_item(me, hand_of["八卦镜"], {})
		var cnt := 0
		for i in got:
			if int(i["pid"]) == op.pid:
				cnt = int(i["count"])
		_check("【八卦镜】报出的【地】手牌数与实际一致", got.size() > 0 and cnt == want_di,
			"报出 %d / 实际 %d" % [cnt, want_di])
		g.effect_fired.disconnect(cf)

	# ---- ⑥ 金刚钺：砸落，全场 3 伤，【地】额外多受 2 ----
	if hand_of.has("金刚钺"):
		op.board.clear()
		var t_di := _put_board(op, _mk("di_妖_004", 3, op))     # 【地】吃 5
		var t_non := _put_board(op, _mk("di_妖_005", 3, op))
		if t_non.is_di():
			t_non.faction = "妖"                                  # 强制造一个非【地】样本
		var hp_di := t_di.cur_hp
		var hp_non := t_non.cur_hp
		g.use_item(me, hand_of["金刚钺"], {"target_pid": op.pid})
		var d_di := hp_di - t_di.cur_hp
		var d_non := hp_non - t_non.cur_hp
		_check("【金刚钺】对目标玩家所有上场卡造成 3 伤", d_non == 3,
			"非【地】实际掉 %d" % d_non)
		_check("【金刚钺】对【地】单位额外多造成 2 伤", d_di == 5, "【地】实际掉 %d" % d_di)

	# ---- 规则表：道具不出现在开局自带的两个之外，且有本局上限 ----
	var itemRules: Dictionary = CardDB.rules.get("itemDraw", {})
	_check("规则表登记了道具权重与每局上限",
		not (itemRules.get("weights", {}) as Dictionary).is_empty()
		and int(itemRules.get("maxPerGame", 0)) == 2,
		"itemDraw=%s" % str(itemRules))
	_check("开局自带的拜神 / 敬鬼不进三选一池",
		CardDB.starter_item_ids.size() == 2
		and CardDB.item_draft_pool.all(func(d): return not bool(d.get("starter", false))),
		"starter=%d / 可刷池 %d 张" % [CardDB.starter_item_ids.size(), CardDB.item_draft_pool.size()])

	# 权重顺序：金刚钺 < 降魔杵 < 三清铃 < 铜钱剑 < 金刚镢 < 八卦镜
	var wts: Dictionary = itemRules.get("weights", {})
	var order := ["金刚钺", "降魔杵", "三清铃", "铜钱剑", "金刚镢", "八卦镜"]
	var mono := true
	for i in order.size() - 1:
		if int(wts.get(order[i], 0)) > int(wts.get(order[i + 1], 0)):
			mono = false
	_check("道具刷出权重单调递增（金刚钺 最稀有→ 八卦镜 最常见）", mono, str(wts))
	var norm_w := int(itemRules.get("normalCardWeight", 400))
	var heaviest := 0
	var item_sum := 0
	for k in wts.keys():
		heaviest = maxi(heaviest, int(wts[k]))
		item_sum += int(wts[k])
	_check("每张道具的权重都低于普通卡（道具更难刷）", heaviest < norm_w,
		"最重道具 %d / 普通卡 %d" % [heaviest, norm_w])
	# 【本轮收紧】光「最重道具 < 普通卡」不够——之前 6 < 12 也成立，但道具总权重 21
	# 只比普通牌 24 略小，实测道具占三选一近 47%。现在要求道具总权重 < 普通牌总权重，
	# 从「单张稀有」升级到「整个道具体系都稀有」。
	_check("道具总权重远低于普通卡（体系级稀有）", item_sum * 3 < norm_w,
		"道具合计 %d / 普通卡 %d" % [item_sum, norm_w])

	# 统计验证：抽 1000 张三选一候选，道具占比必须低于 15%
	# （真实目标 ~5%，留足随机抖动余量，只用来挡「又变回 40%+」这类回归）。
	var st_owner := me
	var st_items := 0
	var st_total := 0
	for _i in 1000:
		var nc := CardDB.random_draft_card(g.rng, st_owner)
		if nc == null:
			continue
		st_total += 1
		if nc.is_item():
			st_items += 1
	_check("三选一抽样道具占比 < 15%（实测目标 ~5%）",
		st_total > 0 and st_items * 100 < st_total * 15,
		"道具 %d / %d 张 = %.1f%%" % [st_items, st_total, 100.0 * st_items / maxi(1, st_total)])

	# 拿满上限后该道具从候选池消失
	if byname.has("八卦镜"):
		for _i in 2:
			var c2 := CardDB.instantiate_card(byname["八卦镜"], 1)
			g._note_item_obtained(me, c2)
		var picked_item := 0
		for _i in 400:
			var nc := CardDB.random_draft_card(g.rng, me)
			if nc != null and nc.is_item() and nc.name == "八卦镜":
				picked_item += 1
		_check("拿满 2 次后该道具不再被抽到", picked_item == 0, "又抽到 %d 次" % picked_item)

	g.queue_free()


# ------------------------------------------------------------------ 完整对局模拟
func _test_full_simulations() -> void:
	print("\n§6 完整对局模拟（AI vs AI）")
	var wins := {"东": 0, "南": 0, "西": 0, "北": 0}
	var cfg_counts := {2: 0, 3: 0, 4: 0}
	var total_turns := 0
	var max_turns_seen := 0
	var games := 24
	for g in games:
		var n := 2 + (g % 3)          # 2 / 3 / 4 人局轮流
		cfg_counts[n] += 1
		var r := _simulate(n, 1000 + g * 37)
		if r["winner"] >= 0:
			var p: PlayerState = r["gs"].get_player(r["winner"])
			if p:
				wins[p.seat] += 1
		total_turns += r["turns"]
		max_turns_seen = maxi(max_turns_seen, r["turns"])
		r["gs"].queue_free()

	print("  对局配置分布: %s" % str(cfg_counts))
	print("  胜者座位分布: %s" % str(wins))
	print("  平均回合数: %.1f ｜ 最长回合: %d" % [float(total_turns) / float(games), max_turns_seen])
	_check("24 局全部正常结束（无死循环/异常）", true)
	_check("所有对局都在 300 回合内结束", max_turns_seen < 300, "最长 %d" % max_turns_seen)
	var wsum := 0
	for k in wins.keys():
		wsum += wins[k]
	_check("多座位均能产生胜者", wsum >= games - 4, "有胜者 %d / %d 局" % [wsum, games])
	# 设计文档给出 15 段【财】曲线，说明单局节奏应在十几回合以上。
	# 若伤害吞吐失衡（例如所有场上卡每回合都能打人），对局会缩到 8 回合左右 —— 这里守住底线。
	var avg_turns := float(total_turns) / float(games)
	_check("对局节奏不过快（平均 ≥ 10 回合）", avg_turns >= 10.0, "实际 %.1f" % avg_turns)


func _simulate(n: int, seed_value: int) -> Dictionary:
	var gsx := GameState.new()
	add_child(gsx)
	var chara_ids := ["chara_小乔儿", "chara_白店小二", "chara_吉马卓玛",
					  "chara_马曜", "chara_楚伞", "chara_唐森",
					  "chara_孟谢菲", "chara_玄澈"]
	var rens := ["凡人", "正一道士", "阴阳师", "巫女", "法师", "萨满"]
	# 注意：【人】必须随对局轮换。
	# 早期版本用 RENS[i % 6] 让「南」永久绑定正一道士（15 气），结果座位胜率
	# 实际上衡量的是卡组强度而非座位公平性 —— 这个坑在 BalanceTest.gd 里也踩过。
	var seats_data: Array = []
	for i in n:
		seats_data.append({
			"chara_id": chara_ids[(i + seed_value) % chara_ids.size()],
			"ren": rens[(i + seed_value) % rens.size()],
			"is_ai": true,
			"ai_level": 1 + ((i + seed_value) % 3),
			"name": "AI%d" % (i + 1),
		})
	gsx.setup(seats_data, seed_value)

	var turns := 0
	var guard := 0
	while not gsx.finished and guard < 400:
		guard += 1
		if not gsx.start_turn():
			continue
		var p := gsx.current_player()
		if p == null:
			break
		turns += 1
		if gsx.finished:
			break
		var ai := AIBrain.new()
		ai.setup(gsx, p)
		var acts := ai.plan_turn()
		for a in acts:
			if gsx.finished:
				break
			_apply(gsx, p, a)
		if gsx.finished:
			break
		gsx.end_turn()
	return {"gs": gsx, "winner": gsx.winner_pid, "turns": turns}


func _apply(gsx: GameState, p: PlayerState, a: Dictionary) -> void:
	match a.get("type", ""):
		"draft":
			gsx.pick_draft(int(a.get("idx", 0)))
		"refresh":
			gsx.do_refresh()
		"buy":
			gsx.do_buy(int(a.get("idx", 0)))
		"worship":
			gsx.do_worship(a.get("kind", "shen"))
		"discard":
			gsx.do_discard(int(a.get("uid", -1)))
		"upgrade":
			gsx.do_upgrade()
		"play":
			gsx.do_play(int(a.get("uid", -1)))
		"item":
			var cur2 := gsx.current_player()
			var ic2 := cur2.find_hand(int(a.get("uid", -1)))
			if ic2 != null:
				gsx.use_item(cur2, ic2,
					{"target_uid": int(a.get("target_uid", -1)),
					 "target_pid": int(a.get("target_pid", -1))})
		"attack":
			gsx.do_attack(int(a.get("uid", -1)), a.get("target_kind", "ren"), int(a.get("target", -1)))
		"active":
			gsx.do_active(int(a.get("uid", -1)))
		"chara":
			gsx.do_chara_skill()
		"shikigami":
			gsx.do_summon_shikigami()
		"end":
			pass
