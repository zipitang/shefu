extends Node
## CardDB —— 全局卡牌数据库（Autoload 单例）
## 负责载入 data/*.json，构建卡池、角色表、规则常量，
## 并提供卡牌实例化 / 随机抽取 / 查询接口。

signal db_ready

const DATA_DIR := "res://data/"

var cards: Array = []              # 全量卡牌定义（Dictionary）
var card_index: Dictionary = {}    # id -> 定义
var characters: Array = []         # 12 角色
var chara_index: Dictionary = {}
var ren_cards: Array = []          # 6 张【人】大本营卡
var ren_index: Dictionary = {}
var rules: Dictionary = {}
## 角色名 -> 方形头像路径（res://assets/chara_face/NNN.webp）
## 生成源见 tools/build_ui_assets.py：头像文件序号与 assets/chara/NNN.webp 严格同序，
## 所以这里按「名字」对齐，而不是靠字符串替换 art 路径 —— 改名/换图时不会悄悄错位。
var face_by_name: Dictionary = {}
## 角色名 -> {face, scene, bg}（大厅预览两层 + 头像，一次查全）
var _media_by_name: Dictionary = {}

var _uid_counter: int = 0
var loaded: bool = false

## 常规池（不含【人】牌、不含四相/十二生肖，含可刷道具）
var draft_pool: Array = []
## 非道具常规池（用于「随机给一张牌」这类不该塞道具的效果）
var normal_draft_pool: Array = []
## 可刷道具池（已排除开局自带的拜神/敬鬼）
var item_draft_pool: Array = []
## 特殊池（四相 / 十二生肖），仅由专属技能或特定触发获得
var special_pool: Array = []
## 开局自带的专属道具（拜神 / 敬鬼），永远不进入三选一
var starter_item_ids: Dictionary = {}


func _ready() -> void:
	load_all()


func _load_json(fname: String) -> Variant:
	var path := DATA_DIR + fname
	if not FileAccess.file_exists(path):
		push_error("[CardDB] 缺少数据文件: " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var res: Variant = JSON.parse_string(txt)
	if res == null:
		push_error("[CardDB] JSON 解析失败: " + path)
	return res


func load_all() -> void:
	draft_pool.clear()
	normal_draft_pool.clear()
	item_draft_pool.clear()
	special_pool.clear()
	starter_item_ids.clear()
	cards = _load_json("cards.json")
	if cards == null:
		cards = []
	for c in cards:
		card_index[c["id"]] = c
		var is_item: bool = c.get("faction", "") == "道具"
		# 开局自带的拜神/敬鬼：永远不进三选一卡池。
		# 【为什么必须显式排除】它们本来就在 draft_pool 里，而它们的功能是「右侧专属卡位的
		# 回合技能」，被抽到手上后那张牌既不能拖、也没有 itemFunc 可结算 —— 会变成一张死牌。
		if is_item and bool(c.get("starter", false)):
			starter_item_ids[c["id"]] = true
			continue
		if c.get("pool", "normal") == "special":
			special_pool.append(c)
			continue
		draft_pool.append(c)
		if is_item:
			item_draft_pool.append(c)
		else:
			normal_draft_pool.append(c)

	characters = _load_json("characters.json")
	if characters == null:
		characters = []
	for c in characters:
		chara_index[c["id"]] = c

	# ---- 角色展示三件套：方形头像 / 对局内立绘 / 背景 ----
	# 三者同源同序（见 tools/build_ui_assets.py），manifest 里按「名字」对齐。
	# 【为什么不直接替换 art 路径的编号】三套图的文件名各不相同（背景还带「背景」后缀，
	# 吉马卓玛那张连后缀都没有），按文件名排序会各排各的；按名字对齐才不会被改名坑到。
	face_by_name.clear()
	_media_by_name.clear()
	var fm: Variant = _load_json("face_manifest.json")
	if fm is Array:
		for e in fm:
			var k := str(e.get("name", ""))
			face_by_name[k] = str(e.get("art", ""))
			_media_by_name[k] = {
				"face": str(e.get("art", "")),
				"scene": str(e.get("scene", "")),
				"bg": str(e.get("bg", "")),
			}
	# 每个角色挂上 face / scene / bg：找不到就退回 9:16 立绘，绝不出现空白卡。
	for c in characters:
		var nm := str(c.get("name", ""))
		var media: Dictionary = _resolve_media(nm)
		var fp: String = str(media.get("face", ""))
		c["face"] = fp if fp != "" else c.get("art", "")
		var sp: String = str(media.get("scene", ""))
		c["scene"] = sp if sp != "" else c.get("art", "")
		var bp: String = str(media.get("bg", ""))
		c["bg"] = bp if bp != "" else ""

	ren_cards = _load_json("ren_cards.json")
	if ren_cards == null:
		ren_cards = []
	for r in ren_cards:
		ren_index[r["name"]] = r

	rules = _load_json("rules.json")
	if rules == null:
		rules = {}

	loaded = true
	db_ready.emit()


# ------------------------------------------------------------------ 卡牌实例
## 由定义创建一张可交易的卡牌实例（带 uid / 当前生命 / 冷却）
func instantiate_card(card_id: String, tier_override: int = -1) -> CCard:
	var def: Dictionary = card_index.get(card_id, {})
	if def.is_empty():
		push_warning("[CardDB] 未知卡牌 id: " + card_id)
		return null
	var c := CCard.new()
	c.setup(def, _uid_counter)
	_uid_counter += 1
	if tier_override > 0:
		c.apply_tier(tier_override)
	return c


## 随机取一张常规池卡牌实例。
## 【为什么改从 normal_draft_pool 取】道具是「稀有奖励」，只能经三选一（random_draft_card）
## 按权重 + 每局上限获得。若这里仍从 draft_pool（含道具）取，起手发牌 / 抽牌效果 / 召唤
## 都会以均匀概率塞道具，既绕过「每局最多 2 次」的限额，也绕过了稀有度——这正是
## 「道具概率忽高忽低、算法不统一」的根。现在：道具唯一入口 = 三选一。
func random_card(rng: RandomNumberGenerator, tier_filter: int = -1) -> CCard:
	var pool := normal_draft_pool
	if tier_filter > 0:
		var f: Array = []
		for d in pool:
			if int(d.get("tier", 1)) == tier_filter:
				f.append(d)
		if not f.is_empty():
			pool = f
	if pool.is_empty():
		return null
	var def: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	return instantiate_card(def["id"])


## 按 sub 类别随机（佛/神/妖/鬼/魔/奇兽/道具）
func random_card_by_sub(rng: RandomNumberGenerator, subs: Array) -> CCard:
	var pool: Array = []
	for d in draft_pool:
		if subs.has(d.get("sub", "")):
			pool.append(d)
	if pool.is_empty():
		return null
	var def: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	return instantiate_card(def["id"])


## 按 tag 随机（例如「护法金刚」）
func random_card_by_tag(rng: RandomNumberGenerator, tag: String) -> CCard:
	var pool: Array = []
	for d in cards:
		if d.get("tags", []).has(tag):
			pool.append(d)
	if pool.is_empty():
		return null
	var def: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	return instantiate_card(def["id"])


# ------------------------------------------------------------------ 三选一：带权重的道具
## 抽一张三选一候选牌。
##
## 道具要「比其他卡牌刷出概率低得多」，且每种道具一局最多获得 N 次；权重关系为
##   金刚钺 < 降魔杵 < 三清铃 < 铜钱剑 < 金刚镢 < 八卦镜
##
## 【统一算法】两段式权重带：
##   - 普通牌 = 一整个大权重 `normalCardWeight`（代表全部 219 张常规牌），
##   - 道具 = 各自权重之和（1+2+3+4+5+6 = 21，已拿满上限的道具权重归 0）。
##   一次均匀掷点在 [0, normalCardWeight + 道具总权重) 上，落在普通段就抽普通牌，
##   落在道具段就按道具权重带线性扫。
##   这样道具总占比 = 21 / (normalCardWeight + 21)，由 normalCardWeight 单一参数
##   决定稀有度（当前 400 → 道具约 5%），不再有「普通牌加两遍权重」这类魔法数。
func random_draft_card(rng: RandomNumberGenerator, owner: PlayerState = null) -> CCard:
	var idr: Dictionary = CardDB.rules.get("itemDraw", {})
	var normal_w: int = int(idr.get("normalCardWeight", 400))
	if owner == null or item_draft_pool.is_empty():
		return random_card(rng)
	# 收集「还没拿满上限」的道具，凑成权重带
	var items: Array = []          # [ {def, w} ]
	var item_total: int = 0
	for d in item_draft_pool:
		var nm: String = str(d.get("name", ""))
		var cap: int = int(d.get("itemMaxPerGame", 2))
		if cap > 0 and owner.item_got_count(nm) >= cap:
			continue                # 本局已拿满，直接不再出现在卡池里
		var w: int = maxi(1, int(d.get("itemWeight", 1)))
		items.append({"def": d, "w": w})
		item_total += w
	if item_total <= 0:
		return random_card(rng)
	# 一次掷点：普通段（normal_w）在前，道具段（item_total）在后
	var roll: int = rng.randi_range(0, normal_w + item_total - 1)
	if roll < normal_w:
		return random_card(rng)
	roll -= normal_w
	for p in items:
		roll -= int(p["w"])
		if roll < 0:
			return instantiate_card(str((p["def"] as Dictionary)["id"]))
	return random_card(rng)


func get_chara(cid: String) -> Dictionary:
	return chara_index.get(cid, {})


## 按名字取角色三件套。名字对不上时用「后缀互相包含」兜底 ——
## 实测角色叫「白店小二」而素材文件是「店小二.png」，写死别名表会在换图改名时再炸一次。
func _resolve_media(nm: String) -> Dictionary:
	if _media_by_name.has(nm):
		return _media_by_name[nm]
	for fname in _media_by_name.keys():
		var fs := str(fname)
		if nm.ends_with(fs) or fs.ends_with(nm):
			return _media_by_name[fname]
	return {}


## 按卡名找定义 id（三清铃要召唤【僵尸】，用它定位）
func find_id_by_name(nm: String) -> String:
	for d in cards:
		if str(d.get("name", "")) == nm:
			return str(d.get("id", ""))
	return ""


func get_ren(name: String) -> Dictionary:
	return ren_index.get(name, {})


## 该卡是否属于【天】（神/佛/四相/十二生肖）
func is_tian(c: CCard) -> bool:
	return c.faction == "天"


func is_di(c: CCard) -> bool:
	return c.faction == "地"


func is_guizu(c: CCard) -> bool:
	return c.sub == "鬼" or c.group.begins_with("地/鬼")


func is_buddha(c: CCard) -> bool:
	return c.sub == "佛" or c.group.begins_with("天/佛")
