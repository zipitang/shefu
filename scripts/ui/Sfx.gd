extends Node
## Sfx —— 全局音效管理器（Autoload 单例，注册名 Sfx）
## ------------------------------------------------------------------
## · 音效来自 tools/build_audio_pack.py 挑选的真实素材（UI界面音效素材包 /
##   interface 界面 / 技能音效 / 环境音效 / 雷电 / 怪物），按语义与材质取用。
##
## ★ 固定音效，不做随机 ★
##   用户明确要求：「不准许使用随机播放音效，必须是固定的」。旧版会在
##   <name>.ogg / <name>_1.ogg / <name>_2.ogg 之间随机取一个并叠加音高抖动 ——
##   同一个操作每次听起来都不一样，玩家永远记不住反馈，等于没有音效设计。
##   现在 **一个音效名 = 一个固定文件**，音高也不抖（pitch 恒为 1.0，
##   连 pitch 抖动参数都已从 API 里删掉 —— 留着就会有人再用）。
##   同类型成组素材（雷电1-惊雷 / 雷电2-闷雷）在管线里拆成独立名字
##   （bolt / bolt_deep）显式登记，由调用方指名使用，依然不是随机。
##
## · 对象池复用 AudioStreamPlayer，避免每次播放都 new 节点；
## · 懒加载 + 缓存，缺失文件只警告一次，不阻塞流程；
## · 同一音效 55ms 内连播时压低音量，避免叠成爆音；
## · 提供 enabled / volume 供设置面板调节。

const DIR := "res://assets/audio/"
## 【为什么是 16】一次袭人可能同时触发：出刀 + 命中 + 战报 + 资源结算，
## 再叠加悬停/点击，12 条会互相抢占导致后面的音被截断。
const POOL_SIZE := 16

static var enabled: bool = true
static var volume: float = 0.8          ## 0.0 ~ 1.0

var _pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}           ## name -> AudioStream（固定一份）
var _missing: Dictionary = {}
var _last_play: Dictionary = {}
var _cursor := 0
## 【诊断计数】name -> 播放次数。仅用于测试断言「某个音效真的被触发了」
## （无头环境没有声卡，听觉验不了，只能数调用）。生产逻辑不读它，零副作用。
var _play_count: Dictionary = {}


## 某个音效名被播放过几次（测试用；见 _play_count）。
func play_count(name: String) -> int:
	return int(_play_count.get(name, 0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


## 取某个音效名对应的音频流（固定、缓存）。找不到只警告一次。
## 扩展名按 .ogg -> .wav -> .mp3 顺序找（管线保持源扩展名）
func _stream_for(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var exts := PackedStringArray([".ogg", ".wav", ".mp3"])
	for e in exts:
		var path: String = DIR + name + e
		if ResourceLoader.exists(path):
			var s := load(path) as AudioStream
			if s != null:
				# 【★ 强制关闭循环】部分素材（敬鬼 worship_gui / 雷电 bolt）的
				# wav 文件自带 smpl loop 标记，Godot 导入器在 edit/loop_mode=0
				# （Detect From WAV）下会**读走这个标记**、导成 loop_mode=1 向前
				# 循环 —— 于是敬鬼那声呼啸喘气就一直响，听感像循环播放（而代码层
				# 根本没有循环：play 是一次性的）。这里加载后一律锁死为不循环；
				# 本工程没有任何一个音效需要循环，BGM 是另一套、不走这里。
				if s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
					(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
				_streams[name] = s
				return s
	if not _missing.has(name):
		_missing[name] = true
		push_warning("[Sfx] 缺少音效: " + DIR + name + "(.ogg/.wav/.mp3)")
	_streams[name] = null
	return null


## 播放一个音效（固定）。
##   name    音效名（见 assets/audio/，不含扩展名）
##   vol_db  相对音量（负=更轻），悬停这类提示音一般给 -20 上下
## 【没有 pitch 抖动参数】用户要求「必须是固定的」—— 想有变化就多登记一个名字
## （bolt / bolt_deep），而不是让同一个动作每次听起来都不一样。
func play(name: String, vol_db: float = 0.0) -> void:
	if not enabled or volume <= 0.0:
		return
	var s := _stream_for(name)
	if s == null:
		return
	# 同一音效 55ms 内连播时压制音量，避免爆音
	var now := Time.get_ticks_msec()
	if _last_play.has(name) and now - int(_last_play[name]) < 55:
		vol_db -= 7.0
	_last_play[name] = now

	var p := _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	p.stream = s
	p.pitch_scale = 1.0      # ★ 固定：不随机、不抖动
	p.volume_db = linear_to_db(clampf(volume, 0.0, 1.0)) + vol_db
	p.play()
	_play_count[name] = int(_play_count.get(name, 0)) + 1


## UI 提示音（悬停）：音量固定压得很低，音高不抖。
func hover() -> void:
	play("ui_hover", -24.0)


## 按技能特效名播放对应音效（与 CCard.fx_for_type / 卡面 fx 字段一一对应）。
## 名称本身就是文件名，只有历史遗留的 "magic" 需要折到 "play"。
func play_fx(fx: String, vol_db: float = 0.0) -> void:
	if fx == "":
		return
	play("play" if fx == "magic" else fx, vol_db)
