class_name CardView
extends Control
## 卡牌控件 —— 2.5D 伪 3D 渲染 + 陀螺仪感应闪卡
## ------------------------------------------------------------------
## · 弹簧阻尼倾斜：鼠标/陀螺仪驱动，带物理回弹，不生硬
## · Billboard 朝向镜头：卡面反向视差补偿，倾斜时卡面始终「看向」玩家
## · 悬浮待机：手牌轻微呼吸浮动，悬停抬升 + 动态投影
## · foil = true：斜向流光 + 星光粒子（闪卡）
## · 内置演出：anim_enter / anim_lunge / anim_shake / anim_flash / anim_die

signal card_pressed(card: CCard)
signal card_right_pressed(card: CCard)
signal card_hovered(card: CCard)
signal card_unhovered(card: CCard)
signal skill_pressed(card: CCard)
signal drag_started(card: CCard)
signal drag_moved(card: CCard, global_pos: Vector2)
signal drag_dropped(card: CCard, global_pos: Vector2)
## 拖拽被强制取消（源卡在拖拽途中被销毁）。只用于清理幽灵卡，**不代表落牌**。
signal drag_cancelled(card: CCard)

const CARD_W := 176.0
const CARD_H := 312.0
const MINI_W := 58.0
const MINI_H := 103.0

## 全局开关（设置面板可关掉陀螺仪 / 特效）
static var gyro_enabled := true
static var effects_enabled := true
## 【★ 测试训练场专用开关】闪卡（foil）流光总闸。
## 用户要求：在 SheFuDev 上先**临时关掉所有卡牌的闪卡特效**，恢复普通卡牌样式，
## 方便专注核对卡面本身。★ 只关「闪卡流光」这一层，悬停 / 选中 / 被瞄准 / 冷却 /
## 起乩等**交互动效一律不动** —— 所以不能复用 effects_enabled（那是全量总闸）。
## 正式版保持 true。
static var foil_enabled := true
## 【★ 测试训练场专用开关】伪 3D 视差总闸（"陀螺仪特效"那一套）。
##
## 【为什么需要】用户反馈「卡牌选中时叠加的金色闪光陀螺仪特效，和底层卡牌本体
## 图层重叠，看起来像两张卡叠在一起」。根因不是真有两张卡，而是这套视差机制：
##   · `_art2`（底层描边色块）故意偏移 (3,5) 伪造纸牌厚度；
##   · `_art`（主卡面）放大 1.06 + billboard 反向补偿 `-total.x*7, -total.y*5`
##     来「保住正对镜头」。
## 但 1.06 的放大余量只有 3.8~4.6px（手牌卡宽 126~152px），**小于 7px 的平移量** ——
## 于是主卡面平移后露出底层 `_art2` 的边缘，视觉上就是「卡里还嵌着一张错位的卡」。
##
## 关掉它 = 恢复「普通卡牌」：不倾斜、不视差、不 billboard 平移，卡面老老实实
## 铺满。★ 只关这一层：悬停抬升 / 选中 / 被瞄准 / 冷却 / 起乩等**交互动效一律不动**。
## 正式版保持 true。
static var pseudo3d_enabled := true

## 【★ 测试训练场专用开关】「整卡一起动」悬停动效总闸。
##
## 【为什么需要】用户要求（SheFuDev）：鼠标悬停手牌时，让**这张卡的全部**一起动，
## 而不是只有卡面/局部动。关掉伪 3D（pseudo3d_enabled=false）后，卡面已经归位、
## 不再自己倾斜；但 `self`（整卡）在悬停时仍只有「上浮 + 等比放大 + 把扇形角度
## 摆正」三件事 —— 观感偏静态。
##
## 打开后（Dev 版），悬停时**整个 CardView 作为一个刚体**动：
##   · 整卡跟随鼠标做**双轴旋转**（`rotation` 叠鼠标倾角，左右倾 + 用 scale.x 压
##     等效前后倾）；
##   · 整卡在基准放大上再叠一层**呼吸脉动**（轻微，肉眼可见但不晃眼）；
##   · 抬起 / 摆正 / 置顶照旧。
##
## ★ 只影响 `hover_lift` 的手牌；场上卡 / 卡牌库卡不受影响。正式版保持 false，
##   「只改 SheFuDev」这条铁律由此开关 + `apply_dev_visuals()` 一起兜住。
static var whole_card_hover := false

static var _tex_cache: Dictionary = {}

## 逐帧绘制用的字体缓存（SystemFont 每次 new 都很贵，冷却遮罩是逐帧画的）
static var _draw_font: Font = null
## 兼容旧引用（真身已迁到 UITheme.font()，见其注释）


## _draw() 里画文字统一走这里；字体进程内只建一次（见 UITheme.font 的说明）
static func draw_font() -> Font:
	return UITheme.font()

var card: CCard
var compact: bool = false          ## 紧凑模式（对方场面用小卡）
var selectable: bool = true
var selected: bool = false
var foil: bool = false             ## 闪卡流光（单一方向柔光扫过）
var highlight_new: bool = false    ## 刚获得的牌高亮
## 被「指向性道具」瞄准中：卡面四角亮出准星并整体泛青蓝光。
## 【为什么独立于 selected】selected 是「我选中了它、准备行动」，
## target_glow 是「对方的牌正被我瞄准」——两者会同时出现在一张卡上（选了自己的天卡再瞄对方的卡），
## 复用同一个开关会互相覆盖。
var target_glow: bool = false
var idle_float: bool = false       ## 待机呼吸浮动（手牌用）
var board_mode: bool = false       ## 场上模式：祇/点数徽标 + 主动技能图标 + 冷却遮罩
var draggable: bool = false        ## 可拖拽（手牌）
var dragging: bool = false         ## 正在被拖拽

## ---- 手牌悬停（KARDS 手感）：抬升 + 放大 + 置顶 ----
var hover_lift: bool = false       ## 悬停时是否抬升（只有手牌开启）
var home_pos := Vector2.ZERO       ## 扇形里的原始位置（悬停结束要还原）
var home_rot := 0.0                ## 扇形里的原始角度
var home_z := 0                    ## 扇形里的原始层级
var home_scale := Vector2.ONE      ## 扇形里的原始缩放（Y 轴向心倾斜 → 两侧横向压窄）
var _lift_t := 0.0                 ## 0..1 悬停抬升进度（弹簧）

## ---- 冷却视觉 ----
var cd_cur: int = 0                ## 剩余冷却回合
var cd_max: int = 1                ## 冷却总回合数
var _glow_t := 0.0                 ## 冷却结束的四边外发光，1 -> 0 衰减

var _hover := false
var _zone_seen := false            ## 指针是否确实进过悬停区（无头测试的守卫，见 _process）
var _dbg_enter := 0                ## 诊断：真实 mouse_entered 派发次数
var _dbg_exit := 0                 ## 诊断：真实 mouse_exited 派发次数
const LIFT_PX := 76.0              ## 手牌悬停上浮高度（KARDS 手感：要一眼看出来）
var _press := false
var _press_pos := Vector2.ZERO
var _suppress_click := false
var _tilt := Vector2.ZERO          ## 当前倾角（-1..1）
var _tilt_vel := Vector2.ZERO      ## 弹簧速度
var _tilt_goal := Vector2.ZERO
var _gyro := Vector2.ZERO
var _foil_t := 0.0
var _idle_t := 0.0
var _idle_phase := 0.0
var _lift := 0.0                   ## 悬停抬升量 0..1（弹簧）
var _lift_vel := 0.0
var _want_size := Vector2.ZERO     ## 入树前预设的尺寸
var _built := false
var _face_base_pos := Vector2.ZERO ## 动画层基准位移（lunge 用）
var _last_drag_gpos := Vector2.ZERO ## 拖拽最后已知的全局鼠标位置（离树兜底用）

## 【拖拽单例】全场景同一时刻只允许一张卡处于拖拽态。
## 之前 BattleScreen 的 _ghost 是普通成员变量：一旦中途重开拖拽（或拖拽源卡在
## 释放前被刷新销毁），_ghost 会被覆盖 / 永远等不到 drag_dropped，
## 于是那张半透明的「残影卡」就永久留在屏幕上（实测过这个 bug）。
static var active_drag: CardView = null

# 子节点
var _face: Control
var _art: TextureRect
var _art2: TextureRect             ## 视差底层（描边填充）
## `_art2` 的静态基准偏移（由 _layout() 按卡大小算好）。伪 3D 关闭时用它归位，
## 不再硬编码 (3,5) —— compact 卡是 (2,3)，写死会在大卡/小卡之间漂。
var _art2_base := Vector2.ZERO
var _thick: Control                ## 厚度层：边缘暗边 + 左上高光 + 底厚边（2.5D 伪厚度）
var _overlay: Control
var _glow_layer: Control           ## 冷却结束的外发光层（不裁剪，画在卡面之外）
var _z_backup: int = 0             ## 发光期间临时抬升的层级，结束要还回去
var _name_lbl: Label
var _sub_lbl: Label
var _tier_lbl: Label
var _stat_lbl: Label
var _hint_lbl: Label
var _hp_bar: ProgressBar
var _cd_lbl: Label
var _state_lbl: Label
var _temp_lbl: Label               ## 临时单位计时（三清铃召唤的【僵尸】）
var _badge_l: Control              ## 左下徽标（祇/体）
var _badge_r: Control              ## 右下徽标（击/气伤）
var _skill_btn: Control            ## 主动技能图标（冷却转圈）
var _hit_btn: Button               ## 铺满全卡的点击层，同时也是悬停信号的唯一来源


static func texture_for(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[path] = t
	return t


static func clear_texture_cache() -> void:
	_tex_cache.clear()


## 竖直渐变纹理缓存（key = 颜色+两端 alpha 的组合）——
## 【★ 为什么需要它：修「条形码阴影」】旧版暗角/厚度用「for i in 46: draw_rect(1.4px)」
## 一条条半透明横条去模拟渐变。横条 y 是小数、彼此没对齐像素，相邻条又只有 1.4px 高，
## 叠加起来就是**摩尔纹 → 一条条竖直/水平的「条形码」**。
## 现在改成**一张真渐变纹理一次 draw_texture_rect**：GPU 双线性插值出连续渐变，
## 彻底没有离散条带。（GradientTexture2D 内部是 256px 渐变，够平滑。）
## 【为什么委托给 UITheme】BattleScreen / DevPanel 等也要用同一张渐变，
## 缓存放 UITheme 一处，避免每个类各存一份、还容易拼错参数。
static func vgrad(col: Color, a_top: float, a_bot: float) -> GradientTexture2D:
	return UITheme.vgrad(col, a_top, a_bot)


## 【★ 修「条形码阴影」· 闪卡光带】竖直金带「中间亮、两侧柔」的水平渐变（1×256，横向 fill）。
## 旧版用 36 条离散 `draw_rect` 堆这个衰减 → 条宽只有 1~2px 又没对齐像素 = 竖条摩尔纹。
## 一次渐变纹理绘制，GPU 插值连续。
static var _sweep_grad_cache: GradientTexture2D = null
static func _make_sweep_grad() -> GradientTexture2D:
	var g := Gradient.new()
	# 0 → 0.5 → 1：两侧全透，中心最亮（0.36），平方衰减在渐变里用 3 个停靠点近似
	g.set_color(0, Color(1.0, 0.87, 0.50, 0.0))
	g.set_color(1, Color(1.0, 0.87, 0.50, 0.0))
	g.add_point(0.28, Color(1.0, 0.87, 0.50, 0.09))
	g.add_point(0.5, Color(1.0, 0.87, 0.50, 0.36))
	g.add_point(0.72, Color(1.0, 0.87, 0.50, 0.09))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 1
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(1.0, 0.0)
	_sweep_grad_cache = t
	return t


func _init() -> void:
	# 【关键】CardView 自己是 Control，但卡面上铺着一个**铺满全卡的 Button**（_hit_btn）
	# 专门用于点击。鼠标命中的永远是那个 Button，所以 CardView 自身的
	# mouse_entered / mouse_exited **一次都不会触发** —— 这正是「手牌悬停没反应」的根因。
	# 因此：命中的唯一入口交给 _hit_btn（见 _build），自身设为 IGNORE。
	# 注意 `_input()` 是 Node 级回调，与 mouse_filter 无关，拖拽不受影响。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_idle_phase = randf() * TAU


func _ready() -> void:
	_build()
	_built = true
	if _want_size != Vector2.ZERO:
		size = _want_size
		custom_minimum_size = _want_size
	else:
		custom_minimum_size = Vector2(MINI_W if compact else CARD_W, MINI_H if compact else CARD_H)
		size = custom_minimum_size
	pivot_offset = size * 0.5
	_layout()
	# 悬停信号挂在 _hit_btn 上（见 _build 的说明）：它才是真正的鼠标命中目标。
	# 挂在这里是兜底 —— _build 里已经连过，这里只在缺失时补。
	if _hit_btn != null and not _hit_btn.mouse_entered.is_connected(_on_enter):
		_hit_btn.mouse_entered.connect(_on_enter)
		_hit_btn.mouse_exited.connect(_on_exit)
	refresh()
	set_process(true)

func set_compact(v: bool) -> void:
	compact = v
	var sz := _want_size if _want_size != Vector2.ZERO else Vector2(MINI_W if compact else CARD_W, MINI_H if compact else CARD_H)
	_want_size = sz
	if not _built:
		return
	custom_minimum_size = sz
	size = sz
	pivot_offset = size * 0.5
	_layout()
	refresh()


# ==================================================================== 构建
func _build() -> void:
	_face = Control.new()
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.clip_contents = true
	add_child(_face)

	# 底层：阵营色描边（形成"厚度"）
	_art2 = TextureRect.new()
	_art2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art2.modulate = Color(0.28, 0.22, 0.34, 1.0)
	_face.add_child(_art2)

	# 主卡面
	_art = TextureRect.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face.add_child(_art)

	# 厚度层：画在立绘之上，伪造「纸牌边缘厚度」（内阴影 + 顶面高光 + 底面厚边）
	_thick = Control.new()
	_thick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thick.draw.connect(_draw_thickness)
	_face.add_child(_thick)

	# 渐变遮罩 + 流光 + 星光层
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_face.add_child(_overlay)

	# 冷却结束的外发光层：**必须挂在 _face 之外**。
	# _face.clip_contents = true 会把所有溢出卡面的绘制裁掉，
	# 如果发光画在 _overlay 上，「向外发出亮光」就会退化成贴着边的两条暗线。
	_glow_layer = Control.new()
	_glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_layer.draw.connect(_draw_glow)
	add_child(_glow_layer)

	# 文本层
	_name_lbl = UITheme.mk_label("", 15, UITheme.TEXT)
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_name_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_name_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_name_lbl.add_theme_constant_override("shadow_outline_size", 3)
	_name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_face.add_child(_name_lbl)

	_sub_lbl = UITheme.mk_label("", 11, UITheme.GOLD_DIM)
	_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_child(_sub_lbl)

	_tier_lbl = UITheme.mk_label("", 11, UITheme.GOLD)
	_tier_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_face.add_child(_tier_lbl)

	_stat_lbl = UITheme.mk_label("", 12, UITheme.TEXT)
	_stat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_child(_stat_lbl)

	_hint_lbl = UITheme.mk_label("", 10, UITheme.TEXT_DIM)
	_hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_face.add_child(_hint_lbl)

	_hp_bar = ProgressBar.new()
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.show_percentage = false
	_hp_bar.add_theme_stylebox_override("background", UITheme.flat_style(Color(0, 0, 0, 0.6), 3))
	var f := StyleBoxFlat.new()
	f.bg_color = UITheme.QI
	f.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("fill", f)
	_face.add_child(_hp_bar)

	_cd_lbl = UITheme.mk_label("", 13, UITheme.AZURE)
	_cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_face.add_child(_cd_lbl)

	_state_lbl = UITheme.mk_label("", 12, UITheme.CINNABAR)
	_state_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_face.add_child(_state_lbl)

	# 临时单位计时：写在血条下面，用【玉色】跟「封/禁」的蓝红区分开
	_temp_lbl = UITheme.mk_label("", 12, UITheme.JADE)
	_temp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_temp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_face.add_child(_temp_lbl)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(func():
		if _suppress_click:
			_suppress_click = false
			return
		card_pressed.emit(card))
	btn.gui_input.connect(_on_gui_input)
	# 【悬停的唯一信号源】这张 btn 铺满全卡，鼠标命中的永远是它；
	# CardView 自身的 mouse_entered 在它之下永远收不到事件。
	# 所以悬停/离开必须从这里转发出去（这是「悬停没反应」的根因修复）。
	btn.mouse_entered.connect(_on_enter)
	btn.mouse_exited.connect(_on_exit)
	_hit_btn = btn
	add_child(btn)

	# ---- 场上模式覆盖层（徽标 + 技能图标，直接挂在卡牌上，随整体变换） ----
	_badge_l = _make_badge()
	add_child(_badge_l)
	_badge_r = _make_badge()
	add_child(_badge_r)
	var si := SkillIcon.new()
	si.pressed.connect(func(): skill_pressed.emit(card))
	_skill_btn = si
	add_child(_skill_btn)

	_layout()


## 徽标：半透明黑底药丸 + 图标 + 数字
func _make_badge() -> Control:
	var b := Badge.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.visible = false
	return b


## 场上模式开关
func set_board_mode(v: bool) -> void:
	board_mode = v
	if not _built:
		return
	_layout()
	refresh()


## 外部指定尺寸（手牌 / 场面 / 图鉴各用不同尺寸）
func set_size_px(w: float, h: float) -> void:
	_want_size = Vector2(w, h)
	if not _built:
		return
	custom_minimum_size = _want_size
	size = _want_size
	pivot_offset = size * 0.5
	_layout()
	refresh()


func _layout() -> void:
	var w: float = size.x
	var h: float = size.y
	var k: float = h / CARD_H
	_face.size = Vector2(w, h)
	_glow_layer.size = Vector2(w, h)
	_glow_layer.position = Vector2.ZERO
	if compact or h < 150.0:
		_art2.position = Vector2(2, 3)
		_art2_base = Vector2(2, 3)
		_art2.size = Vector2(w, h)
		_art.position = Vector2.ZERO
		_art.size = Vector2(w, h)
		_thick.size = Vector2(w, h)
		_thick.queue_redraw()
		_overlay.size = Vector2(w, h)
		_name_lbl.position = Vector2(3, h - maxf(18.0, h * 0.15))
		_name_lbl.size = Vector2(w - 6, maxf(14.0, h * 0.13))
		_name_lbl.add_theme_font_size_override("font_size", maxi(9, int(h * 0.115)))
		_sub_lbl.visible = false
		_tier_lbl.visible = false
		_stat_lbl.visible = false
		_hint_lbl.visible = false
		_hp_bar.visible = false
		_cd_lbl.visible = false
		_state_lbl.visible = false
		_temp_lbl.visible = false
		return

	_art2.visible = true
	_sub_lbl.visible = true
	_tier_lbl.visible = true
	_stat_lbl.visible = true
	_hint_lbl.visible = true
	_hp_bar.visible = true
	_cd_lbl.visible = true
	_state_lbl.visible = true
	_temp_lbl.visible = true

	var pad: float = 8.0 * k
	var fs_name: int = maxi(11, int(17.0 * k))
	var fs_small: int = maxi(9, int(12.5 * k))
	var fs_hint: int = maxi(8, int(10.5 * k))

	_art2.position = Vector2(3.0 * k, 5.0 * k)
	_art2_base = Vector2(3.0 * k, 5.0 * k)
	_art2.size = Vector2(w, h)
	_art.position = Vector2.ZERO
	_art.size = Vector2(w, h)
	_thick.size = Vector2(w, h)
	_thick.queue_redraw()
	_overlay.size = Vector2(w, h)

	var block_h: float = 100.0 * k
	var y0: float = h - block_h
	_name_lbl.position = Vector2(pad, y0 + 4.0 * k)
	_name_lbl.size = Vector2(w - pad * 2, fs_name * 1.35)
	_name_lbl.add_theme_font_size_override("font_size", fs_name)
	_sub_lbl.position = Vector2(pad, y0 + 30.0 * k)
	_sub_lbl.size = Vector2(w - pad * 2, fs_small * 1.3)
	_sub_lbl.add_theme_font_size_override("font_size", fs_small)
	_tier_lbl.position = Vector2(w - 50.0 * k, 6.0 * k)
	_tier_lbl.size = Vector2(44.0 * k, fs_small * 1.3)
	_tier_lbl.add_theme_font_size_override("font_size", fs_small)
	_stat_lbl.position = Vector2(pad, y0 + 48.0 * k)
	_stat_lbl.size = Vector2(w - pad * 2, fs_small * 1.3)
	_stat_lbl.add_theme_font_size_override("font_size", fs_small)
	_hint_lbl.position = Vector2(pad, y0 + 66.0 * k)
	_hint_lbl.size = Vector2(w - pad * 2, 32.0 * k)
	_hint_lbl.add_theme_font_size_override("font_size", fs_hint)
	_hp_bar.position = Vector2(pad, 8.0 * k)
	_hp_bar.size = Vector2(w - 58.0 * k, maxf(7.0, 9.0 * k))
	_cd_lbl.position = Vector2(w - 42.0 * k, 26.0 * k)
	_cd_lbl.size = Vector2(34.0 * k, fs_small * 1.3)
	_cd_lbl.add_theme_font_size_override("font_size", fs_small)
	_state_lbl.position = Vector2(0, h * 0.40)
	_state_lbl.size = Vector2(w, fs_name * 1.4)
	_state_lbl.add_theme_font_size_override("font_size", fs_name)
	_temp_lbl.position = Vector2(pad, 22.0 * k)
	_temp_lbl.size = Vector2(w - 58.0 * k, fs_small * 1.3)
	_temp_lbl.add_theme_font_size_override("font_size", fs_small)

	# ---- 场上模式：隐藏文字统计，改用图标徽标 ----
	var bd := 34.0 * k            # 徽标高度（旧值 30k 在 232px 的场上卡上只有 22px，看不清）
	_badge_l.position = Vector2(4.0 * k, h - bd - 4.0 * k)
	_badge_l.size = Vector2(w * 0.47, bd)
	_badge_r.position = Vector2(w - w * 0.47 - 4.0 * k, h - bd - 4.0 * k)
	_badge_r.size = Vector2(w * 0.47, bd)
	var sd := 40.0 * k            # 技能图标直径
	_skill_btn.position = Vector2(w - sd - 3.0 * k, h * 0.5 - sd * 0.5)
	_skill_btn.size = Vector2(sd, sd)
	if board_mode:
		_stat_lbl.visible = false
		_hint_lbl.visible = false
		_cd_lbl.visible = false
		_badge_l.visible = true
		_badge_r.visible = true
	else:
		_badge_l.visible = false
		_badge_r.visible = false
		_skill_btn.visible = false


# ==================================================================== 数据刷新
func refresh() -> void:
	if not _built or card == null:
		return
	var col := UITheme.sub_color(card.sub)
	_name_lbl.text = card.name
	_art.texture = texture_for(card.art)
	_art2.texture = _art.texture
	if compact:
		queue_redraw()
		return
	_sub_lbl.text = "%s·%s" % [card.faction, card.sub]
	_sub_lbl.add_theme_color_override("font_color", col)
	_tier_lbl.text = "★".repeat(card.tier)
	_tier_lbl.add_theme_color_override("font_color", UITheme.GOLD)
	if card.is_tian():
		_stat_lbl.text = "祇 %d ｜ 击 %d" % [card.cur_hp if card.on_board else card.max_hp, card.atk]
	else:
		_stat_lbl.text = "体 %d ｜ 击 %d ｜ 气伤 %d" % [
			card.cur_hp if card.on_board else card.max_hp, card.atk, card.atk_qi]
	_stat_lbl.add_theme_color_override("font_color", UITheme.GOLD)

	# 技能提示
	var hint := ""
	if not card.skill_name("active").is_empty():
		hint = "主动·%s" % card.skill_name("active")
	elif not card.skill_name("passive").is_empty():
		hint = "被动·%s" % card.skill_name("passive")
	if card.tier >= 2 and not card.skill_name("on_remove").is_empty():
		hint += "  ｜  下场·%s" % card.skill_name("on_remove")
	_hint_lbl.text = hint

	_hp_bar.visible = card.on_board and not board_mode
	if card.on_board:
		_hp_bar.max_value = maxi(1, card.max_hp)
		_hp_bar.value = clampi(card.cur_hp, 0, card.max_hp)
	# ---- 冷却：读进 cd_cur / cd_max，供 _draw_overlay 画「自下而上褪去」的黑幕 ----
	# cd_max 取「本次冷却的总长」cooldown_span（核心层在进冷却的瞬间写入），
	# 这样黑幕永远从「整张盖满」开始，再随 cd_cur 递减而自下而上褪去。
	# 万一 span 丢了（旧存档/异常路径），退回技能冷却值兜底，绝不让分母为 0。
	cd_cur = 0
	cd_max = 1
	if card.on_board:
		cd_cur = maxi(0, card.cooldown)
		if cd_cur > 0:
			cd_max = maxi(cd_cur, card.cooldown_span)
		else:
			cd_max = maxi(1, card.active_cd())
	# 被冻结/封锁时也走同一套遮罩语义（只是文案不同）
	if cd_cur <= 0 and card.on_board and card.frozen > 0:
		cd_cur = card.frozen
		cd_max = card.frozen
	_cd_lbl.text = ""
	if card.on_board and cd_cur > 0 and not board_mode:
		_cd_lbl.text = "CD%d" % cd_cur

	# ---- 场上模式徽标 ----
	if board_mode and card.on_board:
		var bl := _badge_l as Badge
		var br := _badge_r as Badge
		if card.is_tian():
			bl.set_data("shield", "%d" % maxi(card.cur_hp, 0), UITheme.AZURE)
			bl.tooltip_text = "【祇】%d/%d —— 神佛的生命，归零即被拔除" % [card.cur_hp, card.max_hp]
			br.set_data("swords", "%d" % card.atk, UITheme.GOLD)
			br.tooltip_text = "【击】%d —— 制衡时对对方【天】造成的伤害" % card.atk
		else:
			bl.set_data("heart", "%d" % maxi(card.cur_hp, 0), UITheme.QI)
			bl.tooltip_text = "【体】%d/%d —— 归零即被拔除" % [card.cur_hp, card.max_hp]
			br.set_data("bolt", "%d" % card.atk_qi, UITheme.CINNABAR)
			br.tooltip_text = "【点数】%d —— 袭人时对【人】造成的【气】伤害" % card.atk_qi
		bl.queue_redraw()
		br.queue_redraw()
		# 技能图标
		var si := _skill_btn as SkillIcon
		if card.has_active():
			si.visible = true
			si.cd_cur = cd_cur
			# 图标上的转圈表达「技能自身还剩多久」，与卡面黑幕的分母刻意区分开
			si.cd_max = maxi(cd_cur, maxi(1, card.active_cd()))
			si.tooltip_text = "【%s】%s%s" % [
				card.skill_name("active"),
				"冷却中（剩 %d 回合 / 共 %d 回合）\n" % [cd_cur, maxi(1, card.active_cd())] if cd_cur > 0 else "点击发动\n",
				card.skill_desc("active")]
			si.queue_redraw()
		else:
			si.visible = false
	elif board_mode:
		_badge_l.visible = false
		_badge_r.visible = false
		_skill_btn.visible = false
	_state_lbl.text = ""
	_temp_lbl.text = ""
	_temp_lbl.add_theme_color_override("font_color", UITheme.JADE)
	if card.on_board and card.frozen > 0:
		_state_lbl.text = "封"
		_state_lbl.add_theme_color_override("font_color", UITheme.AZURE)
	elif card.sealed > 0:
		_state_lbl.text = "禁"
		_state_lbl.add_theme_color_override("font_color", UITheme.CINNABAR)
	# 临时单位（三清铃的【僵尸】）：把剩余回合写在卡面上，
	# 否则玩家只会看到三张【僵尸】「莫名其妙自己没了」。
	if card.on_board and card.temp_turns > 0:
		_temp_lbl.text = "临时 · 余 %d 回合" % card.temp_turns
	elif card.on_board and card.passive_sealed > 0:
		_temp_lbl.text = "被动封印"
		_temp_lbl.add_theme_color_override("font_color", UITheme.GOLD_DIM)
	queue_redraw()


func set_card(c: CCard, p_compact: bool = false) -> void:
	card = c
	if p_compact != compact:
		compact = p_compact
		var sz := Vector2(MINI_W, MINI_H) if compact else Vector2(CARD_W, CARD_H)
		if _want_size == Vector2.ZERO:
			_want_size = sz
	if not _built:
		return
	if _want_size == Vector2.ZERO:
		_want_size = Vector2(MINI_W if compact else CARD_W, MINI_H if compact else CARD_H)
	custom_minimum_size = _want_size
	size = _want_size
	pivot_offset = size * 0.5
	_layout()
	refresh()


func set_selected(v: bool) -> void:
	selected = v
	set_process(true)
	queue_redraw()


## 瞄准高亮开关（指向性道具划过时点亮）
func set_target_glow(v: bool) -> void:
	if target_glow == v:
		return
	target_glow = v
	set_process(true)
	queue_redraw()


## 记录这张卡在扇形手牌里的「原位」，悬停抬升后要还原回来
func set_home(p: Vector2, rot: float, z: int, sc: Vector2 = Vector2.ONE) -> void:
	home_pos = p
	home_rot = rot
	home_z = z
	home_scale = sc


## 冷却刚刚结束：四边向外发光提示（同时把黑幕清掉）
func play_cd_ready() -> void:
	cd_cur = 0
	_glow_t = 1.0
	set_process(true)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()
	if _glow_layer != null:
		# 发光期间抬到同排卡牌之上，否则左右邻卡会把它溢出的光盖住
		if z_index < 5:
			_z_backup = z_index
			z_index = 5
		_glow_layer.queue_redraw()


## 由 UI 层告知「上一次刷新时这张卡的剩余冷却」，用于识别「冷却刚刚结束」的瞬间。
## cd_cur / cd_max 已由 refresh() 从卡牌数据读好，这里只负责触发发光演出。
func note_cooldown(prev: int) -> void:
	if prev > 0 and cd_cur <= 0:
		play_cd_ready()


## 悬停抬升的目标位移（KARDS 式：整张牌往上升起并摆正）
func _lift_offset() -> Vector2:
	if not hover_lift:
		return Vector2.ZERO
	return Vector2(0, -LIFT_PX) * _lift_t


# ==================================================================== 演出动画
func play_gain_anim() -> void:
	if not effects_enabled:
		return
	modulate = Color(2.0, 1.8, 1.2, 1.0)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.45)


## 入场：缩小 + 旋转 + 透明 → 弹性展开（容器布局安全：不动 position）
## rot_target：落位角度（扇形手牌要停在自己的扇角上，而不是一律摆正）
## 发牌挤压（squash & stretch）：先横向膨胀、纵向压扁（像被「拍」进桌面），
## 再反向过冲、最后弹回原位 —— 模拟纸牌有质量、有弹性的物理落位，不再轻飘飘平移。
func anim_enter(delay: float = 0.0, rot_target: float = 0.0) -> void:
	if not effects_enabled or not _built:
		return
	scale = home_scale * Vector2(0.30, 0.30)
	rotation = rot_target - 0.18
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(false)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(self, "modulate:a", 1.0, 0.10)
	tw.tween_property(self, "scale", home_scale * Vector2(1.18, 0.70), 0.13).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", home_scale * Vector2(0.92, 1.06), 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "scale", home_scale, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw2 := create_tween()
	tw2.set_parallel(false)
	if delay > 0.0:
		tw2.tween_interval(delay + 0.10)
	tw2.tween_property(self, "rotation", rot_target, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 攻击前冲：卡面层朝方向猛冲后弹回（返回 tween 供 await）
func anim_lunge(dir: Vector2) -> Tween:
	var tw := create_tween()
	if not effects_enabled:
		return tw
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.UP
	tw.tween_property(_face, "position", _face_base_pos + d * 26.0, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_face, "position", _face_base_pos, 0.34).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	return tw


## 受击抖动 + 红闪
func anim_shake() -> void:
	if not effects_enabled:
		return
	var tw := create_tween()
	var steps := 6
	for i in steps:
		var off := Vector2((5.0 if i % 2 == 0 else -5.0) * (1.0 - float(i) / steps), 0)
		tw.tween_property(_face, "position", _face_base_pos + off, 0.04)
	tw.tween_property(_face, "position", _face_base_pos, 0.08)
	var tw2 := create_tween()
	_face.modulate = Color(2.2, 0.7, 0.7, 1.0)
	tw2.tween_property(_face, "modulate", Color.WHITE, 0.4)


## 金色闪光（合成 / 治疗 / 增益）
func anim_flash(col: Color = Color(1.9, 1.6, 0.9, 1.0)) -> void:
	if not effects_enabled:
		return
	_face.modulate = col
	var tw := create_tween()
	tw.tween_property(_face, "modulate", Color.WHITE, 0.5)


## 施法演出：弹性放大脉冲 + 卡面染色闪光 + 技能图标旋转一圈
func anim_cast(fx_color: Color = UITheme.GOLD) -> void:
	if not effects_enabled:
		return
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.16, 1.16), 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _face:
		_face.modulate = Color(
			minf(2.2, 0.55 + fx_color.r * 1.7),
			minf(2.2, 0.55 + fx_color.g * 1.7),
			minf(2.2, 0.55 + fx_color.b * 1.7), 1.0)
		var tw2 := create_tween()
		tw2.tween_property(_face, "modulate", Color.WHITE, 0.5)
	var si := _skill_btn as SkillIcon
	if si != null:
		si.cast_spin()


## 离场：缩小 + 微旋 + 淡出（之后由调用方移除节点）
func anim_die() -> Tween:
	var tw := create_tween()
	if effects_enabled:
		var t2 := tw.parallel()
		t2.tween_property(self, "scale", Vector2(0.2, 0.2), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t2.tween_property(self, "rotation", 0.15, 0.32)
		t2.tween_property(self, "modulate:a", 0.0, 0.30)
	return tw


# ==================================================================== 绘制
func _draw() -> void:
	var w := size.x
	var h := size.y
	var col := UITheme.sub_color(card.sub) if card else UITheme.GOLD_DIM
	var r := 6.0 if compact else 10.0

	# 动态投影：随倾角反向偏移，随离地高度变大变淡变扁 —— 伪 3D 的关键
	# 离地高度 = max(通用 hover 弹簧, 手牌抬升弹簧)：手牌被「拿起」上浮时，
	# 投影要明显放大、变淡、下移 —— 就像卡牌真的离桌面越来越远。
	var ground := maxf(_lift, _lift_t)
	var sh_off := Vector2(3.0 - _tilt.x * 7.0, 6.0 + ground * 16.0 - _tilt.y * 4.0)
	var sh_alpha := clampf(0.52 - ground * 0.24, 0.06, 0.7)
	var sh_scale := Vector2(1.0 + ground * 0.20, 0.16 + ground * 0.06)
	draw_set_transform(sh_off + Vector2(w * 0.5, h), 0.0, sh_scale)
	draw_circle(Vector2.ZERO, w * 0.52, Color(0, 0, 0, sh_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 卡体底色 + 双重描边（外圈阵营色 + 内圈细金线）
	var bw := 2.0 if compact else 2.5
	if selected:
		col = UITheme.GOLD
		bw = 3.5
	if _hover and selectable:
		col = col.lerp(Color.WHITE, 0.35)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0, 0, 0, 0.85), true)
	_draw_round_border(Rect2(Vector2(1, 1), Vector2(w - 2, h - 2)), col, bw, r)
	if not compact:
		var inner := UITheme.GOLD
		inner.a = 0.28 + _lift * 0.25
		_draw_round_border(Rect2(Vector2(4, 4), Vector2(w - 8, h - 8)), inner, 1.0, r - 2.0)

	# 选中呼吸光圈
	if selected:
		var pulse := 0.20 + 0.12 * sin(_idle_t * 5.0)
		_draw_round_border(Rect2(Vector2(-2, -2), Vector2(w + 4, h + 4)),
			Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, pulse), 4.0, r + 2.0)

	# 被指向性道具瞄准：青蓝准星 + 四角括号
	# 【为什么用青蓝】金色已经背了「选中 / 阵营 / 阶数」三件事，
	# 再用金色就分不出「我要打它」和「我选了它」。青蓝在这套配色里只此一处。
	if target_glow:
		var az := UITheme.AZURE
		var pl := 0.55 + 0.35 * sin(_idle_t * 7.0)
		_draw_round_border(Rect2(Vector2(-3, -3), Vector2(w + 6, h + 6)),
			Color(az.r, az.g, az.b, pl), 3.0, r + 3.0)
		var arm: float = maxf(14.0, w * 0.22)
		var th: float = 3.0
		var cc := Color(az.r, az.g, az.b, 0.95)
		# 左上
		draw_rect(Rect2(Vector2(-4, -4), Vector2(arm, th)), cc, true)
		draw_rect(Rect2(Vector2(-4, -4), Vector2(th, arm)), cc, true)
		# 右上
		draw_rect(Rect2(Vector2(w + 4 - arm, -4), Vector2(arm, th)), cc, true)
		draw_rect(Rect2(Vector2(w + 4 - th, -4), Vector2(th, arm)), cc, true)
		# 左下
		draw_rect(Rect2(Vector2(-4, h + 4 - th), Vector2(arm, th)), cc, true)
		draw_rect(Rect2(Vector2(-4, h + 4 - arm), Vector2(th, arm)), cc, true)
		# 右下
		draw_rect(Rect2(Vector2(w + 4 - arm, h + 4 - th), Vector2(arm, th)), cc, true)
		draw_rect(Rect2(Vector2(w + 4 - th, h + 4 - arm), Vector2(th, arm)), cc, true)


## 厚度层：伪造纸牌边缘厚度（2.5D 伪 3D）
## 画在立绘之上、渐变遮罩之下。统一左上光源：
## · 右侧 + 底部 = 厚度侧面（暗，越靠边越深，模拟 Z 轴挤压出的纸牌侧面）
## · 左侧 + 顶部 = 顶面/侧面受光（一条高光边，模拟被光照亮的纸牌棱）
## · 底部一条窄厚边 = 纸牌底面，下缘带一丝反光
##
## 【★ 修「毛刺边缘 + 条形码阴影」】旧版右侧/底部暗边用 7 段离散色块、每段宽
## `ew/steps + 0.7`（那个 +0.7 是**故意重叠**想遮掩段间缝）。但段间重叠 = 同一处
## 被压暗两次 → **明显的阶梯状条纹**（用户看到的「毛刺」）；y 又是小数、没对齐像素
## → 边界发毛。现在改用**一张真渐变纹理**横向铺开：一次绘制、双线性插值、连续无条带，
## 并把边条对齐到整数像素（`floor`），彻底消除锯齿。
func _draw_thickness() -> void:
	if _thick == null:
		return
	var w := _thick.size.x
	var h := _thick.size.y
	if w <= 2.0 or h <= 2.0:
		return
	var ew := clampf(minf(w, h) * 0.045, 3.0, 7.0)   # 边缘厚度宽度（随卡大小微调）

	# ① 右侧暗边：自外（实）向内（透）的连续渐变（left→right alpha 0.46→0）
	var grad_r := vgrad(Color.BLACK, 0.46, 0.0)
	_thick.draw_texture_rect(grad_r, Rect2(w - ew, 0.0, ew, h), false)

	# ② 底部暗边：自下（实）向上（透）的连续渐变
	var grad_b := vgrad(Color.BLACK, 0.0, 0.50)
	_thick.draw_texture_rect(grad_b, Rect2(0.0, h - ew, w, ew), false)

	# ③ 底部厚边（Z 轴底面）+ 下缘微反光
	_thick.draw_rect(Rect2(0.0, floorf(h - 2.6), w, 2.6), Color(0.0, 0.0, 0.0, 0.38), true)
	_thick.draw_line(Vector2(0.0, floorf(h) - 0.5), Vector2(w, floorf(h) - 0.5),
		Color(1.0, 1.0, 1.0, 0.10), 1.0, true)
	# ④ 左上高光（顶面/左侧面受光）
	_thick.draw_line(Vector2(0.0, 0.5), Vector2(w, 0.5),
		Color(1.0, 1.0, 1.0, 0.30), 1.5, true)


## 圆角矩形描边。
## 【★ 修「毛刺边缘」】旧版直边 `draw_line` 没开抗锯齿、圆角只用 6 段 `draw_arc`
## → 圆角是「六边形折线」、直边端点是硬切 = 肉眼可见的毛刺/台阶。
## 现在：① 所有 draw_line 打开 antialiased；② 圆角段数按半径自适应（越多越圆滑，
## 但小卡不必浪费），最少 10 段；③ 端点用 ROUND 才不会有方头接缝。
func _draw_round_border(rect: Rect2, col: Color, width: float, r: float) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.position.x + rect.size.x
	var y1 := rect.position.y + rect.size.y
	# 圆角段数：随半径增加，钳在 10~24 之间（半径 10 的卡角 10~16 段已足够圆滑）
	var seg := clampi(int(r * 1.6) + 8, 10, 24)
	draw_line(Vector2(x0 + r, y0), Vector2(x1 - r, y0), col, width, true)
	draw_line(Vector2(x0 + r, y1), Vector2(x1 - r, y1), col, width, true)
	draw_line(Vector2(x0, y0 + r), Vector2(x0, y1 - r), col, width, true)
	draw_line(Vector2(x1, y0 + r), Vector2(x1, y1 - r), col, width, true)
	draw_arc(Vector2(x0 + r, y0 + r), r, PI, PI * 1.5, seg, col, width, true)
	draw_arc(Vector2(x1 - r, y0 + r), r, PI * 1.5, TAU, seg, col, width, true)
	draw_arc(Vector2(x1 - r, y1 - r), r, 0, PI * 0.5, seg, col, width, true)
	draw_arc(Vector2(x0 + r, y1 - r), r, PI * 0.5, PI, seg, col, width, true)


func _draw_overlay() -> void:
	var w := _overlay.size.x
	var h := _overlay.size.y
	# ---------- 上下暗角（渐变遮罩）----------
	# 【★ 修「条形码阴影」】旧版用 46 条 / 22 条 1.4px 半透明横条去堆渐变：
	# 横条高度（1.4）不是整数、y 又是小数，条与条之间没对齐像素 →
	# 半透明叠加出**摩尔纹条纹**，正是用户看到的「条形码阴影」。
	# 现在改成**每侧一张真渐变纹理、一次绘制**：GPU 双线性插值，连续无条带。
	# 底：自下沿（浓 0.86）向上（透 0）渐隐，高 46px
	_overlay.draw_texture_rect(vgrad(Color(0.02, 0.015, 0.04), 0.0, 0.86),
		Rect2(0.0, floorf(h - 46.0), w, 46.0), false)
	# 顶：自上沿（浓 0.55）向下（透 0）渐隐，高 22px
	_overlay.draw_texture_rect(vgrad(Color(0.02, 0.015, 0.04), 0.55, 0.0),
		Rect2(0.0, 0.0, w, 22.0), false)
	# 中央分隔金线（对齐半像素 → 1px 实线不糊）
	var col := UITheme.sub_color(card.sub) if card else UITheme.GOLD
	col.a = 0.55
	_overlay.draw_line(Vector2(10, floorf(h - 112.0) + 0.5),
		Vector2(w - 10, floorf(h - 112.0) + 0.5), col, 1.0, true)

	# ---------- 闪卡流光：全卡唯一光效 =「一道竖直金带 · 自左向右扫描」 ----------
	# 需求：把所有花哨的斜向/多方向闪光统一掉，只留这一种。
	# 竖直 = 光带垂直于卡面上下贯通；横向扫描 = 自左向右匀速掠过。
	# 旧版峰值 alpha 只有 0.085、还叠了多条斜带与星光粒子，既看不清又刺眼。
	if foil and foil_enabled and effects_enabled and _face and w > 4.0:
		var period := 2.4
		var kk := fmod(_foil_t, period) / period
		var cx := -w * 0.40 + kk * (w * 1.80)      # 光带中心：从卡外扫到卡外，不留停顿感
		var half := w * 0.17                        # 光带半宽
		# 【★ 修「条形码阴影」】旧版用 36 条离散竖条 `draw_rect(step_w)` 去堆「中间亮、两侧柔」的
		# 光带：条宽 = 2*half/36 ≈ 1~2px、x 又是小数，条与条之间重叠/缝隙 → 竖条摩尔纹。
		# 现在改成**一次水平渐变纹理**（中心不透明 → 两侧全透），GPU 插值无条带。
		var grad := _sweep_grad_cache
		if grad == null:
			grad = _make_sweep_grad()
		_overlay.draw_texture_rect(grad, Rect2(cx - half, 0.0, half * 2.0, h), false)
		# 金带核心高光：一道更亮的竖线，读起来才是「金光」而不是一块黄雾
		if cx > -4.0 and cx < w + 4.0:
			_overlay.draw_rect(Rect2(cx - 1.2, 0.0, 2.4, h),
				Color(1.0, 0.96, 0.80, 0.30), true)
		# 上下端收边：让光带看起来是「扫过」而非「贴了一条黄条」
		var cap := h * 0.10
		_overlay.draw_rect(Rect2(cx - half, 0.0, half * 2.0, cap),
			Color(0.02, 0.015, 0.04, 0.30), true)
		_overlay.draw_rect(Rect2(cx - half, h - cap, half * 2.0, cap),
			Color(0.02, 0.015, 0.04, 0.30), true)

	# ---------- 冷却黑幕：用完即整张压暗，随后「自下而上」褪去 ----------
	if cd_cur > 0 and cd_max > 0:
		var frac := clampf(float(cd_cur) / float(cd_max), 0.0, 1.0)
		var cut := h * frac                                # 黑幕下沿（随冷却向上退）
		_overlay.draw_rect(Rect2(0, 0, w, cut), Color(0.03, 0.03, 0.05, 0.62), true)
		# 下沿的「融化」渐变：让边界不是一条硬线
		# 【★ 修「条形码阴影」】旧版 18 条 1.4px 横条堆渐变 → 未对齐像素 + 半透明叠加 = 摩尔纹。
		# 现在一张竖直渐变纹理（浓 → 透）一次绘制。
		var fade := minf(26.0, cut)
		_overlay.draw_texture_rect(vgrad(Color(0.03, 0.03, 0.05), 0.62 * 0.9, 0.0),
			Rect2(0.0, cut - fade, w, fade), false)
		# 边界处一道冷光，提示「正在恢复」
		_overlay.draw_line(Vector2(2, cut), Vector2(w - 2, cut),
			Color(0.62, 0.78, 1.0, 0.5), 1.4, true)
		# 剩余回合数
		var f := CardView.draw_font()
		var fs := maxi(14, int(h * 0.11))
		_overlay.draw_string(f, Vector2(0, cut - 10.0), "⟳ %d" % cd_cur,
			HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.85, 0.92, 1.0, 0.92))

	# 冷却结束的第一瞬：卡面整体"过曝"一下，然后迅速收掉。
	# 这一层走 _overlay（被 _face 裁切），只在卡内闪；溢出的部分交给 _draw_glow。
	if _glow_t > 0.0:
		var fl: float = pow(clampf(_glow_t, 0.0, 1.0), 3.0)
		_overlay.draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.98, 0.88, 0.38 * fl), true)

	# 选中高亮
	if selected:
		_overlay.draw_rect(Rect2(0, 0, w, h), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.10), true)


## 冷却结束：卡牌四边向外发亮。
## 画在 _glow_layer 上（_face 的兄弟节点、不裁剪），坐标可以自由取负值，
## 所以光晕能真正溢到卡面之外 —— 这才是玩家要的「四边向外发出亮光」。
##
## 【尺寸单位】这里一律用**屏幕像素**，不乘 k。
## 光是「发射物」，不是卡面装饰：场面卡只有手牌的一半大，
## 若按 k 缩放，场面卡的发光会缩到 3px，玩家根本看不见（踩过这个坑）。
func _draw_glow() -> void:
	if _glow_layer == null or _glow_t <= 0.0:
		return
	var w: float = _glow_layer.size.x
	var h: float = _glow_layer.size.y
	if w <= 1.0 or h <= 1.0:
		return
	var t: float = clampf(_glow_t, 0.0, 1.0)
	var fade: float = t * t                       # 亮度包络：起手最亮，末端快速收
	var reach: float = 8.0 + 30.0 * (1.0 - t)     # 光晕外推距离（px）

	# ---- ① 外层泛光：由外向内一层层叠，替代真高斯模糊 ----
	var steps := 10
	var prev := 0.0
	for i in steps:
		var u: float = float(i + 1) / float(steps)
		var a: float = 0.17 * fade * (1.0 - u) * (1.0 - u)
		if a <= 0.004:
			continue
		var o: float = reach * u
		_glow_layer.draw_rect(Rect2(-o, -o, w + o * 2.0, h + o * 2.0),
			Color(1.0, 0.90, 0.60, a), true)
		prev = o

	# ---- ② 内层暖光：贴近卡边的一圈，让光"贴着"卡出来 ----
	var near := maxf(prev * 0.30, 3.0)
	for i in 5:
		var u: float = float(i + 1) / 5.0
		var a: float = 0.20 * fade * (1.0 - u)
		var o: float = near * u
		_glow_layer.draw_rect(Rect2(-o, -o, w + o * 2.0, h + o * 2.0),
			Color(1.0, 0.97, 0.82, a), true)

	# ---- ③ 四边亮条：光源本体，明确"这条边在发光" ----
	var core := Color(1.0, 0.98, 0.88, fade)
	var lw: float = 3.0
	_glow_layer.draw_line(Vector2(-1, 0), Vector2(w + 1, 0), core, lw, true)
	_glow_layer.draw_line(Vector2(-1, h), Vector2(w + 1, h), core, lw, true)
	_glow_layer.draw_line(Vector2(0, -1), Vector2(0, h + 1), core, lw, true)
	_glow_layer.draw_line(Vector2(w, -1), Vector2(w, h + 1), core, lw, true)

	# ---- ④ 四角闪光：让"亮"聚在角上，视觉更像一次爆发 ----
	var c_len: float = minf(34.0, minf(w, h) * 0.38)
	var c_col := Color(1.0, 1.0, 0.94, fade)
	var corners := [
		[Vector2(0, 0), Vector2(1, 1)],
		[Vector2(w, 0), Vector2(-1, 1)],
		[Vector2(0, h), Vector2(1, -1)],
		[Vector2(w, h), Vector2(-1, -1)],
	]
	for c in corners:
		var p: Vector2 = c[0]
		var d: Vector2 = c[1]
		_glow_layer.draw_line(p, p + Vector2(d.x * c_len, 0), c_col, 3.6, true)
		_glow_layer.draw_line(p, p + Vector2(0, d.y * c_len), c_col, 3.6, true)


# ==================================================================== 拖拽
## 拖拽在 _input 层处理：Button 只负责「点击」，一旦移动超过阈值就升级为拖拽，
## 并吃掉后续事件，避免拖完手一松又被判定成「点击选中」。
##
## 【铁律】松开鼠标这一下必须终结拖拽，且**不能**被 draggable / selectable /
## is_visible_in_tree() 这些前置条件拦掉 —— 中途任何一次 _refresh() 都会把源卡
## queue_free 掉，如果释放事件因此被丢弃，上层 BattleScreen 就永远等不到
## drag_dropped，那张半透明的拖拽残影会永久留在屏幕上。
func _input(event: InputEvent) -> void:
	if card == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if not draggable or not selectable or not is_visible_in_tree():
				return
			if get_global_rect().has_point(mb.global_position):
				_press = true
				_press_pos = mb.global_position
		else:
			_press = false
			if dragging:
				_finish_drag(mb.global_position)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _press:
		var mm := event as InputEventMouseMotion
		_last_drag_gpos = mm.global_position
		if not dragging:
			if mm.global_position.distance_to(_press_pos) <= 12.0:
				return
			if not draggable or not selectable:
				return
			dragging = true
			active_drag = self
			_suppress_click = true
			_drag_look()
			drag_started.emit(card)
		if dragging:
			drag_moved.emit(card, mm.global_position)
			get_viewport().set_input_as_handled()


## 统一收尾：无论正常释放还是节点被销毁，都走这里
func _finish_drag(gpos: Vector2) -> void:
	if not dragging:
		return
	dragging = false
	if active_drag == self:
		active_drag = null
	_restore_drag_look()
	drag_dropped.emit(card, gpos)


## 兜底：源卡在拖拽途中被 _refresh() 销毁时，通知 BattleScreen 把幽灵卡扫掉。
##
## 【重要】这里**只发「取消」信号，绝不发 drag_dropped**。
## 节点此刻正在被移出场景树，如果走 _finish_drag → drag_dropped →
## BattleScreen._play_card → _after_action → _refresh → _refresh_hand → add_child，
## 就会撞上 "Parent node is busy setting up children, add_child() failed"，
## 手牌会整片建不出来（实测过，整个手牌区变空）。
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and dragging:
		dragging = false
		if active_drag == self:
			active_drag = null
		drag_cancelled.emit(card)


func _drag_look() -> void:
	if _face == null:
		return
	_face.modulate = Color(1.0, 1.0, 1.0, 0.35)
	z_index = 90


func _restore_drag_look() -> void:
	if _face == null:
		return
	_face.modulate = Color.WHITE
	z_index = home_z if hover_lift else 0


# ==================================================================== 交互
func _on_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			card_right_pressed.emit(card)
			accept_event()


func _on_enter() -> void:
	_dbg_enter += 1
	_hover = true
	card_hovered.emit(card)
	if hover_lift:
		# 手牌：抬升 + 置顶交由 _process 的弹簧统一处理（避免和 tween 打架）
		set_process(true)
		# 【★ 手牌悬停音（Dev 版）】用户要求：鼠标掠过手牌区的卡牌时，
		# 播放和右侧按钮悬停经过一样的音效（ui_hover）。
		# 【为什么只给 hover_lift（手牌）】场上卡 / 卡牌库卡共用同一个 CardView，
		# 它们已有各自的交互，加音会变吵；而「掠过手牌」正是用户点名的场景。
		# 【为什么只挂 once per enter】mouse_entered 本身只在进入时发一次，
		# 粘滞悬停逻辑不会重复触发它（退出被挡下时不发 exited，也就没有二次 entered）。
		# 【Dev 门控】whole_card_hover 是 Dev 版才开的开关，顺带作为音效开关 ——
		# 正式版保持 false → 一行音效都不多，符合「只改 SheFuDev」。
		if whole_card_hover:
			UITheme.ui_sound("ui_hover", -22.0)
	else:
		z_index = 40
		if effects_enabled:
			var tw := create_tween()
			tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.16)
	queue_redraw()


func _on_exit() -> void:
	# 【粘滞悬停】手牌抬起时，命中区（_hit_btn 铺满卡面）会被一起带着向上跑。
	# 若光标停在卡片下半部，抬起就会「抽走」光标脚下的命中区 →
	# 触发 mouse_exited → 卡片落回 → 又进入 → 无限抖动，
	# 表现出来就是「悬停忽上忽下 / 像是没生效」。
	# 所以：离开时先看光标是否仍落在「原位矩形」内，是则继续保持悬停。
	if hover_lift and _pointer_in_hover_zone():
		return
	_dbg_exit += 1
	_hover = false
	_zone_seen = false
	_tilt_goal = Vector2.ZERO
	card_unhovered.emit(card)
	if hover_lift:
		set_process(true)
	else:
		z_index = 0
		if effects_enabled:
			var tw := create_tween()
			tw.tween_property(self, "scale", Vector2.ONE, 0.18)
	queue_redraw()


## 悬停判定区 = 「未抬起的原位矩形」∪「当前(可能已抬起)的矩形」，各外扩 12px。
## 取并集是为了让「抬起后光标仍在新位置」与「光标留在原位置」两种情况都算悬停，
## 从根本上消除抬起/落回之间的抖动。
func _hover_zone() -> Rect2:
	var par := get_parent() as CanvasItem
	var base := Vector2.ZERO
	if par != null:
		base = par.get_global_transform().origin
	var home := Rect2(base + home_pos, size).grow(12.0)
	var cur := get_global_rect().grow(12.0)
	return home.merge(cur)


func _pointer_in_hover_zone() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	return _hover_zone().has_point(vp.get_mouse_position())


func _process(delta: float) -> void:
	_idle_t += delta

	# ---------- 鼠标倾角（提前算好，整卡动效要用） ----------
	# 【为什么提到前面】整卡一起动（whole_card_hover）需要把鼠标位置映射到
	# **整卡 rotation/scale**，而这段原本排在悬停抬升之后。提前算，两处共用。
	var mouse_tilt := Vector2.ZERO
	if _hover and is_visible_in_tree():
		var ml := get_local_mouse_position()
		mouse_tilt = Vector2(
			clampf((ml.x / maxf(size.x, 1.0)) * 2.0 - 1.0, -1.0, 1.0),
			clampf((ml.y / maxf(size.y, 1.0)) * 2.0 - 1.0, -1.0, 1.0))

	# ---------- 手牌悬停抬升（KARDS 手感：抬起、摆正、置顶） ----------
	if hover_lift:
		# 兜底落下：光标真的离开「粘滞悬停区」时收尾，防止被粘滞逻辑挡下的那次 exit
		# 让卡片永久悬停在半空。
		# 【守卫】只有「指针确实进过悬停区」之后才有资格落下 ——
		# 无头测试里没有真实鼠标，指针始终在 (0,0)，否则会一进悬停就被立刻清掉。
		if _pointer_in_hover_zone():
			_zone_seen = true
		elif _hover and _zone_seen and not dragging:
			_hover = false
			_zone_seen = false
			card_unhovered.emit(card)
		var goal := 1.0 if (_hover and not dragging) else 0.0
		if goal > 0.0 or _lift_t > 0.001 or _lift_vel > 0.001:
			var lacc := (goal - _lift_t) * 190.0 - _lift_vel * 17.0
			_lift_vel += lacc * delta
			_lift_t += _lift_vel * delta
			if _lift_t < 0.0 and goal <= 0.0:
				_lift_t = 0.0
				_lift_vel = 0.0
			if goal <= 0.0 and _lift_t <= 0.002:
				# 完全落回原位，恢复扇形里的原始姿态/层级
				_lift_t = 0.0
				_lift_vel = 0.0
				if not dragging:
					position = home_pos
					rotation = home_rot
					scale = home_scale
					z_index = home_z
			else:
				_lift_t = clampf(_lift_t, 0.0, 1.15)
				position = home_pos + Vector2(0, -LIFT_PX * _lift_t)
				z_index = 300            # 远高于任何手牌（手牌层级只是 0..n-1 的序号）
				if whole_card_hover:
					# ---------- 【★ 整卡一起动】 ----------
					# 用户要求：悬停时「这张卡的全部」一起动。这里把鼠标位置映射成
					# **整卡刚体**的姿态变化，和 `_face` 的内层视差彻底分开：
					#   · rotation：基准扇形角度摆正后，再叠鼠标左右倾角（跟随鼠标）；
					#   · scale：基准放大 1.18 上再叠「呼吸脉动」+ 鼠标上下倾角造成的
					#     横向压窄（模拟整卡前后俯仰，Control 无 skew 故用 scale.x 等效）；
					#   · 呼吸用 _idle_t 驱动，幅度 ~3%，肉眼可见但不晃眼。
					var base_scale := 1.0 + 0.18 * _lift_t
					var breathe := 1.0 + sin(_idle_t * 2.6) * 0.03
					var sx := base_scale * (1.0 - absf(mouse_tilt.y) * 0.05) * breathe
					var sy := base_scale * breathe
					scale = home_scale * Vector2(sx, sy)
					# 扇形原角先随抬升摆正，再叠鼠标水平倾角（±0.13rad ≈ ±7.5°）
					rotation = home_rot * maxf(0.0, 1.0 - _lift_t * 1.2) + mouse_tilt.x * 0.13 * _lift_t
				else:
					rotation = home_rot * maxf(0.0, 1.0 - _lift_t * 1.2)
					var sc := 1.0 + 0.18 * _lift_t
					scale = home_scale * Vector2(sc, sc)

	# ---------- 冷却结束的四边外发光衰减（约 0.85s，够看清又不烦） ----------
	if _glow_t > 0.0:
		_glow_t = maxf(0.0, _glow_t - delta * 1.18)
		if _glow_layer != null:
			_glow_layer.queue_redraw()
		if _overlay != null:
			_overlay.queue_redraw()
		if _glow_t <= 0.0 and not hover_lift:
			z_index = _z_backup      # 发光结束，层级还回去
		queue_redraw()

	if not effects_enabled or _face == null:
		return
	# ---------- 目标倾角：鼠标位置 ----------
	# 【★ 整卡一起动时，内层 _face 不再单独倾】否则整卡 + 卡面会「双重倾斜」，
	# 视觉上又是错层。整卡模式把倾斜交给整卡 rotation（见上面的 whole_card_hover 段），
	# 这里把目标倾角强制归零，让卡面老老实实贴住卡框。
	if whole_card_hover:
		_tilt_goal = Vector2.ZERO
	else:
		_tilt_goal = mouse_tilt

	# ---------- 陀螺仪 / 加速度计 ----------
	if gyro_enabled:
		var acc := Input.get_accelerometer()
		var g := Input.get_gyroscope()
		if acc.length() > 0.1 or g.length() > 0.01:
			var gx: float = clampf(acc.x * 0.6 + g.y * 0.05, -1.0, 1.0)
			var gy: float = clampf(-acc.y * 0.6 + g.x * 0.05, -1.0, 1.0)
			_gyro = _gyro.lerp(Vector2(gx, gy), delta * 4.0)
	else:
		_gyro = _gyro.lerp(Vector2.ZERO, delta * 4.0)

	# ---------- 弹簧阻尼（带轻微过冲，手感顺滑） ----------
	var stiff := 150.0
	var damp := 14.0
	var acc2 := (_tilt_goal - _tilt) * stiff - _tilt_vel * damp
	_tilt_vel += acc2 * delta
	_tilt += _tilt_vel * delta

	# 悬停抬升弹簧
	var lift_goal := 1.0 if _hover else 0.0
	var lacc := (lift_goal - _lift) * 120.0 - _lift_vel * 13.0
	_lift_vel += lacc * delta
	_lift = clampf(_lift + _lift_vel * delta, -0.15, 1.2)

	var total := _tilt + _gyro * 0.8
	total = total.limit_length(1.2)

	# ---------- 应用伪 3D ----------
	# 【★ 测试训练场：pseudo3d_enabled=false 时整块短路】只跳「倾斜 / 视差 /
	# billboard 平移」这一套（就是造成「两张卡叠影」的东西）；下面 `_lift`
	# （悬停抬升）与 `bob`（待机浮动）是**交互动效**，一律照常。
	var total3 := total if pseudo3d_enabled else Vector2.ZERO
	var max_angle := 0.14
	_face.rotation = -total3.x * max_angle * 0.9
	_face.scale = Vector2(1.0 - absf(total3.y) * 0.02, 1.0)
	_face.pivot_offset = size * 0.5

	# 待机呼吸浮动（仅手牌启用）
	var bob := Vector2.ZERO
	if idle_float and not _hover:
		bob = Vector2(0, sin(_idle_t * 1.5 + _idle_phase) * 2.2)
		_face.rotation += sin(_idle_t * 1.1 + _idle_phase) * 0.006

	# 【★ 整卡一起动时，卡面不再单独做「内层抬升」】_lift 的 -7px 位移是给
	# 「整卡不动、只有卡面浮起」那套老手感用的。整卡模式下整卡已经整体上浮
	# （见上面 self.position），卡面再自己浮 7px 就变成「双层上浮」= 又是错层感。
	var inner_lift := 0.0 if whole_card_hover else _lift * 7.0
	_face.position = _face_base_pos + Vector2(total3.x * 3.5, -absf(total3.x) * 2.0 + total3.y * 1.5 - inner_lift) + bob

	# ---------- Billboard：卡面反向补偿，始终「朝向镜头」 ----------
	# 倾斜时卡面图反向平移，使画面内容保持正对玩家，边框层正向位移形成厚度。
	# 【★ 关掉伪 3D 时归位】_art 必须回到铺满 + 1.0 缩放（不留 1.06），否则
	# 卡面比边框大一圈、被 clip_contents 裁掉后反而切边；_art2 也要回到 _layout()
	# 设定的基准偏移（3,5），维持原来的「厚度」静态观感。
	if _art:
		if pseudo3d_enabled:
			_art.position = Vector2(-total3.x * 7.0, -total3.y * 5.0)
			_art.scale = Vector2(1.06, 1.06)  # 放大遮掉平移露出的边缘
		else:
			_art.position = Vector2.ZERO
			_art.scale = Vector2.ONE
		_art.pivot_offset = size * 0.5
	if _art2:
		if pseudo3d_enabled:
			_art2.position = _art2_base + Vector2(total3.x * 5.0, total3.y * 3.0)
		else:
			# 【★ 修「图层重影」】_art2 是「暗色轮廓底层」，_layout() 给它设了
			# `(3k,5k)` 的基准偏移来伪造纸牌厚度。但这个偏移在**不倾斜**时依然生效 ——
			# `_art2` 尺寸与卡面同为 (w,h)，一偏移就在右侧/底部**露出 3~5px 暗边**，
			# 看起来就是「卡牌描边旁边又叠了一道错位的边」= 重影。
			# 关掉伪 3D 时它会老老实实待在正后方（不露边）；但用户要的是**全局**
			# 干净 —— 所以这里在「整卡悬停模式（=Dev 的干净样式）」下也把它归零，
			# 让轮廓层与主卡面完全重合，不再有任何错位暗边。
			_art2.position = Vector2.ZERO if whole_card_hover else _art2_base

	# 选中 / 闪卡 / 冷却 / 被瞄准 需要逐帧重绘
	# 【★ foil_enabled=false 时（SheFuDev）不再为闪卡逐帧重绘】—— 交互动效
	# （selected / target_glow / cd / _glow_t）的条件原样保留，不受影响。
	var foil_live := foil and foil_enabled
	if foil_live or selected or cd_cur > 0 or _glow_t > 0.0 or target_glow:
		if foil_live:
			_foil_t += delta                # 周期 2.4s 扫一趟（见 _draw_overlay 的 period）
		_overlay.queue_redraw()
		queue_redraw()


# ==================================================================== 内部类
## 图标徽标：半透明黑底药丸 + 图标 + 数字（场上卡的 祇/体/击/点数）
## 旧版药丸只有 22px 高、数字挤在右侧，看上去就是「一个蓝方块 / 一个黄方块」，
## 这里把图标缩到药丸内部留白、数字加粗放大，一眼能读出数值。
class Badge:
	extends Control
	var icon_name := "heart"
	var text := ""
	var col := Color.WHITE

	func set_data(p_icon: String, p_text: String, p_col: Color) -> void:
		icon_name = p_icon
		text = p_text
		col = p_col
		tooltip_text = ""

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := h * 0.5
		var bg := Color(0.03, 0.02, 0.05, 0.88)
		# 药丸底
		draw_circle(Vector2(r, r), r, bg)
		draw_circle(Vector2(w - r, r), r, bg)
		draw_rect(Rect2(r, 0, w - r * 2, h), bg, true)
		# 边线（阵营色）
		var line := Color(col.r, col.g, col.b, 0.72)
		draw_arc(Vector2(r, r), r - 1.0, PI * 0.5, PI * 1.5, 16, line, 1.6, true)
		draw_arc(Vector2(w - r, r), r - 1.0, -PI * 0.5, PI * 0.5, 16, line, 1.6, true)
		draw_line(Vector2(r, 1), Vector2(w - r, 1), line, 1.6, true)
		draw_line(Vector2(r, h - 1), Vector2(w - r, h - 1), line, 1.6, true)
		# 图标
		var tex: Texture2D = UITheme.icon(icon_name)
		var iw := h - 9.0
		if tex != null:
			draw_texture_rect(tex, Rect2(4.5, 4.5, iw, iw), false, Color(col.r, col.g, col.b, 1.0))
		# 数字
		var f := CardView.draw_font()
		var fs := int(h * 0.66)
		draw_string(f, Vector2(iw + 9.0, h * 0.5 + fs * 0.37), text,
			HORIZONTAL_ALIGNMENT_LEFT, w - iw - 11.0, fs, Color(1.0, 0.98, 0.92))


## 主动技能图标：点击触发，冷却时显示转圈（饼图）动画
class SkillIcon:
	extends Control
	signal pressed
	var cd_cur := 0
	var cd_max := 1
	var _hover := false
	var _spin := 0.0          ## 施法旋转（1 → 0 衰减）

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				pressed.emit()
				accept_event()

	## 发动技能时调用：图标旋转一圈
	func cast_spin() -> void:
		_spin = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		if _spin > 0.0:
			_spin = maxf(0.0, _spin - delta * 1.8)
			queue_redraw()
		elif cd_cur > 0:
			queue_redraw()   # 冷却转圈持续扫动

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		var ready := cd_cur <= 0
		var bg := Color(0.05, 0.04, 0.08, 0.88)
		var edge := UITheme.GOLD if ready else Color(0.45, 0.42, 0.5)
		if _hover and ready:
			edge = Color(1.0, 0.9, 0.6)
			draw_circle(c, r + 2.0, Color(1.0, 0.85, 0.4, 0.25))
		draw_circle(c, r, bg)
		draw_arc(c, r - 1.0, 0, TAU, 24, edge, 2.0, true)
		# 施法光环
		if _spin > 0.0:
			var k := 1.0 - _spin
			draw_arc(c, r + 3.0 + k * 12.0, 0, TAU, 28,
				Color(1.0, 0.88, 0.5, 0.55 * _spin), 3.0, true)
		var tex: Texture2D = UITheme.icon("bolt")
		if tex:
			var iw := size.x * 0.58
			var tint := Color(1.0, 0.88, 0.55) if ready else Color(0.55, 0.52, 0.6)
			if _spin > 0.0:
				draw_set_transform(c, _spin * TAU, Vector2.ONE)
				draw_texture_rect(tex, Rect2(-Vector2(iw, iw) * 0.5, Vector2(iw, iw)), false, tint)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_texture_rect(tex, Rect2(c - Vector2(iw, iw) * 0.5, Vector2(iw, iw)), false, tint)
		if cd_cur > 0:
			# 冷却转圈：从顶部顺时针的暗色饼图 = 剩余冷却比例，缓慢扫动
			var frac := clampf(float(cd_cur) / float(maxi(1, cd_max)), 0.0, 1.0)
			var pts := PackedVector2Array([c])
			var steps := 20
			for i in steps + 1:
				var a := -PI * 0.5 + frac * TAU * float(i) / steps
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, Color(0.02, 0.02, 0.04, 0.78))
			# 剩余回合数
			var f := CardView.draw_font()
			var fs := int(size.x * 0.44)
			draw_string(f, Vector2(0, c.y + fs * 0.38), str(cd_cur),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(0.95, 0.9, 0.75))
