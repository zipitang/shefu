# -*- coding: utf-8 -*-
"""
《摄伏》卡牌技能主题库
================================================================================
设计目标（用户需求原文）：
  「在图鉴中（除了道具卡）所有卡牌不论阶数，都有自己的被动，然后就是 1 阶卡只有
    一个技能（要么上场，要么下场，要么主动），2 阶有两个技能，三阶卡牌就是三个技能，
    设计要有创意且符合原著以及强度适中，而且一些卡牌之间要可以做到相互搭配适配，
    技能这一块再详细对照每张卡牌名字对应，要好好设计，符合设定。」

--------------------------------------------------------------------------------
三条硬规则（由 build_cards.py 强制执行，SelfTest 回归）
--------------------------------------------------------------------------------
  R1  非道具卡一律拥有 passive；
  R2  非道具卡的技能位数量 == 卡牌阶数（1 阶 1 个 / 2 阶 2 个 / 3 阶 3 个），
      技能位取自 {on_play, on_remove, active}；
  R3  道具卡不携带任何技能（只有功能，见 ITEM_FUNCS）。

--------------------------------------------------------------------------------
为什么要「家族 + 法名」而不是给 227 张卡各写一遍
--------------------------------------------------------------------------------
  纯手写 227 套 × 4 槽 = 900 多条技能，维护和复现都会失控；
  纯按 sub 分派又会退回上一轮被骂的「所有人技能都是镇压」。
  折中方案：
    · FAMILY  —— 把卡按**神话谱系**归族（护法金刚 / 四大天王 / 五岳大帝 / 龙生九子 …），
                  同族共享设计空间（这才是「符合设定」的地方）；
    · EPITHET —— 每张卡从自己的名字里取出一个 2~4 字「法名」（鼓雷 / 金钟 / 时轮 …），
                  技能名 = 法名 + 家族词干，于是**技能名天然与该卡对应且全卡池不重复**；
    · 每个槽位给 2~4 个效果变体，由卡牌 id 的 crc32 确定性选取 ——
      同族两张卡的技能名不同、机制也不完全相同。

--------------------------------------------------------------------------------
强度基准（「强度适中」的落点）
--------------------------------------------------------------------------------
  被动   ：1~2 点小收益，每回合都吃，是卡的身份。
  上场技 ：一次性、1~3 点量级。
  下场技 ：被拔除时的补偿，一般 1~2 点量级。
  主动技 ：消耗「主动行动」额度 + 冷却 2~4 回合，2~4 点量级。
  阶数越高 → 技能**数量**越多（R2），而不是单个技能数值翻倍。
  因此本文件里所有数值都写**绝对值**，技能上标 absolute=True，
  不会被 _apply_tier_scaling 追加 per_tier 放大（否则 3 阶卡会同时吃
  「多两个技能」和「每个技能翻倍」两份收益，直接超模）。

--------------------------------------------------------------------------------
【铁律】效果类型必须落在 EffectRunner.gd 的 match 分支内；
        被动槽只能放 PlayerState 认识的 aura_*（见其 _aura 读取点），
        写错类型不会报错，只会静默失效 —— 数据里写着、卡面画着、实战没反应。
================================================================================
"""

# =============================================================================
# 一、家族 → 四槽技能模板
#    槽位条目格式： ("技能名模板", "描述", [effects...])
#    技能名模板里的 {e} 会被替换成该卡的法名。
#    描述里的 {v0}/{v1} 按 effects 数组下标替换成实际数值（务必与数组对齐）。
# =============================================================================
FAMILIES = {

    # ------------------------------------------------------------------ 天 / 佛
    # 忿怒相：明王 / 护法战神 —— 以「降魔」为轴，能拔除、能压制
    "忿怒": {
        "passive": [
            ("{e}怒目", "敌方【地】袭向你的【人】时，气伤 -1（多张不叠加）。",
             [{"type": "aura_enemy_di_atk", "value": 1}]),
            ("{e}威光", "己方场上所有【天】的攻击 +1。",
             [{"type": "aura_tian_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}伏魔", "上场时，对对方场上生命最低的【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}]),
            ("{e}镇邪", "上场时，对对方【人】造成 1 点【气】伤害，并抽 1 张牌。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 1},
              {"type": "draw", "target": "self", "value": 1}]),
        ],
        "on_remove": [
            ("{e}遗威", "被拔除时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}不灭", "被拔除时，己方【人】获得 2 点护盾【气】。",
             [{"type": "shield_qi", "value": 2}]),
        ],
        "active": [
            ("{e}焚魔", "冷却 3 回合。对所有对方【地】单位造成 1 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 1}], 3),
            ("{e}断罪", "冷却 3 回合。对对方场上生命最低的单位造成 3 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 3}], 3),
        ],
    },

    # 慈悲相：菩萨 / 佛陀 —— 回气、护盾、复活，是「天」阵营的续航核心
    "慈悲": {
        "passive": [
            ("{e}悲愿", "己方回合开始时，己方【人】获得 1 点护盾【气】。",
             [{"type": "aura_start_shield", "value": 1}]),
            ("{e}福田", "每回合【财】结算 +1 点。",
             [{"type": "aura_wealth", "value": 1}]),
        ],
        "on_play": [
            ("{e}普度", "上场时，己方【人】恢复 3 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 3}]),
            ("{e}垂护", "上场时，己方【人】获得 3 点护盾【气】。",
             [{"type": "shield_qi", "value": 3}]),
        ],
        "on_remove": [
            ("{e}余荫", "被拔除时，己方【人】恢复 2 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 2}]),
            ("{e}舍身", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
        ],
        "active": [
            ("{e}甘露", "冷却 3 回合。己方【人】恢复 4 点【气】并抽 1 张牌。",
             [{"type": "heal_qi", "target": "self_ren", "value": 4},
              {"type": "draw", "target": "self", "value": 1}], 3),
            ("{e}莲台", "冷却 3 回合。己方场上所有单位恢复 2 点生命。",
             [{"type": "heal_board_all", "side": "self", "value": 2}], 3),
        ],
    },

    # 福德：吉祥天母 / 大黑天 —— 财与资源机器，和「财」体系天然搭配
    "福德": {
        "passive": [
            ("{e}聚宝", "每回合【财】结算 +2 点。",
             [{"type": "aura_wealth", "value": 2}]),
            ("{e}施财", "己方回合开始时额外获得 1 点【法】。",
             [{"type": "aura_fa_gain", "value": 1}]),
        ],
        "on_play": [
            ("{e}献瑞", "上场时，获得 3 点【财】。",
             [{"type": "gain_res", "res": "wealth", "value": 3}]),
            ("{e}开库", "上场时，抽 2 张牌。",
             [{"type": "draw", "target": "self", "value": 2}]),
        ],
        "on_remove": [
            ("{e}遗财", "被拔除时，获得 2 点【财】。",
             [{"type": "gain_res", "res": "wealth", "value": 2}]),
        ],
        "active": [
            ("{e}广济", "冷却 3 回合。获得 5 点【财】并抽 1 张牌。",
             [{"type": "gain_res", "res": "wealth", "value": 5},
              {"type": "draw", "target": "self", "value": 1}], 3),
        ],
    },

    # 金翅：迦楼罗 —— 专食龙蛇，斩首型
    "金翅": {
        "passive": [
            ("{e}锐目", "己方场上所有【天】的攻击 +1。",
             [{"type": "aura_tian_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}搏龙", "上场时，对对方场上生命最低的【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}]),
        ],
        "on_remove": [
            ("{e}振羽", "被拔除时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
        ],
        "active": [
            ("{e}噬魂", "冷却 3 回合。拔除对方场上 1 张生命不超过 2 的单位。",
             [{"type": "execute_board", "side": "enemy", "hp_limit": 2}], 3),
        ],
    },

    # 护法金刚（17 张）—— 门神型肉盾，护人 + 攒羁绊
    "护法": {
        "passive": [
            ("{e}镇守", "己方场上所有【天】的【祇】+1。",
             [{"type": "aura_tian_hp", "value": 1}]),
            ("{e}护身", "敌方【地】袭向你的【人】时，气伤 -1（多张不叠加）。",
             [{"type": "aura_enemy_di_atk", "value": 1}]),
            ("{e}无相", "己方回合开始时，己方【人】获得 1 点护盾【气】。",
             [{"type": "aura_start_shield", "value": 1}]),
            ("{e}肃杀", "己方场上所有【天】的攻击 +1。",
             [{"type": "aura_tian_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}结阵", "上场时，己方【人】获得 3 点护盾【气】。",
             [{"type": "shield_qi", "value": 3}]),
            ("{e}点卯", "上场时，获得 1 张【护法金刚】入手。",
             [{"type": "grant_card_tag", "tag": "护法金刚", "value": 1}]),
            ("{e}降魔", "上场时，对对方场上生命最低的【地】单位造成 1 点伤害，并抽 1 张牌。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 1},
              {"type": "draw", "target": "self", "value": 1}]),
        ],
        "on_remove": [
            ("{e}不坏", "被拔除时，己方【人】获得 2 点护盾【气】。",
             [{"type": "shield_qi", "value": 2}]),
            ("{e}余威", "被拔除时，己方【人】恢复 2 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 2}]),
            ("{e}遗志", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
        ],
        "active": [
            ("{e}铁壁", "冷却 3 回合。己方【人】获得 4 点护盾【气】。",
             [{"type": "shield_qi", "value": 4}], 3),
            ("{e}伏魔阵", "冷却 3 回合。对所有对方【地】单位造成 1 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 1}], 3),
            ("{e}铸身", "冷却 3 回合。本牌自身 +2 生命。",
             [{"type": "buff_self_hp", "value": 2}], 3),
        ],
    },

    # 十二生肖（12 张）—— 各具物性，靠法名区分（子鼠 / 寅虎 / 辰龙 …）
    "生肖": {
        "passive": [
            ("{e}天时", "己方场上所有【天】的【祇】+1。",
             [{"type": "aura_tian_hp", "value": 1}]),
            ("{e}地利", "每回合【财】结算 +1 点。",
             [{"type": "aura_wealth", "value": 1}]),
            ("{e}人和", "每回合额外获得 1 次「主动行动」。",
             [{"type": "aura_action_max", "value": 1}]),
            ("{e}灵机", "己方回合开始时额外抽 1 张牌。",
             [{"type": "aura_turn_draw", "value": 1}]),
        ],
        "on_play": [
            ("{e}呈祥", "上场时，抽 1 张牌，并随机获得 1 张【十二生肖】入手。",
             [{"type": "draw", "target": "self", "value": 1},
              {"type": "summon_to_hand", "group": "十二生肖", "value": 1}]),
            ("{e}守岁", "上场时，获得 2 点【财】。",
             [{"type": "gain_res", "res": "wealth", "value": 2}]),
            ("{e}报晓", "上场时，己方【人】恢复 2 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 2}]),
        ],
        "on_remove": [
            ("{e}归位", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
            ("{e}反噬", "被拔除时，对对方【人】造成 1 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 1}]),
            ("{e}余泽", "被拔除时，己方【人】恢复 2 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 2}]),
        ],
        "active": [
            ("{e}奋蹄", "冷却 2 回合。对对方场上生命最低的单位造成 2 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 2}], 2),
            ("{e}定身", "冷却 3 回合。封锁对方场上所有【地】单位 1 回合。",
             [{"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1}], 3),
            ("{e}养元", "冷却 3 回合。本牌自身 +2 生命。",
             [{"type": "buff_self_hp", "value": 2}], 3),
        ],
    },

    # 四相（朱雀 / 玄武 / 白虎 / 青龙）—— 3 阶天花板单位
    "四相": {
        "passive": [
            ("{e}天威", "己方场上所有【天】的【祇】+2。",
             [{"type": "aura_tian_hp", "value": 2}]),
            ("{e}罡气", "己方场上所有【天】的攻击 +1。",
             [{"type": "aura_tian_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}镇四野", "上场时，对所有对方【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}]),
            ("{e}开泰", "上场时，己方【人】获得 4 点护盾【气】。",
             [{"type": "shield_qi", "value": 4}]),
            ("{e}司春", "上场时，己方场上所有单位恢复 2 点生命，并抽 1 张牌。",
             [{"type": "heal_board_all", "side": "self", "value": 2},
              {"type": "draw", "target": "self", "value": 1}]),
        ],
        "on_remove": [
            ("{e}余烈", "被拔除时，己方所有【天】单位 +1【祇】，并对对方【人】造成 3 点【气】伤害。",
             [{"type": "buff_tian_hp_all", "value": 1},
              {"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
        ],
        "active": [
            ("{e}天罚", "冷却 3 回合。对所有对方【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}], 3),
            ("{e}相争", "冷却 3 回合。令对方场上最前的两张单位互相攻击。",
             [{"type": "clash_enemy_board", "value": 2}], 3),
        ],
    },

    # 五岳大帝 —— 镇守型，厚、稳、能封
    "岳镇": {
        "passive": [
            ("{e}岳峙", "己方场上所有【天】的【祇】+1。",
             [{"type": "aura_tian_hp", "value": 1}]),
            ("{e}山镇", "己方回合开始时，己方【人】获得 1 点护盾【气】。",
             [{"type": "aura_start_shield", "value": 1}]),
        ],
        "on_play": [
            ("{e}封禅", "上场时，己方【人】获得 3 点护盾【气】。",
             [{"type": "shield_qi", "value": 3}]),
            ("{e}安岳", "上场时，本牌自身 +2 生命。",
             [{"type": "buff_self_hp", "value": 2}]),
        ],
        "on_remove": [
            ("{e}岳倾", "被拔除时，己方【人】恢复 3 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 3}]),
        ],
        "active": [
            ("{e}镇岳", "冷却 3 回合。封锁对方场上所有单位 1 回合。",
             [{"type": "freeze_board", "side": "enemy", "turns": 1}], 3),
            ("{e}崩山", "冷却 2 回合。对对方场上生命最低的单位造成 2 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 2}], 2),
        ],
    },

    # 五德星君 —— 资源型，与「法 / 源」体系搭配
    "星君": {
        "passive": [
            ("{e}星辉", "己方回合开始时额外获得 1 点【法】。",
             [{"type": "aura_fa_gain", "value": 1}]),
            ("{e}曜灵", "己方回合开始时额外获得 1 点【源】。",
             [{"type": "aura_yuan_gain", "value": 1}]),
            ("{e}列宿", "己方场上所有【天】的【祇】+1。",
             [{"type": "aura_tian_hp", "value": 1}]),
        ],
        "on_play": [
            ("{e}曜世", "上场时，获得 2 点【法】并抽 1 张牌。",
             [{"type": "gain_res", "res": "fa", "value": 2},
              {"type": "draw", "target": "self", "value": 1}]),
            ("{e}垂象", "上场时，获得 2 点【源】并抽 1 张牌。",
             [{"type": "gain_res", "res": "yuan", "value": 2},
              {"type": "draw", "target": "self", "value": 1}]),
        ],
        "on_remove": [
            ("{e}陨曜", "被拔除时，获得 1 点【法】与 1 点【源】。",
             [{"type": "gain_res", "res": "fa", "value": 1},
              {"type": "gain_res", "res": "yuan", "value": 1}]),
        ],
        "active": [
            ("{e}星陨", "冷却 2 回合。对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}], 2),
            ("{e}斗转", "冷却 3 回合。掷骰定伤，对对方【人】造成 1~6 点【气】伤害。",
             [{"type": "dice_damage", "max": 6}], 3),
        ],
    },

    # 四大天王（增长 / 多闻 / 广目 / 持国）—— 各执法器，护世
    "天王": {
        "passive": [
            ("{e}护世", "己方场上所有【天】的【祇】+1。",
             [{"type": "aura_tian_hp", "value": 1}]),
            ("{e}执器", "己方场上所有【天】的攻击 +1。",
             [{"type": "aura_tian_atk", "value": 1}]),
            ("{e}镇方", "己方回合开始时，己方【人】获得 1 点护盾【气】。",
             [{"type": "aura_start_shield", "value": 1}]),
            ("{e}护民", "敌方【地】袭向你的【人】时，气伤 -1（多张不叠加）。",
             [{"type": "aura_enemy_di_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}巡视", "上场时，己方【人】获得 3 点护盾【气】。",
             [{"type": "shield_qi", "value": 3}]),
            ("{e}降伏", "上场时，对对方场上生命最低的【地】单位造成 1 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 1}]),
            ("{e}赐福", "上场时，获得 2 点【财】并抽 1 张牌。",
             [{"type": "gain_res", "res": "wealth", "value": 2},
              {"type": "draw", "target": "self", "value": 1}]),
            ("{e}辨察", "上场时，抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
        ],
        "on_remove": [
            ("{e}归位", "被拔除时，己方【人】获得 2 点护盾【气】。",
             [{"type": "shield_qi", "value": 2}]),
            ("{e}余威", "被拔除时，己方【人】恢复 2 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 2}]),
        ],
        "active": [
            ("{e}镇界", "冷却 3 回合。对所有对方【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}], 3),
            ("{e}定身", "冷却 3 回合。封锁对方场上所有【地】单位 1 回合。",
             [{"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1}], 3),
        ],
    },

    # 天尊（15 张天王组）—— 高阶雷部/护法，输出为轴
    "天尊": {
        "passive": [
            ("{e}天威", "己方场上所有【天】的攻击 +1。",
             [{"type": "aura_tian_atk", "value": 1}]),
            ("{e}神威", "己方场上所有【天】的【祇】+1。",
             [{"type": "aura_tian_hp", "value": 1}]),
            ("{e}疾行", "每回合额外获得 1 次「主动行动」。",
             [{"type": "aura_action_max", "value": 1}]),
            ("{e}开阵", "己方回合开始时额外抽 1 张牌。",
             [{"type": "aura_turn_draw", "value": 1}]),
        ],
        "on_play": [
            ("{e}荡魔", "上场时，对所有对方【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}]),
            ("{e}雷罚", "上场时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}布阵", "上场时，抽 1 张牌并己方【人】获得 2 点护盾【气】。",
             [{"type": "draw", "target": "self", "value": 1},
              {"type": "shield_qi", "value": 2}]),
        ],
        "on_remove": [
            ("{e}雷殛", "被拔除时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}遗法", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
            ("{e}余烬", "被拔除时，对对方场上随机单位造成 2 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 2, "count": 1}]),
        ],
        "active": [
            ("{e}天雷", "冷却 3 回合。对所有对方【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}], 3),
            ("{e}斩罪", "冷却 3 回合。对对方场上生命最低的单位造成 3 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 3}], 3),
            ("{e}禁法", "冷却 3 回合。封锁对方场上所有单位 1 回合。",
             [{"type": "freeze_board", "side": "enemy", "turns": 1}], 3),
        ],
    },

    # 五火真君 —— 纯火，全场灼烧
    "火部": {
        "passive": [
            ("{e}炎上", "己方场上所有【天】的攻击 +2。",
             [{"type": "aura_tian_atk", "value": 2}]),
            ("{e}炽烈", "己方场上所有【地】的攻击 +1。",
             [{"type": "aura_di_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}焚野", "上场时，对所有对方【地】单位造成 3 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 3}]),
        ],
        "on_remove": [
            ("{e}爆燃", "被拔除时，对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
        ],
        "active": [
            ("{e}燎原", "冷却 4 回合。对所有对方【地】单位造成 3 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 3}], 4),
        ],
    },

    # 星宿（亢金龙 / 奎木狼 / 星宫二十八宿）—— 抽牌与铺场
    "星宿": {
        "passive": [
            ("{e}列曜", "己方回合开始时额外抽 1 张牌。",
             [{"type": "aura_turn_draw", "value": 1}]),
            ("{e}周天", "己方场上所有【天】的【祇】+1。",
             [{"type": "aura_tian_hp", "value": 1}]),
        ],
        "on_play": [
            ("{e}星聚", "上场时，抽 2 张牌。",
             [{"type": "draw", "target": "self", "value": 2}]),
            ("{e}应宿", "上场时，随机获得 2 张【十二生肖】入手。",
             [{"type": "summon_to_hand", "group": "十二生肖", "value": 2}]),
        ],
        "on_remove": [
            ("{e}星散", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
        ],
        "active": [
            ("{e}星雨", "冷却 2 回合。对所有对方【地】单位造成 1 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 1}], 2),
        ],
    },

    # 神天大照（大天狗 / 月读 / 玉藻前 / 素盏鸣尊 / 迦具土）—— 单体高压
    "日轮": {
        "passive": [
            ("{e}威仪", "己方场上所有【天】的攻击 +1。",
             [{"type": "aura_tian_atk", "value": 1}]),
            ("{e}妖力", "己方场上所有【地】的攻击 +1。",
             [{"type": "aura_di_atk", "value": 1}]),
            ("{e}神速", "每回合额外获得 1 次「主动行动」。",
             [{"type": "aura_action_max", "value": 1}]),
        ],
        "on_play": [
            ("{e}显形", "上场时，对对方场上生命最低的单位造成 2 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 2}]),
            ("{e}惑心", "上场时，对对方场上随机单位造成 2 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 2, "count": 1}]),
        ],
        "on_remove": [
            ("{e}反噬", "被拔除时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}留影", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
        ],
        "active": [
            ("{e}秘术", "冷却 2 回合。对对方场上生命最低的单位造成 3 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 3}], 2),
            ("{e}遁天", "冷却 4 回合。将对方场上 1 张 2 阶及以下的卡弹回其手牌。",
             [{"type": "bounce_board", "side": "enemy", "value": 1, "tier_limit": 2}], 4),
        ],
    },

    # 门神（尉迟恭 / 秦琼）—— 最纯粹的护人
    "门神": {
        "passive": [
            ("{e}守户", "敌方【地】袭向你的【人】时，气伤 -1（多张不叠加）。",
             [{"type": "aura_enemy_di_atk", "value": 1}]),
            ("{e}镇宅", "己方回合开始时，己方【人】获得 1 点护盾【气】。",
             [{"type": "aura_start_shield", "value": 1}]),
        ],
        "on_play": [
            ("{e}挡门", "上场时，己方【人】获得 3 点护盾【气】。",
             [{"type": "shield_qi", "value": 3}]),
        ],
        "on_remove": [
            ("{e}不倒", "被拔除时，己方【人】获得 2 点护盾【气】。",
             [{"type": "shield_qi", "value": 2}]),
        ],
        "active": [
            ("{e}拒敌", "冷却 3 回合。封锁对方场上所有【地】单位 1 回合。",
             [{"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1}], 3),
        ],
    },

    # 黑白无常 / 孟婆 / 钟馗 —— 勾魂夺魄，手牌干扰 + 处决
    "幽冥": {
        "passive": [
            ("{e}阴气", "敌方【地】袭向你的【人】时，气伤 -1（多张不叠加）。",
             [{"type": "aura_enemy_di_atk", "value": 1}]),
            ("{e}香火", "每回合【财】结算 +1 点。",
             [{"type": "aura_wealth", "value": 1}]),
        ],
        "on_play": [
            ("{e}勾魂", "上场时，令对方随机弃 1 张手牌。",
             [{"type": "discard_enemy", "value": 1}]),
            ("{e}锁魄", "上场时，封锁对方 1 张手牌 1 回合。",
             [{"type": "seal_hand_card", "side": "enemy", "value": 1, "turns": 1}]),
        ],
        "on_remove": [
            ("{e}索命", "被拔除时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}引渡", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
        ],
        "active": [
            ("{e}判死", "冷却 3 回合。拔除对方场上 1 张生命不超过 2 的单位。",
             [{"type": "execute_board", "side": "enemy", "hp_limit": 2}], 3),
            ("{e}收魂", "冷却 3 回合。拔除对方场上 1 张【地】单位。",
             [{"type": "destroy_di"}], 3),
        ],
    },

    # 齐名百圣（36 张）—— 人神/自然神/英雄神的大杂院，靠法名与变体拉开
    "百圣": {
        "passive": [
            ("{e}圣德", "每回合【财】结算 +1 点。",
             [{"type": "aura_wealth", "value": 1}]),
            ("{e}灵应", "己方回合开始时额外获得 1 点【法】。",
             [{"type": "aura_fa_gain", "value": 1}]),
            ("{e}神恩", "己方回合开始时额外获得 1 点【源】。",
             [{"type": "aura_yuan_gain", "value": 1}]),
            ("{e}庇护", "己方场上所有【天】的【祇】+1。",
             [{"type": "aura_tian_hp", "value": 1}]),
            ("{e}显圣", "己方场上所有【天】的攻击 +1。",
             [{"type": "aura_tian_atk", "value": 1}]),
            ("{e}庇佑", "己方回合开始时，己方【人】获得 1 点护盾【气】。",
             [{"type": "aura_start_shield", "value": 1}]),
            ("{e}香火", "每回合额外获得 1 次「主动行动」。",
             [{"type": "aura_action_max", "value": 1}]),
            ("{e}垂听", "己方回合开始时额外抽 1 张牌。",
             [{"type": "aura_turn_draw", "value": 1}]),
            ("{e}地脉", "己方场上所有【地】的对【人】气伤 +1。",
             [{"type": "aura_self_di_qi", "value": 1}]),
            ("{e}济民", "升级【人】的消耗 -1（多张叠加）。",
             [{"type": "aura_upgrade_cost", "value": 1}]),
        ],
        "on_play": [
            ("{e}显灵", "上场时，抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
            ("{e}赐福", "上场时，获得 2 点【财】。",
             [{"type": "gain_res", "res": "wealth", "value": 2}]),
            ("{e}施法", "上场时，获得 2 点【法】。",
             [{"type": "gain_res", "res": "fa", "value": 2}]),
            ("{e}布施", "上场时，获得 2 点【源】。",
             [{"type": "gain_res", "res": "yuan", "value": 2}]),
            ("{e}降妖", "上场时，对对方场上生命最低的【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}]),
            ("{e}惩恶", "上场时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}安民", "上场时，己方【人】恢复 2 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 2}]),
            ("{e}结庐", "上场时，己方【人】获得 2 点护盾【气】。",
             [{"type": "shield_qi", "value": 2}]),
        ],
        "on_remove": [
            ("{e}遗泽", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
            ("{e}余恩", "被拔除时，己方【人】恢复 2 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 2}]),
            ("{e}荫庇", "被拔除时，己方【人】获得 2 点护盾【气】。",
             [{"type": "shield_qi", "value": 2}]),
            ("{e}报复", "被拔除时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}遗物", "被拔除时，返还 1 张 1 阶材料牌。",
             [{"type": "gain_material", "value": 1}]),
            ("{e}留福", "被拔除时，获得 2 点【财】。",
             [{"type": "gain_res", "res": "wealth", "value": 2}]),
            ("{e}余温", "被拔除时，对对方场上随机单位造成 2 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 2, "count": 1}]),
        ],
        "active": [
            ("{e}神迹", "冷却 2 回合。对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}], 2),
            ("{e}诛邪", "冷却 3 回合。对对方场上生命最低的单位造成 3 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 3}], 3),
            ("{e}庇佑众生", "冷却 3 回合。己方【人】恢复 4 点【气】。",
             [{"type": "heal_qi", "target": "self_ren", "value": 4}], 3),
            ("{e}通神", "冷却 3 回合。抽 2 张牌。",
             [{"type": "draw", "target": "self", "value": 2}], 3),
            ("{e}定乾坤", "冷却 3 回合。封锁对方场上所有单位 1 回合。",
             [{"type": "freeze_board", "side": "enemy", "turns": 1}], 3),
            ("{e}铸灵", "冷却 3 回合。本牌自身 +3 生命。",
             [{"type": "buff_self_hp", "value": 3}], 3),
        ],
    },

    # 夜游神 —— 潜行侦察，手牌干扰
    "夜游": {
        "passive": [
            ("{e}夜行", "每回合额外获得 1 次「主动行动」。",
             [{"type": "aura_action_max", "value": 1}]),
            ("{e}潜踪", "己方回合开始时额外抽 1 张牌。",
             [{"type": "aura_turn_draw", "value": 1}]),
        ],
        "on_play": [
            ("{e}窥视", "上场时，抽 2 张牌。",
             [{"type": "draw", "target": "self", "value": 2}]),
            ("{e}隐身", "上场时，己方手牌信息隐藏 1 回合。",
             [{"type": "fog_hand", "turns": 1}]),
        ],
        "on_remove": [
            ("{e}遁走", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
        ],
        "active": [
            ("{e}窃符", "冷却 3 回合。从对方手中夺取 1 张牌。",
             [{"type": "steal_hand", "value": 1}], 3),
            ("{e}封符", "冷却 3 回合。封锁对方 2 张手牌 1 回合。",
             [{"type": "seal_hand_card", "side": "enemy", "value": 2, "turns": 1}], 3),
        ],
    },

    # 龙（金龙 / 黄龙）
    "龙": {
        "passive": [
            ("{e}龙威", "己方场上所有【天】的【祇】+2。",
             [{"type": "aura_tian_hp", "value": 2}]),
            ("{e}龙气", "己方场上所有【天】的攻击 +1。",
             [{"type": "aura_tian_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}腾云", "上场时，对所有对方【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}]),
        ],
        "on_remove": [
            ("{e}龙吟", "被拔除时，己方所有【天】+1【祇】，并对对方【人】造成 2 点【气】伤害。",
             [{"type": "buff_tian_hp_all", "value": 1},
              {"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
        ],
        "active": [
            ("{e}布雨", "冷却 3 回合。对所有对方【地】单位造成 3 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 3}], 3),
        ],
    },

    # ------------------------------------------------------------------ 地
    # 异兽（龙生九子 + 四凶）—— 强身、夺牌、压制
    "异兽": {
        "passive": [
            ("{e}兽性", "己方场上所有【地】的攻击 +1。",
             [{"type": "aura_di_atk", "value": 1}]),
            ("{e}妖气", "己方场上所有【地】的对【人】气伤 +1。",
             [{"type": "aura_self_di_qi", "value": 1}]),
            ("{e}贪饕", "每回合【财】结算 +1 点。",
             [{"type": "aura_wealth", "value": 1}]),
            ("{e}凶顽", "己方场上所有【天】的【祇】+1。",
             [{"type": "aura_tian_hp", "value": 1}]),
        ],
        "on_play": [
            ("{e}扑咬", "上场时，对对方场上生命最低的单位造成 2 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 2}]),
            ("{e}撕扯", "上场时，对对方场上随机单位造成 2 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 2, "count": 1}]),
            ("{e}吞噬", "上场时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}掳掠", "上场时，掠夺对方 2 点【财】。",
             [{"type": "steal_res", "res": "wealth", "value": 2}]),
        ],
        "on_remove": [
            ("{e}凶煞", "被拔除时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}尸骸", "被拔除时，返还 1 张 1 阶材料牌。",
             [{"type": "gain_material", "value": 1}]),
            ("{e}兽血", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
        ],
        "active": [
            ("{e}扑杀", "冷却 2 回合。对对方场上生命最低的单位造成 2 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 2}], 2),
            ("{e}狂噬", "冷却 3 回合。对对方场上随机单位造成 3 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 3, "count": 1}], 3),
            ("{e}夺舍", "冷却 4 回合。将对方场上 1 张 2 阶及以下的卡据为己有。",
             [{"type": "conquer_board", "tier_limit": 2}], 4),
        ],
    },

    # 妖（24 张）—— 阴柔、控制、偷取
    "妖异": {
        "passive": [
            ("{e}妖气", "己方场上所有【地】的攻击 +1。",
             [{"type": "aura_di_atk", "value": 1}]),
            ("{e}媚惑", "己方场上所有【地】的对【人】气伤 +1。",
             [{"type": "aura_self_di_qi", "value": 1}]),
            ("{e}狡黠", "每回合额外获得 1 次「主动行动」。",
             [{"type": "aura_action_max", "value": 1}]),
        ],
        "on_play": [
            ("{e}惑心", "上场时，对对方场上随机单位造成 2 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 2, "count": 1}]),
            ("{e}偷袭", "上场时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}缠足", "上场时，封锁对方场上所有【地】单位 1 回合。",
             [{"type": "freeze_board", "side": "enemy", "filter": "地", "turns": 1}]),
            ("{e}窃财", "上场时，掠夺对方 2 点【财】。",
             [{"type": "steal_res", "res": "wealth", "value": 2}]),
        ],
        "on_remove": [
            ("{e}怨念", "被拔除时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}蜕壳", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
            ("{e}遗毒", "被拔除时，令对方随机弃 1 张手牌。",
             [{"type": "discard_enemy", "value": 1}]),
        ],
        "active": [
            ("{e}噬心", "冷却 2 回合。对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}], 2),
            ("{e}乱神", "冷却 3 回合。对对方场上随机单位造成 3 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 3, "count": 1}], 3),
            ("{e}遣返", "冷却 4 回合。将对方场上 1 张 2 阶及以下的卡弹回其手牌。",
             [{"type": "bounce_board", "side": "enemy", "value": 1, "tier_limit": 2}], 4),
        ],
    },

    # 鬼（20 张）—— 索命、处决、同归于尽
    "鬼魅": {
        "passive": [
            ("{e}阴煞", "己方场上所有【地】的攻击 +1。",
             [{"type": "aura_di_atk", "value": 1}]),
            ("{e}戾气", "己方场上所有【地】的对【人】气伤 +1。",
             [{"type": "aura_self_di_qi", "value": 1}]),
            ("{e}鬼哭", "敌方【地】袭向你的【人】时，气伤 -1（多张不叠加）。",
             [{"type": "aura_enemy_di_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}索魂", "上场时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}摄魄", "上场时，封锁对方 1 张手牌 1 回合。",
             [{"type": "seal_hand_card", "side": "enemy", "value": 1, "turns": 1}]),
            ("{e}索命", "上场时，令对方随机弃 1 张手牌。",
             [{"type": "discard_enemy", "value": 1}]),
            ("{e}阴噬", "上场时，对对方场上随机单位造成 2 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 2, "count": 1}]),
        ],
        "on_remove": [
            ("{e}怨噬", "被拔除时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
            ("{e}阴魂", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
            ("{e}遗恨", "被拔除时，对对方场上生命最低的单位造成 1 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 1}]),
        ],
        "active": [
            ("{e}勾魂", "冷却 2 回合。对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}], 2),
            ("{e}夺命", "冷却 3 回合。拔除对方场上 1 张生命不超过 2 的单位。",
             [{"type": "execute_board", "side": "enemy", "hp_limit": 2}], 3),
            ("{e}祭鬼", "冷却 3 回合。牺牲己方场上 1 张单位，对对方【人】造成 3 点【气】伤害。",
             [{"type": "sacrifice_board", "side": "self"},
              {"type": "damage_qi", "target": "enemy_ren", "value": 3}], 3),
        ],
    },

    # 三尸（上尸彭踞 / 中尸彭蹻 / 中尸彭踬）—— 道家三尸，专攻心气
    "三尸": {
        "passive": [
            ("{e}蚀心", "己方场上所有【地】的对【人】气伤 +2。",
             [{"type": "aura_self_di_qi", "value": 2}]),
            ("{e}损体", "己方场上所有【地】的攻击 +1。",
             [{"type": "aura_di_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}诉事", "上场时，对对方【人】造成 2 点【气】伤害，并令其随机弃 1 张手牌。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2},
              {"type": "discard_enemy", "value": 1}]),
            ("{e}缠身", "上场时，对对方场上随机单位造成 2 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 2, "count": 1}]),
        ],
        "on_remove": [
            ("{e}尸变", "被拔除时，对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
        ],
        "active": [
            ("{e}蚀魄", "冷却 3 回合。对对方【人】造成 4 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 4}], 3),
        ],
    },

    # 五孽（妖孽 / 怪孽 / 精孽 / 鬼孽 / 魔孽）—— 3 阶精锐
    "五孽": {
        "passive": [
            ("{e}孽力", "己方场上所有【地】的攻击 +2。",
             [{"type": "aura_di_atk", "value": 2}]),
            ("{e}孽气", "己方场上所有【地】的对【人】气伤 +2。",
             [{"type": "aura_self_di_qi", "value": 2}]),
        ],
        "on_play": [
            ("{e}降灾", "上场时，对对方场上生命最低的单位造成 3 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 3}]),
            ("{e}作孽", "上场时，对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
        ],
        "on_remove": [
            ("{e}孽报", "被拔除时，对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
        ],
        "active": [
            ("{e}涂炭", "冷却 4 回合。对所有对方【地】单位造成 3 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 3}], 4),
        ],
    },

    # 五灾（回禄 / 无支祁 / 旱魃 / 疫鬼 / 蝗神）—— 天灾化身
    "五灾": {
        "passive": [
            ("{e}灾氛", "己方场上所有【地】的对【人】气伤 +2。",
             [{"type": "aura_self_di_qi", "value": 2}]),
            ("{e}祸延", "己方场上所有【地】的攻击 +1。",
             [{"type": "aura_di_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}降灾", "上场时，对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
            ("{e}殃及", "上场时，对对方场上随机单位造成 3 点伤害。",
             [{"type": "debuff_board", "side": "enemy", "value": 3, "count": 1}]),
        ],
        "on_remove": [
            ("{e}灾劫", "被拔除时，对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
        ],
        "active": [
            ("{e}天灾", "冷却 3 回合。对所有对方【地】单位造成 2 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 2}], 3),
        ],
    },

    # 五行尸（僵尸 / 木魁 / 水鬼 / 焚灭鬼 / 金煞鬼）—— 皮厚、能复活
    "五行尸": {
        "passive": [
            ("{e}尸气", "己方场上所有【地】的攻击 +1。",
             [{"type": "aura_di_atk", "value": 1}]),
            ("{e}不朽", "己方场上所有【地】的对【人】气伤 +1。",
             [{"type": "aura_self_di_qi", "value": 1}]),
        ],
        "on_play": [
            ("{e}凝尸", "上场时，本牌自身 +2 生命。",
             [{"type": "buff_self_hp", "value": 2}]),
            ("{e}噬生", "上场时，对对方【人】造成 2 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 2}]),
        ],
        "on_remove": [
            ("{e}还魂", "被拔除时，从弃置区回收 1 张牌回手牌。",
             [{"type": "revive_discard", "value": 1}]),
        ],
        "active": [
            ("{e}尸变", "冷却 3 回合。本牌自身 +3 生命。",
             [{"type": "buff_self_hp", "value": 3}], 3),
        ],
    },

    # 魑魅魍魉 —— 幻术、偷牌、迷雾
    "魑魅": {
        "passive": [
            ("{e}幻形", "每回合额外获得 1 次「主动行动」。",
             [{"type": "aura_action_max", "value": 1}]),
        ],
        "on_play": [
            ("{e}惑乱", "上场时，复制己方 1 张随机手牌。",
             [{"type": "copy_hand", "value": 1}]),
            ("{e}障目", "上场时，己方手牌信息隐藏 1 回合。",
             [{"type": "fog_hand", "turns": 1}]),
        ],
        "on_remove": [
            ("{e}幻灭", "被拔除时，己方抽 1 张牌。",
             [{"type": "draw", "target": "self", "value": 1}]),
        ],
        "active": [
            ("{e}夺形", "冷却 3 回合。从对方手中夺取 1 张牌。",
             [{"type": "steal_hand", "value": 1}], 3),
            ("{e}迷魂", "冷却 3 回合。封锁对方 2 张手牌 1 回合。",
             [{"type": "seal_hand_card", "side": "enemy", "value": 2, "turns": 1}], 3),
        ],
    },

    # 魔（8 张）—— 最高输出，自带代价
    "魔道": {
        "passive": [
            ("{e}魔威", "己方场上所有【地】的攻击 +2。",
             [{"type": "aura_di_atk", "value": 2}]),
            ("{e}魔力", "己方场上所有【地】的对【人】气伤 +2。",
             [{"type": "aura_self_di_qi", "value": 2}]),
            ("{e}贪欲", "每回合【财】结算 +2 点。",
             [{"type": "aura_wealth", "value": 2}]),
            ("{e}魔障", "敌方【地】袭向你的【人】时，气伤 -1（多张不叠加）。",
             [{"type": "aura_enemy_di_atk", "value": 1}]),
        ],
        "on_play": [
            ("{e}屠戮", "上场时，对对方场上生命最低的单位造成 3 点伤害。",
             [{"type": "damage_weakest", "side": "enemy", "value": 3}]),
            ("{e}献祭", "上场时，牺牲己方场上 1 张单位，对对方【人】造成 3 点【气】伤害。",
             [{"type": "sacrifice_board", "side": "self"},
              {"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
            ("{e}蚀魂", "上场时，对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
            ("{e}掠取", "上场时，掠夺对方 3 点【财】。",
             [{"type": "steal_res", "res": "wealth", "value": 3}]),
        ],
        "on_remove": [
            ("{e}魔息", "被拔除时，对对方【人】造成 3 点【气】伤害。",
             [{"type": "damage_qi", "target": "enemy_ren", "value": 3}]),
            ("{e}重生", "被拔除时，从弃置区回收 1 张牌回手牌，并抽 1 张牌。",
             [{"type": "revive_discard", "value": 1},
              {"type": "draw", "target": "self", "value": 1}]),
        ],
        "active": [
            ("{e}灭世", "冷却 4 回合。对所有对方【地】单位造成 3 点伤害。",
             [{"type": "damage_board_all", "side": "enemy", "filter": "地", "value": 3}], 4),
            ("{e}弑神", "冷却 4 回合。拔除对方场上 1 张生命不超过 3 的单位。",
             [{"type": "execute_board", "side": "enemy", "hp_limit": 3}], 4),
            ("{e}夺魄", "冷却 4 回合。将对方场上 1 张 2 阶及以下的卡据为己有。",
             [{"type": "conquer_board", "tier_limit": 2}], 4),
        ],
    },
}


# =============================================================================
# 二、卡名 → 家族
# =============================================================================
FAMILY = {
    # ---- 天 / 佛 ----
    "不动明王": "忿怒", "迦梨": "忿怒", "金刚亥母": "忿怒", "除魔童子": "忿怒", "斗战胜佛": "忿怒",
    "南无观世音菩萨": "慈悲", "地藏菩萨": "慈悲", "弥勒佛": "慈悲",
    "阿弥陀佛": "慈悲", "金蝉子": "慈悲",
    "吉祥天母": "福德", "大黑天": "福德",
    "迦楼罗": "金翅",
    # ---- 护法金刚 ----
    "三相神尊金刚": "护法", "九天威武金刚": "护法", "吓魔至尊金刚": "护法", "哼哈金刚": "护法",
    "善灭金刚": "护法", "圣甲猎鬼金刚": "护法", "时轮金刚": "护法", "法轮功德大吉金刚": "护法",
    "荡魔金刚": "护法", "西天护座金刚": "护法", "西天涤灵神威金刚": "护法", "赤法金刚": "护法",
    "辟邪杀魔金刚": "护法", "避魔天尊金刚": "护法", "金钟送法金刚": "护法", "铁面罗刹金刚": "护法",
    "鼓雷金刚": "护法",
    # ---- 十二生肖 ----
    "子鼠": "生肖", "丑牛": "生肖", "寅虎": "生肖", "卯兔": "生肖", "辰龙": "生肖", "巳蛇": "生肖",
    "午马": "生肖", "未羊": "生肖", "申猴": "生肖", "酉鸡": "生肖", "戌狗": "生肖", "亥猪": "生肖",
    # ---- 四相 ----
    "朱雀": "四相", "玄武": "四相", "白虎": "四相", "青龙": "四相",
    # ---- 五岳大帝 ----
    "东岳大帝": "岳镇", "南岳大帝": "岳镇", "西岳大帝": "岳镇", "北岳大帝": "岳镇", "中岳大帝": "岳镇",
    # ---- 五德星君 ----
    "金德星君": "星君", "木德星君": "星君", "水德星君": "星君", "火德星君": "星君", "土德星君": "星君",
    # ---- 四大天王 ----
    "增长天王": "天王", "多闻天王": "天王", "广目天王": "天王", "持国天王": "天王",
    # ---- 天王 ----
    "九阳定雷天尊": "天尊", "五雷真法天王": "天尊", "十字至臻天王": "天尊",
    "太阳星君": "天尊", "御尊天王": "天尊", "托塔李天王李靖": "天尊", "损天王": "天尊",
    "玄冰真君": "天尊", "真武斩妖天王": "天尊", "破魔天尊": "天尊", "金轮圆法天王": "天尊",
    "降魔天王": "天尊", "除魔降鬼真君": "天尊", "雷嗔天君": "天尊", "面燃大帝": "天尊",
    # ---- 五火真君 ----
    "五火真君": "火部", "五火真君附身": "火部", "五火除魔震灾威严魔怒相": "火部",
    # ---- 星宿 ----
    "亢金龙": "星宿", "奎木狼": "星宿", "星宫二十八宿": "星宿",
    # ---- 神天大照 ----
    "大天狗": "日轮", "月读大命": "日轮", "玉狐-玉藻前": "日轮",
    "素盏鸣尊": "日轮", "迦具土": "日轮",
    # ---- 门神 ----
    "尉迟恭": "门神", "秦琼": "门神",
    # ---- 幽冥 ----
    "孟婆": "幽冥", "白无常": "幽冥", "钟馗": "幽冥", "黑无常": "幽冥",
    # ---- 齐名百圣 ----
    "二郎神": "百圣", "井神": "百圣", "光明太子": "百圣", "后羿": "百圣", "哪吒": "百圣",
    "善财童子": "百圣", "增天王": "百圣", "夜播神": "百圣", "天蓬元帅": "百圣", "夸父": "百圣",
    "女娲": "百圣", "守田神": "百圣", "巨灵神": "百圣", "建御雷神": "百圣", "开天神": "百圣",
    "开山神": "百圣", "杀神": "百圣", "泰山石敢当": "百圣", "灯神": "百圣", "灶神": "百圣",
    "煞面虎-虎爷": "百圣", "犬神": "百圣", "琴瑟神": "百圣", "电神": "百圣", "瘟神": "百圣",
    "白帝将军": "百圣", "神农": "百圣", "英歌神": "百圣", "虎神": "百圣", "财神": "百圣",
    "镇武神": "百圣", "雷神": "百圣", "雷震子": "百圣", "青帝将军": "百圣", "风神": "百圣",
    "黄帝": "百圣",
    # ---- 夜游神 ----
    "夜游神": "夜游", "夜游降临": "夜游",
    # ---- 龙 ----
    "金龙": "龙", "黄龙": "龙",
    # ---- 地 / 奇兽 ----
    "吞口": "异兽", "嘲风": "异兽", "囚牛": "异兽", "杌": "异兽", "比奥天": "异兽",
    "混沌": "异兽", "狴犴": "异兽", "狻猊": "异兽", "睚眦": "异兽", "穷奇": "异兽",
    "蒲牢": "异兽", "螭吻": "异兽", "赑屃": "异兽", "饕餮": "异兽", "麒麟": "异兽",
    # ---- 地 / 妖 ----
    "九尾狐": "妖异", "傲因": "妖异", "八岐大蛇": "妖异", "凶鸮": "妖异", "吞拿": "妖异",
    "唐伞小僧": "妖异", "土蜘蛛": "妖异", "夜叉": "妖异", "山童": "妖异", "山魈": "妖异",
    "巨罗刹": "妖异", "年兽": "妖异", "毛羽毛现": "妖异", "河童": "妖异", "灾火牢成": "妖异",
    "狼妖": "妖异", "猫又": "妖异", "目目连": "妖异", "络新妇": "妖异", "罗刹": "妖异",
    "虎妖": "妖异", "镰鼬": "妖异", "骨妖": "妖异", "鬼修山": "妖异",
    # ---- 地 / 鬼 ----
    "伥鬼": "鬼魅", "刀兵鬼": "鬼魅", "大口鬼": "鬼魅", "娜娜": "鬼魅", "寒冰鬼": "鬼魅",
    "情炎鬼": "鬼魅", "拾骨鬼": "鬼魅", "无目鬼": "鬼魅", "比卢": "鬼魅", "波聪": "鬼魅",
    "狐鬼": "鬼魅", "画皮鬼": "鬼魅", "百目鬼": "鬼魅", "红衣女鬼": "鬼魅", "茨木童子": "鬼魅",
    "酒吞童子": "鬼魅", "飞僵": "鬼魅", "飞头蛮": "鬼魅", "鬼婴": "鬼魅", "鬼王": "鬼魅",
    # ---- 三尸 ----
    "上尸彭踞": "三尸", "下尸彭蹻": "三尸", "中尸彭踬": "三尸",
    # ---- 五孽 ----
    "妖孽-九婴": "五孽", "怪孽-蜚": "五孽", "精孽-木客": "五孽",
    "鬼孽-罗刹女": "五孽", "魔孽-波旬": "五孽",
    # ---- 五灾 ----
    "回禄": "五灾", "无支祁": "五灾", "旱魃": "五灾", "疫鬼": "五灾", "蝗神": "五灾",
    # ---- 五行尸 ----
    "僵尸": "五行尸", "木魁": "五行尸", "水鬼": "五行尸", "焚灭鬼": "五行尸", "金煞鬼": "五行尸",
    # ---- 魑魅魍魉 ----
    "魍魉": "魑魅", "魑魅": "魑魅",
    # ---- 魔 ----
    "万骨魔君": "魔道", "大黑爱婴佛母": "魔道", "幽影魔君": "魔道", "梦魇魔君": "魔道",
    "毕舍遮": "魔道", "瘟癀鬼帝": "魔道", "白衣女魔": "魔道", "血煞魔尊": "魔道",
}

# 少数卡名的「法名」需要人工指定（自动截取会得到别扭或撞车的词）
EPITHET = {
    "南无观世音菩萨": "观音", "托塔李天王李靖": "托塔", "玉狐-玉藻前": "玉藻",
    "煞面虎-虎爷": "虎爷", "泰山石敢当": "石敢当", "三清铃": "三清",
    "五火除魔震灾威严魔怒相": "魔怒", "五火真君附身": "附身", "星宫二十八宿": "二十八宿",
    "妖孽-九婴": "九婴", "怪孽-蜚": "蜚", "精孽-木客": "木客",
    "鬼孽-罗刹女": "罗刹女", "魔孽-波旬": "波旬",
    "大黑爱婴佛母": "佛母", "毗卢": "毗卢",
}


# =============================================================================
# 三、道具卡功能（无技能，只有一次性功能）
#     · func   —— GameState.use_item 的分派键
#     · target —— 拖拽 / 点击的落点类型：
#                  "unit"   指向对方场上某一张卡
#                  "player" 指向某个玩家（多人局指向具体对手）
#                  "self"   拖入己方场地即可释放
#                  "none"   不进手牌（开局自带的拜神/敬鬼，走右侧专属卡位）
#     · weight —— 刷出权重（越小越难刷）。用户要求：
#                  金刚钺 < 降魔杵 < 三清铃 < 铜钱剑 < 金刚镢 < 八卦镜
#     · max_per_game —— 每种道具一局最多获得 2 次，之后除非特殊技能否则不再刷出
# =============================================================================
ITEM_FUNCS = {
    "item_root_004": {
        "name": "金刚钺", "func": "axe", "target": "player",
        "weight": 1, "max_per_game": 2,
        "desc": "拖到某个对手的方向释放：巨钺自天而降，对该玩家所有上场卡造成 3 点伤害，"
                "其中【地】单位额外多受 2 点。"},
    "item_root_007": {
        "name": "降魔杵", "func": "purge", "target": "unit",
        "weight": 2, "max_per_game": 2,
        "desc": "拖到对方场上一张卡：直接拔除该卡。"},
    "item_root_000": {
        "name": "三清铃", "func": "zombies", "target": "self",
        "weight": 3, "max_per_game": 2,
        "desc": "拖入己方场地释放：召唤 3 张临时【僵尸】，可正常行动，持续 3 回合后全体退场。"},
    "item_root_006": {
        "name": "铜钱剑", "func": "ward", "target": "self",
        "weight": 4, "max_per_game": 2,
        "desc": "拖入己方场地释放：己方【人】获得 3 层【辟邪】，每回合消 1 层；"
                "持有【辟邪】期间，其他玩家无法用【地】卡攻击你的【人】。"},
    "item_root_005": {
        "name": "金刚镢", "func": "seal", "target": "unit",
        "weight": 5, "max_per_game": 2,
        "desc": "拖到对方场上一张卡：该卡下回合无法行动，其被动也被一并封印。"},
    "item_root_001": {
        "name": "八卦镜", "func": "reveal_di", "target": "self",
        "weight": 6, "max_per_game": 2,
        "desc": "拖入己方场地释放：只向自己显示各方手牌里各有几张【地】卡。"},
}
# 拜神 / 敬鬼：开局自带的专属卡，不进入三选一卡池，也不占手牌
ITEM_STARTERS = {
    "item_root_002": {"name": "拜神", "func": "worship_shen"},
    "item_root_003": {"name": "敬鬼", "func": "worship_gui"},
}

