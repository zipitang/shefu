class_name Dev
extends RefCounted
## 测试训练场总开关（★ 只有测试版 exe 会打开；主程序 SheFu.exe 全程 enabled=false）
## ------------------------------------------------------------------
## 【★ 为什么是「静态类 + 默认全 false」而不是条件编译 / 另一份代码】
##   主程序 SheFu.exe 与测试程序 SheFuDev.exe **共用同一份源码**。
##   下面每个开关默认 false 时，挂在规则层的那些钩子等于「什么都没做」——
##   主程序的对局逻辑与引入本文件之前逐条等价，不存在任何行为漂移；
##   测试版由 Main.gd 在启动时把 enabled 置 true，整套工具才上线。
##   另一份分支代码会立刻分叉（改一处得改两处），所以刻意不这么做。
##
## 【判断「这是测试版」的三个信号，任一命中即可】
##   ① 导出预设的 custom_features 里带 "devtest" 特性标签（正式做法）
##   ② 命令行 ++ --dev（源码运行时用）
##   ③ 可执行文件名里含 "dev"（SheFuDev.exe）—— 兜底，防止特性标签在某个导出后端失效
##
## 【为什么作弊要落在规则层，而不是只做 UI 侧「显示出 ∞」】
##   光把数字写成 ∞ 而 can_xxx() 仍然按真实余量判定，会出现「显示 ∞ 却点不动」的
##   假开关 —— 那比没有这个开关更坏。所以统一从 res_amount / spend_res 这一对
##   唯一入口改：门槛放宽 + 不真扣，显示层只是顺带把它画成 ∞。

static var enabled: bool = false

# ---- 数值作弊 ----
static var no_qi_loss: bool = false        ## 全场不掉【气】（谁都不会被打死）
static var no_cooldown: bool = false       ## 所有技能冷却恒为 0
static var infinite_wealth: bool = false   ## 【财】不减
static var infinite_fa: bool = false       ## 【法】不减
static var infinite_yuan: bool = false     ## 【源】不减
static var infinite_crane: bool = false    ## 【千纸鹤】不减
static var no_board_cap: bool = false      ## 解除场上单位数量上限
static var no_action_limit: bool = false   ## 每回合「主动行动」不限次

## 资源余量：无限时返回一个大数，让所有 `x >= cost` 的门槛自然通过。
const BIG := 999999


static func reset_all() -> void:
	no_qi_loss = false
	no_cooldown = false
	infinite_wealth = false
	infinite_fa = false
	infinite_yuan = false
	infinite_crane = false
	no_board_cap = false
	no_action_limit = false


static func set_all(v: bool) -> void:
	no_qi_loss = v
	no_cooldown = v
	infinite_wealth = v
	infinite_fa = v
	infinite_yuan = v
	infinite_crane = v
	no_board_cap = v
	no_action_limit = v


## 按名字读写某个开关 —— 给命令行 `--devflag no_qi_loss,no_cooldown` 与
## 自动化测试用。写成显式 match 而不是反射：静态变量不在 Object.set() 的
## 属性表里，反射拿不到，而且写错名字时宁可明确失败也不要静默无效。
static func set_flag(name: String, v: bool) -> bool:
	match name.strip_edges():
		"no_qi_loss": no_qi_loss = v
		"no_cooldown": no_cooldown = v
		"infinite_wealth": infinite_wealth = v
		"infinite_fa": infinite_fa = v
		"infinite_yuan": infinite_yuan = v
		"infinite_crane": infinite_crane = v
		"no_board_cap": no_board_cap = v
		"no_action_limit": no_action_limit = v
		_: return false
	return true


static func flag_names() -> Array:
	return ["no_qi_loss", "no_cooldown", "infinite_wealth", "infinite_fa",
		"infinite_yuan", "infinite_crane", "no_board_cap", "no_action_limit"]


## 某个资源是否处于「无限」状态（wealth / fa / yuan）
static func res_infinite(res: String) -> bool:
	if not enabled:
		return false
	match res:
		"wealth": return infinite_wealth
		"fa": return infinite_fa
		"yuan": return infinite_yuan
	return false


## 已开启的作弊项数量（顶栏按钮上的小红点提示用）
static func active_count() -> int:
	if not enabled:
		return 0
	var n := 0
	for v in [no_qi_loss, no_cooldown, infinite_wealth, infinite_fa, infinite_yuan,
			infinite_crane, no_board_cap, no_action_limit]:
		if bool(v):
			n += 1
	return n


static func profile() -> String:
	return "dev=%s 不掉气=%s 无冷却=%s 无限财=%s 无限法=%s 无限源=%s 无限纸鹤=%s 不限场位=%s 无限行动=%s" % [
		str(enabled), str(no_qi_loss), str(no_cooldown), str(infinite_wealth),
		str(infinite_fa), str(infinite_yuan), str(infinite_crane),
		str(no_board_cap), str(no_action_limit)]
