class_name GameState
extends Node
## 《摄伏》核心对局引擎
## ------------------------------------------------------------------
## 纯规则层：不依赖任何 UI。UI / AI 都通过本类的公开方法推进对局。
## 回合流程严格对齐设计文档第十三节「最终循环」。

signal log_message(text: String)
signal state_changed
signal turn_started(pid: int)
signal draft_opened(options: Array)
signal game_over(winner_pid: int)
signal card_played(pid: int, card: CCard)
signal unit_removed(pid: int, card: CCard)
signal effect_fired(info: Dictionary)

const SEATS := ["东", "南", "西", "北"]

## 座位布局（对齐设计文档）：
##   2 人局  推荐 东 / 西         → 索引 [0, 2]
##   3 人局      东 / 南 / 西      → 索引 [0, 1, 2]
##   4 人局      东 / 南 / 西 / 北 → 索引 [0, 1, 2, 3]
const SEAT_LAYOUTS := {
	2: [0, 2],
	3: [0, 1, 2],
	4: [0, 1, 2, 3],
}

var players: Array = []            ## Array[PlayerState]
var turn_order: Array = []         ## pid 顺序
var turn_cursor: int = 0
var round_no: int = 0
var rng := RandomNumberGenerator.new()
var finished: bool = false
var winner_pid: int = -1

# 当前回合的临时状态
var current_draft: Array = []      ## Array[CCard] 三选一
var draft_cost_paid: bool = false
var pending_qi_events: Array = []
## 多人局：每个玩家选定的"主目标"（pid -> 目标 pid）
## 单目标效果（袭人 / 掠夺 / 弃牌等）默认指向主目标；未指定时自动取【气】最少的对手。
var target_map: Dictionary = {}


func _ready() -> void:
	pass


# ==================================================================== 初始化
func setup(seats_data: Array, seed_value: int = 0) -> void:
	## seats_data: [{ "chara_id": String, "ren": String, "is_ai": bool, "ai_level": int, "name": String }]
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	players.clear()
	turn_order.clear()
	var layout: Array = SEAT_LAYOUTS.get(seats_data.size(), SEAT_LAYOUTS[4])
	for i in seats_data.size():
		var d: Dictionary = seats_data[i]
		var chara := CardDB.get_chara(d.get("chara_id", ""))
		var ren := CardDB.get_ren(d.get("ren", "凡人"))
		var ps := PlayerState.new()
		var seat: String = SEATS[int(layout[i % layout.size()])]
		var disp: String = d.get("name", chara.get("name", "玩家%d" % (i + 1)))
		ps.setup(i, seat, chara, ren)
		ps.display_name = disp
		ps.is_ai = bool(d.get("is_ai", false))
		ps.ai_level = int(d.get("ai_level", 2))
		# 初始手牌：4 张常规池
		for k in 4:
			var c := CardDB.random_card(rng)
			if c:
				c.owner_id = ps.pid
				ps.hand.append(c)

		players.append(ps)
		turn_order.append(ps.pid)

	# ---- 后手补偿 ----
	# 先手在每个环节都早一步（抢三选一、抢【财】、抢上场），这个领先会滚雪球：
	# 实测 2 人局无补偿时先手胜率 ~75%（见 scripts/BalanceTest.gd）。
	# 按座位序号线性补偿：越靠后拿得越多，抵消「行动顺序」带来的系统性偏差。
	# 用 ceil 而非 round：round 会让第 2 个座位（如 4 人局的【南】）在小数值下被抹成 0，
	# 结果「补偿」反而把中段座位推成了最弱位（实测 4 人局 南 仅 10% 胜率）。
	#
	# 也支持显式按座位给量（comp 里带 "qi" / "wealth" 数组）：
	# 线性模型无法表达「先手第一个打的就是 2 号位」这种结构性劣势，
	# 需要单独给 2 号位（南）多补一点。
	var comp := _compensation_for(players.size())
	if not comp.is_empty():
		var cnt := players.size()
		var qi_arr: Array = comp.get("qi", [])
		var w_arr: Array = comp.get("wealth", [])
		for i in cnt:
			var qi_bonus := 0
			var w_bonus := 0
			if i < qi_arr.size() or i < w_arr.size():
				if i < qi_arr.size():
					qi_bonus = int(qi_arr[i])
				if i < w_arr.size():
					w_bonus = int(w_arr[i])
			else:
				var frac: float = float(i) / float(maxi(1, cnt - 1))
				qi_bonus = int(ceil(float(comp.get("laterQi", 0)) * frac))
				w_bonus = int(ceil(float(comp.get("laterWealth", 0)) * frac))
			if qi_bonus <= 0 and w_bonus <= 0:
				continue
			var later: PlayerState = players[i]
			if qi_bonus > 0:
				later.qi += qi_bonus
				later.qi_max += qi_bonus
			if w_bonus > 0:
				later.add_res("wealth", w_bonus)
			log_msg("【后手补偿】%s（%s）额外获得 气 +%d / 财 +%d" % [
				later.display_name, later.seat, qi_bonus, w_bonus])

	round_no = 0
	turn_cursor = 0
	finished = false
	winner_pid = -1
	log_msg("=== 《摄伏》对局开始 · %d 人局 ===" % players.size())
	for p in players:
		log_msg("  %s 落座【%s】· %s（%s）｜ 气 %d" % [
			p.display_name, p.seat, p.chara.get("title", "?"), p.ren_type, p.qi])
	state_changed.emit()


# ==================================================================== 工具
func set_target(pid: int, victim_pid: int) -> void:
	if pid != victim_pid:
		target_map[pid] = victim_pid
		state_changed.emit()


func get_target(pid: int) -> int:
	return int(target_map.get(pid, -1))


## 主目标解析：显式指定 > 气最少的存活对手 > 任意对手
##
## 平手时按「顺时针距离」取最近的一位，而不是 players 数组里最先出现的那位。
## 原因：所有 AI 都按数组顺序取第一个平手目标时，会对同一个人集火
## （3 人局里 南/西/北 全扑向东），死亡顺序就被座位序号决定了 —— 实测「南」
## 的胜率被压到 10% 左右。改成顺时针取最近，集火关系自然成为一个环，
## 每人承受的压力对等。
func opponent_of(p: PlayerState) -> PlayerState:
	var vid := get_target(p.pid)
	if vid >= 0:
		var q := get_player(vid)
		if q != null and q.pid != p.pid and not q.dead:
			return q
	var n := players.size()
	var best: PlayerState = null
	var best_qi := 1 << 30
	var best_dist := 1 << 30
	for e in players:
		if e.pid == p.pid or e.dead:
			continue
		var dist: int = (e.pid - p.pid + n) % n
		if e.qi < best_qi or (e.qi == best_qi and dist < best_dist):
			best = e
			best_qi = e.qi
			best_dist = dist
	if best != null:
		return best
	for e in players:
		if e.pid != p.pid:
			return e
	return null


func enemies_of(p: PlayerState) -> Array:
	var out: Array = []
	for q in players:
		if q.pid != p.pid and not q.dead:
			out.append(q)
	return out


func alive_players() -> Array:
	var out: Array = []
	for p in players:
		if not p.dead:
			out.append(p)
	return out


func current_player() -> PlayerState:
	if turn_order.is_empty():
		return null
	return get_player(turn_order[turn_cursor % turn_order.size()])


func get_player(pid: int) -> PlayerState:
	for p in players:
		if p.pid == pid:
			return p
	return null


## 后手补偿配置：优先按人数查表，2 人局回落到 duelCompensation
func _compensation_for(n: int) -> Dictionary:
	var tbl: Dictionary = CardDB.rules.get("compensationByCount", {})
	if tbl.has(str(n)):
		var d: Dictionary = tbl[str(n)]
		if bool(d.get("enabled", true)):
			return d
		return {}
	if n == 2:
		var dc: Dictionary = CardDB.rules.get("duelCompensation", {})
		if bool(dc.get("enabled", false)):
			return dc
	return {}


func res_cn(res: String) -> String:
	match res:
		"wealth": return "财"
		"fa": return "法"
		"yuan": return "源"
	return res


## 取一组效果里首个类型（用于推导特效名）
func _first_etype(effects: Array) -> String:
	if effects.is_empty():
		return ""
	return str((effects[0] as Dictionary).get("type", ""))


func log_msg(t: String) -> void:
	log_message.emit(t)


# ==================================================================== 回合流程
## 返回 true 表示该玩家回合正式开始；false 表示跳过了死亡玩家（调用方应继续循环）
func start_turn() -> bool:
	if finished:
		return false
	var p := current_player()
	if p == null:
		return false
	if p.dead:
		advance_cursor()
		return false

	p.turn_index += 1
	p.reset_turn_flags()
	# 场面：冷却与状态递减
	for u in p.board:
		u.tick_cooldown()          # 内部同步清理 cooldown_span
		if u.frozen > 0:
			u.frozen -= 1
		if u.qi_blocked > 0:
			u.qi_blocked -= 1
		if u.sealed > 0:
			u.sealed -= 1
		if u.passive_sealed > 0:
			u.passive_sealed -= 1
	# 临时单位（三清铃召唤的【僵尸】）计时：归零即「退场」。
	# 【注意】是退场不是拔除 —— 刻意不走 remove_unit，
	# 因此不触发下场技能、也不给对手任何收益（对手白嫖到收益就变成负反馈了）。
	var leaving: Array = []
	for u3 in p.board:
		if u3.temp_turns > 0:
			u3.temp_turns -= 1
			if u3.temp_turns <= 0:
				leaving.append(u3)
	for u4 in leaving:
		p.board.erase(u4)
		u4.on_board = false
		p.discard.append(u4)
		log_msg("◈ 临时单位 %s 时限已到，退场" % u4.name)
	# 辟邪（铜钱剑）每回合消 1 层
	if p.ward > 0:
		p.ward -= 1
		log_msg("◈ %s 的【辟邪】-1（余 %d 层）" % [p.display_name, p.ward])
	if p.chara_cd > 0:
		p.chara_cd -= 1
	# 拜神 / 敬鬼：跨回合冷却（默认 3）。与 chara_cd 同款：用掉置 3，每到自己回合 -1。
	if p.worship_cd > 0:
		p.worship_cd -= 1
	p.clear_temp_buffs()

	log_msg("— 第 %d 回合 · %s（%s）行动 —" % [p.turn_index, p.display_name, p.seat])
	turn_started.emit(p.pid)

	# 1. 结算【财】
	settle_wealth(p)

	# 1.5 场上被动光环的回合开始结算
	# aura_start_shield / aura_turn_draw 是「每回合都吃」的持续收益，
	# 必须挂在回合开始，而不是上场那一下 —— 否则一张 1 阶卡等于永久收益白拿一次。
	var sh := p.aura_start_shield()
	if sh > 0:
		p.shield_qi += sh
		log_msg("◈ 场上被动：%s 获得 %d 点护盾【气】" % [p.display_name, sh])
	var td := p.aura_turn_draw()
	if td > 0:
		draw_cards(p, td)
		log_msg("◈ 场上被动：%s 额外抽 %d 张牌" % [p.display_name, td])

	# 2. 免费三选一（强制）
	open_draft(false)
	state_changed.emit()
	return true


## 结算【财】——凡人阵营每回合累加
func settle_wealth(p: PlayerState) -> void:
	if p.is_mortal_faction():
		var curve: Array = CardDB.rules.get("wealthCurve", [3, 3, 4, 4, 5, 5])
		var idx: int = clampi(p.turn_index - 1, 0, curve.size() - 1)
		var gain: int = int(curve[idx]) + p.aura_wealth()
		p.add_res("wealth", gain)
		log_msg("【财】结算：%s +%d（累计 %d）" % [p.display_name, gain, p.wealth])
	elif p.is_shaman():
		log_msg("【财】结算：%s 为萨满，无法使用【财】" % p.display_name)
	elif p.is_buddha_faction():
		log_msg("【财】结算：%s 为佛门，无法获得【财】（每回合免费三选一【护法金刚】）" % p.display_name)

	# 正一道士：【法】的自然增长（每回合少量）
	if p.ren_type == "正一道士":
		p.add_res("fa", 1)
	# 阴阳师：【源】的自然增长
	if p.ren_type == "阴阳师":
		p.add_res("yuan", 1)
	# 场上被动：每回合额外【法】/【源】（与出身无关，谁都吃）
	var fg := p.aura_fa_gain()
	if fg > 0:
		p.add_res("fa", fg)
		log_msg("◈ 场上被动：%s 额外获得 %d 点【法】" % [p.display_name, fg])
	var yg := p.aura_yuan_gain()
	if yg > 0:
		p.add_res("yuan", yg)
		log_msg("◈ 场上被动：%s 额外获得 %d 点【源】" % [p.display_name, yg])
	# 佛门：免费获得 1 张护法金刚（每回合）
	if p.is_buddha_faction():
		var g := CardDB.random_card_by_tag(rng, "护法金刚")
		if g:
			g.owner_id = p.pid
			p.hand.append(g)
			log_msg("%s 每回合免费获得【护法金刚】×1" % p.display_name)
	# 萨满：每回合从各玩家手中抢 1 张
	if p.is_shaman():
		for e in enemies_of(p):
			if e.is_buddha_faction():
				continue          # 佛属性角色不可被抢
			steal_hand(p, e, 1)


# ==================================================================== 三选一
## 三选一 = 一个「取牌台」：点一张直接拿走。
##   · 每回合前 draftFreePerTurn 次取牌免费（不计【财】）
##   · 免费额度用完后，每次取牌消耗 buyCost（默认 3【财】）
##   · 取走一张后该位置立刻补一张，牌面始终保持 3 张，直到玩家收起 / 结束回合
func open_draft(after_buy: bool = false) -> void:
	current_draft = roll_draft(int(CardDB.rules.get("draftCount", 3)))
	draft_cost_paid = after_buy
	draft_opened.emit(current_draft)
	state_changed.emit()


## 收起牌面（玩家主动关闭，或回合结束）
func close_draft() -> void:
	if current_draft.is_empty():
		return
	current_draft = []
	state_changed.emit()


## 生成三选一选项（不给【人】牌、不给开局自带的拜神/敬鬼）
##
## 【为什么去掉了「聚卡偏置」】原来的偏置是「优先给出手牌里已有的同名卡，帮玩家凑 3 张合成」。
## 合成整条移除后，这条偏置从「有用」直接翻转成「有害」：
##   ① 相同卡牌不能同时上场（boardUnique），第二张同名卡上不了场；
##   ② 又没有合成路径，第二张同名卡连升阶都用不掉；
## 于是它只剩「占一个手牌位 + 弃置换 1 点资源」的价值，等于三选一里明摆着塞废牌。
## 现在改成反向偏置：优先给出**手牌里还没有的卡**，并且三张选项之间也不重复。
## 道具的刷出概率与「一局最多 2 次」的限额由 CardDB.random_draft_card 统一处理。
func roll_draft(n: int) -> Array:
	var out: Array = []
	var p := current_player()
	for i in n:
		var c: CCard = null
		if p:
			var owned: Dictionary = {}
			for h in p.hand:
				owned[h.id] = true
			for o in out:
				owned[o.id] = true
			for _try in 12:
				var cand: CCard = CardDB.random_draft_card(rng, p)
				if cand == null:
					break
				if not owned.has(cand.id):
					c = cand
					break
		if c == null:
			c = CardDB.random_draft_card(rng, p)
		if c:
			c.owner_id = p.pid if p else 0
			out.append(c)
	return out


## 本次取牌需要花多少【财】（0 = 还在免费额度内）
func draft_take_cost(p: PlayerState) -> int:
	if p == null:
		return 0
	if p.draft_free_left > 0:
		return 0
	return buy_cost()


## 能否再取一张（牌面非空 + 轮到自己 + 付得起 + 未超出付费上限）
func can_take_draft(p: PlayerState) -> bool:
	if p == null or current_draft.is_empty():
		return false
	if not is_my_turn(p):
		return false
	var cost := draft_take_cost(p)
	if cost <= 0:
		return true
	if not p.is_mortal_faction():
		return false          # 非凡人阵营没有【财】，只能吃免费额度
	var cap := int(CardDB.rules.get("draftPaidCapPerTurn", 3))
	if p.draft_paid_count >= cap:
		return false
	return p.res_amount("wealth") >= cost


## 取牌（免费 / 付费统一入口）。取走的位置立刻补一张新牌。
func do_take_draft(idx: int) -> bool:
	var p := current_player()
	if p == null or idx < 0 or idx >= current_draft.size():
		return false
	if not can_take_draft(p):
		return false
	var cost := draft_take_cost(p)
	if cost > 0:
		p.spend_res("wealth", cost)
		p.draft_paid_count += 1
	else:
		p.draft_free_left -= 1
	var c: CCard = current_draft[idx]
	c.owner_id = p.pid
	p.hand.append(c)
	_note_item_obtained(p, c)
	p.draft_used = true
	if cost > 0:
		log_msg("%s 花 %d【财】购入 %s" % [p.display_name, cost, c.tag_label()])
	else:
		log_msg("%s 三选一取得 %s（免费）" % [p.display_name, c.tag_label()])
	var nc := CardDB.random_draft_card(rng, p)
	if nc:
		nc.owner_id = p.pid
		current_draft[idx] = nc
	else:
		current_draft.remove_at(idx)
	draft_opened.emit(current_draft)
	state_changed.emit()
	return true


## 兼容旧调用（AI / 测试）：等价于 do_take_draft
func pick_draft(idx: int) -> bool:
	return do_take_draft(idx)


# ==================================================================== 刷新 / 购买
## 刷新费用：免费1次 -> 1财 -> 2财 -> 3财
func refresh_cost(p: PlayerState) -> int:
	if not p.free_refresh_used:
		return 0
	var ladder: Array = CardDB.rules.get("refreshCostLadder", [1, 2, 3])
	var i: int = clampi(p.refresh_count, 0, ladder.size() - 1)
	return int(ladder[i])


## 免费刷新对所有阵营开放；付费刷新只有持有【财】的凡人阵营能做
func can_refresh(p: PlayerState) -> bool:
	if current_draft.is_empty():
		return false
	if p == null or not is_my_turn(p):
		return false
	var cost := refresh_cost(p)
	if cost <= 0:
		return true
	if not p.is_mortal_faction():
		return false
	return p.res_amount("wealth") >= cost


## 能否「开出一批牌面」—— 卡牌商店的判据。
## 【★ 为什么不能复用 can_refresh】can_refresh() 第一句就是
##   `if current_draft.is_empty(): return false`：它服务的是牌面里那枚「刷新」按钮
##   （牌面都不在，刷新什么？）。而卡牌商店恰恰是**在牌面为空时**才需要它 ——
##   两者的定义域正好互补。之前商店直接调 can_refresh，于是「收起牌面再点商店」
##   永远落进 else 分支弹一句「【财】不足，开不了张」—— 明明口袋里 12 财。
func can_open_draft(p: PlayerState) -> bool:
	if p == null or not is_my_turn(p):
		return false
	if not current_draft.is_empty():
		return true
	var cost := refresh_cost(p)
	if cost <= 0:
		return true
	if not p.is_mortal_faction():
		return false
	return p.res_amount("wealth") >= cost


func do_refresh() -> bool:
	var p := current_player()
	# 用 can_open_draft：刷新按钮（牌面在）与商店开张（牌面空）都要走得通
	if not can_open_draft(p):
		return false
	var cost := refresh_cost(p)
	if cost > 0:
		p.spend_res("wealth", cost)
	if not p.free_refresh_used:
		p.free_refresh_used = true
	else:
		p.refresh_count += 1
	current_draft = roll_draft(int(CardDB.rules.get("draftCount", 3)))
	log_msg("%s 刷新牌面（花费 %d【财】）" % [p.display_name, cost])
	draft_opened.emit(current_draft)
	state_changed.emit()
	return true


func buy_cost() -> int:
	return int(CardDB.rules.get("buyCost", 3))


## 旧接口：购买 = 付费取牌（保留给测试与外部脚本）
func can_buy(p: PlayerState, idx: int) -> bool:
	if idx < 0 or idx >= current_draft.size():
		return false
	return can_take_draft(p)


func do_buy(idx: int) -> bool:
	return do_take_draft(idx)


# ==================================================================== 拜神 / 敬鬼
## 拜神 / 敬鬼的冷却回合数（用户要求：3 回合）。语义 = 「用一次之后要等 3 个自己的回合」。
func worship_cooldown() -> int:
	return maxi(1, int(CardDB.rules.get("worshipCooldown", 3)))


func can_worship(p: PlayerState) -> bool:
	if p == null or p.worship_cd > 0:
		return false
	if not is_my_turn(p):
		return false
	return true


## kind: "shen" 请神（天） / "gui" 敬鬼（地）
func do_worship(kind: String) -> Dictionary:
	var p := current_player()
	if not can_worship(p):
		return {"ok": false, "msg": "拜神/敬鬼冷却中（剩 %d 回合）" % (p.worship_cd if p != null else 0)}
	p.worship_cd = 0 if (Dev.enabled and Dev.no_cooldown) else worship_cooldown()
	var dice := rng.randi_range(int(CardDB.rules.get("diceMin", 1)), int(CardDB.rules.get("diceMax", 6)))
	var got: Array = []
	for i in dice:
		var subs: Array = ["神", "佛"] if kind == "shen" else ["妖", "鬼", "魔"]
		var c := CardDB.random_card_by_sub(rng, subs)
		if c:
			c.owner_id = p.pid
			p.hand.append(c)
			got.append(c)
	log_msg("%s %s，掷得 %d 点，获得 %d 张【%s】牌" % [
		p.display_name, "请神" if kind == "shen" else "敬鬼", dice, got.size(),
		"天" if kind == "shen" else "地"])
	state_changed.emit()
	return {"ok": true, "dice": dice, "cards": got}


# ==================================================================== 弃置换资源
## 【★ 用户要求】弃置**可以全部弃掉**，不必保底留 1 张。
## 旧版 `hand.size() > 1` 是为了防「把手牌弃空之后无牌可打」，
## 但那是设计上的越权 —— 玩家愿意清空手牌换资源就该允许（且弃置本身不消耗行动数）。
func can_discard(p: PlayerState) -> bool:
	return p != null and p.hand.size() > 0


## 弃一张会换到哪种资源 —— 与 do_discard(auto) 的口径**同一处**维护，
## 让 UI 能在点击瞬间就放对音效（财 → 铜钱声），不必等状态回读。
func discard_res(p: PlayerState) -> String:
	if p == null:
		return "wealth"
	if p.is_mortal_faction():
		return "wealth"
	elif p.ren_type == "正一道士":
		return "fa"
	elif p.ren_type == "阴阳师":
		return "yuan"
	return "wealth"


## 弃 1 张牌换 1 点资源（按阵营）
func do_discard(uid: int, res: String = "auto") -> bool:
	var p := current_player()
	if p == null or p.hand.is_empty():
		return false
	var c := p.find_hand(uid)
	if c == null:
		return false
	if res == "auto":
		res = discard_res(p)
	p.hand.erase(c)
	p.discard.append(c)
	var gain: int = int(CardDB.rules.get("discardGain", {}).get(res, 1))
	if p.is_mortal_faction() or true:
		p.add_res(res, gain)
	log_msg("【弃置】%s 弃掉 %s，获得 %d 点【%s】" % [p.display_name, c.tag_label(), gain, res_cn(res)])
	state_changed.emit()
	return true


# ==================================================================== 升级【人】
func upgrade_info(p: PlayerState) -> Dictionary:
	var cost: int = int(p.ren.get("upgradeCost", 3)) - p.aura_upgrade_discount()
	cost = maxi(1, cost)
	var res: String = p.ren.get("upgrade", "none")
	var qi_gain: int = int(p.ren.get("upgradeQi", 2))
	match p.ren_type:
		"凡人", "巫女":
			return {"ok": true, "res": "wealth", "cost": cost, "qi": qi_gain,
					"desc": "花 %d【财】买【人】，+%d【气】" % [cost, qi_gain]}
		"正一道士":
			return {"ok": true, "res": "fa", "cost": cost, "qi": qi_gain,
					"desc": "消耗 %d【法】收【徒】，+%d【气】" % [cost, qi_gain]}
		"阴阳师":
			return {"ok": true, "res": "yuan", "cost": cost, "qi": qi_gain,
					"desc": "消耗 %d【源】收【阴阳师】，+%d【气】" % [cost, qi_gain]}
		"法师":
			return {"ok": p.believers > 0, "res": "believer", "cost": 1,
					"qi": 3, "desc": "消耗 1【信众】，+3【气】并 +1【阿弥陀佛】（当前信众 %d）" % p.believers}
		"萨满":
			return {"ok": false, "res": "none", "cost": 0, "qi": 0,
					"desc": "萨满不能升级【人】，靠每回合抢牌"}
	return {"ok": false, "res": "none", "cost": 0, "qi": 0, "desc": "无法升级"}


func can_upgrade(p: PlayerState) -> bool:
	var info := upgrade_info(p)
	if not info["ok"]:
		return false
	if info["res"] == "believer":
		return p.believers >= 1
	return p.res_amount(info["res"]) >= int(info["cost"])


func do_upgrade() -> bool:
	var p := current_player()
	if not can_upgrade(p):
		return false
	var info := upgrade_info(p)
	if info["res"] == "believer":
		p.believers -= 1
	else:
		p.spend_res(info["res"], int(info["cost"]))
	p.ren_count += 1
	p.heal_qi(int(info["qi"]))
	# 增加【人】后，场上【天】的【祇】上限同步提升（并等量回血，体现"人多势众"）
	for u in p.board:
		if u.is_tian():
			var nb := p.tian_base_hp(u)
			var delta: int = maxi(0, nb - u.max_hp)
			u.max_hp = maxi(u.max_hp, nb)
			u.cur_hp = mini(u.max_hp, u.cur_hp + delta)
	log_msg("【升级·人】%s → 第 %d 张【人】，%s" % [p.display_name, p.ren_count, info["desc"]])
	state_changed.emit()
	return true


## 阴阳师 / 巫女：消耗千纸鹤召唤式神
## 【为什么是两种人】用户指定：式神按钮只对「阴阳师」与「巫女」开放，
## 且两者共用同一套千纸鹤机制（己方单位被拔除时获得）。
static func is_shikigami_ren(t: String) -> bool:
	return t == "阴阳师" or t == "巫女"


func do_summon_shikigami() -> bool:
	var p := current_player()
	if p == null or not is_shikigami_ren(p.ren_type):
		return false
	var free_crane := Dev.enabled and Dev.infinite_crane
	if p.paper_cranes <= 0 and not free_crane:
		return false
	if not free_crane:
		p.paper_cranes -= 1
	p.shikigami += 1
	# 每 2 个式神提供 2 点护盾气
	if p.shikigami % 2 == 0:
		p.shield_qi += int(CardDB.rules.get("shikigamiQi", 2))
		log_msg("【式神】2 个式神为阴阳师提供 %d 点护盾【气】" % int(CardDB.rules.get("shikigamiQi", 2)))
	else:
		log_msg("【式神】召唤 1 个式神（累计 %d 个）" % p.shikigami)
	state_changed.emit()
	return true


# ==================================================================== 起乩（上场）
## 上场后不可下场、不可合成
## 当前可同时上场的【非道具】卡牌上限 —— 与「轮数」挂钩：前期少、后期多。
## 配置见 rules.json 的 boardCap：clamp(base + 轮数 * perRound, base, max)。
## 道具是即时结算的消耗品，不占场位，所以不计入。
func board_cap(p: PlayerState = null) -> int:
	# 测试训练场：解除场位上限（把整套组合铺满，一次看完互动效果）
	if Dev.enabled and Dev.no_board_cap:
		return 999
	var cfg: Dictionary = CardDB.rules.get("boardCap", {})
	if not bool(cfg.get("enabled", true)):
		return 999
	var base: int = maxi(1, int(cfg.get("base", 2)))
	var per: int = int(cfg.get("perRound", 1))
	var cap: int = base + maxi(0, round_no) * per
	cap = clampi(cap, base, maxi(base, int(cfg.get("max", 7))))
	# 特殊技能 / 角色可以「额外多上几张」
	if p != null:
		cap += maxi(0, p.board_bonus)
	return cap


func board_cap_label() -> String:
	return "第 %d 轮上限 %d 张" % [round_no, board_cap()]


## 为什么这张牌上不了场？返回 "" 表示可以。
## 单独做成函数是为了让 UI 能拿到**具体原因**去提示玩家，
## 而不是只丢一句「无法起乩」让人摸不着头脑。
func play_block_reason(p: PlayerState, uid: int) -> String:
	var c := p.find_hand(uid)
	if c == null:
		return "这张牌不在手牌里"
	if c.sealed > 0:
		return "该牌被封锁，本回合不能上场"
	# 道具即时结算、不留场，不受场位上限与同名限制
	if c.faction == "道具":
		return ""
	# 需求：相同卡牌不能同时上场
	if bool(CardDB.rules.get("boardUnique", {}).get("enabled", true)) and p.board_has_id(c.id):
		return "场上已有同一张【%s】，不能重复上场" % c.name
	# 需求：上场上限与轮数挂钩（临时单位【僵尸】不占数额）
	var cap := board_cap(p)
	if p.board_occupied() >= cap:
		return "场上已达上限（第 %d 轮最多 %d 张），先让卡牌下场或等下一轮" % [round_no, cap]
	return ""


func can_play(p: PlayerState, uid: int) -> bool:
	return play_block_reason(p, uid) == ""


func do_play(uid: int) -> bool:
	var p := current_player()
	if not can_play(p, uid):
		return false
	var c := p.find_hand(uid)
	# 道具：拖入即释放（消耗品，不占场位），结算后进弃置区。
	# 【必须在 erase 之前分流】use_item 自己负责「从手牌移除 + 进弃置」，
	# 如果这里先 erase 再调 use_item，失败回滚时就找不到这张牌了。
	if c.faction == "道具":
		return use_item(p, c, {})
	p.hand.erase(c)
	c.on_board = true
	c.owner_id = p.pid
	c.set_cooldown(0)
	if c.is_tian():
		c.max_hp = p.tian_base_hp(c)
		c.cur_hp = c.max_hp
	else:
		c.max_hp = c.hp
		c.cur_hp = c.max_hp
	p.board.append(c)
	log_msg("%s 起乩：%s 上场（生命 %d）" % [p.display_name, c.tag_label(), c.cur_hp])

	# 护法金刚羁绊 → 直接发一张【降魔杵】手牌（不再是旧版的「计数器」）
	if c.tags.has("护法金刚"):
		p.guardians_played += 1
		var need: int = int(CardDB.rules.get("guardianBond", {}).get("need", 4))
		if p.guardians_played >= need and not p.vajra_got:
			p.vajra_got = true
			var vc := CardDB.instantiate_card("item_root_007")
			if vc != null:
				vc.owner_id = p.pid
				p.hand.append(vc)
				_note_item_obtained(p, vc)
				log_msg("★ 羁绊达成【护法金刚】×%d → 获得 1 张【降魔杵】！" % p.guardians_played)

	# 上场技能
	EffectRunner.run_all(self, c.skill_effects("on_play"), p,
		{"source": c, "fx": c.skill_fx("on_play")})
	_apply_on_play_ultimate(p, c)
	card_played.emit(p.pid, c)
	state_changed.emit()
	return true


## 3 阶解锁的终极效果（按 sub 强化一次）
func _apply_on_play_ultimate(p: PlayerState, c: CCard) -> void:
	if c.tier < 3:
		return
	match c.sub:
		"佛": p.heal_qi(2)
		"神": draw_cards(p, 1)
		"妖", "鬼", "魔", "奇兽": deal_qi_damage(opponent_of(p), 2, p)
	log_msg("  ↳ 终极技能触发（%s）" % c.sub)


# ==================================================================== 道具卡
## 道具不带技能，只有功能 —— 由 card["itemFunc"] 分派（源头见 tools/card_skills.py 的 ITEM_FUNCS）。
## ctx 里带落点信息：
##   ctx.target_uid  —— itemTarget == "unit"   时指向的场上卡
##   ctx.target_pid  —— itemTarget == "player" 时指向的玩家
##
## 【为什么道具必须走独立入口而不是「一个 on_play 技能」】
##   道具的功能里有指向性的（降魔杵/金刚镢/金刚钺）和全局性的（三清铃/铜钱剑/八卦镜），
##   它们的落点、目标解析、特效演出完全不同，硬塞进 EffectRunner 的效果池里会让
##   那个 match 分支膨胀得无法维护，而且「指向哪张卡」这件事在效果层拿不到上下文。
func _note_item_obtained(p: PlayerState, c: CCard) -> void:
	# 记录「本局该道具已获得几次」，用于每种道具一局最多 2 次的上限。
	if p == null or c == null or not c.is_item():
		return
	p.note_item_got(c.name)


## 在所有玩家的场面里定位一张卡（多人局要能跨玩家找到目标）
func locate_board_card(uid: int) -> Dictionary:
	for q in players:
		var cc: CCard = q.find_board(uid)
		if cc != null:
			return {"player": q, "card": cc}
	return {}


## 道具落点是否成立。返回 {ok, reason}。
## 【为什么要有前置校验】
##   原来的写法是「先把牌从手牌抹掉、再进 _item_xxx 里判目标，判不过就 log 一句『牌仍被消耗』」。
##   AI 拿着一手道具乱指的时候，会出现「一张 3 阶强度的道具被系统自己吃掉、什么都没发生」，
##   那是纯粹的负反馈。所以改成：目标不合法 → 牌原地留着，给玩家一句能看懂的原因。
func can_use_item(p: PlayerState, c: CCard, ctx: Dictionary = {}) -> Dictionary:
	if p == null or c == null or not c.is_item():
		return {"ok": false, "reason": "这不是道具卡"}
	if c.item_func == "":
		return {"ok": false, "reason": "【%s】只能在专属卡位使用，不能拖入手牌结算" % c.name}
	match c.item_target:
		"unit":
			# 指向对方场上一张具体卡（降魔杵 / 金刚镢）
			var uid := int(ctx.get("target_uid", -1))
			var loc := locate_board_card(uid)
			if loc.is_empty():
				return {"ok": false, "reason": "【%s】需要指向对方场上一张卡" % c.name}
			if (loc["player"] as PlayerState).pid == p.pid:
				return {"ok": false, "reason": "【%s】只能指向对方的卡" % c.name}
			return {"ok": true, "reason": ""}
		"player":
			# 指向某个对手本人（金刚钺）
			var tpid := int(ctx.get("target_pid", -1))
			for q in players:
				if q.pid == tpid and q.pid != p.pid:
					return {"ok": true, "reason": ""}
			return {"ok": false, "reason": "【%s】需要指向一位对手" % c.name}
		_:
			return {"ok": true, "reason": ""}


func use_item(p: PlayerState, c: CCard, ctx: Dictionary = {}) -> bool:
	if p == null or c == null or not c.is_item():
		return false
	var chk := can_use_item(p, c, ctx)
	if not chk.get("ok", false):
		log_msg("✗ %s" % chk.get("reason", "道具无法使用"))
		state_changed.emit()
		return false
	p.hand.erase(c)
	c.on_board = false
	var ok := false
	match c.item_func:
		"purge":     ok = _item_purge(p, c, ctx)
		"seal":      ok = _item_seal(p, c, ctx)
		"zombies":   ok = _item_zombies(p, c)
		"ward":      ok = _item_ward(p, c)
		"reveal_di": ok = _item_reveal_di(p, c)
		"axe":       ok = _item_axe(p, c, ctx)
		_:
			log_msg("✗ 道具【%s】的功能键「%s」没有实现" % [c.name, c.item_func])
	p.discard.append(c)
	state_changed.emit()
	return ok


## 降魔杵：指向对方场上一张卡 → 直接拔除（特效：红色书法「降」）
func _item_purge(p: PlayerState, c: CCard, ctx: Dictionary) -> bool:
	var loc := locate_board_card(int(ctx.get("target_uid", -1)))
	if loc.is_empty():
		return false
	var owner_p: PlayerState = loc["player"]
	var t: CCard = loc["card"]
	log_msg("★ %s 掷出【降魔杵】—— 降！目标 %s" % [p.display_name, t.tag_label()])
	effect_fired.emit({"kind": "item_calligraphy", "text": "降", "tone": "cinnabar",
		"uid": t.uid, "pid": owner_p.pid, "caster": p.pid,
		"name": "降魔杵", "sub": "直接拔除目标"})
	remove_unit(t, p, "降魔杵")
	return true


## 金刚镢：指向对方场上一张卡 → 该卡下回合无法行动，被动一并封印（特效：金色书法「封」）
func _item_seal(p: PlayerState, c: CCard, ctx: Dictionary) -> bool:
	var loc := locate_board_card(int(ctx.get("target_uid", -1)))
	if loc.is_empty():
		return false
	var owner_p: PlayerState = loc["player"]
	var t: CCard = loc["card"]
	# frozen / passive_sealed 都在「目标自己的回合开始时」递减一次，
	# 所以要让它在**下一个回合**里全程失效，必须给 2（2→1 仍 >0，整回合被封；下一回合才归零）。
	t.frozen = maxi(t.frozen, 2)
	t.passive_sealed = maxi(t.passive_sealed, 2)
	log_msg("★ %s 掷出【金刚镢】—— 封！%s 下回合无法行动，被动被封印" % [p.display_name, t.name])
	effect_fired.emit({"kind": "item_calligraphy", "text": "封", "tone": "gold",
		"uid": t.uid, "pid": owner_p.pid, "caster": p.pid,
		"name": "金刚镢", "sub": "封印行动与被动"})
	return true


## 三清铃：拖入己方场地 → 召唤 3 张临时【僵尸】，3 回合后退场
func _item_zombies(p: PlayerState, c: CCard) -> bool:
	var zid := CardDB.find_id_by_name("僵尸")
	if zid == "":
		log_msg("✗ 【三清铃】失败：卡池里找不到【僵尸】")
		return false
	var got: Array = []
	for i in 3:
		var z := CardDB.instantiate_card(zid)
		if z == null:
			break
		z.owner_id = p.pid
		z.temp_turns = 3
		summon(p, z, true)
		got.append(z)
	log_msg("★ %s 摇响【三清铃】—— 召唤 %d 张临时【僵尸】（在场 3 回合后自动退场）"
		% [p.display_name, got.size()])
	effect_fired.emit({"kind": "item_zombies", "pid": p.pid, "count": got.size(),
		"name": "三清铃", "uids": got.map(func(z): return z.uid)})
	return not got.is_empty()


## 铜钱剑：拖入己方场地 → 己方【人】获得 3 层【辟邪】（每回合消 1 层）
func _item_ward(p: PlayerState, c: CCard) -> bool:
	p.ward = maxi(p.ward, 3)
	log_msg("★ %s 祭起【铜钱剑】—— 己方【人】获得 3 层【辟邪】（每回合消 1 层，其间【地】卡无法袭人）"
		% p.display_name)
	effect_fired.emit({"kind": "item_ward", "pid": p.pid, "value": p.ward, "name": "铜钱剑"})
	return true


## 八卦镜：拖入己方场地 → 只向自己显示各方手牌里【地】卡的数量
func _item_reveal_di(p: PlayerState, c: CCard) -> bool:
	var info: Array = []
	for q in players:
		if q.pid == p.pid:
			continue
		var n := 0
		for h in q.hand:
			if h.is_di():
				n += 1
		info.append({"pid": q.pid, "seat": q.seat, "name": q.display_name, "count": n})
	log_msg("★ %s 照【八卦镜】—— %s" % [p.display_name, "、".join(
		info.map(func(i): return "%s 手牌【地】×%d" % [i["name"], i["count"]]))])
	effect_fired.emit({"kind": "reveal_di", "pid": p.pid, "info": info, "name": "八卦镜"})
	return true


## 金刚钺：指向某个玩家 → 巨钺砸下，对其所有上场卡造成 3 点伤害，【地】额外多受 2 点
func _item_axe(p: PlayerState, c: CCard, ctx: Dictionary) -> bool:
	var tpid := int(ctx.get("target_pid", -1))
	var tgt: PlayerState = null
	for q in players:
		if q.pid == tpid and q.pid != p.pid:
			tgt = q
			break
	if tgt == null:
		return false
	log_msg("★ %s 祭起【金刚钺】—— 巨钺自天而降，砸向 %s 的场面！" % [p.display_name, tgt.display_name])
	effect_fired.emit({"kind": "item_axe", "pid": p.pid, "target_pid": tgt.pid, "name": "金刚钺"})
	for u in tgt.board.duplicate():
		var dmg := 3
		if u.is_di():
			dmg += 2                   # 【地】单位额外受伤
		damage_unit(u, dmg, p, true, 0)
	return true


# ==================================================================== 攻击 / 主动技能
## 克制关系校验：返回 {ok, reason}
func can_attack(attacker: PlayerState, unit: CCard, target_kind: String, target: CCard) -> Dictionary:
	if not attacker.has_action():
		return {"ok": false, "reason": "本回合主动行动已用完（%d/%d）" % [attacker.actions_used, attacker.action_limit()]}
	if unit.frozen > 0:
		return {"ok": false, "reason": "该单位被封锁，本回合无法行动"}
	if unit.cooldown > 0:
		return {"ok": false, "reason": "主动技能冷却中（剩 %d 回合）" % unit.cooldown}
	var e := opponent_of(attacker)
	if target_kind == "ren":
		if unit.is_tian():
			return {"ok": false, "reason": "【神】【佛】无法对【人】造成伤害"}
		if unit.qi_blocked > 0:
			return {"ok": false, "reason": "该单位被封锁，无法对【人】发起攻击"}
		# 铜钱剑【辟邪】：地卡被完全挡在【人】之外
		if e.ward > 0 and unit.is_di():
			return {"ok": false, "reason": "对方【人】受【辟邪】护体，【地】卡无法攻击（剩 %d 层）" % e.ward}
		return {"ok": true}
	# 攻击场上单位
	if target == null:
		return {"ok": false, "reason": "目标不存在"}
	if unit.is_tian():
		if target.faction == "地":
			return {"ok": true}
		if target.faction == "天":
			return {"ok": true, "reason": "制衡：互相扣【祇】"}
		return {"ok": false, "reason": "【天】无法攻击该目标"}
	if unit.is_di():
		if target.faction == "天":
			return {"ok": false, "reason": "【地】被【天】克制，无法攻击【天】"}
		if target.faction == "地":
			if unit.is_guizu() and target.is_guizu():
				return {"ok": false, "reason": "【鬼】无法攻击【鬼】"}
			return {"ok": true}
		return {"ok": false, "reason": "非法目标"}
	return {"ok": false, "reason": "该卡不能主动攻击"}


## 执行攻击：target_kind = "ren" 或 "unit"
func do_attack(attacker_uid: int, target_kind: String, target_uid: int = -1) -> Dictionary:
	var p := current_player()
	var e := opponent_of(p)
	var u := p.find_board(attacker_uid)
	if u == null:
		return {"ok": false, "msg": "进攻单位不存在"}
	var target: CCard = null
	if target_kind == "unit":
		target = e.find_board(target_uid)
	var chk := can_attack(p, u, target_kind, target)
	if not chk["ok"]:
		log_msg("✗ " + chk["reason"])
		return {"ok": false, "msg": chk["reason"]}
	# 消耗一次主动行动额度
	p.actions_used += 1

	if target_kind == "ren":
		# 【神】被动「天威压地」：防守方场上【天】越多，袭向它的【气】伤越低
		var dmg := maxi(0, p.effective_atk_qi(u) - e.aura_enemy_di_atk())
		if dmg <= 0:
			log_msg("— %s 的【天】压制了 %s 的袭人，气伤归零" % [e.display_name, u.name])
		deal_qi_damage(e, dmg, p)
		if dmg > 0:
			log_msg("%s %s 袭向 %s 的【人】，造成 %d 点【气】伤害" % [p.display_name, u.name, e.display_name, dmg])
		# 法师（佛）降伏【地】单位：此处为直接攻击人气，不触发降伏
		u.raise_cooldown(1)
		after_action_check()
		state_changed.emit()
		return {"ok": true}

	# 场上对攻
	# 【注意】攻击力要叠加各自主人的 aura_tian_atk / aura_di_atk 被动，
	# 否则那些「己方所有【天】+1 攻」的被动就是一张画在卡面上的空头支票。
	if u.is_tian() and target.faction == "地":
		log_msg("%s 以【天】镇压 %s" % [u.name, target.tag_label()])
		remove_unit(target, p, "镇压")
		u.raise_cooldown(1)
	elif u.is_tian() and target.faction == "天":
		var d1 := u.atk + p.aura_tian_atk()
		var d2 := target.atk + e.aura_tian_atk()
		log_msg("【天】制衡：%s ↔ %s（互扣 %d / %d【祇】）" % [u.name, target.name, d2, d1])
		damage_unit(u, d2, e, false, 0)
		damage_unit(target, d1, p, false, 0)
		u.raise_cooldown(1)
	else:
		var a_dmg := u.atk + p.aura_di_atk()
		var b_dmg := target.atk + e.aura_di_atk()
		log_msg("%s ↔ %s 互击（%d / %d）" % [u.name, target.name, b_dmg, a_dmg])
		damage_unit(u, b_dmg, e, false, 0)
		damage_unit(target, a_dmg, p, false, 0)
		u.raise_cooldown(1)
	after_action_check()
	state_changed.emit()
	return {"ok": true}


## 使用场上卡牌的主动技能
func do_active(uid: int, ctx: Dictionary = {}) -> bool:
	var p := current_player()
	var u := p.find_board(uid)
	if u == null or not u.has_active():
		return false
	if u.cooldown > 0 or u.frozen > 0:
		log_msg("✗ 该单位尚在冷却/被封锁")
		return false
	if not p.has_action():
		log_msg("✗ 本回合主动行动已用完（%d/%d）" % [p.actions_used, p.action_limit()])
		return false
	p.actions_used += 1
	var a := u.skill("active")
	ctx["source"] = u
	ctx["fx"] = u.skill_fx("active")
	# 镇压的阶数上限
	ctx["chosen_tier"] = u.tier + int(a.get("effects", [{}])[0].get("tier_limit", 1)) if not a.get("effects", []).is_empty() else 0
	log_msg("%s 发动【%s】（%s）" % [p.display_name, a.get("name", ""), u.name])
	EffectRunner.run_all(self, a.get("effects", []), p, ctx)
	# 冷却至少 1 回合：数据里漏写 cd 时也不能同回合反复发动
	u.set_cooldown(maxi(1, u.active_cd()))
	after_action_check()
	state_changed.emit()
	return true


## 角色专属技能
func do_chara_skill(ctx: Dictionary = {}) -> bool:
	var p := current_player()
	if p.chara.is_empty():
		return false
	if p.chara_cd > 0:
		log_msg("✗ 专属技能冷却中（剩 %d 回合）" % p.chara_cd)
		return false
	var sk: Dictionary = p.chara.get("skill", {})
	if sk.is_empty():
		return false
	log_msg("★ %s 发动专属技能【%s】" % [p.display_name, sk.get("name", "")])
	ctx["fx"] = CCard.fx_for_type(_first_etype(sk.get("effects", [])))
	EffectRunner.run_all(self, sk.get("effects", []), p, ctx)
	# 测试训练场「无冷却」：角色技能同样立刻可再发（否则测 combo 要等 3 回合）
	p.chara_cd = 0 if (Dev.enabled and Dev.no_cooldown) else int(sk.get("cd", 3))
	after_action_check()
	state_changed.emit()
	return true


# ==================================================================== 伤害 / 拔除
func deal_qi_damage(target: PlayerState, v: int, source: PlayerState) -> void:
	if v <= 0:
		return
	var applied := target.take_qi_damage(v)
	if applied > 0:
		log_msg("  ↳ %s 的【气】-%d（余 %d）" % [target.display_name, applied, target.qi])
	else:
		log_msg("  ↳ 伤害被护盾吸收")
	effect_fired.emit({"kind": "qi_damage", "pid": target.pid, "value": applied,
		"source_pid": source.pid if source != null else -1})
	# 法师（佛）：降伏地单位获得信众 —— 由 remove_unit 处理
	check_win()


func damage_unit(unit: CCard, v: int, source: PlayerState, ignore_counter: bool = false, draw_on_kill: int = 0) -> void:
	if unit == null or not unit.on_board:
		return
	unit.cur_hp -= v
	log_msg("  ↳ %s 受到 %d 点伤害（余 %d/%d）" % [unit.name, v, maxi(unit.cur_hp, 0), unit.max_hp])
	effect_fired.emit({"kind": "unit_damage", "uid": unit.uid, "value": v,
		"source_pid": source.pid if source != null else -1})
	if unit.cur_hp <= 0:
		remove_unit(unit, source, "重伤")
		if draw_on_kill > 0:
			draw_cards(source, draw_on_kill)


## 拔除：从场上移入弃置区，触发下场技能
func remove_unit(unit: CCard, remover: PlayerState, reason: String) -> void:
	if unit == null:
		return
	var owner := get_player(unit.owner_id)
	if owner == null:
		return
	if not owner.board.has(unit):
		return
	owner.board.erase(unit)
	unit.on_board = false
	owner.discard.append(unit)
	log_msg("✦ %s 被拔除（%s）" % [unit.tag_label(), reason])
	unit_removed.emit(owner.pid, unit)

	# 下场技能（被拔除时触发）
	EffectRunner.run_all(self, unit.skill_effects("on_remove"), owner,
		{"source": unit, "fx": unit.skill_fx("on_remove")})

	# 正一道士：对方单位被拔除/钉死 → 获得【法】
	for p in players:
		if p.ren_type == "正一道士" and p.pid != owner.pid:
			var f: int = int(CardDB.rules.get("faOnKill", 1))
			p.add_res("fa", f)
			log_msg("  ↳ 正一道士 %s 获得 %d 点【法】" % [p.display_name, f])

	# 阴阳师 / 巫女：己方单位被拔除 → 获得【千纸鹤】
	if is_shikigami_ren(owner.ren_type):
		var pc: int = int(CardDB.rules.get("paperCraneOnDeath", 1))
		owner.paper_cranes += pc
		log_msg("  ↳ %s %s 获得 %d 个【千纸鹤】" % [owner.ren_type, owner.display_name, pc])

	# 法师（佛）：降伏【地】单位 → 获得【信众】
	if owner.ren_type == "法师" and unit.faction == "地":
		owner.believers += 1
		owner.amituofo += 1
		log_msg("  ↳ 法师 %s 降伏【地】单位，获得 1【信众】、+1【阿弥陀佛】" % owner.display_name)

	# 亡灵单位归位后重新清算天卡祇上限
	for u in owner.board:
		if u.is_tian():
			var nb := owner.tian_base_hp(u)
			u.max_hp = maxi(1, nb)
			u.cur_hp = mini(u.cur_hp, u.max_hp)
	check_win()


# ==================================================================== 抽牌 / 弃牌
func draw_cards(p: PlayerState, n: int) -> void:
	for i in n:
		var c := CardDB.random_card(rng)
		if c:
			c.owner_id = p.pid
			p.hand.append(c)
	log_msg("%s 抽了 %d 张牌（手牌 %d）" % [p.display_name, n, p.hand.size()])


func discard_random(p: PlayerState, n: int) -> void:
	for i in mini(n, p.hand.size()):
		var idx := rng.randi_range(0, p.hand.size() - 1)
		var c: CCard = p.hand[idx]
		p.hand.remove_at(idx)
		p.discard.append(c)
		log_msg("%s 随机弃置了 1 张手牌" % p.display_name)


func steal_hand(thief: PlayerState, victim: PlayerState, n: int) -> void:
	for i in mini(n, victim.hand.size()):
		var idx := rng.randi_range(0, victim.hand.size() - 1)
		var c: CCard = victim.hand[idx]
		victim.hand.remove_at(idx)
		c.owner_id = thief.pid
		thief.hand.append(c)
		log_msg("⚑ %s 从 %s 手中抢走 1 张手牌" % [thief.display_name, victim.display_name])


# ==================================================================== 选目标辅助
func pick_weakest_board(p: PlayerState) -> CCard:
	var best: CCard = null
	for u in p.board:
		if best == null or u.cur_hp < best.cur_hp:
			best = u
	return best


func pick_random_board(p: PlayerState) -> CCard:
	if p.board.is_empty():
		return null
	return p.board[rng.randi_range(0, p.board.size() - 1)]


func random_from_special(group: String) -> CCard:
	var gkey := "天/" + group
	var pool: Array = []
	for d in CardDB.cards:
		if d.get("group", "") == gkey:
			pool.append(d)
	if pool.is_empty():
		return null
	return CardDB.instantiate_card(pool[rng.randi_range(0, pool.size() - 1)].id)


## 直接上场（召唤，不消耗手牌）
func summon(p: PlayerState, c: CCard, silent: bool = false) -> void:
	c.on_board = true
	c.owner_id = p.pid
	if c.is_tian():
		c.max_hp = p.tian_base_hp(c)
	else:
		c.max_hp = c.hp
	c.cur_hp = c.max_hp
	p.board.append(c)
	if not silent:
		log_msg("%s 召唤 %s 上场" % [p.display_name, c.tag_label()])
	EffectRunner.run_all(self, c.skill_effects("on_play"), p,
		{"source": c, "fx": c.skill_fx("on_play")})


# ==================================================================== 回合结束
func after_action_check() -> void:
	check_win()


func end_turn() -> void:
	if finished:
		return
	var p := current_player()
	if p:
		# 回合结束：清理临时状态
		for u in p.board:
			u.extra_qi = 0
		_apply_fatigue(p)
		log_msg("— %s（%s）结束回合 —" % [p.display_name, p.seat])
	# 收起三选一牌面（玩家本回合没取的牌不带入下一回合）
	close_draft()
	advance_cursor()
	check_win()


## 力竭（防死局保险）：超过 fatigueStartRound 后，每位玩家在自己回合结束时流失【气】
## 数值随回合递增，保证任何对局都会在有限回合内分出胜负。
func _apply_fatigue(p: PlayerState) -> void:
	if p.dead:
		return
	var start := int(CardDB.rules.get("fatigueStartRound", 30))
	if round_no < start:
		return
	var step := int(CardDB.rules.get("fatigueStepRounds", 8))
	var per := 1 + int((round_no - start) / maxi(1, step))
	p.take_qi_damage(per)
	log_msg("⌛ 力竭：%s 流失 %d 点【气】（第 %d 回合）" % [p.display_name, per, round_no])


## 指针前移一位；每绕一圈 round_no +1
func advance_cursor() -> void:
	turn_cursor += 1
	if turn_order.size() > 0 and turn_cursor % turn_order.size() == 0:
		round_no += 1


func check_win() -> void:
	if finished:
		return
	var alive := alive_players()
	if alive.size() <= 1:
		finished = true
		winner_pid = alive[0].pid if alive.size() == 1 else -1
		if winner_pid >= 0:
			var w := get_player(winner_pid)
			log_msg("★★★ %s 获胜！耗尽对手【气】，天下归伏。 ★★★" % w.display_name)
		else:
			log_msg("★★★ 同归于尽，无人生还 ★★★")
		game_over.emit(winner_pid)


func is_my_turn(p: PlayerState) -> bool:
	var c := current_player()
	return c != null and c.pid == p.pid


func public_state() -> Dictionary:
	var out: Array = []
	for p in players:
		var hand_info: Array = []
		if p.hand_hidden > 0:
			hand_info = []
		out.append({
			"pid": p.pid, "name": p.display_name, "seat": p.seat,
			"qi": p.qi, "qi_max": p.qi_max, "shield": p.shield_qi,
			"wealth": p.wealth, "fa": p.fa, "yuan": p.yuan,
			"hand": p.hand.size(), "board": p.board.size(),
			"ren": p.ren_count, "ren_type": p.ren_type, "dead": p.dead,
			"chara": p.chara.get("name", ""),
		})
	return {"round": round_no, "turn": current_player().seat if current_player() else "-",
			"players": out, "finished": finished, "winner": winner_pid}
