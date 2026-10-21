extends Node
## 全局设置（Autoload 名 Settings）
## ------------------------------------------------------------------
## 负责「启动时就该定下来」的东西：窗口模式 / 分辨率 / 音量 / 棋盘开关。
## 【为什么必须做成 autoload 而不是某个界面的字段】
##   1. 窗口模式要在**任何界面出现之前**生效，否则会看到「先全屏闪一下再变窗口」；
##   2. 设置被大厅 / 房间 / 对局三处共享，界面各存一份必然不一致；
##   3. 用户改完要持久化，下次启动还得是这个样子。
##
## 存 user://settings.cfg（ConfigFile，纯文本，出问题能直接删掉重来）。
##
## 默认值取**窗口化 1600×900**：默认全屏是上一版的行为，用户明确反馈
## 「进入后是真全屏」影响使用，所以首次运行给一个带系统边框、居中的窗口，
## 想要全屏在设置里点一下即可（选择会被记住）。

const CFG_PATH := "user://settings.cfg"

signal changed

## 全屏（无边框铺满） vs 窗口化
var fullscreen: bool = false
## 窗口模式下的尺寸（16:9 三档）
var window_w: int = 1600
var window_h: int = 900
## 音效音量 0.0 ~ 1.0
var master_volume: float = 0.8
## 动态海报 / 卡牌的陀螺仪视差
var gyro: bool = true
## 全局特效开关（卡牌动效 / 粒子）
var effects: bool = true

const RES_OPTS := [
	{"w": 1600, "h": 900, "label": "1600 × 900"},
	{"w": 1440, "h": 810, "label": "1440 × 810"},
	{"w": 1280, "h": 720, "label": "1280 × 720"},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_cfg()
	apply_display()
	apply_audio()
	# 把两个开关同步到 CardView 的静态变量（画面表现层读的是那边）
	CardView.gyro_enabled = gyro
	CardView.effects_enabled = effects


# ------------------------------------------------------------------ 读 / 写
func load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return                       # 没有存档 = 首次运行，用默认值
	fullscreen = bool(cf.get_value("display", "fullscreen", fullscreen))
	window_w = int(cf.get_value("display", "window_w", window_w))
	window_h = int(cf.get_value("display", "window_h", window_h))
	master_volume = clampf(float(cf.get_value("audio", "volume", master_volume)), 0.0, 1.0)
	gyro = bool(cf.get_value("play", "gyro", gyro))
	effects = bool(cf.get_value("play", "effects", effects))


func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "window_w", window_w)
	cf.set_value("display", "window_h", window_h)
	cf.set_value("audio", "volume", master_volume)
	cf.set_value("play", "gyro", gyro)
	cf.set_value("play", "effects", effects)
	cf.save(CFG_PATH)


# ------------------------------------------------------------------ 应用
## 应用窗口模式。headless（无头截图 / 单测）下 DisplayServer 没有窗口概念，
## 直接跳过 —— 否则在某些平台会打印一堆 "Window mode not supported" 噪声。
func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# 截图流程（++ --shot）由 --resolution 决定画布尺寸，设置面板不得改窗口，
	# 否则截图会被强制成 1600×900，验收尺寸对不上（实测踩到）。
	if OS.get_cmdline_user_args().has("--shot"):
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	# 【顺序不能反】先切窗口化再设尺寸；反过来会被全屏模式的约束吃掉尺寸设置
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# ================= 可用区必须用 screen_get_usable_rect =================
	# 【为什么不用 screen_get_size】它在窗口上屏前返回的是**物理分辨率**、
	# 上屏后才变成带 DPI 缩放（本机 125%）的**逻辑分辨率** —— 同一台机器上
	# 启动早期读到 (1920,1080)、1 秒后读到 (1536,864)。用早期的值判断
	# 「1600×900 放得下」会得出错误结论，窗口于是比逻辑屏幕还大、边框被挤出屏幕外，
	# 看起来就是「一进游戏就是真全屏」——正是用户报的问题。
	# screen_get_usable_rect() 两个时机都返回稳定的逻辑尺寸（还自动扣掉任务栏）。
	var ur := DisplayServer.screen_get_usable_rect()
	if ur.size.x <= 0 or ur.size.y <= 0:
		ur = Rect2i(Vector2i.ZERO, DisplayServer.screen_get_size())
	var avail := Vector2(ur.size) * 0.98          # 再留一点给窗口边框
	var w := float(window_w)
	var h := float(window_h)
	if w > avail.x or h > avail.y:
		var k := minf(avail.x / w, avail.y / h)
		w *= k
		h *= k
	var wsz := Vector2i(int(w), int(h))
	DisplayServer.window_set_size(wsz)
	DisplayServer.window_set_position(ur.position + (ur.size - wsz) / 2)


func apply_audio() -> void:
	Sfx.volume = master_volume


func set_fullscreen(v: bool) -> void:
	if fullscreen == v:
		return
	fullscreen = v
	apply_display()
	save_cfg()
	changed.emit()
	Sfx.play("ui_fullscreen", -5.0)


func set_resolution(w: int, h: int) -> void:
	window_w = w
	window_h = h
	apply_display()
	save_cfg()
	changed.emit()


func set_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	save_cfg()
	changed.emit()


func set_gyro(v: bool) -> void:
	gyro = v
	CardView.gyro_enabled = v
	save_cfg()
	changed.emit()


func set_effects(v: bool) -> void:
	effects = v
	CardView.effects_enabled = v
	save_cfg()
	changed.emit()
