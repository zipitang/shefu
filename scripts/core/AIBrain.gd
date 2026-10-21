class_name AIBrain
extends RefCounted
## 分档次 AI 玩家
## 不直接修改 GameState，而是产出一串「动作」(Action) 交由 Battle 场景逐步播放，
## 这样 AI 的决策过程在界面上是可见、可回放的。

var gs: GameState
var me: PlayerState

const LV_EASY := 1
const LV_NORMAL := 2
const LV_HARD := 3


func setup(p_gs: GameState, p_me: PlayerState) -> void:
	gs = p_gs
	me = p_me


## 估算「本回合第 k 次刷新」（k 从 0 起）的费用。
## 与 GameState.refresh_cost() 的阶梯一致：首次免费，之后按 refreshCostLadder 递增。
## 必须能在「尚未真正执行刷新」时预测后续几次的费用，否则规划时会反复算成同一个价。
func _refresh_cost_at(k: int) -> int:
	var ladder: Array = CardDB.rules.get("refreshCostLadder", [1, 2, 3])
	if not me.free_refresh_used and k == 0:
		return 0
	var paid_index: int = k - (0 if me.free_refresh_used else 1)
	return int(ladder[clampi(me.refresh_count + maxi(0, paid_index), 0, ladder.size() - 1)])


# ==================================================================== 卡牌估值
func score_card(c: CCard) -> float:
	if c == null:
		return -999.0
	var e := gs.opponent_of(me)
	var s := float(c.tier) * 10.0
	if c.is_tian():
		s += 6.0
		# 对方有地卡时，天卡价值飙升（可镇压）
		for u in e.board:
			if u.faction == "地":
				s += 5.0
				break
	else:
		s += 8.0                       # 地卡能直接打气，是赢牌关键
		s += float(c.atk_qi) * 2.0
	# 守护羁绊
	if c.tags.has("护法金刚"):
		s += float(me.guardians_played) * 3.0
	# 被动光环
	for ef in c.skill_effects("passive"):
		if ef.get("type", "") == "aura_wealth" and me.is_mortal_faction():
			s += 6.0
	# 道具
	if c.is_item():
		s += 4.0
	return s


func best_card_index(cards: Array) -> int:
	var bi := 0
	var bs := -1e9
	for i in cards.size():
		var s := score_card(cards[i])
		match me.ai_level:
			LV_EASY:
				s += gs.rng.randf_range(-8.0, 8.0)
			LV_NORMAL:
				s += gs.rng.randf_range(-2.0, 2.0)
			_:
				pass
		if s > bs:
			bs = s
			bi = i
	return bi


# ==================================================================== 产生整回合动作
func plan_turn() -> Array:
	var acts: Array = []
	var e := gs.opponent_of(me)

	# ---------- 1. 经济阶段（整块必须排在「取牌」之前！） ----------
	# 【顺序铁律】刷新会把整副牌面换掉，所以必须先决定「要不要刷」，再决定「取哪张」。
	# 旧版把「取牌」放在最前面（那时 pick_draft 会清空牌面），执行到刷新/购买时牌面已空，
	# 于是 AI 的所有刷新与购买动作**全部静默失败**——【财】除了升级【人】之外无人可花。
	#
	# 花费优先级：【升级·人】（直接 +气，最能滚雪球） > 刷新牌面 > 付费取牌。
	# 三者共用同一个【财】余额，避免「先买光牌、再也升不起级」。
	var w_left: int = me.wealth

	# (a) 升级【人】：凡人/巫女花【财】，正一道士用【法】，阴阳师用【源】，法师用【信众】
	var up_info := gs.upgrade_info(me)
	if me.ai_level >= LV_NORMAL and bool(up_info.get("ok", false)):
		var up_res: String = str(up_info.get("res", "none"))
		var up_cost: int = maxi(0, int(up_info.get("cost", 0)))
		var up_pool: int = w_left
		if up_res == "believer":
			up_pool = me.believers
		elif up_res != "wealth":
			up_pool = me.res_amount(up_res)
		var up_cap: int = 1 if me.ai_level == LV_NORMAL else 2
		var up_times := 0
		while up_times < up_cap and up_pool >= up_cost:
			acts.append({"type": "upgrade"})
			up_pool -= up_cost
			if up_res == "wealth":
				w_left = up_pool
			up_times += 1

	# (b) 刷新牌面
	if not gs.current_draft.is_empty():
		var refresh_budget := 0
		match me.ai_level:
			LV_EASY: refresh_budget = 1        # 免费那次谁都会用
			LV_NORMAL: refresh_budget = 1
			_: refresh_budget = 3
		var tries := 0
		while tries < refresh_budget:
			if not gs.can_refresh(me):
				break
			var cur_best := -1e9
			for c in gs.current_draft:
				cur_best = maxf(cur_best, score_card(c))
			if cur_best >= 22.0:
				break                  # 牌面已经够好，没必要再刷
			var rcost := _refresh_cost_at(tries)
			if rcost > w_left:
				break                  # 刷不起就停
			acts.append({"type": "refresh"})
			w_left -= rcost
			tries += 1

	# (c) 取牌：先吃掉免费额度，再按【财】决定还能买几张
	#     免费额度对所有阵营开放（非凡人阵营没有【财】，只能吃免费那一张）。
	if not gs.current_draft.is_empty():
		var buy_cap := 0
		match me.ai_level:
			LV_EASY: buy_cap = 0
			LV_NORMAL: buy_cap = 1
			_: buy_cap = 3
		var paid_times := 0
		var free_left: int = me.draft_free_left
		while not gs.current_draft.is_empty():
			if free_left <= 0 and paid_times >= buy_cap:
				break
			var bi := best_card_index(gs.current_draft)
			var sc := score_card(gs.current_draft[bi])
			var cost_here: int = 0 if free_left > 0 else gs.buy_cost()
			if cost_here > 0:
				if w_left < cost_here:
					break
				if sc < 14.0 and w_left < 10:
					break          # 牌太差就不值得花【财】
			acts.append({"type": "draft", "idx": bi})
			if cost_here > 0:
				w_left -= cost_here
				paid_times += 1
			else:
				free_left -= 1

	# ---------- 2. 拜神 / 敬鬼（每回合 1 次） ----------
	if gs.can_worship(me):
		var want_tian := 0
		for u in e.board:
			if u.faction == "地":
				want_tian += 1
		var kind := "shen" if want_tian > 0 else "gui"
		if me.ai_level == LV_EASY:
			kind = "shen" if gs.rng.randf() < 0.5 else "gui"
		acts.append({"type": "worship", "kind": kind})

	# ---------- 4. 弃置换资源（卡手时） ----------
	if me.ai_level >= LV_NORMAL and me.hand.size() > 8:
		var worst: CCard = null
		var ws := 1e9
		for c in me.hand:
			var s := score_card(c)
			if s < ws:
				ws = s
				worst = c
		if worst:
			acts.append({"type": "discard", "uid": worst.uid, "res": "auto"})

	# ---------- 6. 起乩（上场） ----------
	# 场位上限由规则层统一裁决（与轮数挂钩，且禁止同名牌重复上场），
	# AI 必须走同一个 can_play，否则它会一直计划一些永远执行不了的动作。
	# 【道具要跳过】道具走的是 use_item 那条独立入口（带落点上下文），
	# 混进这条通用上场循环里，指向性道具会因为「没有目标」被规则层挡回来。
	var play_order: Array = me.hand.duplicate()
	play_order.sort_custom(func(a, b): return score_card(a) > score_card(b))
	for c in play_order:
		if c.is_item():
			continue
		if not gs.can_play(me, c.uid):
			continue
		acts.append({"type": "play", "uid": c.uid})

	# ---------- 7. 道具（带落点） ----------
	acts.append_array(_plan_items(me, e))

	# ---------- 8. 主动行动（袭人 / 镇压 / 制衡，受 actionsPerTurn 额度限制） ----------
	# 先收集所有候选行动并按价值排序，再取额度内最高价值的若干条。
	var cands: Array = []
	for u in me.board:
		if u.cooldown > 0 or u.frozen > 0:
			continue
		if u.is_tian():
			# 【天】：优先镇压【地】（直接消灭，最赚），其次与对方【天】制衡
			var di_target: CCard = null
			for t in e.board:
				if t.faction == "地" and t.tier <= u.tier + 1:
					if di_target == null or t.tier > di_target.tier:
						di_target = t
			if di_target != null:
				cands.append({
					"pri": 100.0 + float(di_target.tier) * 3.0,
					"type": "attack", "uid": u.uid,
					"target_kind": "unit", "target": di_target.uid,
				})
				continue
			if me.ai_level >= LV_NORMAL:
				var tian_target: CCard = null
				for t in e.board:
					if t.faction == "天":
						if tian_target == null or t.cur_hp < tian_target.cur_hp:
							tian_target = t
				if tian_target != null:
					cands.append({
						"pri": 40.0 + float(u.atk) - float(tian_target.cur_hp),
						"type": "attack", "uid": u.uid,
						"target_kind": "unit", "target": tian_target.uid,
					})
		else:
			if u.qi_blocked > 0:
				continue
			if e.qi > 0 or e.shield_qi > 0:
				var dmg := me.effective_atk_qi(u)
				cands.append({
					"pri": 50.0 + float(dmg) * 6.0,
					"type": "attack", "uid": u.uid, "target_kind": "ren",
				})
	# 简单 AI 记错账：随机扰动 + 有概率漏掉行动
	if me.ai_level == LV_EASY:
		for cd in cands:
			cd["pri"] = float(cd["pri"]) + gs.rng.randf_range(-30.0, 30.0)
		if not cands.is_empty() and gs.rng.randf() < 0.35:
			cands.remove_at(0)
	cands.sort_custom(func(a, b): return float(a["pri"]) > float(b["pri"]))
	var quota: int = me.actions_left()
	if me.ai_level == LV_EASY:
		quota = mini(quota, 1)
	for i in mini(quota, cands.size()):
		var cd: Dictionary = cands[i]
		acts.append({
			"type": "attack", "uid": cd["uid"],
			"target_kind": cd["target_kind"], "target": cd.get("target", -1),
		})

	# ---------- 9. 角色专属技能 ----------
	if me.chara_cd <= 0 and me.ai_level >= LV_NORMAL:
		acts.append({"type": "chara"})

	# ---------- 10. 阴阳师 / 巫女 式神 ----------
	if GameState.is_shikigami_ren(me.ren_type) and me.paper_cranes > 0:
		acts.append({"type": "shikigami"})

	acts.append({"type": "end"})
	return acts


## 道具规划 —— 六种道具各自的落点与收益完全不同，逐个判。
##
## 【为什么要单独成函数】道具的落点是「上下文」而不是「卡面数据」：
## 降魔杵要挑对方最值钱的那张、金刚钺要挑场面最厚的那家、
## 铜钱剑只在对方真有【地】卡威胁时才有意义。这些判断放在主循环里会把 plan_turn 撑爆。
func _plan_items(p: PlayerState, e: PlayerState) -> Array:
	var out: Array = []
	if p.ai_level < LV_NORMAL:
		return out
	for c in p.hand:
		if not c.is_item():
			continue
		match c.item_func:
			"purge":
				# 降魔杵：拔掉对方场上「阶数最高 / 血最厚」的那张
				var best: CCard = null
				var bs := -1e9
				for t in e.board:
					var s := float(t.tier) * 10.0 + float(t.cur_hp) + float(t.atk)
					if s > bs:
						bs = s
						best = t
				if best != null and bs >= 21.0:      # 至少 2 阶，才值得花掉一根杵
					out.append({"type": "item", "uid": c.uid, "target_uid": best.uid})
			"seal":
				# 金刚镢：封对方场上攻击最高的那张（让它下回合打不出来）
				var hi: CCard = null
				var ha := -1
				for t in e.board:
					if t.atk > ha:
						ha = t.atk
						hi = t
				if hi != null:
					out.append({"type": "item", "uid": c.uid, "target_uid": hi.uid})
			"axe":
				# 金刚钺：砸场面最厚的那一家
				var th: PlayerState = null
				for q in gs.players:
					if q.pid == p.pid or q.board.is_empty():
						continue
					if th == null or q.board.size() > th.board.size():
						th = q
				if th != null:
					out.append({"type": "item", "uid": c.uid, "target_pid": th.pid})
			"zombies":
				# 三清铃：场面空就补，场面满了别浪费（僵尸是临时单位，退场不触发任何技能）
				if p.board.size() + 3 <= gs.board_cap(p):
					out.append({"type": "item", "uid": c.uid})
			"ward":
				# 铜钱剑：自己没辟邪、且对方手牌里确实有【地】卡时才值
				if p.ward <= 0:
					var di_hand := 0
					for h in e.hand:
						if h.is_di():
							di_hand += 1
					if di_hand > 0 or e.board.any(func(t): return t.is_di()):
						out.append({"type": "item", "uid": c.uid})
			"reveal_di":
				# 八卦镜：纯信息牌，中高难度才用（简单 AI 不会利用这个信息）
				if p.ai_level >= LV_HARD:
					out.append({"type": "item", "uid": c.uid})
	return out
