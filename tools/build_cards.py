# -*- coding: utf-8 -*-
"""
《摄伏》卡牌数据库生成器
--------------------------------------------------
读取 data/asset_manifest.json（285 张卡面），生成：
  data/cards.json        —— 全量卡牌（阵营/阶数/数值/四类技能）
  data/characters.json   —— 12 角色 + 专属技能 + 人卡映射
  data/rules.json        —— 全局规则常量（财曲线/刷新价/合成表/克制表）

技能统一用「可执行 effect」描述，由 GDScript 端 EffectRunner 解释执行。
"""
import copy
import json, os, zlib

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(BASE, "data")

MANIFEST = json.load(open(os.path.join(DATA, "asset_manifest.json"), encoding="utf-8"))

# 立绘文件名与游戏内角色名不一致时的别名表。
# 踩过的坑：「角色」目录里的图叫 店小二.png，而设计文档里的角色名是「白店小二」，
# 严格按名字匹配会拿不到立绘图，结果大厅里那个格子是全黑的（而且不报错）。
ART_ALIAS = {
    ("chara", "白店小二"): "店小二",
}

# ------------------------------------------------------------------ 稀有度/阶数表
# 组 key -> (tier, sub)  sub: 佛/神/妖/鬼/魔/奇兽
TIER_TABLE = {
    # ---- 天 ----
    "天/神_齐名百圣":        (1, "神"),
    "天/神_齐名百圣_夜游神": (2, "神"),
    "天/神_四大天王":        (2, "神"),
    "天/神_五岳大帝":        (2, "神"),
    "天/神_五德星君":        (2, "神"),
    "天/神_门神":            (2, "神"),
    "天/神_星宿":            (2, "神"),
    "天/神_黑白无常":        (2, "神"),
    "天/神_龙":              (2, "神"),
    "天/神_天王":            (3, "神"),
    "天/神_天王_五火真君":   (3, "神"),
    "天/神_神天大照":        (3, "神"),
    "天/佛_护法金刚":        (1, "佛"),
    "天/佛":                 (2, "佛"),
    "天/四相":               (3, "神"),
    "天/十二生肖":           (1, "神"),
    # ---- 地 ----
    "地/妖":                 (1, "妖"),
    "地/鬼":                 (1, "鬼"),
    "地/鬼_三尸":            (2, "鬼"),
    "地/鬼_五孽":            (3, "鬼"),
    "地/鬼_五灾":            (3, "鬼"),
    "地/鬼_五行尸_金尸":     (2, "鬼"),
    "地/鬼_五行尸_木尸":     (2, "鬼"),
    "地/鬼_五行尸_水尸":     (2, "鬼"),
    "地/鬼_五行尸_火尸":     (2, "鬼"),
    "地/鬼_五行尸_土尸":     (2, "鬼"),
    "地/鬼_魑魅魍魉":        (2, "鬼"),
    "地/魔":                 (3, "魔"),
    "地/奇兽":               (2, "奇兽"),
    "道具/root":             (1, "道具"),
}
DEFAULT_TIER = (1, "妖")

# ------------------------------------------------------------------ 数值公式
def stats_for(top, sub, tier, is_special=False):
    """返回 (hp, atk, atk_qi)
       hp     : 天=祇基数(会再叠加己方人数) / 地=体质
       atk    : 单位对单位伤害
       atk_qi : 对【人】造成的气伤
    """
    if top == "天":
        hp   = tier                                  # 祇 = tier + 己方人数量
        atk  = tier
        atk_qi = 0                                   # 神佛无法对【人】造成伤害
    else:  # 地
        hp   = tier
        atk  = tier
        atk_qi = tier                                # 地卡可损耗【人】的气
    if is_special:                                   # 四相 / 十二生肖
        hp += 1
        atk += 1
        atk_qi += 1
    return hp, atk, atk_qi



# ------------------------------------------------------------------ 四类技能原型池
# ─────────────────────────────────────────────────────────────────────────────
# 旧实现只按 sub（佛/神/妖/鬼/魔/奇兽）取一条写死的模板，于是 102 张【神】+30 张
# 【佛】全都顶着同一个主动技「镇压」（130 张），87 张【地】全是「袭人」（85 张）；
# on_remove 整个卡池只有 7 个名字、passive 只有 7 个 —— 玩家一眼看过去就是
# 「怎么所有人技能都是镇压」。谁站在哪条分支上只取决于 sub，和卡牌本身无关。
#
# 现在改成「大原型池 + 确定性取样」：
#   ① 全卡池内四元组（on_play/on_remove/passive/active 的技能名）互不相同；
#   ② 同一张卡四个槽位的技能名互不相同；
#   ③ 同一分组内尽量不撞名（36 张【齐名百圣】不会再共用同一招），池子走完才允许）；
#   ④ subs 只是「风味偏好」而非硬约束 —— 做成硬约束等于换个维度继续同质化。
#
# 取样用 zlib.crc32 而不是内置 hash()：后者每个进程都会掺随机盐，
# 生成器每跑一次数据都不一样（无法复现、无法 diff），这在做回归时是致命的。
#
# 约束（照抄现网实现，改错任何一条都会静默失效或直接让 SelfTest 挂掉）：
#   · 效果类型必须落在 EffectRunner.gd 的 match 分支内；
#   · passive 槽只能放 PlayerState 认识的 5 种 aura_*，放别的不会有任何反应；
#   · desc 里的 {v0}/{c0}/{t0} 按「effects 数组下标」替换，占位符与效果必须错位对齐；
#   · aura_enemy_di_atk 在 PlayerState 里取【最大值】而非累加，必须恒为 1；
#   · destroy_di 读的是 ctx.chosen_tier，而 GameState.do_active 只从 effects[0]
#     推导 chosen_tier —— 所以 destroy_di 只能出现在 effects[0]。
# ─────────────────────────────────────────────────────────────────────────────

# ============ 技能生成：家族主题库 + 阶数门控 ============
# ─────────────────────────────────────────────────────────────────────────────
# 设计说明见 tools/card_skills.py 的抬头注释。这里只做三件事：
#   ① 决定这张卡「开哪几个技能位」—— 数量由阶数决定，性格由家族决定；
#   ② 把家族模板 + 该卡自己的「法名」渲染成技能字典；
#   ③ 全卡池范围内保证技能名互不相同。
#
# 【为什么整条废弃了原来的四条原型池】
#   旧实现是「四类大池子 + 按 sub 偏好取样」，池中技能名与卡牌本身毫无关系：
#   取哪一条只看 cid 的 crc32 哈希，抽到啥全凭运气。于是会出现
#   「不动明王」顶着一条『魔道滋长』被动的荒唐组合 —— 名字与效果各说各话。
#   现在：技能名 = 该卡法名 + 家族词干（鼓雷金刚 → 鼓雷镇守），
#         技能效果 = 该卡所属神话谱系（金刚一族都是护法），两者都锚在卡牌名字上。
#
# 【阶数门控】用户需求：1 阶只有 1 个技能、2 阶 2 个、3 阶 3 个。
#   因此强度曲线走「技能**数量**」而不是「单个技能数值翻倍」——
#   本文件所有家族技能都写绝对值并标 absolute=True，
#   由 _apply_tier_scaling 跳过，避免 3 阶卡把两份收益一起吃下去导致超模。
# ─────────────────────────────────────────────────────────────────────────────

import card_skills as CS

SLOT_ORDER = ("on_play", "on_remove", "active")


def _h32(*parts) -> int:
    """确定性取样键。

    【踩过的坑】不要用 Python 内置 hash()：它每个进程都会掺随机盐
    （PYTHONHASHSEED），于是生成器每跑一次产出的数据都不一样 ——
    既无法复现、也无法 diff，做回归时是致命的。crc32 稳定。
    """
    return zlib.crc32("|".join(str(p) for p in parts).encode("utf-8")) & 0x7FFFFFFF

# 各家族的主轴技能位 —— 1 阶卡优先拿它，
# 保证「只有一个技能」时也能一眼看出这张卡属于哪一路。
FAMILY_PRIMARY = {
    # 天：护法 / 赐福类，主轴是「上场那一下」
    "慈悲": "on_play", "福德": "on_play", "护法": "on_play", "生肖": "on_play",
    "四相": "on_play", "岳镇": "on_play", "星君": "on_play", "天王": "on_play",
    "星宿": "on_play", "门神": "on_play", "百圣": "on_play", "龙": "on_play",
    "五行尸": "on_play",
    # 地：凶煞类，主轴是「消耗行动、带冷却」的主动技
    "忿怒": "active", "金翅": "active", "天尊": "active", "火部": "active",
    "日轮": "active", "幽冥": "active", "夜游": "active",
    "异兽": "active", "妖异": "active", "鬼魅": "active", "三尸": "active",
    "五孽": "active", "五灾": "active", "魑魅": "active", "魔道": "active",
}

# 法名截取时要剥掉的通用后缀（按「先长后短」排列，避免「金刚」被先拆成「金」）
_STRIP_SUFFIX = (
    "除魔震灾威严魔怒相", "金刚", "天王", "大帝", "星君", "真君", "天母", "菩萨",
    "童子", "将军", "元帅", "大命", "神兽", "魔君", "鬼帝", "女魔", "魔尊", "佛母",
    "鬼王", "太子", "神", "鬼", "妖", "魔", "兽", "尸", "佛", "君", "尊",
)


def _stem(name: str) -> str:
    for suf in _STRIP_SUFFIX:
        if len(name) > len(suf) and name.endswith(suf):
            return name[: -len(suf)]
    return name


def _auto_epithet(name: str) -> str:
    s = _stem(name)
    if len(s) >= 2:
        return s[:2]
    return name[:2] if len(name) >= 2 else name


def _build_epithets() -> dict:
    """为每张卡算一个「同族内唯一」的法名。

    同族内唯一就够了：技能名 = 法名 + 家族词干，
    只要同族法名不同，技能名自然不同（跨族撞名另有全局兜底）。
    """
    members: dict = {}
    for m in MANIFEST:
        if m["top"] in ("角色", "人"):
            continue
        fam = CS.FAMILY.get(m["name"])
        if fam is None:
            continue
        members.setdefault(fam, []).append(m["name"])
    out: dict = {}
    for fam, names in members.items():
        used: set = set()
        for nm in sorted(names):
            base = CS.EPITHET.get(nm) or _auto_epithet(nm)
            stem = _stem(nm)
            cand = base
            if cand in used:
                cand = ""
                for k in range(3, max(5, len(stem) + 1)):
                    if stem[:k] and stem[:k] not in used:
                        cand = stem[:k]
                        break
                if not cand:
                    i = 2
                    while base + str(i) in used:
                        i += 1
                    cand = base + str(i)
            used.add(cand)
            out[nm] = cand
    return out


EPITHETS = _build_epithets()

# 全卡池技能名登记表（跨族撞名的兜底）
_SKILL_NAME_USED: dict = {}


def _reset_skill_registry() -> None:
    """每次生成前重置，保证可复现。
    先把 SIGNATURE 里的技能名占上，防止家族生成器撞到它们。"""
    _SKILL_NAME_USED.clear()
    for nm, slots in SIGNATURE.items():
        for _k, sk in slots.items():
            if isinstance(sk, dict) and sk.get("name"):
                _SKILL_NAME_USED[sk["name"]] = nm


def _variant(pool: list, cid: str, slot: str) -> tuple:
    return pool[_h32(cid, slot, "var") % len(pool)]


def _render(entry: tuple, fam: str, epithet: str) -> dict:
    """家族模板 → 技能字典。技能名里的 {e} 换成该卡法名。"""
    name_t, desc, effs = entry[0], entry[1], entry[2]
    cd = int(entry[3]) if len(entry) > 3 else 0
    nm: str = name_t.replace("{e}", epithet)
    if nm in _SKILL_NAME_USED:
        nm = nm + fam[0]          # 跨族撞名的兜底（正常数据下不会触发）
    _SKILL_NAME_USED[nm] = True
    sk = {
        "name": nm,
        "desc": desc,
        "effects": copy.deepcopy(effs),
        # absolute=True —— 见文件抬头：阶数带来的强度走「技能数量」，不再放大单条数值
        "absolute": True,
    }
    if cd > 0:
        sk["cd"] = cd
    return sk


def _pick_slots(cid: str, tier: int, fam: str, sig_slots: tuple) -> list:
    """决定这张卡开哪几个技能位。

    优先级：签名技能所在槽位（那张卡最出彩的一招要留住）
            → 家族主轴槽位 → 其余槽位（用 crc32 打散，保证同族不同卡不一样）。
    """
    order: list = []
    for s in sig_slots:
        if s in SLOT_ORDER and s not in order:
            order.append(s)
    prim = FAMILY_PRIMARY.get(fam, "on_play")
    if prim not in order:
        order.append(prim)
    rest = [s for s in SLOT_ORDER if s not in order]
    rest.sort(key=lambda s: _h32(cid, s, "slot"))
    order += rest
    return order[: max(1, tier)]


def build_skills(cid: str, group: str, sub: str, tier: int, name: str,
                 is_item: bool = False) -> dict:
    """按「卡名 + 阶数」产出该卡的技能字典。

    道具卡返回四个全 None 的槽位：道具不带技能，只有功能（GameState.use_item 分派）。
    """
    if is_item:
        return {"on_play": None, "on_remove": None, "passive": None, "active": None}
    fam = CS.FAMILY.get(name)
    if fam is None:
        raise RuntimeError(
            "卡牌『%s』没有分配技能家族 —— 请在 tools/card_skills.py 的 FAMILY 表里补上" % name)
    famd: dict = CS.FAMILIES[fam]
    ep: str = EPITHETS.get(name) or _auto_epithet(name)
    sig: dict = SIGNATURE.get(name, {})
    slots = _pick_slots(cid, tier, fam, tuple(sig.keys()))

    out: dict = {"passive": _render(_variant(famd["passive"], cid, "passive"), fam, ep)}
    for s in SLOT_ORDER:
        if s not in slots:
            out[s] = None
        elif s in sig:
            # 签名技能覆写（深拷贝，别让 _apply_tier_scaling 就地写脏 SIGNATURE）
            out[s] = copy.deepcopy(sig[s])
        else:
            out[s] = _render(_variant(famd[s], cid, s), fam, ep)
    return out



# ------------------------------------------------------------------ 签名技能（按卡名定制）
# 在模板技能之上按卡名覆写对应槽位，强调观赏性 / 趣味性 / 战略性。
SIGNATURE = {
    # ================= 星宿（用户点名：随机召唤十二生肖） =================
    "星宫二十八宿": {"on_play": {
        "name": "星宿下凡",
        "desc": "上场时，随机召唤 2 张【十二生肖】进入手牌。",
        "effects": [{"type": "summon_to_hand", "group": "十二生肖", "value": 2}],
        "fx": "summon"}},
    "亢金龙": {"active": {
        "name": "金龙啸空", "cd": 2,
        "desc": "冷却 2 回合。对所有对方【地】单位造成 1 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 1}],
        "fx": "quake"}},
    "奎木狼": {"active": {
        "name": "狼星逐月", "cd": 2,
        "desc": "冷却 2 回合。对对方【人】造成 1 点【气】伤害，并抽 1 张牌。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 1},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "slash"}},

    # ================= 黑白无常 / 钟馗 / 孟婆 =================
    "钟馗": {"on_play": {
        "name": "捉鬼天师",
        "desc": "上场时，直接钉死对方 1 张阶数 ≤2 的【地】卡。",
        "effects": [{"type": "destroy_di", "tier_limit": 2}],
        "fx": "purge"}},
    "黑无常": {"on_play": {
        "name": "勾魂索",
        "desc": "上场时，将对方场上 1 张阶数 ≤2 的卡弹回其手牌。",
        "effects": [{"type": "bounce_board", "side": "enemy", "value": 1, "tier_limit": 2}],
        "fx": "chain"}},
    "白无常": {"on_play": {
        "name": "摄魄幡",
        "desc": "上场时，对方随机弃 1 张手牌，己方抽 1 张牌。",
        "effects": [{"type": "discard_enemy", "value": 1},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "soul"}},
    "孟婆": {"on_play": {
        "name": "忘川汤",
        "desc": "上场时，从己方弃置区复活 1 张牌回手牌；对方随机弃 1 张手牌。",
        "effects": [{"type": "revive_discard", "value": 1},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "revive"}},

    # ================= 龙 / 门神 / 四大天王 =================
    "金龙": {"on_play": {
        "name": "龙威浩荡",
        "desc": "上场时，对所有对方【地】单位造成 1 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 1}],
        "fx": "quake"}},
    "黄龙": {"on_play": {
        "name": "黄龙镇土",
        "desc": "上场时，封锁对方所有【地】单位 1 回合。",
        "effects": [{"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1}],
        "fx": "freeze"}},
    "秦琼": {"on_play": {
        "name": "门神镇宅",
        "desc": "上场时，己方【人】获得 3 点护盾【气】。",
        "effects": [{"type": "shield_qi", "value": 3}],
        "fx": "shield"}},
    "尉迟恭": {"on_play": {
        "name": "鞭锏驱邪",
        "desc": "上场时，对对方场上生命最低的单位造成 3 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 3}],
        "fx": "smash"}},
    "增长天王": {"on_play": {
        "name": "南方增长",
        "desc": "上场时，己方所有【天】+1【祇】。",
        "effects": [{"type": "buff_tian_hp_all", "value": 1}],
        "fx": "buff"}},
    "多闻天王": {"on_play": {
        "name": "北方多闻",
        "desc": "上场时，抽 2 张牌。",
        "effects": [{"type": "draw", "target": "self", "value": 2}],
        "fx": "draw"}},
    "广目天王": {"on_play": {
        "name": "西方广目",
        "desc": "上场时，封锁对方 2 张手牌 1 回合。",
        "effects": [{"type": "seal_hand_card", "side": "enemy", "value": 2, "turns": 1}],
        "fx": "seal"}},
    "持国天王": {"on_play": {
        "name": "东方持国",
        "desc": "上场时，己方【人】按场上【天】数量恢复【气】（每尊 1 点）。",
        "effects": [{"type": "qi_per_tian", "value": 1}],
        "fx": "heal"}},

    # ================= 名门大神（齐名百圣 / 五岳 / 星君） =================
    "二郎神": {"on_play": {
        "name": "天眼破妄",
        "desc": "上场时，消灭对方 1 张阶数 ≤3 的【地】卡，并抽 1 张牌。",
        "effects": [{"type": "destroy_di", "tier_limit": 3},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "purge"}},
    "哪吒": {"on_play": {
        "name": "三头六臂",
        "desc": "上场时，对对方所有单位造成 1 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1}],
        "fx": "quake"}},
    "后羿": {"on_play": {
        "name": "射日",
        "desc": "上场时，对对方场上攻击最高的单位造成 4 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 4}],
        "fx": "arrow"}},
    "女娲": {"on_play": {
        "name": "补天造化",
        "desc": "上场时，己方【人】恢复 3 点【气】，并复制 1 张己方手牌。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 3},
                    {"type": "copy_hand", "value": 1}],
        "fx": "heal"}},
    "夸父": {"on_play": {
        "name": "逐日之躯",
        "desc": "上场时，自身获得 3 点【祇】；己方所有【天】+1【祇】。",
        "effects": [{"type": "buff_self_hp", "value": 3},
                    {"type": "buff_tian_hp_all", "value": 1}],
        "fx": "buff"}},
    "财神": {"on_play": {
        "name": "招财进宝",
        "desc": "上场时，己方获得 4 点【财】，并抽 1 张牌。",
        "effects": [{"type": "gain_res", "res": "wealth", "value": 4},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "coin"}},
    "雷神": {"on_play": {
        "name": "雷霆万钧",
        "desc": "上场时，对对方 1 张随机单位造成 3 点伤害并封锁 1 回合。",
        "effects": [{"type": "debuff_board", "side": "enemy", "value": 3, "count": 1},
                    {"type": "freeze_board", "side": "enemy", "turns": 1}],
        "fx": "bolt"}},
    "神农": {"on_play": {
        "name": "百草济世",
        "desc": "上场时，己方【人】恢复 2 点【气】，己方场上所有单位 +2 生命。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 2},
                    {"type": "heal_board_all", "side": "self", "value": 2}],
        "fx": "heal"}},
    "天蓬元帅": {"on_play": {
        "name": "九齿镇妖",
        "desc": "上场时，对对方场上所有【地】单位造成 1 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 1}],
        "fx": "quake"}},
    "巨灵神": {"on_play": {
        "name": "开山巨力",
        "desc": "上场时，自身 +2【祇】，并对对方场上生命最低单位造成 2 点伤害。",
        "effects": [{"type": "buff_self_hp", "value": 2},
                    {"type": "damage_weakest", "side": "enemy", "value": 2}],
        "fx": "smash"}},
    "东岳大帝": {"on_play": {
        "name": "东岳判生",
        "desc": "上场时，己方【人】恢复 3 点【气】，并从弃置区回收 1 张牌。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 3},
                    {"type": "recycle_discard", "value": 1}],
        "fx": "heal"}},
    "南岳大帝": {"on_play": {
        "name": "南岳炎衡",
        "desc": "上场时，对对方所有单位造成 1 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1}],
        "fx": "quake"}},
    "西岳大帝": {"on_play": {
        "name": "西岳金戈",
        "desc": "上场时，直接钉死对方 1 张生命 ≤3 的场上卡。",
        "effects": [{"type": "execute_board", "side": "enemy", "hp_limit": 3}],
        "fx": "purge"}},
    "北岳大帝": {"on_play": {
        "name": "北岳玄冰",
        "desc": "上场时，封锁对方所有单位 1 回合。",
        "effects": [{"type": "freeze_board", "side": "enemy", "turns": 1}],
        "fx": "freeze"}},
    "中岳大帝": {"on_play": {
        "name": "中岳镇岳",
        "desc": "上场时，己方所有【天】+2【祇】。",
        "effects": [{"type": "buff_tian_hp_all", "value": 2}],
        "fx": "buff"}},
    "金德星君": {"on_play": {
        "name": "金德肃杀",
        "desc": "上场时，对对方场上攻击最高的单位造成 3 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 3}],
        "fx": "slash"}},
    "木德星君": {"on_play": {
        "name": "木德回春",
        "desc": "上场时，己方【人】恢复 2 点【气】，并抽 1 张牌。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 2},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "heal"}},
    "水德星君": {"on_play": {
        "name": "水德润下",
        "desc": "上场时，弃对方 1 张手牌，己方抽 1 张牌。",
        "effects": [{"type": "discard_enemy", "value": 1},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "draw"}},
    "火德星君": {"on_play": {
        "name": "火德焚天",
        "desc": "上场时，对对方【人】造成 2 点【气】伤害。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 2}],
        "fx": "fire"}},
    "土德星君": {"on_play": {
        "name": "土德厚载",
        "desc": "上场时，己方【人】获得 3 点护盾【气】。",
        "effects": [{"type": "shield_qi", "value": 3}],
        "fx": "shield"}},

    # ================= 神天大照（日系神明） =================
    "大天狗": {"on_play": {
        "name": "天狗风",
        "desc": "上场时，对对方所有单位造成 2 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 2}],
        "fx": "wind"}},
    "玉狐-玉藻前": {"on_play": {
        "name": "九尾魅影",
        "desc": "上场时，随机夺取对方 2 张手牌，对方各补抽 1 张。",
        "effects": [{"type": "steal_hand", "value": 2}],
        "fx": "soul"}},
    "素盏鸣尊": {"on_play": {
        "name": "十拳剑",
        "desc": "上场时，钉死对方 1 张阶数 ≤3 的【地】卡，并抽 1 张牌。",
        "effects": [{"type": "destroy_di", "tier_limit": 3},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "purge"}},
    "月读大命": {"on_play": {
        "name": "月隐",
        "desc": "上场时，使对方下回合手牌信息隐藏，并弃其 1 张手牌。",
        "effects": [{"type": "fog_hand", "turns": 1},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "moon"}},
    "迦具土": {"on_play": {
        "name": "火之迦具土",
        "desc": "上场时，对所有对方单位造成 2 点伤害，对方随机弃 1 张手牌。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 2},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "fire"}},

    # ================= 佛门 =================
    "阿弥陀佛": {"on_play": {
        "name": "无量光明",
        "desc": "上场时，己方【人】恢复 4 点【气】并获得 3 点护盾【气】。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 4},
                    {"type": "shield_qi", "value": 3}],
        "fx": "heal"}},
    "南无观世音菩萨": {"on_play": {
        "name": "慈航普度",
        "desc": "上场时，己方【人】恢复 3 点【气】，从弃置区复活 1 张牌回手牌。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 3},
                    {"type": "revive_discard", "value": 1}],
        "fx": "revive"}},
    "地藏菩萨": {"on_play": {
        "name": "地狱不空",
        "desc": "上场时，己方所有【天】+2【祇】，并令对方随机弃 1 张手牌。",
        "effects": [{"type": "buff_tian_hp_all", "value": 2},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "buff"}},
    "斗战胜佛": {"on_play": {
        "name": "金箍棒",
        "desc": "上场时，对对方场上生命最低的单位造成 4 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 4}],
        "fx": "smash"}},
    "弥勒佛": {"on_play": {
        "name": "大肚能容",
        "desc": "上场时，己方获得 3 点【财】，己方【人】恢复 2 点【气】。",
        "effects": [{"type": "gain_res", "res": "wealth", "value": 3},
                    {"type": "heal_qi", "target": "self_ren", "value": 2}],
        "fx": "coin"}},

    # ================= 四相（特殊池：拜神/敬鬼产物） =================
    "朱雀": {"on_play": {
        "name": "南明离火",
        "desc": "上场时，对所有对方单位造成 2 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 2}],
        "fx": "fire"}},
    "玄武": {"on_play": {
        "name": "北冥玄甲",
        "desc": "上场时，己方【人】获得 4 点护盾【气】，自身 +2【祇】。",
        "effects": [{"type": "shield_qi", "value": 4},
                    {"type": "buff_self_hp", "value": 2}],
        "fx": "shield"}},
    "白虎": {"on_play": {
        "name": "西极庚金",
        "desc": "上场时，直接钉死对方 1 张生命 ≤3 的场上卡。",
        "effects": [{"type": "execute_board", "side": "enemy", "hp_limit": 3}],
        "fx": "purge"}},
    "青龙": {"on_play": {
        "name": "东极青云",
        "desc": "上场时，己方所有【天】+2【祇】，并抽 1 张牌。",
        "effects": [{"type": "buff_tian_hp_all", "value": 2},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "buff"}},

    # ================= 十二生肖（特殊池：星宿 / 拜神产物） =================
    "子鼠": {"on_play": {
        "name": "鼠窃狗盗",
        "desc": "上场时，从对方偷取 2 点【财】。",
        "effects": [{"type": "steal_res", "res": "wealth", "value": 2}],
        "fx": "coin"}},
    "丑牛": {"on_play": {
        "name": "牛气冲天",
        "desc": "上场时，自身 +2【祇】。",
        "effects": [{"type": "buff_self_hp", "value": 2}],
        "fx": "buff"}},
    "寅虎": {"on_play": {
        "name": "虎啸山林",
        "desc": "上场时，对对方场上生命最低的单位造成 2 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 2}],
        "fx": "smash"}},
    "卯兔": {"on_play": {
        "name": "狡兔三窟",
        "desc": "上场时，己方【人】获得 2 点护盾【气】并抽 1 张牌。",
        "effects": [{"type": "shield_qi", "value": 2},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "shield"}},
    "辰龙": {"on_play": {
        "name": "龙吟九霄",
        "desc": "上场时，己方所有【天】+1【祇】。",
        "effects": [{"type": "buff_tian_hp_all", "value": 1}],
        "fx": "buff"}},
    "巳蛇": {"on_play": {
        "name": "灵蛇吐信",
        "desc": "上场时，对对方【人】造成 1 点【气】伤害并使其随机弃 1 张手牌。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 1},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "slash"}},
    "午马": {"on_play": {
        "name": "天马行空",
        "desc": "上场时，抽 1 张牌。",
        "effects": [{"type": "draw", "target": "self", "value": 1}],
        "fx": "draw"}},
    "未羊": {"on_play": {
        "name": "三阳开泰",
        "desc": "上场时，己方【人】恢复 2 点【气】。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 2}],
        "fx": "heal"}},
    "申猴": {"on_play": {
        "name": "灵猴戏法",
        "desc": "上场时，复制 1 张己方随机手牌。",
        "effects": [{"type": "copy_hand", "value": 1}],
        "fx": "summon"}},
    "酉鸡": {"on_play": {
        "name": "金鸡报晓",
        "desc": "上场时，抽 1 张牌，己方【人】恢复 1 点【气】。",
        "effects": [{"type": "draw", "target": "self", "value": 1},
                    {"type": "heal_qi", "target": "self_ren", "value": 1}],
        "fx": "draw"}},
    "戌狗": {"on_play": {
        "name": "犬守门庭",
        "desc": "上场时，己方【人】获得 2 点护盾【气】。",
        "effects": [{"type": "shield_qi", "value": 2}],
        "fx": "shield"}},
    "亥猪": {"on_play": {
        "name": "福猪拱门",
        "desc": "上场时，获得 3 点【财】。",
        "effects": [{"type": "gain_res", "res": "wealth", "value": 3}],
        "fx": "coin"}},

    # ================= 地·妖 =================
    "九尾狐": {"on_play": {
        "name": "魅惑众生",
        "desc": "上场时，随机获得对方 1 张手牌，对方补抽 1 张。",
        "effects": [{"type": "steal_hand", "value": 1}],
        "fx": "soul"}},
    "八岐大蛇": {"on_play": {
        "name": "八首噬世",
        "desc": "上场时，对所有对方单位造成 1 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1}],
        "fx": "quake"}},
    "年兽": {"active": {
        "name": "岁末咆哮", "cd": 2,
        "desc": "冷却 2 回合。对对方【人】造成 3 点【气】伤害。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 3}],
        "fx": "roar"}},
    "唐伞小僧": {"on_play": {
        "name": "伞下藏身",
        "desc": "上场时，己方【人】获得 2 点护盾【气】。",
        "effects": [{"type": "shield_qi", "value": 2}],
        "fx": "shield"}},
    "络新妇": {"on_play": {
        "name": "蛛丝缠缚",
        "desc": "上场时，封锁对方 1 张随机场上单位 1 回合。",
        "effects": [{"type": "freeze_board", "side": "enemy", "turns": 1}],
        "fx": "chain"}},
    "土蜘蛛": {"on_play": {
        "name": "地网缚敌",
        "desc": "上场时，封锁对方所有【地】单位 1 回合。",
        "effects": [{"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1}],
        "fx": "chain"}},
    "罗刹": {"on_play": {
        "name": "罗刹啖血",
        "desc": "上场时，对对方【人】造成 2 点【气】伤害。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 2}],
        "fx": "slash"}},
    "虎妖": {"on_play": {
        "name": "裂地扑杀",
        "desc": "上场时，对对方场上生命最低的单位造成 3 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 3}],
        "fx": "smash"}},
    "骨妖": {"on_play": {
        "name": "白骨森森",
        "desc": "上场时，从己方弃置区复活 1 张牌回手牌。",
        "effects": [{"type": "revive_discard", "value": 1}],
        "fx": "revive"}},
    "夜叉": {"on_play": {
        "name": "夜叉疾袭",
        "desc": "上场时，对对方【人】造成 1 点【气】伤害并抽 1 张牌。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 1},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "slash"}},
    "山魈": {"on_play": {
        "name": "魈影惑心",
        "desc": "上场时，对方随机弃 1 张手牌。",
        "effects": [{"type": "discard_enemy", "value": 1}],
        "fx": "seal"}},
    "镰鼬": {"on_play": {
        "name": "旋风斩",
        "desc": "上场时，对所有对方单位造成 1 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1}],
        "fx": "wind"}},

    # ================= 地·鬼 =================
    "酒吞童子": {"on_play": {
        "name": "鬼王斟酒",
        "desc": "上场时，自身 +3【体】，并对对方【人】造成 2 点【气】伤害。",
        "effects": [{"type": "buff_self_hp", "value": 3},
                    {"type": "damage_qi", "target": "enemy_ren", "value": 2}],
        "fx": "fire"}},
    "茨木童子": {"on_play": {
        "name": "鬼手夺魂",
        "desc": "上场时，钉死对方 1 张阶数 ≤2 的【地】卡。",
        "effects": [{"type": "destroy_di", "tier_limit": 2}],
        "fx": "purge"}},
    "酒吞": {"on_play": {
        "name": "醉斩",
        "desc": "上场时，对对方场上生命最低的单位造成 2 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 2}],
        "fx": "slash"}},
    "画皮鬼": {"on_play": {
        "name": "画皮易容",
        "desc": "上场时，随机获得对方 1 张手牌，对方补抽 1 张。",
        "effects": [{"type": "steal_hand", "value": 1}],
        "fx": "soul"}},
    "红衣女鬼": {"on_play": {
        "name": "红衣索命",
        "desc": "上场时，对对方【人】造成 2 点【气】伤害。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 2}],
        "fx": "slash"}},
    "鬼王": {"on_play": {
        "name": "鬼王号令",
        "desc": "上场时，己方所有【地】单位 +1 生命，并对对方【人】造成 1 点【气】伤害。",
        "effects": [{"type": "heal_board_all", "side": "self", "value": 1},
                    {"type": "damage_qi", "target": "enemy_ren", "value": 1}],
        "fx": "summon"}},
    "百目鬼": {"on_play": {
        "name": "百目窥心",
        "desc": "上场时，使对方下回合手牌信息隐藏。",
        "effects": [{"type": "fog_hand", "turns": 1}],
        "fx": "moon"}},
    "飞头蛮": {"on_play": {
        "name": "飞头夜袭",
        "desc": "上场时，对对方【人】造成 1 点【气】伤害并抽 1 张牌。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 1},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "slash"}},
    "飞僵": {"on_play": {
        "name": "尸气冲天",
        "desc": "上场时，对方场上随机 2 张卡各失去 1 点生命。",
        "effects": [{"type": "debuff_board", "side": "enemy", "value": 1, "count": 2}],
        "fx": "poison"}},

    # ================= 地·五行尸 =================
    "僵尸": {"on_play": {
        "name": "坚尸之躯",
        "desc": "上场时，自身 +2【体】。",
        "effects": [{"type": "buff_self_hp", "value": 2}],
        "fx": "buff"}},
    "木魁": {"on_play": {
        "name": "木魅缠绕",
        "desc": "上场时，封锁对方 1 张随机单位 1 回合。",
        "effects": [{"type": "freeze_board", "side": "enemy", "turns": 1}],
        "fx": "chain"}},
    "水鬼": {"on_play": {
        "name": "拖人下水",
        "desc": "上场时，将对方场上 1 张阶数 ≤2 的卡弹回其手牌。",
        "effects": [{"type": "bounce_board", "side": "enemy", "value": 1, "tier_limit": 2}],
        "fx": "chain"}},
    "焚灭鬼": {"on_play": {
        "name": "焚身业火",
        "desc": "上场时，对所有对方单位造成 1 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1}],
        "fx": "fire"}},
    "金煞鬼": {"on_play": {
        "name": "金煞锋刃",
        "desc": "上场时，对对方场上生命最低的单位造成 3 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 3}],
        "fx": "slash"}},

    # ================= 地·魑魅魍魉 =================
    "魑魅": {"on_play": {
        "name": "迷人眼目",
        "desc": "上场时，封锁对方 1 张随机场上单位 1 回合。",
        "effects": [{"type": "freeze_board", "side": "enemy", "turns": 1}],
        "fx": "chain"}},
    "魍魉": {"on_play": {
        "name": "惑人心神",
        "desc": "上场时，使对方下回合手牌信息隐藏。",
        "effects": [{"type": "fog_hand", "turns": 1}],
        "fx": "moon"}},

    # ================= 地·五灾 =================
    "无支祁": {"active": {
        "name": "兴风作浪", "cd": 2,
        "desc": "冷却 2 回合。将对方场上 1 张阶数 ≤3 的卡弹回其手牌。",
        "effects": [{"type": "bounce_board", "side": "enemy", "value": 1, "tier_limit": 3}],
        "fx": "wind"}},
    "旱魃": {"on_play": {
        "name": "赤地千里",
        "desc": "上场时，对方【财】-3（最低 0），己方获得等量【财】。",
        "effects": [{"type": "steal_res", "res": "wealth", "value": 3}],
        "fx": "fire"}},
    "疫鬼": {"on_play": {
        "name": "瘟疫蔓延",
        "desc": "上场时，对对方所有单位造成 1 点伤害，并使其随机弃 1 张手牌。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "poison"}},
    "蝗神": {"on_play": {
        "name": "蝗灾蔽日",
        "desc": "上场时，对对方场上所有【地】单位造成 2 点伤害，且本局场位上限 +1（蝗群遮天蔽日）。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2},
                    {"type": "board_bonus", "value": 1}],
        "fx": "quake"}},
    "回禄": {"on_play": {
        "name": "回禄焚城",
        "desc": "上场时，对所有对方单位造成 2 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 2}],
        "fx": "fire"}},

    # ================= 地·五孽 =================
    "妖孽-九婴": {"on_play": {
        "name": "九婴啼火",
        "desc": "上场时，对所有对方单位造成 2 点伤害，并令对方随机弃 1 张手牌。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 2},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "fire"}},
    "怪孽-蜚": {"on_play": {
        "name": "蜚灾横行",
        "desc": "上场时，对对方【人】造成 3 点【气】伤害。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 3}],
        "fx": "poison"}},
    "精孽-木客": {"on_play": {
        "name": "木客缚魂",
        "desc": "上场时，封锁对方所有单位 1 回合。",
        "effects": [{"type": "freeze_board", "side": "enemy", "turns": 1}],
        "fx": "chain"}},
    "鬼孽-罗刹女": {"on_play": {
        "name": "罗刹噬心",
        "desc": "上场时，钉死对方 1 张阶数 ≤3 的【地】卡，并对其【人】造成 1 点【气】伤害。",
        "effects": [{"type": "destroy_di", "tier_limit": 3},
                    {"type": "damage_qi", "target": "enemy_ren", "value": 1}],
        "fx": "purge"}},
    "魔孽-波旬": {"on_play": {
        "name": "波旬乱法",
        "desc": "上场时，随机夺取对方 2 张手牌，所有对方单位失去 1 点生命。",
        "effects": [{"type": "steal_hand", "value": 2},
                    {"type": "damage_board_all", "side": "enemy", "value": 1}],
        "fx": "soul"}},

    # ================= 地·三尸 =================
    "上尸彭踞": {"on_play": {
        "name": "上尸伐心",
        "desc": "上场时，对方随机弃 1 张手牌，己方抽 1 张牌。",
        "effects": [{"type": "discard_enemy", "value": 1},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "seal"}},
    "中尸彭踬": {"on_play": {
        "name": "中尸乱性",
        "desc": "上场时，对对方【人】造成 2 点【气】伤害。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 2}],
        "fx": "slash"}},
    "下尸彭蹻": {"on_play": {
        "name": "下尸夺魄",
        "desc": "上场时，将对方场上 1 张阶数 ≤2 的卡弹回其手牌。",
        "effects": [{"type": "bounce_board", "side": "enemy", "value": 1, "tier_limit": 2}],
        "fx": "chain"}},

    # ================= 地·魔 =================
    "梦魇魔君": {"on_play": {
        "name": "梦魇缠身",
        "desc": "上场时，封锁对方所有【地】单位 1 回合（无法对【人】攻击）。",
        "effects": [{"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1, "block_qi": True}],
        "fx": "moon"}},
    "血煞魔尊": {"on_play": {
        "name": "血煞滔天",
        "desc": "上场时，牺牲己方场上 1 张卡，对对方【人】造成 4 点【气】伤害。",
        "effects": [{"type": "sacrifice_board", "side": "self", "filter": ""},
                    {"type": "damage_qi", "target": "enemy_ren", "value": 4}],
        "fx": "slash"}},
    "瘟癀鬼帝": {"on_play": {
        "name": "瘟癀散播",
        "desc": "上场时，对所有对方单位造成 1 点伤害，对方随机弃 1 张手牌。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "poison"}},
    "万骨魔君": {"on_play": {
        "name": "万骨朝宗",
        "desc": "上场时，己方【人】获得 3 点护盾【气】，自身 +2【体】，抽 1 张牌，且本局场位上限 +1（万骨皆可为兵）。",
        "effects": [{"type": "shield_qi", "value": 3},
                    {"type": "buff_self_hp", "value": 2},
                    {"type": "draw", "target": "self", "value": 1},
                    {"type": "board_bonus", "value": 1}],
        "fx": "summon"}},
    "幽影魔君": {"on_play": {
        "name": "幽影蚀魂",
        "desc": "上场时，对对方【人】造成 2 点【气】伤害并使其随机弃 1 张手牌。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 2},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "soul"}},
    "毕舍遮": {"on_play": {
        "name": "食人精魄",
        "desc": "上场时，对对方场上生命最低的单位造成 4 点伤害并自愈 2 点。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 4},
                    {"type": "buff_self_hp", "value": 2}],
        "fx": "smash"}},
    "白衣女魔": {"on_play": {
        "name": "白衣索魂",
        "desc": "上场时，随机夺取对方 1 张手牌，并令对方场上 1 张卡失去 2 点生命。",
        "effects": [{"type": "steal_hand", "value": 1},
                    {"type": "debuff_board", "side": "enemy", "value": 2, "count": 1}],
        "fx": "soul"}},
    "大黑爱婴佛母": {"on_play": {
        "name": "佛母慈护",
        "desc": "上场时，己方所有【天】+2【祇】，己方【人】恢复 2 点【气】。",
        "effects": [{"type": "buff_tian_hp_all", "value": 2},
                    {"type": "heal_qi", "target": "self_ren", "value": 2}],
        "fx": "heal"}},

    # ================= 地·奇兽 =================
    "饕餮": {"on_play": {
        "name": "饕餮吞天",
        "desc": "上场时，获得 2 点【财】并抽 1 张牌。",
        "effects": [{"type": "gain_res", "res": "wealth", "value": 2},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "coin"}},
    "麒麟": {"on_play": {
        "name": "麒麟送瑞",
        "desc": "上场时，己方【人】恢复 2 点【气】并抽 1 张牌。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 2},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "heal"}},
    "穷奇": {"on_play": {
        "name": "穷奇食善",
        "desc": "上场时，对方随机弃 1 张手牌。",
        "effects": [{"type": "discard_enemy", "value": 1}],
        "fx": "seal"}},
    "混沌": {"on_play": {
        "name": "混沌无相",
        "desc": "上场时，己方场上随机 1 张卡变化为同阵营同阶的另一张随机卡。",
        "effects": [{"type": "transform_board"}],
        "fx": "summon"}},
    "狴犴": {"on_play": {
        "name": "狴犴断狱",
        "desc": "上场时，消灭对方 1 张生命 ≤2 的场上卡。",
        "effects": [{"type": "execute_board", "side": "enemy", "hp_limit": 2}],
        "fx": "purge"}},
    "睚眦": {"on_play": {
        "name": "睚眦必报",
        "desc": "上场时，对对方场上生命最低的单位造成 3 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 3}],
        "fx": "slash"}},
    "狻猊": {"on_play": {
        "name": "狻猊啸烟",
        "desc": "上场时，己方【人】获得 3 点护盾【气】。",
        "effects": [{"type": "shield_qi", "value": 3}],
        "fx": "shield"}},
    "螭吻": {"on_play": {
        "name": "螭吻御水",
        "desc": "上场时，己方【人】恢复 3 点【气】。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 3}],
        "fx": "heal"}},
    "赑屃": {"on_play": {
        "name": "赑屃负山",
        "desc": "上场时，自身 +3【体】。",
        "effects": [{"type": "buff_self_hp", "value": 3}],
        "fx": "buff"}},
    "蒲牢": {"on_play": {
        "name": "蒲牢鸣钟",
        "desc": "上场时，封锁对方所有【地】单位 1 回合。",
        "effects": [{"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1}],
        "fx": "chain"}},
    "囚牛": {"on_play": {
        "name": "囚牛知音",
        "desc": "上场时，抽 2 张牌。",
        "effects": [{"type": "draw", "target": "self", "value": 2}],
        "fx": "draw"}},
    "嘲风": {"on_play": {
        "name": "嘲风望远",
        "desc": "上场时，使对方下回合手牌信息隐藏，己方抽 1 张牌。",
        "effects": [{"type": "fog_hand", "turns": 1},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "moon"}},
    "吞口": {"on_play": {
        "name": "吞口辟邪",
        "desc": "上场时，对方场上随机 2 张卡各失去 1 点生命。",
        "effects": [{"type": "debuff_board", "side": "enemy", "value": 1, "count": 2}],
        "fx": "smash"}},
    "杌": {"on_play": {
        "name": "杌木为妖",
        "desc": "上场时，己方场上所有单位 +1 生命。",
        "effects": [{"type": "heal_board_all", "side": "self", "value": 1}],
        "fx": "heal"}},
    "比奥天": {"on_play": {
        "name": "比奥噬天",
        "desc": "上场时，对对方所有单位造成 1 点伤害并抽 1 张牌。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "quake"}},

    # ================= 天·天王（3 阶） =================
    "托塔李天王李靖": {"on_play": {
        "name": "玲珑宝塔",
        "desc": "上场时，封锁对方所有单位 1 回合并对其【人】造成 2 点【气】伤害。",
        "effects": [{"type": "freeze_board", "side": "enemy", "turns": 1},
                    {"type": "damage_qi", "target": "enemy_ren", "value": 2}],
        "fx": "freeze"}},
    "真武斩妖天王": {"on_play": {
        "name": "真武荡魔",
        "desc": "上场时，钉死对方 1 张阶数 ≤3 的【地】卡。",
        "effects": [{"type": "destroy_di", "tier_limit": 3}],
        "fx": "purge"}},
    "降魔天王": {"on_play": {
        "name": "金刚降魔",
        "desc": "上场时，直接钉死对方 1 张生命 ≤4 的场上卡。",
        "effects": [{"type": "execute_board", "side": "enemy", "hp_limit": 4}],
        "fx": "purge"}},
    "雷嗔天君": {"on_play": {
        "name": "五雷轰顶",
        "desc": "上场时，对对方所有单位造成 1 点伤害，并对其【人】造成 2 点【气】伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1},
                    {"type": "damage_qi", "target": "enemy_ren", "value": 2}],
        "fx": "bolt"}},
    "五雷真法天王": {"on_play": {
        "name": "雷法天威",
        "desc": "上场时，对对方所有单位造成 2 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 2}],
        "fx": "bolt"}},
    "九阳定雷天尊": {"on_play": {
        "name": "九阳定雷",
        "desc": "上场时，对对方所有单位造成 1 点伤害，己方所有【天】+1【祇】。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 1},
                    {"type": "buff_tian_hp_all", "value": 1}],
        "fx": "bolt"}},
    "面燃大帝": {"on_play": {
        "name": "面燃业火",
        "desc": "上场时，对对方【人】造成 3 点【气】伤害。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 3}],
        "fx": "fire"}},
    "五火真君": {"on_play": {
        "name": "五火燎原",
        "desc": "上场时，对所有对方单位造成 2 点伤害。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 2}],
        "fx": "fire"}},
    "五火真君附身": {"on_play": {
        "name": "真君附体",
        "desc": "上场时，自身 +3【祇】，己方所有【天】+1【祇】。",
        "effects": [{"type": "buff_self_hp", "value": 3},
                    {"type": "buff_tian_hp_all", "value": 1}],
        "fx": "buff"}},
    "五火除魔震灾威严魔怒相": {"on_play": {
        "name": "魔怒震灾",
        "desc": "上场时，对所有对方单位造成 2 点伤害，并令对方随机弃 2 张手牌。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "value": 2},
                    {"type": "discard_enemy", "value": 2}],
        "fx": "fire"}},
    "太阳星君": {"on_play": {
        "name": "日曜当空",
        "desc": "上场时，己方【人】恢复 5 点【气】。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 5}],
        "fx": "heal"}},
    "玄冰真君": {"on_play": {
        "name": "玄冰封天",
        "desc": "上场时，封锁对方所有单位 1 回合。",
        "effects": [{"type": "freeze_board", "side": "enemy", "turns": 1}],
        "fx": "freeze"}},
    "破魔天尊": {"on_play": {
        "name": "破魔真言",
        "desc": "上场时，消灭对方所有阶数 ≤2 的【地】卡。",
        "effects": [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 4}],
        "fx": "purge"}},
    "御尊天王": {"on_play": {
        "name": "御尊无为",
        "desc": "上场时，己方所有【天】+2【祇】，己方【人】获得 3 点护盾【气】。",
        "effects": [{"type": "buff_tian_hp_all", "value": 2},
                    {"type": "shield_qi", "value": 3}],
        "fx": "shield"}},
    "金轮圆法天王": {"on_play": {
        "name": "金轮转法",
        "desc": "上场时，抽 2 张牌，并令对方随机弃 1 张手牌。",
        "effects": [{"type": "draw", "target": "self", "value": 2},
                    {"type": "discard_enemy", "value": 1}],
        "fx": "draw"}},

    # ================= 器具 / 其他 =================
    "三清铃": {"on_play": {
        "name": "三清铃响",
        "desc": "使用后，己方【人】恢复 2 点【气】并抽 1 张牌。",
        "effects": [{"type": "heal_qi", "target": "self_ren", "value": 2},
                    {"type": "draw", "target": "self", "value": 1}],
        "fx": "heal"}},
    "八卦镜": {"on_play": {
        "name": "八卦照妖",
        "desc": "使用后，己方【人】获得 3 点护盾【气】。",
        "effects": [{"type": "shield_qi", "value": 3}],
        "fx": "shield"}},
    "铜钱剑": {"on_play": {
        "name": "铜钱剑阵",
        "desc": "使用后，对对方场上生命最低的单位造成 3 点伤害。",
        "effects": [{"type": "damage_weakest", "side": "enemy", "value": 3}],
        "fx": "slash"}},
    "金刚钺": {"on_play": {
        "name": "金刚钺斩",
        "desc": "使用后，对对方【人】造成 2 点【气】伤害。",
        "effects": [{"type": "damage_qi", "target": "enemy_ren", "value": 2}],
        "fx": "slash"}},
    "金刚镢": {"on_play": {
        "name": "金刚镢击",
        "desc": "使用后，直接钉死对方 1 张生命 ≤2 的场上卡。",
        "effects": [{"type": "execute_board", "side": "enemy", "hp_limit": 2}],
        "fx": "purge"}},
    "降魔杵": {"on_play": {
        "name": "降魔杵镇",
        "desc": "使用后，钉死对方 1 张阶数 ≤3 的【地】卡。",
        "effects": [{"type": "destroy_di", "tier_limit": 3}],
        "fx": "purge"}},
    "拜神": {"on_play": {
        "name": "拜神祈天",
        "desc": "使用后，随机获得 1 张【天】卡入手。",
        "effects": [{"type": "summon_to_hand", "subs": ["神", "佛"], "value": 1}],
        "fx": "summon"}},
    "敬鬼": {"on_play": {
        "name": "敬鬼祭祀",
        "desc": "使用后，随机获得 1 张【地】卡入手。",
        "effects": [{"type": "summon_to_hand", "subs": ["妖", "鬼", "魔"], "value": 1}],
        "fx": "summon"}},
}


# ------------------------------------------------------------------ 12 角色
CHARACTERS = [
    ("白樰",   "凡",     "草医灵巫",   "灵草绿", "蓑衣、药箱、草药、绿色灵液", "凡人",
     "百草回春", "冷却 2 回合。弃 1 张手牌，为己方【人】恢复 3 点【气】。", 2,
     [{"type": "discard_self", "value": 1}, {"type": "heal_qi", "target": "self_ren", "value": 3}]),
    ("马曜",   "道家",   "紫电狂道",   "紫电紫", "桃木剑、紫电、金色符箓",   "正一道士",
     "紫电诛邪", "冷却 3 回合。对对方 1 张【地】卡造成 2 点伤害并使其下回合无法攻击。", 3,
     [{"type": "damage_board", "side": "enemy", "value": 2, "filter": "地"}, {"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1}]),
    ("朔弥",   "神天大照", "日轮神使", "日轮金", "日轮、金液、白袍",        "阴阳师",
     "日轮照世", "冷却 3 回合。己方所有【天】+1【祇】，并对对方【人】造成 1 点【气】伤害。", 3,
     [{"type": "buff_tian_hp_all", "value": 1}, {"type": "damage_qi", "target": "enemy_ren", "value": 1}]),
    ("楚伞",   "妖",     "青渊战魂",   "青渊蓝", "白色机甲、巨剑、青色灵液", "巫女",
     "青渊斩",   "冷却 2 回合。对对方场上 1 张卡造成 3 点伤害（无视克制关系）。", 2,
     [{"type": "damage_board", "side": "enemy", "value": 3, "ignore_counter": True}]),
    ("阿迪亚", "藏佛",   "骷髅密行者", "焰骨橙", "骷髅兜帽、十字锡杖、橙色火焰", "法师",
     "焰骨焚身", "冷却 3 回合。牺牲己方 1 张【地】卡，对对方【人】造成 3 点【气】伤害。", 3,
     [{"type": "sacrifice_board", "side": "self", "filter": "地", "value": 1}, {"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
    ("小乔儿", "道家",   "血线剑娘",   "血线红", "红线飞剑、红色蝴蝶结、符箓", "正一道士",
     "红线飞剑", "冷却 2 回合。对对方 1 张卡造成 2 点伤害；若将其拔除则己方抽 1 张牌。", 2,
     [{"type": "damage_board", "side": "enemy", "value": 2, "draw_on_kill": 1}]),
    ("唐森",   "藏佛",   "莲印密行者", "莲印粉", "额头莲花、环形锡杖、粉色灵液", "法师",
     "莲印庇护", "冷却 2 回合。为己方 1 张场上【天】恢复 2 点【祇】。", 2,
     [{"type": "heal_board", "side": "self", "filter": "天", "value": 2}]),
    ("白店小二", "凡",   "茶壶剑客",   "青茶碧", "紫铜茶壶剑、茶盘、青色灵液", "凡人",
     "一壶浊酒", "被动：每回合结束额外获得 2 点【财】。主动（冷却 3 回合）：弃 1 张牌换 3 点【财】。", 3,
     [{"type": "discard_self", "value": 1}, {"type": "gain_res", "res": "wealth", "value": 3}]),
    ("青蘅",   "妖",     "竹筒巫女",   "青蘅绿", "竹筒腰带、绿液、金属兽首", "巫女",
     "竹筒蛊",   "冷却 2 回合。随机使对方 1 张手牌被弃置。", 2,
     [{"type": "discard_enemy", "value": 1}]),
    ("吉马卓玛", "藏佛", "转经少女",   "卓玛青", "转经筒、绿松石、白色藏袍", "法师",
     "转经祈福", "冷却 3 回合。获得 1 张【护法金刚】，己方【人】+2 点【气】。", 3,
     [{"type": "grant_card_tag", "tag": "护法金刚", "value": 1}, {"type": "heal_qi", "target": "self_ren", "value": 2}]),
    ("孟谢菲", "仙",     "谪仙白狐",   "流云紫", "折扇、九尾、紫色灵液",     "阴阳师",
     "九尾惑心", "冷却 3 回合。随机获得对方 1 张手牌，对方补抽 1 张。", 3,
     [{"type": "steal_hand", "value": 1}, {"type": "draw", "target": "enemy", "value": 1}]),
    ("玄澈",   "道家",   "阵道天师",   "玄阵青", "脚下法阵、阵旗、青色灵液", "正一道士",
     "玄阵封魔", "冷却 3 回合。对方所有【地】卡下回合无法对【人】发起攻击。", 3,
     [{"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1, "block_qi": True}]),
]

PASSIVE_CHAR = {
    "白店小二": {"name": "茶壶聚宝", "desc": "每回合结束额外获得 2 点【财】。",
                 "effects": [{"type": "aura_wealth", "value": 2}]},
}


# ------------------------------------------------------------------ 12 角色介绍
# 对局内角色名牌下方显示的那两行字。要求：一句话写清「这个人是谁」，
# 允许有画面感，但不要复述技能数值（技能已经写在卡上）。
CHAR_INTRO = {
    "白樰":     "背药箱走山野的草医，衣上总有新采的药香。她不争杀伐，只求同袍不死。",
    "马曜":     "持桃木剑的狂道。符箓未出，紫电先至。",
    "朔弥":     "承日轮之光的白袍神使，一言可令众神加护。",
    "楚伞":     "披白色甲胄的战魂，巨剑过处，青渊翻涌。",
    "阿迪亚":   "兜帽下只见骷髅，锡杖所指，橙焰自骨而生。",
    "小乔儿":   "系红蝶结的剑娘，赤线一出，飞剑自来。",
    "唐森":     "额生莲印的密行者，粉莲一开，便是庇护。",
    "白店小二": "跑堂的伙计，茶壶里装的可不全是茶。",
    "青蘅":     "腰悬竹筒的巫女，筒中蛊虫比刀更近人。",
    "吉马卓玛": "转动经筒的少女，一步一经，一念一护。",
    "孟谢菲":   "折扇半掩的谪仙，九尾一现，人心自失。",
    "玄澈":     "脚下自生法阵的天师，阵旗未落，万魔已困。",
}


# ------------------------------------------------------------------ 组装卡牌
def build_cards():
    cards = []
    _reset_skill_registry()                          # 取样表每次重建，保证可复现
    # 先做一次「家族分配」完整性校验：漏配一张卡就一次性列出全部，
    # 而不是让 build_skills 一张一张抛（那样要跑 N 遍才知道还差哪些）。
    unmapped = [m["name"] for m in MANIFEST
                if m["top"] not in ("角色", "人")
                and m["top"] != "道具"
                and m["name"] not in CS.FAMILY]
    if unmapped:
        raise SystemExit("[FATAL] 以下卡牌未分配技能家族，请在 tools/card_skills.py 的 FAMILY 表补上：\n  "
                         + "、".join(unmapped))
    for m in MANIFEST:
        top_cn = m["top"]
        if top_cn in ("角色", "人"):
            continue                                  # 角色与人卡单独处理
        gkey = f"{top_cn}/{m['group']}"
        tier, sub = TIER_TABLE.get(gkey, DEFAULT_TIER)
        is_special = m["group"] in ("四相", "十二生肖")
        hp, atk, atk_qi = stats_for(top_cn, sub, tier, is_special)

        tags = []
        if m["group"] == "佛_护法金刚":
            tags.append("护法金刚")

        is_item = (top_cn == "道具")
        card = {
            "id": m["id"],
            "name": m["name"],
            "faction": top_cn,                       # 天 / 地 / 道具
            "sub": sub,                                # 佛 神 妖 鬼 魔 奇兽 道具
            "group": gkey,
            "path": m.get("path", []),                 # 原始 PNG 目录层级（图鉴按此建树）
            "topKey": m.get("topKey", ""),
            "tier": tier,                              # 阶数固定，不可升阶（合成已移除）
            "maxTier": tier,                           # 与 tier 一致：没有升阶路径了
            "hp": hp,
            "atk": atk,
            "atkQi": atk_qi,
            "art": m["art"],
            "thumb": m["thumb"],
            "pool": "special" if is_special else "normal",
            "tags": tags,
            # 技能由「卡名 + 阶数」决定：非道具卡必有被动，
            # 技能位数量 == 阶数（1 阶 1 个 / 2 阶 2 个 / 3 阶 3 个）；
            # 道具卡不带技能，只有功能。
            "skills": build_skills(m["id"], gkey, sub, tier, m["name"], is_item),
            "desc": "%s·%s ｜ %d阶 ｜ %s" % (top_cn, sub, tier, m["name"]),
        }
        # 说明：签名技能的覆写已在 build_skills 内部完成 —— 它需要**先**知道
        # 签名占了哪个槽位，才能排出合法的技能位组合（数量必须等于阶数）。
        # 道具卡：把「功能键 / 落点类型 / 刷出权重 / 一局上限」写进数据。
        # 这些值决定 UI 怎么拖、规则层怎么结算，源头在 tools/card_skills.py 的 ITEM_FUNCS。
        if is_item:
            fn: dict = CS.ITEM_FUNCS.get(m["id"], {})
            st: dict = CS.ITEM_STARTERS.get(m["id"], {})
            card["itemFunc"] = fn.get("func", st.get("func", ""))
            card["itemTarget"] = fn.get("target", "none")
            card["itemWeight"] = int(fn.get("weight", 0))
            card["itemMaxPerGame"] = int(fn.get("max_per_game", 0))
            card["starter"] = bool(st)
        _apply_tier_scaling(card)
        cards.append(card)
    return cards


## 随阶数缩放的安全效果类型白名单
## 只有「数值越大越强、且放大会破坏规则」的效果才纳入。
## 刻意排除：aura_enemy_di_atk（取最大值而非叠加，必须保持恒定 1）。
SCALE_SAFE = {
    "heal_qi", "heal_board", "heal_board_all",
    "damage_qi", "damage_board", "damage_board_all", "damage_weakest",
    "shield_qi", "draw", "draw_group", "gain_res", "gain_material",
    "summon_to_hand", "summon_special", "dice_damage", "dice_heal",
    "discard_enemy", "debuff_board", "buff_self_hp", "buff_tian_hp_all",
    "buff_lonely", "revive_discard", "recycle_discard", "steal_hand",
    "steal_res", "bounce_board", "freeze_board", "seal_hand_card",
    "copy_hand", "transform_board", "qi_per_tian", "conquer_board",
}


def _apply_tier_scaling(card):
    """把「写死在某个阶数上」的技能数值改写成可随阶数成长的形式。

    · 签名技能（带 fx）：以卡牌自身卡池阶数为基准 —— 保证该卡在原阶数下
      的数值与描述文字完全一致，只有「合成升阶」后才变强。
    · 通用/附加技能：以 1 阶为基准（沿用原有语义）。
    已经声明过 per_tier / count_per_tier / limit_per_tier 的效果不动。
    """
    base = int(card.get("tier", 1))
    for key, sk in (card.get("skills") or {}).items():
        if not isinstance(sk, dict):
            continue
        # absolute=True —— 家族主题库产出的技能：数值是绝对值，不参与放大。
        # 新的强度曲线走「阶数 → 技能数量」（1/2/3 个），
        # 若再让每条技能随阶数翻倍，3 阶卡会同时吃两份收益，直接超模。
        if sk.get("absolute"):
            continue
        is_signature = "fx" in sk
        for e in (sk.get("effects") or []):
            if not isinstance(e, dict):
                continue
            # fixed=True 的效果（主动技能按阶数追加的那几段）不参与放大：
            # 高阶卡已经多拿了一段效果，再让每段随阶数翻倍会直接超模。
            if e.get("fixed"):
                continue
            if any(k in e for k in ("per_tier", "count_per_tier", "limit_per_tier")):
                continue
            if e.get("type") not in SCALE_SAFE:
                continue
            v = e.get("value")
            if not isinstance(v, int) or v <= 0:
                continue
            step = max(1, v // 3)
            e["per_tier"] = step
            if is_signature and base > 1:
                e["per_tier_from_base"] = True


def build_characters():
    out = []
    for (name, ident, title, color, visual, ren, sk, sdesc, cd, eff) in CHARACTERS:
        c = {
            "id": "chara_%s" % name,
            "name": name,
            "identity": ident,
            "title": title,
            "color": color,
            "visual": visual,
            "intro": CHAR_INTRO.get(name, ""),
            "renCard": ren,
            "art": _find_art("chara", name),
            "thumb": _find_thumb("chara", name),
            "skill": {"name": sk, "desc": sdesc, "cd": cd, "effects": eff},
            "passive": None,
        }
        if name in PASSIVE_CHAR:
            c["passive"] = PASSIVE_CHAR[name]
        out.append(c)
    return out


def _find_art(top_key, name):
    want = ART_ALIAS.get((top_key, name), name)
    for m in MANIFEST:
        if m["topKey"] == top_key and m["name"] == want:
            return m["art"]
    return ""


def _find_thumb(top_key, name):
    want = ART_ALIAS.get((top_key, name), name)
    for m in MANIFEST:
        if m["topKey"] == top_key and m["name"] == want:
            return m["thumb"]
    return ""


def build_ren_cards():
    out = []
    for m in MANIFEST:
        if m["top"] != "人" or m["group"] != "root":
            continue
        n = m["name"]
        cfg = {
            "凡人":     {"upgrade": "wealth", "cost": 3, "qi": 2, "note": "花【财】买人，提供 2 点【气】。"},
            "正一道士": {"upgrade": "fa",     "cost": 3, "qi": 5, "note": "消耗【法】收【徒】，提供 5 点【气】。对方单位被拔除/钉死时获得少量【法】。"},
            "阴阳师":   {"upgrade": "yuan",   "cost": 3, "qi": 2, "note": "消耗【源】收【阴阳师】，提供 2 点【气】；可消耗【千纸鹤】召唤【式神】。"},
            "巫女":     {"upgrade": "wealth", "cost": 3, "qi": 2, "note": "和凡人一样靠【财】买，提供 2 点【气】。"},
            "法师":     {"upgrade": "none",   "cost": 0, "qi": 3, "note": "无法获得【财】；靠降伏【地】单位获得【信众】，提供 3 点【气】并 +1【阿弥陀佛】。"},
            "萨满":     {"upgrade": "none",   "cost": 0, "qi": 0, "note": "不能升级【人】；无法使用【财】；每回合可从各玩家手中抢 1 张手牌（佛属性角色不可被抢）。"},
        }[n]
        out.append({
            "id": m["id"], "name": n, "qi": 15 if n == "正一道士" else 12,
            "art": m["art"], "thumb": m["thumb"],
            "upgrade": cfg["upgrade"], "upgradeCost": cfg["cost"], "upgradeQi": cfg["qi"],
            "note": cfg["note"],
        })
    return out


RULES = {
    "qiMax": 15,
    "wealthCurve": [3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10],
    "wealthCurveNote": "第 N 回合结束获得 curve[N-1] 点【财】，逐回合累加；超出长度后取最后一个值。",
    "freeRefreshPerTurn": 1,
    "refreshCostLadder": [1, 2, 3],
    "buyCost": 3,
    "draftCount": 3,
    "draftPerTurn": 1,
    # 三选一改造成「取牌台」后的经济参数：
    #   · draftFreePerTurn —— 每回合前 N 次点牌取走免费（不计【财】）
    #   · draftPaidCapPerTurn —— 免费额度用完后，本回合还能再花【财】买几次
    #     （不设上限时，高【财】玩家会一回合把牌面买空，手牌爆炸、节奏崩掉）
    "draftFreePerTurn": 1,
    "draftPaidCapPerTurn": 3,
    # 【合成已整条移除】卡牌的阶数在卡池里就是固定的 —— 图鉴里看到的阶数即最终阶数，
    # 不要再引入任何「升阶」路径。技能位数量由阶数决定（1 阶 1 个 / 2 阶 2 个 / 3 阶 3 个），
    # 所以一旦允许升阶，卡面技能就得跟着改写，整套规则会被拖进不一致状态。
    # 【重要】rules.json 是**生成物**：手工只改 data/rules.json 会被下一次
    # tools/build_cards.py 直接覆盖掉（boardCap / boardUnique 就这么丢过一次，
    # 表现是「同一张卡能重复上场、场位也没有上限」，而规则层读到的是一份空字典）。
    # 任何规则常量的唯一真源都在这里。
    "boardCap": {
        "enabled": True, "base": 2, "perRound": 1, "max": 7,
        "note": "常规玩家可同时上场的【非道具】卡牌上限 = clamp(base + 轮数*perRound, base, max)，封顶 7。"
                "临时单位（三清铃召唤的【僵尸】）不占数额；部分技能/特殊角色通过 board_bonus 可再多上几张。",
    },
    "boardUnique": {
        "enabled": True,
        "note": "同一张卡（同一卡牌定义 id，跨阶数也算）不能同时留在自己场上。",
    },
    "discardGain": {"wealth": 1, "fa": 1, "yuan": 1},
    # 拜神 / 敬鬼：从「每回合各一次」改成**冷却 3 回合**。
    # 语义与 chara_cd 一致：用掉后置 3，之后每到自己回合开始减 1，
    # 减到 0 才能再用 —— 也就是「用一次要等 3 个自己的回合」。
    "worshipCooldown": 3,
    "worshipPerTurn": 1,
    # 每回合可消耗的「主动行动」次数（袭人 / 点击场上卡发动主动技能）。
    # 设计文档的回合流程里「主动技能」是单一步骤；不给额度的话所有场上卡每回合
    # 都能打人，实测单局会从 22 回合缩到 8 回合，节奏完全跑偏。
    "actionsPerTurn": 2,
    "actionsPerTurnNote": "每回合可消耗的「主动行动」次数：袭人 / 点击场上卡发动主动技能。",
    # 2 人局后手补偿：先手在抢三选一 / 抢【财】/ 抢上场上都早一步，优势滚雪球。
    # 数值由 scripts/BalanceTest.gd --mode duel 扫参得出（每组 300 局，种子只与局数有关）。
    #
    # 【2026-10 重测修正】上一版取 {10:2} 并声称"先手 52.5%"，那是错的：
    #   当时 AI 的刷新/购买动作因为顺序 bug 全部静默失败（见 AIBrain.plan_turn），
    #   整个模拟里没人花【财】，而且 duel 扫参的种子还掺进了补偿参数本身
    #   （seed = 70000 + qi*131 + w*977 + g*37），每个补偿档打的是不同对手组合，
    #   于是"补偿有效"其实是换对手换出来的假象。
    #   修好经济 + 改成配对种子后重测，无补偿先手胜率高达 72.1%，需要 laterQi=23 才压到 49.7%。
    # 另一条结论也变了：【财】补偿在修复后**依然几乎无效**（0:0→72.1%，0:40→仅 70.0%），
    #   因为对局只有 ~11 回合，后手活不到【财】滚起来；只有【气】是真杠杆。
    "duelCompensation": {
        "enabled": True,
        "laterQi": 10,
        "laterWealth": 2,
        "note": "2 人局后手补偿。2026-10 技能去同质化后重扫（每组 200 局、配对种子）：0:0 先手 64.7% / 8:2 53.3% / 10:2 49.5% / 11:2 47.0% / 12:2 48.0% / 16:2 44.0% / 20:2 40.7% / 23:2 39.3%，取 10:2（49.5%，接近理想 50%）。",
    },
    # 3 / 4 人局的后手补偿：座位序号越靠后拿得越多（线性摊分，见 GameState._compensation_for）。
    #
    # 重要教训（实测数据）：
    #   本作的 AI 会集火「气最低的对手」，而补偿恰好把【气】与座位序号绑定，
    #   于是补偿过重时死亡顺序被座位锁定 —— 4 人局给 {6,10,14} 时偏斜从 ~20 恶化到 54.5
    #   （东 4% / 南 5% / 西 32.5% / 北 58.5%）。多人局只能给极轻的补偿。
    # 2026-10 重测（每组 320 局，配对种子）：
    #   3 人局 1:2 → 平均 16.3 回合、偏斜 19.7（东 40.6 / 南 20.9 / 西 38.4）
    #   4 人局 0:2 → 平均 17.7 回合、偏斜 22.8（东 39.4 / 南 25.6 / 西 18.4 / 北 16.6）
    #   两者平均回合都落在设计文档要求的 12~18 区间内；再加大补偿能略微降偏斜，
    #   但会把单局拉到 20+ 回合，超出设计节奏，故不采用。
    "compensationByCount": {
        "2": {"laterQi": 10, "laterWealth": 2},
        "3": {"laterQi": 1, "laterWealth": 2},
        "4": {"laterQi": 0, "laterWealth": 2},
    },
    "diceMin": 1, "diceMax": 6,
    # 力竭（防死局保险）：第 N 回合起，每位玩家在自己回合结束流失【气】，
    # 每 fatigueStepRounds 回合流失量 +1。确保任何对局都必然收敛。
    "fatigueStartRound": 30,
    "fatigueStepRounds": 8,
    "order": ["东", "南", "西", "北"],
    "counter": {
        "note": "攻击方 -> 防守方",
        "天": {"天": "制衡(互扣祇)", "地": "克制(消灭)", "人": "无法造成伤害"},
        "地": {"天": "被克制(不可攻击)", "地": "鬼不可攻击鬼", "人": "扣气"},
        "人": {"天": "不主动攻击", "地": "不主动攻击", "人": "—"},
    },
    "guardianBond": {"tag": "护法金刚", "need": 4, "reward": "降魔杵"},
    # 道具卡：刷出权重（越小越难刷）与「一局最多获得几次」。
    # 用户要求：概率 金刚钺 < 降魔杵 < 三清铃 < 铜钱剑 < 金刚镢 < 八卦镜；
    # 且每种道具一局最多获得 2 次，2 次后除非特殊技能否则不再刷出。
    # 拜神 / 敬鬼 是开局自带的专属卡，永远不出现在三选一里。
    "itemDraw": {
        "enabled": True,
        "maxPerGame": 2,
        # 权重直接取「其他卡牌 : 该道具」的相对稀有度，见 CardDB.random_draft_card
        "weights": {
            "金刚钺": 1, "降魔杵": 2, "三清铃": 3,
            "铜钱剑": 4, "金刚镢": 5, "八卦镜": 6,
        },
        # 普通牌的总权重。道具总权重固定 21（1..6 之和），
        # 道具占比 = 21 / (normalCardWeight + 21)。
        # 400 → 道具约占 5%（远低于普通牌，满足「道具概率低得多」）。
        "normalCardWeight": 400,
        "starters": ["拜神", "敬鬼"],
        "note": "三选一时，普通牌 = normalCardWeight 一个大权重，道具 = 各权重之和；"
                "该道具本局已拿满 maxPerGame 次则权重归 0。",
    },
    "faOnKill": 1,
    "paperCraneOnDeath": 1,
    "shikigamiQi": 2,
    "believerQi": 3,
    "buddhaQiShield": 2,
}


def main():
    cards = build_cards()
    chars = build_characters()
    ren = build_ren_cards()

    # ---- 效果类型白名单校验 ----
    # 技能写成 JSON 数据后，错别字不会在 Python 侧报错，只会在 Godot 里变成
    # 「[未实现的效果] xxx」一行日志。这里提前拦截。
    known = {
        "heal_qi", "damage_qi", "shield_qi", "draw", "discard_enemy", "discard_self",
        "steal_hand", "seal_hand_card", "fog_hand", "gain_res", "steal_res",
        "gain_material", "grant_card_tag", "recycle_discard", "summon_special",
        "damage_board", "damage_board_all", "damage_weakest", "heal_board",
        "heal_board_all", "buff_self_hp", "buff_tian_hp_all", "buff_lonely",
        "debuff_board", "destroy_di", "execute_board", "sacrifice_board",
        "clash_enemy_board", "freeze_board", "buff_qi_damage", "multiply_qi_damage",
        "draw_by_missing_qi", "summon_to_hand", "revive_discard", "copy_hand",
        "bounce_board", "transform_board", "qi_per_tian", "draw_group",
        "random_wealth_wager",
        "aura_tian_hp", "aura_enemy_di_atk", "aura_self_di_qi", "aura_wealth",
        "aura_upgrade_cost",
        # 每张卡都要有被动，原有的 5 条光环不够分，本次扩充的读取点（见 PlayerState._aura）：
        "aura_tian_atk", "aura_di_atk", "aura_start_shield", "aura_turn_draw",
        "aura_action_max", "aura_fa_gain", "aura_yuan_gain",
        # 本次新增
        "dice_damage", "dice_heal", "conquer_board", "summon_board_group",
        "board_bonus",
    }
    bad: list = []
    for c in cards:
        for slot, sk in c["skills"].items():
            if not sk:
                continue
            for e in sk.get("effects", []):
                if e.get("type", "") not in known:
                    bad.append("%s/%s/%s -> %s" % (c["name"], slot, sk.get("name"), e.get("type")))
    for ch in chars:
        sk = ch.get("skill", {})
        for e in sk.get("effects", []):
            if e.get("type", "") not in known:
                bad.append("chara/%s -> %s" % (ch["name"], e.get("type")))
    if bad:
        raise SystemExit("[FATAL] 未实现的效果类型：\n  " + "\n  ".join(bad))
    print("[check]      效果类型全部在白名单内 ✔")

    json.dump(cards, open(os.path.join(DATA, "cards.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    json.dump(chars, open(os.path.join(DATA, "characters.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    json.dump(ren, open(os.path.join(DATA, "ren_cards.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    json.dump(RULES, open(os.path.join(DATA, "rules.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    print("[cards]      %d" % len(cards))
    print("[characters] %d" % len(chars))
    print("[ren_cards]  %d" % len(ren))

    # 签名技能覆盖率
    sig_hit = sum(1 for c in cards if c["name"] in SIGNATURE)
    print("[signature]  %d 张卡拥有定制签名技能" % sig_hit)

    # ---- 技能体系自检 ----
    # ① 去同质化：用户原话「怎么所有人技能都是镇压什么的？所有卡牌技能都不相同。」
    # ② 阶数门控：非道具卡必有被动，技能位数量 == 阶数，道具卡不带技能。
    # 两条都是「静默失效型」缺陷 —— 数据看着没问题、跑起来也不报错，
    # 只有玩家在卡面上才能发现，所以必须在生成阶段就量出来。
    slot_names = {k: {} for k in ("on_play", "on_remove", "passive", "active")}
    tuples: dict = {}
    gating_bad: list = []
    item_bad: list = []
    passive_missing: list = []
    for c in cards:
        is_item = c.get("faction") == "道具"
        # 道具卡四个槽位恒空，把它们排除在「四元组互异」统计外，
        # 否则 8 张道具会挤成同一组空的四元组，把「重复 7 张」这种假警报打出来。
        if not is_item:
            key = []
            for k in ("on_play", "on_remove", "passive", "active"):
                sk = c["skills"].get(k)
                nm = sk.get("name", "") if sk else ""
                slot_names[k][nm] = slot_names[k].get(nm, 0) + 1
                key.append(nm)
            tuples[tuple(key)] = tuples.get(tuple(key), 0) + 1
        if is_item:
            for k in ("on_play", "on_remove", "passive", "active"):
                if c["skills"].get(k):
                    item_bad.append("%s/%s" % (c["name"], k))
            continue
        if not c["skills"].get("passive"):
            passive_missing.append(c["name"])
        cnt = sum(1 for k in ("on_play", "on_remove", "active") if c["skills"].get(k))
        if cnt != int(c["tier"]):
            gating_bad.append("%s(%d阶→%d个)" % (c["name"], c["tier"], cnt))

    non_item_n = sum(1 for c in cards if c.get("faction") != "道具")
    print("[variety]    非道具卡 %d 张 ｜ 四元组互异 %d 组（最多一组 %d 张）"
          % (non_item_n, len(tuples), max(tuples.values())))
    for k, cnt in slot_names.items():
        # 空名 = 「这张卡没有该技能位」，不算技能名，统计时剔除
        real = {n: v for n, v in cnt.items() if n}
        top = sorted(real.items(), key=lambda kv: -kv[1])[:3]
        print("   %-10s 有该技能位 %3d 张 ｜ 不同技能名 %3d 个 ｜ 最高频 %s"
              % (k, sum(real.values()), len(real),
                 "、".join("%s×%d" % (n, v) for n, v in top)))
    dup_cards = non_item_n - len(tuples)
    if dup_cards:
        print("   ⚠ 仍有 %d 张非道具卡与他人四元组相同" % dup_cards)

    # 阶数门控汇总（按阶数分布打印，一眼看强度曲线）
    by_tier: dict = {}
    for c in cards:
        if c.get("faction") == "道具":
            continue
        by_tier.setdefault(int(c["tier"]), []).append(c)
    for t in sorted(by_tier):
        print("   %d 阶：%3d 张" % (t, len(by_tier[t])))
    print("[gating]     非道具卡缺被动 %d 张 ｜ 技能位≠阶数 %d 张 ｜ 道具卡带技能 %d 处"
          % (len(passive_missing), len(gating_bad), len(item_bad)))
    if passive_missing:
        raise SystemExit("[FATAL] 以下卡牌没有被动：\n  " + "、".join(passive_missing[:20]))
    if gating_bad:
        raise SystemExit("[FATAL] 以下卡牌技能位数量与阶数不符：\n  " + "、".join(gating_bad[:20]))
    if item_bad:
        raise SystemExit("[FATAL] 以下道具卡带着不该有的技能：\n  " + "、".join(item_bad[:20]))
    print("[check]      阶数门控 / 道具无技能 全部通过 ✔")

    # 立绘完整性校验：任何一条没有 art 都直接报错退出。
    # 「静默生成一条没有立绘的数据」比「生成失败」更难排查 —— 大厅里只会看到一个黑格子。
    missing = []
    for grp, items in (("characters", chars), ("ren_cards", ren)):
        for it in items:
            if not it.get("art"):
                missing.append("%s/%s" % (grp, it.get("name")))
    if missing:
        raise SystemExit("[FATAL] 以下条目缺少立绘，请在 ART_ALIAS 中补充别名或检查源图目录：\n  "
                         + "\n  ".join(missing))
    print("[check]      所有角色/人卡立绘均已匹配 ✔")


if __name__ == "__main__":
    main()
