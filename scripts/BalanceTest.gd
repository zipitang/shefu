extends Node
## 平衡性扫参器（无头运行）
## ------------------------------------------------------------------
##   godot --headless scenes/BalanceTest.tscn ++ --games 60
##   godot --headless scenes/BalanceTest.tscn ++ --games 60 --actions 1,2,3,99
##
## 对不同「每回合主动行动额度」批量跑 AI vs AI 对局，输出：
##   座位胜率、平均回合数、伤害来源分布，用于挑选最贴合设计文档节奏的参数。
## 设计文档给出 15 段【财】曲线，说明单局长度应落在 12~18 回合量级。

const CHARA_IDS := [
	"chara_小乔儿", "chara_白店小二", "chara_吉马卓玛", "chara_马曜",
	"chara_楚伞", "chara_唐森", "chara_孟谢菲", "chara_玄澈",
]
const RENS := ["凡人", "正一道士", "阴阳师", "巫女", "法师", "萨满"]

var _games_per_cfg := 20


func _ready() -> void:
	print("\n========== 《摄伏》平衡性扫参 ==========\n")
	var args := OS.get_cmdline_user_args()
	_games_per_cfg = int(_arg(args, "--games", "20"))
	var mode := _arg(args, "--mode", "full")
	if mode == "duel":
		_sweep_duel(args, _games_per_cfg)
		print("\n[RESULT] 扫参完成")
		get_tree().quit(0)
		return
	if mode == "seat":
		_sweep_seat(args, _games_per_cfg)
		print("\n[RESULT] 扫参完成")
		get_tree().quit(0)
		return

	var actions_list: Array = []
	for s in _arg(args, "--actions", "1,2,3,99").split(","):
		if not str(s).strip_edges().is_empty():
			actions_list.append(int(str(s).strip_edges()))
	if actions_list.is_empty():
		actions_list = [1, 2, 3, 99]

	print("每档配置对局数: %d  (2/3/4 人局各占 1/3)\n" % _games_per_cfg)
	print("  %-4s %-9s %-8s %-8s %-34s %s" % ["", "对局类型", "平均回合", "中位回合", "座位胜利分布", "偏斜"])
	print("-".repeat(88))

	for lim in actions_list:
		CardDB.rules["actionsPerTurn"] = int(lim)
		_sweep(int(lim))

	CardDB.rules["actionsPerTurn"] = 2
	print("\n[RESULT] 扫参完成")
	get_tree().quit(0)


## 2 人局专项：扫描后手补偿组合
func _sweep_duel(args: PackedStringArray, games: int) -> void:
	var comps := _arg(args, "--comp", "0:0,2:0,4:0,6:2,8:2,0:4").split(",")
	print("2 人局专项扫参（东 vs 西），每组 %d 局\n" % games)
	print("  %-14s %-10s %-10s %s" % ["后手补偿(气:财)", "平均回合", "中位回合", "先手胜率"])
	print("-".repeat(60))
	for cs in comps:
		var parts := str(cs).strip_edges().split(":")
		var qi_c := int(parts[0])
		var w_c := int(parts[1]) if parts.size() > 1 else 0
		# 注意：_compensation_for 优先读 compensationByCount，必须两处都写
		var cfg2 := {"enabled": qi_c > 0 or w_c > 0, "laterQi": qi_c, "laterWealth": w_c}
		CardDB.rules["duelCompensation"] = cfg2
		CardDB.rules["compensationByCount"]["2"] = cfg2
		var east := 0
		var lens: Array = []
		for g in games:
			# 种子只与「第几局」有关，绝不允许掺入 qi_c / w_c——
			# 否则每个补偿档打的是不同的对手组合，胜率差异里混进了卡组随机性，
			# 看起来是「补偿有效」其实只是换了对手。
			var r := _simulate(2, 70000 + g * 37)
			lens.append(int(r["turns"]))
			if int(r["winner"]) == 0:
				east += 1
			r["gs"].queue_free()
		lens.sort()
		var avg := 0.0
		for v in lens:
			avg += float(v)
		avg /= float(maxi(1, lens.size()))
		var med: int = int(lens[lens.size() / 2]) if not lens.is_empty() else 0
		print("  %-14s %-10.1f %-10d 东 %d/%d (%.1f%%)" % [
			"%d:%d" % [qi_c, w_c], avg, med, east, games, float(east) / float(games) * 100.0])


## 多座位补偿扫参：对 3 人 / 4 人局分别扫候选 (气:财) 组合，输出各座位胜率与偏斜
##   godot --headless scenes/BalanceTest.tscn ++ --mode seat --games 80 \
##         --c3 "0:0,1:2,0:4,2:3" --c4 "0:0,1:1,1:2,2:2"
func _sweep_seat(args: PackedStringArray, games: int) -> void:
	var list3 := _arg(args, "--c3", "0:0,1:2,0:4,2:3").split(",")
	var list4 := _arg(args, "--c4", "0:0,1:1,1:2,2:2").split(",")
	var seat3 := _arg(args, "--c3seat", "")
	var seat4 := _arg(args, "--c4seat", "")
	for n in [3, 4]:
		var lst: Array = list3 if n == 3 else list4
		var seat_str: String = seat3 if n == 3 else seat4
		print("\n--- %d 人局座位补偿扫参（每组 %d 局）---" % [n, games])
		print("  %-22s %-9s %-8s %s" % ["补偿", "平均回合", "偏斜", "座位胜率"])
		print("-".repeat(86))
		if seat_str.strip_edges() != "":
			# 显式按座位：多个配置用 ';' 分隔，单个配置形如 "0,2,2|0,3,4"（气数组|财数组）
			for one in seat_str.split(";"):
				var s := str(one).strip_edges()
				if s == "":
					continue
				var halves := s.split("|")
				var qa := _int_arr(str(halves[0]))
				var wa := _int_arr(str(halves[1])) if halves.size() > 1 else []
				CardDB.rules["compensationByCount"][str(n)] = {"qi": qa, "wealth": wa}
				_report_seat(n, games, "气%s财%s" % [str(qa), str(wa)])
		for cs in lst:
			var parts := str(cs).strip_edges().split(":")
			if parts.size() < 2:
				continue
			var qi_c := int(parts[0])
			var w_c := int(parts[1])
			CardDB.rules["compensationByCount"][str(n)] = {
				"laterQi": qi_c, "laterWealth": w_c}
			_report_seat(n, games, "%d:%d" % [qi_c, w_c])


func _int_arr(s: String) -> Array:
	var out: Array = []
	for p in s.split(","):
		var t := str(p).strip_edges()
		if t != "":
			out.append(int(t))
	return out


func _report_seat(n: int, games: int, label: String) -> void:
	var wins := {"东": 0, "南": 0, "西": 0, "北": 0}
	var seen := {"东": 0, "南": 0, "西": 0, "北": 0}
	var lens: Array = []
	for g in games:
		var r := _simulate(n, 50000 + n * 7919 + g * 41)
		var gsx: GameState = r["gs"]
		if int(r["winner"]) >= 0:
			var p: PlayerState = gsx.get_player(int(r["winner"]))
			if p != null:
				wins[p.seat] = int(wins[p.seat]) + 1
		for p2 in gsx.players:
			seen[p2.seat] = int(seen[p2.seat]) + 1
		lens.append(int(r["turns"]))
		gsx.queue_free()
	lens.sort()
	var avg := 0.0
	for v in lens:
		avg += float(v)
	avg /= float(maxi(1, lens.size()))
	var rates: Array = []
	var dist := ""
	for s in ["东", "南", "西", "北"]:
		if int(seen[s]) <= 0:
			continue
		var rate := float(wins[s]) / float(seen[s]) * 100.0
		rates.append(rate)
		dist += "%s %4.1f%%  " % [s, rate]
	var dev := 0.0
	if rates.size() >= 2:
		rates.sort()
		dev = float(rates[rates.size() - 1]) - float(rates[0])
	print("  %-22s %-9.1f %-8.1f %s" % [label, avg, dev, dist])


func _sweep(limit: int) -> void:
	# 分档统计：ALL / 2 人 / 3 人 / 4 人
	var buckets := {"ALL": _bucket_new(), "2": _bucket_new(), "3": _bucket_new(), "4": _bucket_new()}
	for cfg in [2, 3, 4]:
		for g in _games_per_cfg:
			var seed_value: int = 90000 + limit * 977 + int(cfg) * 131 + g * 37
			var r := _simulate(int(cfg), seed_value)
			for key in ["ALL", str(int(cfg))]:
				var b: Dictionary = buckets[key]
				var wins: Dictionary = b["wins"]
				var seen: Dictionary = b["seen"]
				var lens: Array = b["lens"]
				if int(r["winner"]) >= 0:
					var p: PlayerState = r["gs"].get_player(int(r["winner"]))
					if p != null:
						wins[p.seat] = int(wins[p.seat]) + 1
				for p2 in r["gs"].players:
					seen[p2.seat] = int(seen[p2.seat]) + 1
				lens.append(int(r["turns"]))
			r["gs"].queue_free()

	for key in ["ALL", "2", "3", "4"]:
		_print_bucket(limit, key, buckets[key])


func _bucket_new() -> Dictionary:
	return {
		"wins": {"东": 0, "南": 0, "西": 0, "北": 0},
		"seen": {"东": 0, "南": 0, "西": 0, "北": 0},
		"lens": [] as Array,
	}


func _print_bucket(limit: int, key: String, b: Dictionary) -> void:
	var wins: Dictionary = b["wins"]
	var seen: Dictionary = b["seen"]
	var lens: Array = b["lens"]
	if lens.is_empty():
		return
	lens.sort()
	var avg := 0.0
	for v in lens:
		avg += float(v)
	avg /= float(lens.size())
	var median: int = int(lens[lens.size() / 2])

	var rates: Array = []
	var dist_str := ""
	for s in ["东", "南", "西", "北"]:
		var played: int = int(seen[s])
		if played <= 0:
			continue
		var rate := float(wins[s]) / float(played) * 100.0
		rates.append(rate)
		dist_str += "%s %d/%-3d(%4.1f%%)  " % [s, wins[s], played, rate]
	var dev := 0.0
	if rates.size() >= 2:
		rates.sort()
		dev = float(rates[rates.size() - 1]) - float(rates[0])

	print("  %-4s %-9s %-8.1f %-8d %-34s %5.1f" % [
		("额度" + str(limit)) if key == "ALL" else "", key + "人局", avg, median, dist_str, dev])


func _simulate(n: int, seed_value: int) -> Dictionary:
	var gsx := GameState.new()
	add_child(gsx)
	var seats_data: Array = []
	for i in n:
		# 注意：【人】必须随对局变化，否则某个座位会长期绑定特定【人】，
		# 让「座位胜率」变成「卡组强度」的代理指标（早期版本就踩过这个坑）。
		seats_data.append({
			"chara_id": CHARA_IDS[(i + seed_value) % CHARA_IDS.size()],
			"ren": RENS[(i + seed_value) % RENS.size()],
			"is_ai": true,
			# 【重要】ai_level 绝不能与 ren 共用同一个取模基准。
			# 早期写法 1 + ((i + seed) % 3) 会让 (i+seed)%6 完全决定等级，
			# 于是 RENS[0]=凡人、RENS[3]=巫女 永远落在 level 1（EASY），
			# 而 EASY 不参与刷新/购买/升级——偏偏这两个阵营正是靠【财】升级的，
			# 结果整轮扫参里【财】无人消耗，财补偿看起来完全无效。
			"ai_level": 1 + posmod(i * 2 + int(seed_value / 7.0), 3),
			"name": "AI%d" % (i + 1),
		})
	gsx.setup(seats_data, seed_value)

	var dbg := OS.get_environment("SF_DEBUG") == "1"
	var n_buy := 0
	var n_refresh := 0
	var n_upgrade := 0
	var n_upgrade_ok := 0
	if dbg:
		for pp in gsx.players:
			print("   [DBG-INIT] %s seat=%s ren=%s mortal=%s wealth=%d qi=%d" % [
				pp.display_name, pp.seat, pp.ren_type, str(pp.is_mortal_faction()),
				pp.wealth, pp.qi])

	var turns := 0
	var guard := 0
	while not gsx.finished and guard < 900:
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
		var planned := ai.plan_turn()
		if dbg:
			var kinds: Array = []
			for a0 in planned:
				kinds.append(str(a0.get("type", "")))
			print("   [DBG-PLAN] %s(%s,lv%d,w=%d) %s" % [
				p.display_name, p.ren_type, p.ai_level, p.wealth, str(kinds)])
		for a in planned:
			if gsx.finished:
				break
			var ok := _apply(gsx, p, a)
			if dbg:
				print("      -> %s ok=%s (w=%d qi=%d ren=%d)" % [
					str(a.get("type", "")), str(ok), p.wealth, p.qi, p.ren_count])
			match a.get("type", ""):
				"buy": n_buy += 1
				"refresh": n_refresh += 1
				"upgrade":
					n_upgrade += 1
					if ok:
						n_upgrade_ok += 1
		if gsx.finished:
			break
		gsx.end_turn()
	if dbg:
		print("   [DBG-TOT] turns=%d buy=%d refresh=%d upgrade=%d(成功%d)" % [
			turns, n_buy, n_refresh, n_upgrade, n_upgrade_ok])
		for pp in gsx.players:
			print("   [DBG-END ] %s seat=%s ren=%s wealth=%d qi=%d ren_count=%d" % [
				pp.display_name, pp.seat, pp.ren_type, pp.wealth, pp.qi, pp.ren_count])
	if not gsx.finished:
		print("   [WARN] 对局未结束 seed=%d cfg=%d turns=%d" % [seed_value, n, turns])
	return {"gs": gsx, "winner": gsx.winner_pid, "turns": turns}


## 返回该动作是否真的被执行成功（用于诊断 AI 计划与规则层是否脱节）
func _apply(gsx: GameState, p: PlayerState, a: Dictionary) -> bool:
	match a.get("type", ""):
		"draft":
			return gsx.pick_draft(int(a.get("idx", 0)))
		"refresh":
			return gsx.do_refresh()
		"buy":
			return gsx.do_buy(int(a.get("idx", 0)))
		"worship":
			gsx.do_worship(a.get("kind", "shen"))
		"discard":
			return gsx.do_discard(int(a.get("uid", -1)))
		"upgrade":
			return gsx.do_upgrade()
		"play":
			gsx.do_play(int(a.get("uid", -1)))
		"item":
			# 道具走 use_item 独立入口（带落点上下文），不再有旧的 vajra 计数器
			var cur := gsx.current_player()
			var ic := cur.find_hand(int(a.get("uid", -1)))
			if ic != null:
				gsx.use_item(cur, ic,
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
	return true


func _arg(args: PackedStringArray, key: String, def: String) -> String:
	for i in args.size():
		if args[i] == key and i + 1 < args.size():
			return args[i + 1]
	return def
