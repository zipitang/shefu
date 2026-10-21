class_name PlayerState
extends RefCounted
## 单个玩家的完整状态：大本营【人】、【气】、资源、手牌、场面、技能冷却。

var pid: int = 0
var seat: String = "东"            ## 东 / 南 / 西 / 北
var display_name: String = ""
var is_ai: bool = false
var ai_level: int = 1              ## 1 简单 / 2 普通 / 3 困难

# ---- 角色 & 人卡 ----
var chara_id: String = ""
var chara: Dictionary = {}         ## characters.json 条目
var ren: Dictionary = {}           ## ren_cards.json 条目
var ren_type: String = "凡人"

# ---- 生存 ----
var qi: int = 12
var qi_max: int = 12
var ren_count: int = 1
var dead: bool = false

# ---- 资源 ----
var wealth: int = 0                ## 【财】
var fa: int = 0                    ## 【法】
var yuan: int = 0                  ## 【源】

# ---- 手牌 / 场面 ----
var hand: Array = []               ## Array[CCard]
var board: Array = []              ## Array[CCard]
var discard: Array = []            ## 弃置区

# ---- 特殊计数 ----
var shield_qi: int = 0             ## 护盾式【气】（式神提供，被打不掉不追伤）
var paper_cranes: int = 0          ## 千纸鹤
var shikigami: int = 0             ## 式神数量
var believers: int = 0             ## 信众
var amituofo: int = 0              ## 阿弥陀佛光环层数
var guardians_played: int = 0      ## 已起乩的护法金刚数量
var vajra_got: bool = false        ## 是否已获得降魔杵（护法金刚羁绊）
var vajra: int = 0                 ## 降魔杵数量（旧计数式入口，已改为手牌道具卡）
var round_wealth_bonus: int = 0

# ---- 场位加成 ----
## 常规玩家场位上限由规则表 boardCap 决定（封顶 7）。
## 部分技能 / 特殊角色可以「额外多上几张」，通过 board_bonus 累加到场位上限上。
var board_bonus: int = 0

## 场上「占用场位」的单位数：临时单位（三清铃召唤的【僵尸】）不占数额。
func board_occupied() -> int:
	var n := 0
	for u in board:
		if u != null and u.temp_turns <= 0:
			n += 1
	return n

# ---- 辟邪（铜钱剑）----
## 剩余层数：>0 时，其他玩家无法用【地】卡攻击本方【人】。每回合开始消 1 层。
var ward: int = 0

# ---- 道具获取记录 ----
## 道具名 -> 本局已获得次数。用于「每种道具一局最多 2 次」的上限。
var item_got: Dictionary = {}


func item_got_count(name: String) -> int:
	return int(item_got.get(name, 0))


func note_item_got(name: String) -> void:
	item_got[name] = item_got_count(name) + 1

# ---- 回合内状态 ----
var free_refresh_used: bool = false
var refresh_count: int = 0
## 拜神 / 敬鬼的剩余冷却（回合数）。0 = 可以拜。
## 【★ 为什么不再是 bool】用户要求冷却改成 3 回合 —— 旧的 `worship_used` 每回合
## reset_turn_flags() 清零，语义上只能表达「本回合用过」，撑不起多回合冷却。
var worship_cd: int = 0
var draft_used: bool = false
var draft_free_left: int = 0       ## 本回合剩余「免费取牌」次数（用完就要花【财】）
var draft_paid_count: int = 0      ## 本回合已付费取牌次数（受 draftPaidCapPerTurn 限制）
var turn_index: int = 0            ## 自己度过了几个回合
var actions_used: int = 0          ## 本回合已用的「主动行动」次数（袭人 / 场上主动技能）

# ---- 冷却 ----
var chara_cd: int = 0

# ---- 临时增益（回合结束清零） ----
var temp_qi_mult: int = 1
var temp_qi_bonus: int = 0
var temp_qi_turns: int = 0
var qi_immune: int = 0
var hand_hidden: int = 0


func setup(p_pid: int, p_seat: String, chara_def: Dictionary, ren_def: Dictionary) -> void:
	pid = p_pid
	seat = p_seat
	chara = chara_def
	chara_id = chara_def.get("id", "")
	ren = ren_def
	ren_type = ren_def.get("name", "凡人")
	qi = int(ren_def.get("qi", 12))
	qi_max = qi
	display_name = chara_def.get("name", "无名")


func reset_turn_flags() -> void:
	free_refresh_used = false
	refresh_count = 0
	# 【注意】worship_cd 不在这里清零 —— 它是跨回合冷却，由 GameState.start_turn() 递减，
	# 放在这里每回合清零就退回成「每回合各一次」了。
	draft_used = false
	draft_free_left = int(CardDB.rules.get("draftFreePerTurn", 1))
	draft_paid_count = 0
	actions_used = 0


## 本回合「主动行动」额度（袭人 / 点击场上卡发动主动技能）
## 基础值来自 rules.actionsPerTurn，场上被动 aura_action_max 可以再加。
func action_limit() -> int:
	# 测试训练场：不限行动次数（方便连点技能看演出 / 抓 bug）
	if Dev.enabled and Dev.no_action_limit:
		return Dev.BIG
	return int(CardDB.rules.get("actionsPerTurn", 2)) + aura_action_max()


func actions_left() -> int:
	return maxi(0, action_limit() - actions_used)


func has_action() -> bool:
	return actions_left() > 0


func clear_temp_buffs() -> void:
	if temp_qi_turns > 0:
		temp_qi_turns -= 1
		if temp_qi_turns <= 0:
			temp_qi_mult = 1
			temp_qi_bonus = 0
	if qi_immune > 0:
		qi_immune -= 1
	if hand_hidden > 0:
		hand_hidden -= 1


## 场上【天】单位的基础【祇】= 阶数 + 己方【人】数量
func tian_base_hp(c: CCard) -> int:
	return c.tier + ren_count - 1 + aura_tian_hp()


func aura_tian_hp() -> int:
	var v := 0
	for b in board:
		if b.is_tian():
			for e in b.skill_effects("passive"):
				if e.get("type", "") == "aura_tian_hp":
					v += int(e.get("value", 0))
	return v


# ------------------------------------------------------------------ 新增被动光环
# 【为什么要有这一段】「每张卡都有自己的被动」是硬需求，而原来 PlayerState 只认识
# 5 种 aura_*，于是 227 张卡无论起什么名字，被动效果只能反复落在同 5 条上 ——
# 名字不同、机制全同，等于换个维度继续同质化。
# 这里把「场上被动 → 数值」统一成 _aura()，再按需要暴露成语义函数；
# 新增一种被动只需：① 加一个 aura_xxx 类型名；② 在 _aura 调用点接上。
# 【铁律】凡是 aura_* 类型，必须在 PlayerState 有对应读取点，否则它会**静默失效**：
# 数据里写着、卡面也画着，实战一点作用都没有。
func _aura(t: String) -> int:
	var v := 0
	for b in board:
		for e in b.skill_effects("passive"):
			if e.get("type", "") == t:
				v += int(e.get("value", 0))
	return v


## 己方所有【天】的攻击力加成（作用于天 ↔ 天 制衡、天 → 地 镇压的伤害计算）
func aura_tian_atk() -> int:
	return _aura("aura_tian_atk")


## 己方所有【地】的攻击力加成（作用于地 ↔ 地 互击）
func aura_di_atk() -> int:
	return _aura("aura_di_atk")


## 己方回合开始时获得的护盾【气】
func aura_start_shield() -> int:
	return _aura("aura_start_shield")


## 己方回合开始时额外抽牌数
func aura_turn_draw() -> int:
	return _aura("aura_turn_draw")


## 每回合额外「主动行动」次数
func aura_action_max() -> int:
	return _aura("aura_action_max")


## 每回合额外【法】
func aura_fa_gain() -> int:
	return _aura("aura_fa_gain")


## 每回合额外【源】
func aura_yuan_gain() -> int:
	return _aura("aura_yuan_gain")


func aura_wealth() -> int:
	var v := 0
	for b in board:
		for e in b.skill_effects("passive"):
			if e.get("type", "") == "aura_wealth":
				v += int(e.get("value", 0))
	if chara.has("passive") and chara["passive"] != null:
		var pe: Dictionary = chara["passive"]
		for e in pe.get("effects", []):
			if e.get("type", "") == "aura_wealth":
				v += int(e.get("value", 0))
	return v


## 【神】被动「天威压地」：削减「敌方【地】袭向本方【人】」的【气】伤（返回正值）
## 注意：取【最大值】而非累加 —— 否则多张【神】叠加会把【地】唯一的斩首路径彻底封印，
## 导致对局永远打不完（实测出现过 678 回合不结束的死局）。
func aura_enemy_di_atk() -> int:
	var v := 0
	for b in board:
		for e in b.skill_effects("passive"):
			if e.get("type", "") == "aura_enemy_di_atk":
				v = maxi(v, int(e.get("value", 0)))
	return v


func aura_di_qi_bonus() -> int:
	var v := 0
	for b in board:
		for e in b.skill_effects("passive"):
			if e.get("type", "") == "aura_self_di_qi":
				v += int(e.get("value", 0))
	return v


## 【奇兽】被动：升级【人】的资源折扣（返回正值）
func aura_upgrade_discount() -> int:
	var v := 0
	for b in board:
		for e in b.skill_effects("passive"):
			if e.get("type", "") == "aura_upgrade_cost":
				v += int(e.get("value", 0))
	return v


## 有效气伤（对【人】）
func effective_atk_qi(c: CCard) -> int:
	var base := c.atk_qi + aura_di_qi_bonus() + c.extra_qi
	if temp_qi_turns > 0:
		base = int(base * temp_qi_mult) + temp_qi_bonus
	return maxi(base, 0)


func hand_count() -> int:
	return hand.size()


func board_count() -> int:
	return board.size()


func total_qi() -> int:
	return qi + shield_qi


## 是否属于凡人属性阵营（可以使用【财】）
func is_mortal_faction() -> bool:
	return ren_type in ["凡人", "正一道士", "阴阳师", "巫女"]


func is_buddha_faction() -> bool:
	return ren_type == "法师"


func is_shaman() -> bool:
	return ren_type == "萨满"


func res_amount(res: String) -> int:
	# 测试训练场：无限资源时返回大数，让所有 `>= cost` 的门槛自然通过
	# （can_upgrade / can_take_draft / can_refresh … 全走这里，不必逐个加判断）
	if Dev.res_infinite(res):
		return Dev.BIG
	match res:
		"wealth": return wealth
		"fa": return fa
		"yuan": return yuan
	return 0


func add_res(res: String, v: int) -> void:
	match res:
		"wealth": wealth = maxi(0, wealth + v)
		"fa": fa = maxi(0, fa + v)
		"yuan": yuan = maxi(0, yuan + v)


func spend_res(res: String, v: int) -> bool:
	# 测试训练场：无限资源 —— 门槛照过，但**不真的扣**。
	# 【为什么不做成「扣完再补回来」】那样资源数字会跳一下，而且和 aura 的加成
	# 叠加后会溢出成奇怪的值；直接短接才是干净的。
	if Dev.res_infinite(res):
		return true
	if res_amount(res) < v:
		return false
	add_res(res, -v)
	return true


## 掉气（护盾优先，护盾被打破不追伤）
func take_qi_damage(v: int) -> int:
	# 测试训练场：全场不死的开关。放在**唯一入口**上 —— 袭人、力竭、技能气伤
	# 全部经过这里，一处生效即全局生效，不会漏掉某条伤害路径。
	if Dev.enabled and Dev.no_qi_loss:
		return 0
	if qi_immune > 0:
		return 0
	if shield_qi > 0:
		var absorbed := mini(shield_qi, v)
		shield_qi -= absorbed
		v -= absorbed
	if v > 0:
		qi = maxi(0, qi - v)
	if qi <= 0:
		dead = true
	return v


func heal_qi(v: int) -> void:
	qi = mini(qi_max, qi + v)


func find_hand(uid: int) -> CCard:
	for c in hand:
		if c.uid == uid:
			return c
	return null


func find_board(uid: int) -> CCard:
	for c in board:
		if c.uid == uid:
			return c
	return null


## 场上是否已有**同一张卡**（同一卡牌定义 id，跨阶数也算同一张）。
## 用于「相同卡牌不能同时上场」的限制。
func board_has_id(card_id: String) -> bool:
	for c in board:
		if c.id == card_id:
			return true
	return false


func summary() -> String:
	return "%s(%s) 气%d/%d 财%d 法%d 源%d 手牌%d 场面%d" % [
		display_name, seat, qi, qi_max, wealth, fa, yuan, hand.size(), board.size()
	]
