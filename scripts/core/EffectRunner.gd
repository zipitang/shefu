class_name EffectRunner
extends RefCounted
## 技能效果解释器
## 卡牌 / 角色技能统一用 effect 字典数组描述，
## 由本类在 GameState 上执行。所有 effect:
##   { "type": "...", ... 参数 }
## 可选上下文 ctx:
##   { "actor": PlayerState, "chosen_uid": int, "chosen_player": int, "source": CCard }

static func run_all(gs: Node, effects: Array, actor: PlayerState, ctx: Dictionary = {}) -> void:
	for e in effects:
		run(gs, e, actor, ctx)


static func run(gs: Node, e: Dictionary, actor: PlayerState, ctx: Dictionary = {}) -> void:
	var t: String = e.get("type", "")
	var v: int = int(e.get("value", 0))
	var enemy: PlayerState = gs.opponent_of(actor)

	# 统一特效 / 音效钩子：UI 层据此在「技能来源卡」上播演出。
	# fx 可用技能里的 "fx" 字段覆写，否则按效果类型推导。
	var src0: CCard = ctx.get("source", null)
	var fx_name: String = str(ctx.get("fx", ""))
	if fx_name == "":
		fx_name = CCard.fx_for_type(t)
	gs.effect_fired.emit({
		"kind": "skill_fx", "fx": fx_name, "etype": t, "pid": actor.pid,
		"uid": src0.uid if src0 != null else -1,
	})

	match t:
		# ---------------- 【气】相关 ----------------
		"heal_qi":
			var tgt: PlayerState = actor if e.get("target", "self_ren") == "self_ren" else enemy
			tgt.heal_qi(v)
			gs.log_msg("%s 恢复 %d 点【气】（%d/%d）" % [tgt.display_name, v, tgt.qi, tgt.qi_max])

		"damage_qi":
			var tgt2: PlayerState = enemy if e.get("target", "enemy_ren") == "enemy_ren" else actor
			gs.deal_qi_damage(tgt2, v, actor)

		"shield_qi":
			actor.shield_qi += v
			gs.log_msg("%s 获得 %d 点护盾【气】" % [actor.display_name, v])

		# 场位加成：部分技能 / 特殊角色可以「额外多上几张」，累加到 board_cap 上。
		"board_bonus":
			actor.board_bonus += v
			gs.log_msg("%s 场位上限 +%d（可多上 %d 张）" % [actor.display_name, v, v])

		# ---------------- 抽牌 / 弃牌 ----------------
		"draw":
			var who: PlayerState = actor if e.get("target", "self") == "self" else enemy
			gs.draw_cards(who, v)

		"discard_enemy":
			gs.discard_random(enemy, v)

		"discard_self":
			gs.discard_random(actor, v)

		"steal_hand":
			gs.steal_hand(actor, enemy, v)
			gs.draw_cards(enemy, v)     # 对方补抽

		"seal_hand_card":
			var who2: PlayerState = enemy if e.get("side", "enemy") == "enemy" else actor
			var sealed_n := 0
			for c in who2.hand:
				if sealed_n >= v:
					break
				c.sealed = int(e.get("turns", 1))
				sealed_n += 1
			if sealed_n > 0:
				gs.log_msg("%s 的 %d 张手牌被封锁" % [who2.display_name, sealed_n])

		"fog_hand":
			actor.hand_hidden = int(e.get("turns", 1))
			gs.log_msg("%s 的手牌信息被隐藏" % actor.display_name)

		# ---------------- 资源 ----------------
		"gain_res":
			var res: String = e.get("res", "wealth")
			actor.add_res(res, v)
			gs.log_msg("%s 获得 %d 点【%s】" % [actor.display_name, v, gs.res_cn(res)])

		"steal_res":
			var res2: String = e.get("res", "wealth")
			var got: int = mini(enemy.res_amount(res2), v)
			enemy.add_res(res2, -got)
			actor.add_res(res2, got)
			gs.log_msg("%s 从 %s 掠夺 %d 点【%s】" % [actor.display_name, enemy.display_name, got, gs.res_cn(res2)])

		"gain_material":
			for i in v:
				var m: CCard = CardDB.random_card(gs.rng, 1)
				if m:
					actor.hand.append(m)
			gs.log_msg("%s 返还 %d 张 1 阶材料牌" % [actor.display_name, v])

		"grant_card_tag":
			var tag: String = e.get("tag", "护法金刚")
			for i in v:
				var gc: CCard = CardDB.random_card_by_tag(gs.rng, tag)
				if gc:
					gc.owner_id = actor.pid
					actor.hand.append(gc)
			gs.log_msg("%s 获得 %d 张【%s】" % [actor.display_name, v, tag])

		"recycle_discard":
			for i in mini(v, actor.discard.size()):
				var rc: CCard = actor.discard.pop_back()
				rc.owner_id = actor.pid
				actor.hand.append(rc)
			gs.log_msg("%s 从弃置区回收 %d 张牌" % [actor.display_name, v])

		"summon_special":
			var gname: String = e.get("group", "四相")
			for i in v:
				var sp: CCard = gs.random_from_special(gname)
				if sp:
					sp.owner_id = actor.pid
					gs.summon(actor, sp, true)
			gs.log_msg("%s 召唤了【%s】" % [actor.display_name, gname])

		# ---------------- 场面：伤害 / 治疗 ----------------
		"damage_board":
			var side: String = e.get("side", "enemy")
			var target_player: PlayerState = enemy if side == "enemy" else actor
			var uid: int = int(ctx.get("chosen_uid", -1))
			var unit: CCard = target_player.find_board(uid)
			if unit == null:
				unit = gs.pick_weakest_board(target_player)
			if unit == null:
				gs.log_msg("目标为空，效果失效")
				return
			gs.damage_unit(unit, v, actor, bool(e.get("ignore_counter", false)), int(e.get("draw_on_kill", 0)))

		"damage_board_all":
			var side2: String = e.get("side", "enemy")
			var tp2: PlayerState = enemy if side2 == "enemy" else actor
			var filt: String = e.get("filter", "")
			for u in tp2.board.duplicate():
				if filt != "" and u.faction != filt:
					continue
				gs.damage_unit(u, v, actor, true, 0)

		"damage_weakest":
			var side3: String = e.get("side", "enemy")
			var tp3: PlayerState = enemy if side3 == "enemy" else actor
			var wk: CCard = gs.pick_weakest_board(tp3)
			if wk:
				gs.damage_unit(wk, v, actor, true, 0)

		"heal_board":
			var side4: String = e.get("side", "self")
			var tp4: PlayerState = actor if side4 == "self" else enemy
			var filt4: String = e.get("filter", "")
			var uni: CCard = tp4.find_board(int(ctx.get("chosen_uid", -1)))
			if uni == null or (filt4 != "" and uni.faction != filt4):
				uni = null
				for u in tp4.board:
					if filt4 == "" or u.faction == filt4:
						uni = u
						break
			if uni:
				uni.cur_hp = mini(uni.max_hp, uni.cur_hp + v)
				gs.log_msg("%s 恢复 %d 点生命" % [uni.name, v])

		"heal_board_all":
			var tp5: PlayerState = actor if e.get("side", "self") == "self" else enemy
			for u in tp5.board:
				u.cur_hp = mini(u.max_hp, u.cur_hp + v)
			gs.log_msg("%s 场上所有单位 +%d 生命" % [tp5.display_name, v])

		"buff_self_hp":
			var src: CCard = ctx.get("source", null)
			if src:
				src.max_hp += v
				src.cur_hp += v

		"buff_tian_hp_all":
			for u in actor.board:
				if u.is_tian():
					u.max_hp += v
					u.cur_hp += v
			gs.log_msg("%s 所有【天】单位 +%d【祇】" % [actor.display_name, v])

		"buff_lonely":
			if actor.board.size() == 1:
				actor.board[0].max_hp += v
				actor.board[0].cur_hp += v
				gs.log_msg("孤星命：%s +%d 生命" % [actor.board[0].name, v])
			else:
				gs.log_msg("孤星命：场上单位不为 1，效果失效")

		"debuff_board":
			var side6: String = e.get("side", "enemy")
			var tp6: PlayerState = enemy if side6 == "enemy" else actor
			for i in int(e.get("count", 1)):
				var u6: CCard = gs.pick_random_board(tp6)
				if u6:
					gs.damage_unit(u6, v, actor, true, 0)

		# ---------------- 场面：消灭 / 拔除 ----------------
		"destroy_di":
			var lim: int = int(ctx.get("chosen_tier", 0))
			var weakest: CCard = null
			for u in enemy.board:
				if u.faction == "地":
					if lim > 0 and u.tier > lim:
						continue
					if weakest == null or u.cur_hp < weakest.cur_hp:
						weakest = u
			if weakest:
				gs.remove_unit(weakest, actor, "镇压")
			else:
				gs.log_msg("对方没有可镇压的【地】卡")

		"execute_board":
			var lim2: int = int(e.get("hp_limit", 2))
			var cands: Array = []
			var tp7: PlayerState = enemy if e.get("side", "enemy") == "enemy" else actor
			for u in tp7.board:
				if u.cur_hp <= lim2:
					cands.append(u)
			if not cands.is_empty():
				gs.remove_unit(cands[0], actor, "断魂")

		"sacrifice_board":
			var tp8: PlayerState = actor if e.get("side", "self") == "self" else enemy
			var filt8: String = e.get("filter", "")
			for u in tp8.board:
				if filt8 == "" or u.faction == filt8:
					gs.remove_unit(u, actor, "牺牲")
					break

		"clash_enemy_board":
			var picks: Array = []
			for u in enemy.board:
				if picks.size() < v:
					picks.append(u)
			if picks.size() >= 2:
				var a: CCard = picks[0]
				var b: CCard = picks[1]
				gs.damage_unit(a, b.atk, actor, true, 0)
				gs.damage_unit(b, a.atk, enemy, true, 0)

		# ---------------- 控制 ----------------
		"freeze_board":
			var side9: String = e.get("side", "enemy")
			var tp9: PlayerState = enemy if side9 == "enemy" else actor
			var filt9: String = e.get("filter", "")
			var block: bool = bool(e.get("block_qi", false))
			for u in tp9.board:
				if filt9 != "" and u.faction != filt9:
					continue
				u.frozen = maxi(u.frozen, int(e.get("turns", 1)))
				if block:
					u.qi_blocked = maxi(u.qi_blocked, int(e.get("turns", 1)))
			gs.log_msg("%s 的场上单位被封锁 %d 回合" % [tp9.display_name, int(e.get("turns", 1))])

		# ---------------- 增幅 ----------------
		"buff_qi_damage":
			actor.temp_qi_bonus += v
			actor.temp_qi_turns = maxi(actor.temp_qi_turns, int(e.get("turns", 1)))
			gs.log_msg("%s 的地卡气伤 +%d（本回合）" % [actor.display_name, v])

		"multiply_qi_damage":
			actor.temp_qi_mult = int(e.get("value", 2))
			actor.temp_qi_turns = maxi(actor.temp_qi_turns, int(e.get("turns", 1)))
			gs.log_msg("%s 的地卡气伤 x%d（本回合）" % [actor.display_name, int(e.get("value", 2))])

		"draw_by_missing_qi":
			var per: int = maxi(1, int(e.get("per", 3)))
			var missing: int = actor.qi_max - actor.qi
			var n: int = int(missing / per)
			if n > 0:
				gs.draw_cards(actor, n)

		# ---------------- 召唤 / 复活 / 复制（观赏性 & 战略性） ----------------
		"summon_to_hand":
			# 随机召唤牌入手。两种寻址方式：
			#   group —— 特殊卡池（「十二生肖」/「四相」，见 random_from_special 的 "天/"+group）
			#   subs  —— 按 sub 随机（「神」「佛」「妖」「鬼」「魔」「奇兽」）
			# 【踩过的坑】拜神/敬鬼原来写的是 group="神"/"鬼"，而 random_from_special
			# 拼出来的是「天/神」「天/鬼」—— 这两个分组根本不存在，于是技能一声不响地
			# 什么都没抽到（只在日志里留一句「召唤失败：卡池为空」）。按 sub 抽取才对得上语义。
			var gname2: String = e.get("group", "十二生肖")
			var subs2: Array = e.get("subs", [])
			var got2 := 0
			for i in v:
				var sp2: CCard = null
				if not subs2.is_empty():
					sp2 = CardDB.random_card_by_sub(gs.rng, subs2)
				else:
					sp2 = gs.random_from_special(gname2)
				if sp2:
					sp2.owner_id = actor.pid
					actor.hand.append(sp2)
					got2 += 1
			if got2 > 0:
				gs.log_msg("✦ %s 召唤 %d 张【%s】进入手牌"
					% [actor.display_name, got2, gname2 if subs2.is_empty() else "/".join(subs2)])
			else:
				gs.log_msg("召唤失败：【%s】卡池为空" % (gname2 if subs2.is_empty() else "/".join(subs2)))

		"revive_discard":
			# 从己方弃置区随机复活 N 张回手牌
			var got3 := 0
			for i in v:
				if actor.discard.is_empty():
					break
				var idx: int = gs.rng.randi_range(0, actor.discard.size() - 1)
				var rc2: CCard = actor.discard[idx]
				actor.discard.remove_at(idx)
				rc2.owner_id = actor.pid
				actor.hand.append(rc2)
				got3 += 1
			if got3 > 0:
				gs.log_msg("✦ %s 从弃置区复活 %d 张牌（%s）" % [actor.display_name, got3, "、".join(actor.hand.slice(-got3).map(func(c): return c.name))])
			else:
				gs.log_msg("%s 的弃置区为空，复活失败" % actor.display_name)

		"copy_hand":
			# 复制己方随机手牌
			var got4 := 0
			for i in v:
				if actor.hand.is_empty():
					break
				var src2: CCard = actor.hand[gs.rng.randi_range(0, actor.hand.size() - 1)]
				var dup: CCard = CardDB.instantiate_card(src2.id, src2.tier)
				if dup:
					dup.owner_id = actor.pid
					actor.hand.append(dup)
					got4 += 1
			if got4 > 0:
				gs.log_msg("✦ %s 复制了 %d 张手牌" % [actor.display_name, got4])

		"bounce_board":
			# 弹回：对方场上单位回到其手牌（强力节奏技）
			var side10: String = e.get("side", "enemy")
			var tp10: PlayerState = enemy if side10 == "enemy" else actor
			var lim3: int = int(e.get("tier_limit", 99))
			var bounced := 0
			for i in v:
				var cands2: Array = []
				for u in tp10.board:
					if u.tier <= lim3:
						cands2.append(u)
				if cands2.is_empty():
					break
				var pick2: CCard = cands2[gs.rng.randi_range(0, cands2.size() - 1)]
				tp10.board.erase(pick2)
				pick2.on_board = false
				pick2.cur_hp = pick2.max_hp
				pick2.set_cooldown(0)
				pick2.frozen = 0
				tp10.hand.append(pick2)
				bounced += 1
				gs.log_msg("✦ %s 被弹回 %s 的手牌" % [pick2.name, tp10.display_name])
			if bounced == 0:
				gs.log_msg("没有可弹回的目标")
			else:
				gs.state_changed.emit()

		"transform_board":
			# 变化：己方场上随机单位变为「同阵营 + 同阶」的另一张随机卡。
			# 【为什么不再变成「高一阶」】卡牌阶数在卡池里就是固定的（合成已整条移除），
			# max_tier == tier，原来那句 `u.tier < u.max_tier` 永远为假 ——
			# 效果会一声不响地什么都不做。改成同阶换形，
			# 既保住了「混沌无相」的设定，又不破坏「阶数固定」这条规则。
			if actor.board.is_empty():
				gs.log_msg("场上没有可变化的单位")
			else:
				var old: CCard = actor.board[gs.rng.randi_range(0, actor.board.size() - 1)]
				var pool2: Array = []
				for d in CardDB.cards:
					if d.get("faction", "") == old.faction \
							and int(d.get("tier", 1)) == old.tier \
							and d.get("pool", "normal") == "normal" \
							and str(d.get("id", "")) != old.id:
						pool2.append(d)
				if pool2.is_empty():
					gs.log_msg("没有合适的变化目标")
				else:
					var nd: Dictionary = pool2[gs.rng.randi_range(0, pool2.size() - 1)]
					var nc: CCard = CardDB.instantiate_card(nd.id)
					var pos: int = actor.board.find(old)
					actor.board.erase(old)
					gs.log_msg("✦ %s 变化为 %s！" % [old.name, nc.name])
					gs.summon(actor, nc, false)
					if pos >= 0 and pos < actor.board.size() - 1:
						actor.board.erase(nc)
						actor.board.insert(pos, nc)

		"qi_per_tian":
			# 按己方场上【天】数量恢复【气】
			var cnt := 0
			for u in actor.board:
				if u.is_tian():
					cnt += 1
			var heal2: int = cnt * v
			if heal2 > 0:
				actor.heal_qi(heal2)
				gs.log_msg("%s 以 %d 尊【天】恢复 %d 点【气】" % [actor.display_name, cnt, heal2])
			else:
				gs.log_msg("场上无【天】，效果失效")

		"draw_group":
			# 从指定普通分组抽牌入手（如 道具）
			var gname3: String = e.get("group", "")
			var got5 := 0
			for i in v:
				var pool3: Array = []
				for d in CardDB.cards:
					if d.get("pool", "normal") == "normal" and (gname3 == "" or str(d.get("group", "")).ends_with(gname3)):
						pool3.append(d)
				if pool3.is_empty():
					break
				var gc2: CCard = CardDB.instantiate_card(pool3[gs.rng.randi_range(0, pool3.size() - 1)].id)
				gc2.owner_id = actor.pid
				actor.hand.append(gc2)
				got5 += 1
			if got5 > 0:
				gs.log_msg("%s 获得 %d 张【%s】牌" % [actor.display_name, got5, gname3])

		"random_wealth_wager":
			# 趣味：赌财，50% 翻倍 50% 减半
			var w: int = actor.wealth
			if w <= 0:
				gs.log_msg("无财可赌")
			elif gs.rng.randf() < 0.5:
				actor.add_res("wealth", w)
				gs.log_msg("✦ 赌运亨通！%s 的【财】翻倍（+%d）" % [actor.display_name, w])
			else:
				actor.add_res("wealth", -int(ceil(w / 2.0)))
				gs.log_msg("✦ 赌运不济……%s 的【财】减半" % actor.display_name)

		# ---------------- 掷骰 / 夺牌 / 直接召唤（新增观赏性效果） ----------------
		"dice_damage":
			# 掷骰定伤：骰子点数即对对方【人】的【气】伤（UI 会播骰子动画）
			var dmax: int = maxi(2, int(e.get("max", 6)))
			var roll: int = gs.rng.randi_range(1, dmax)
			var bonus: int = int(e.get("bonus", 0))
			gs.effect_fired.emit({"kind": "dice", "pid": actor.pid, "value": roll, "max": dmax})
			gs.log_msg("✦ %s 掷得 %d 点（骰面 %d）" % [actor.display_name, roll, dmax])
			gs.deal_qi_damage(enemy, roll + bonus, actor)

		"dice_heal":
			var dmax2: int = maxi(2, int(e.get("max", 6)))
			var roll2: int = gs.rng.randi_range(1, dmax2)
			gs.effect_fired.emit({"kind": "dice", "pid": actor.pid, "value": roll2, "max": dmax2})
			gs.log_msg("✦ %s 掷得 %d 点，祈求回气" % [actor.display_name, roll2])
			actor.heal_qi(roll2 + int(e.get("bonus", 0)))

		"conquer_board":
			# 夺牌：把对方场上 1 张低阶卡据为己有（战略级节奏技）
			var lim4: int = int(e.get("tier_limit", 2))
			var cands4: Array = []
			for u in enemy.board:
				if u.tier <= lim4:
					cands4.append(u)
			if cands4.is_empty():
				gs.log_msg("没有可夺取的目标")
			else:
				var pk: CCard = cands4[gs.rng.randi_range(0, cands4.size() - 1)]
				enemy.board.erase(pk)
				pk.owner_id = actor.pid
				pk.cur_hp = pk.max_hp
				pk.set_cooldown(0)
				pk.frozen = 0
				actor.board.append(pk)
				gs.log_msg("✦ %s 夺取了 %s 的 %s！" % [actor.display_name, enemy.display_name, pk.name])
				gs.state_changed.emit()

		"summon_board_group":
			# 直接召唤指定分组上场（不入弃置区，是「召唤」不是「起乩」）
			var gname4: String = e.get("group", "十二生肖")
			var summoned := 0
			for i in mini(v, 4):
				var sp4: CCard = gs.random_from_special(gname4)
				if sp4 == null:
					break
				gs.summon(actor, sp4, true)
				summoned += 1
			if summoned > 0:
				gs.log_msg("✦ %s 召唤 %d 张【%s】上场！" % [actor.display_name, summoned, gname4])
				gs.state_changed.emit()

		_:
			gs.log_msg("[未实现的效果] " + t)
