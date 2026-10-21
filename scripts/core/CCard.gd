class_name CCard
extends RefCounted
## 卡牌运行时实例
## 一张卡从卡池抽出 -> 手牌 -> 起乩上场 -> 被拔除，全程由本对象承载状态。

var uid: int = -1
var id: String = ""
var name: String = ""
var faction: String = "天"      ## 天 / 地 / 道具
var sub: String = ""            ## 佛 神 妖 鬼 魔 奇兽 道具
var group: String = ""
var tier: int = 1
var base_tier: int = 1          ## 卡池中的阶数（阶数固定，不会改变）
var max_tier: int = 1           ## == tier；「升阶」路径已整条移除，保留字段只为兼容旧数据

var hp: int = 1                 ## 基础生命（天=祇基数 / 地=体质）
var atk: int = 1                ## 单位对单位伤害
var atk_qi: int = 0             ## 对【人】的气伤

var art: String = ""
var thumb: String = ""
var tags: Array = []
var skills: Dictionary = {}
var desc: String = ""
## 道具功能键与落点类型（只对 faction == "道具" 有意义，见 tools/card_skills.py 的 ITEM_FUNCS）
var item_func: String = ""
var item_target: String = ""

# ---- 运行时状态 ----
var cur_hp: int = 1
var max_hp: int = 1
var on_board: bool = false
var owner_id: int = 0
var cooldown: int = 0           ## 主动技能剩余冷却
var cooldown_span: int = 0      ## 本次冷却的总回合数（UI 画「褪去」进度用；进冷却时写入）
var frozen: int = 0             ## 被冻结回合数
var qi_blocked: int = 0         ## 被封锁气伤的回合数
var sealed: int = 0             ## 手牌被封禁的回合数
var buff_hp: int = 0            ## 被动光环叠加的生命
var extra_qi: int = 0           ## 临时气伤加成
## 临时单位剩余回合数（三清铃召唤的【僵尸】）：
## >0 表示这是一张临时卡，每经过自己的一个回合 -1，归零时「退场」（不是被拔除，
## 因此不触发下场技能、也不给对手任何收益）。0 表示常驻卡。
var temp_turns: int = 0
## 被动被封印的回合数（金刚镢）：>0 时该卡的被动完全不生效，主动也一并封锁。
var passive_sealed: int = 0


func setup(def: Dictionary, new_uid: int) -> void:
	uid = new_uid
	id = def.get("id", "")
	name = def.get("name", "?")
	faction = def.get("faction", "地")
	sub = def.get("sub", "")
	group = def.get("group", "")
	tier = int(def.get("tier", 1))
	base_tier = tier
	max_tier = int(def.get("maxTier", 3))
	hp = int(def.get("hp", 1))
	atk = int(def.get("atk", 1))
	atk_qi = int(def.get("atkQi", 0))
	art = def.get("art", "")
	thumb = def.get("thumb", "")
	tags = def.get("tags", []).duplicate()
	skills = def.get("skills", {})
	desc = def.get("desc", "")
	item_func = str(def.get("itemFunc", ""))
	item_target = str(def.get("itemTarget", ""))
	cur_hp = hp
	max_hp = hp


## 覆写阶数（**已弃用**：合成移除后，阶数在卡池里就是固定的）
##
## 【为什么改成「只校验、不改值」】
##   ① 阶数一变，技能位数量就该跟着变（1/2/3 个），而技能是生成器按阶数固化进数据的，
##      运行时改 tier 会让卡面与技能对不上；
##   ② 旧实现按 `hp = atk = tier` 重算面板，会把 stats_for 给「四相 / 十二生肖」的
##      +1 特殊加成直接抹掉 —— 凡是走 tier_override 的路径（copy_hand 复制场上卡）
##      复制出来的四相都会凭空少 1 点【祇】/【体】。
##   现在只做一致性校验：阶数必须等于卡池阶数，否则明确拒绝并留警告。
func apply_tier(t: int) -> void:
	if t != base_tier:
		push_warning("[CCard] 试图把「%s」从 %d 阶改成 %d 阶；卡牌阶数已固定，本次调用被忽略。"
			% [name, base_tier, t])
		return
	tier = base_tier


func is_valid() -> bool:
	return uid >= 0 and not id.is_empty()


func is_tian() -> bool:
	return faction == "天"


func is_di() -> bool:
	return faction == "地"


func is_item() -> bool:
	return faction == "道具"


func is_guizu() -> bool:
	return sub == "鬼"


func tier_label() -> String:
	return "%d阶" % tier


## 技能安全访问
func skill(key: String) -> Dictionary:
	var s: Variant = skills.get(key, null)
	if s == null:
		return {}
	return s


## 按当前阶数展开后的效果数组
## 生成器把数值写成 base + per_tier×(阶数-1)，这里在运行期算出真实值，
## 于是「1 阶卡合成到 3 阶」时技能同步变强，卡牌品质与实际强度才对等。
##
## 两种缩放基准：
##   · 默认 —— 以「1 阶」为基准（通用技能模板：同一模板在越高阶的卡上越强）
##   · per_tier_from_base —— 以「卡牌自身的卡池阶数」为基准（签名技能：
##     数值按该卡原本的阶数撰写，描述文字里的数字才始终准确；合成升阶后才变强）
func _scaled_effects(key: String) -> Array:
	# 被动被封印（金刚镢「封」）时，被动槽整体失效。
	# 这是「封印被动」唯一的实现落点：只要这里返回空数组，
	# 所有 PlayerState.aura_* 读取点就都读不到它，不需要逐个去改。
	if key == "passive" and passive_sealed > 0:
		return []
	var raw: Array = skill(key).get("effects", [])
	var k: int = maxi(0, tier - 1)
	var out: Array = []
	for e in raw:
		var d: Dictionary = (e as Dictionary).duplicate(true)
		var kk: int = k
		if d.has("per_tier") and bool(d.get("per_tier_from_base", false)):
			kk = maxi(0, tier - base_tier)
		if kk > 0:
			if d.has("per_tier"):
				d["value"] = int(d.get("value", 0)) + int(d["per_tier"]) * kk
			if d.has("count_per_tier"):
				d["count"] = int(d.get("count", 0)) + int(d["count_per_tier"]) * kk
			if d.has("limit_per_tier"):
				d["hp_limit"] = int(d.get("hp_limit", 0)) + int(d["limit_per_tier"]) * kk
		out.append(d)
	return out


func skill_name(key: String) -> String:
	return skill(key).get("name", "")


## 技能描述：把 {v0}/{c0} 占位符替换成展开后的真实数值
func skill_desc(key: String) -> String:
	var s := skill(key)
	if s.is_empty():
		return ""
	var d: String = str(s.get("desc", ""))
	var effs := _scaled_effects(key)
	for i in effs.size():
		var e: Dictionary = effs[i]
		d = d.replace("{v%d}" % i, str(int(e.get("value", 0))))
		d = d.replace("{c%d}" % i, str(int(e.get("count", 0))))
		d = d.replace("{t%d}" % i, str(int(e.get("turns", 0))))
	return d


func skill_effects(key: String) -> Array:
	return _scaled_effects(key)


## 技能特效名（签名技能可显式指定，否则由首个效果类型推导）
func skill_fx(key: String) -> String:
	var s := skill(key)
	if s.is_empty():
		return ""
	var explicit: String = str(s.get("fx", ""))
	if explicit != "":
		return explicit
	var effs: Array = s.get("effects", [])
	if effs.is_empty():
		return ""
	return fx_for_type(str((effs[0] as Dictionary).get("type", "")))


static func fx_for_type(t: String) -> String:
	match t:
		"heal_qi", "heal_board", "heal_board_all", "dice_heal", "qi_per_tian": return "heal"
		"damage_qi", "damage_board", "damage_weakest": return "slash"
		"damage_board_all": return "quake"
		"debuff_board": return "poison"
		"shield_qi": return "shield"
		"destroy_di", "execute_board", "sacrifice_board": return "purge"
		"draw", "draw_group", "draw_by_missing_qi": return "draw"
		"discard_enemy", "seal_hand_card", "fog_hand": return "seal"
		"steal_hand", "steal_res": return "soul"
		"gain_res", "gain_material": return "coin"
		"freeze_board", "bounce_board": return "chain"
		"summon_to_hand", "summon_special", "summon_board_group", "copy_hand", "transform_board": return "summon"
		"revive_discard", "recycle_discard": return "revive"
		"buff_self_hp", "buff_tian_hp_all", "buff_lonely", "heal_board": return "buff"
		"clash_enemy_board", "conquer_board": return "clash"
		"dice_damage", "random_wealth_wager": return "dice"
	return "buff"


func active_cd() -> int:
	return int(skill("active").get("cd", 0))


func has_active() -> bool:
	return not skill("active").is_empty()


## 进入冷却：n <= 0 表示立刻解除。
## 每次重新上冷却都会把 cooldown_span 重置为 n，
## 这样 UI 的黑幕永远从「整张盖满」开始，再随 cooldown 递减自下而上褪去。
func set_cooldown(n: int) -> void:
	# 测试训练场：无冷却 —— 任何「进冷却」的调用都被压成 0。
	# 这是冷却的唯一写入口（do_active / do_attack / tick_cooldown 都汇到这里），
	# 所以一个判断就够，不需要去改每个 do_xxx。
	if Dev.enabled and Dev.no_cooldown:
		cooldown = 0
		cooldown_span = 0
		return
	if n <= 0:
		cooldown = 0
		cooldown_span = 0
		return
	cooldown = n
	cooldown_span = n


## 冷却不足 n 回合时补到 n（不缩短已有冷却）
func raise_cooldown(n: int) -> void:
	if Dev.enabled and Dev.no_cooldown:
		return
	if n > cooldown:
		set_cooldown(n)


## 回合开始：冷却递减一格；归零时一并清掉 span
func tick_cooldown() -> void:
	if cooldown > 0:
		cooldown -= 1
	if cooldown <= 0:
		cooldown = 0
		cooldown_span = 0


## 用于日志的短标签
func tag_label() -> String:
	return "[%s·%s %d阶 %s]" % [faction, sub, tier, name]


func duplicate_card() -> CCard:
	var c := CCard.new()
	c.uid = uid
	c.id = id
	c.name = name
	c.faction = faction
	c.sub = sub
	c.group = group
	c.tier = tier
	c.base_tier = base_tier
	c.max_tier = max_tier
	c.hp = hp
	c.atk = atk
	c.atk_qi = atk_qi
	c.art = art
	c.thumb = thumb
	c.tags = tags.duplicate()
	c.skills = skills
	c.desc = desc
	c.cur_hp = cur_hp
	c.max_hp = max_hp
	c.on_board = on_board
	c.owner_id = owner_id
	c.temp_turns = temp_turns
	c.passive_sealed = passive_sealed
	return c


func to_dict() -> Dictionary:
	return {
		"uid": uid, "id": id, "name": name, "faction": faction, "sub": sub,
		"tier": tier, "cur_hp": cur_hp, "max_hp": max_hp, "atk": atk,
		"atk_qi": atk_qi, "art": art,
	}
