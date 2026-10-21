class_name UITheme
extends RefCounted
## 统一视觉语言：暗底 + 金/朱砂点缀的东方志怪风。
## 所有颜色、字号、样式盒集中在这里，方便整体换肤。

# ---------------- 基础色板 ----------------
const BG          := Color("0e0c14")
const BG_DEEP     := Color("08070d")
const PANEL       := Color("1a1626")
const PANEL_HI    := Color("241e33")
const PANEL_LINE  := Color("37304a")
const GOLD        := Color("e8c36a")
const GOLD_DIM    := Color("a8894a")
const CINNABAR    := Color("c0392b")
const JADE        := Color("4fb286")
const AZURE       := Color("4a90d9")
const PURPLE      := Color("8e6fd0")
const TEXT        := Color("ede6d6")
const TEXT_DIM    := Color("9c93a8")
const QI          := Color("d94f4f")

# ---------------- 阵营配色 ----------------
const FACTION_COLORS := {
	"天": Color("d9a441"),
	"地": Color("4fb286"),
	"道具": Color("5fa8d3"),
}

const SUB_COLORS := {
	"佛": Color("e8c36a"),
	"神": Color("d9a441"),
	"妖": Color("4fb286"),
	"鬼": Color("8e6fd0"),
	"魔": Color("c0392b"),
	"奇兽": Color("b07d3a"),
	"道具": Color("5fa8d3"),
}

const SEAT_COLORS := {
	"东": Color("6fbf8f"),
	"南": Color("d96f6f"),
	"西": Color("d9c46f"),
	"北": Color("6f9fd9"),
}

## 12 位角色的**专属装饰色**（数据源 characters.json 的 color 字段，用的是中文色名）。
## 【为什么要单独一张表】角色名牌、下划线、边框都吃这个颜色 ——
## 它是「这个角色」的视觉签名，比阵营色更个人化，比金色更有辨识度。
const CHARA_COLORS := {
	"灵草绿": Color("5fb87a"),
	"紫电紫": Color("8e6fd0"),
	"日轮金": Color("e8c36a"),
	"青渊蓝": Color("4a86c8"),
	"焰骨橙": Color("e08a3c"),
	"血线红": Color("cf4b3c"),
	"莲印粉": Color("e08cae"),
	"青茶碧": Color("4fae94"),
	"青蘅绿": Color("57b06a"),
	"卓玛青": Color("3fa8a0"),
	"流云紫": Color("9b7fd4"),
	"玄阵青": Color("3f8f96"),
}


static func chara_color(name: String) -> Color:
	return CHARA_COLORS.get(name, GOLD)


static func sub_color(sub: String) -> Color:
	return SUB_COLORS.get(sub, GOLD_DIM)


static func faction_color(faction: String) -> Color:
	return FACTION_COLORS.get(faction, GOLD_DIM)


static func seat_color(seat: String) -> Color:
	return SEAT_COLORS.get(seat, GOLD_DIM)


# ---------------- 字体 ----------------
## 【必须缓存，禁止在 _draw() 里现建】SystemFont.new() 每次都要重新解析系统字体表：
##   ① 性能：每帧重建一次，等于每帧做一次系统字体枚举；
##   ② 正确性：新建的 SystemFont 字形表还没加载完就交给 draw_string()，
##      中文会当场画成一排「豆腐块」——拜神/敬鬼按钮上的灰方块就是这么来的。
## 全项目共用一份，谁要画中文都走 UITheme.font()。
static var _font_cache: Font = null
static var _title_font_cache: Font = null


static func make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑",
		"Source Han Sans SC", "Noto Sans CJK SC", "SimHei", "黑体",
		"PingFang SC", "Heiti SC", "sans-serif",
	])
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.allow_system_fallback = true
	return f


static func make_title_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"STKaiti", "KaiTi", "楷体", "STSong", "SimSun", "宋体",
		"Source Han Serif SC", "Noto Serif CJK SC", "serif",
	])
	f.allow_system_fallback = true
	return f


## 共享正文字体（缓存版，画中文一律用它）
static func font() -> Font:
	if _font_cache == null:
		_font_cache = make_font()
	return _font_cache


## 共享标题字体（缓存版）
static func title_font() -> Font:
	if _title_font_cache == null:
		_title_font_cache = make_title_font()
	return _title_font_cache


# ---------------- 美术资源（assets/ui，欧式金框 + AI 生成背景） ----------------
static var _ui_cache: Dictionary = {}

## 竖直渐变纹理缓存 —— **全局画质修复**：消灭「条形码阴影」。
## 【背景】旧代码到处用「for i in N: draw_rect(1~2px 半透明横条)」拼渐变。
## 条高不是整数、y 是小数 → 条间没对齐像素 + 半透明叠加 = **摩尔纹/条带**
## （用户看到的「条形码阴影」）。这里统一提供真渐变纹理：一次绘制、双线性插值。
static var _vgrad_cache: Dictionary = {}

## 1×256 竖直渐变纹理（顶 alpha=a_top → 底 alpha=a_bot，颜色固定），缓存复用。
## 用法：`draw_texture_rect(UITheme.vgrad(col, 0.0, 0.86), Rect2(...), false)`
static func vgrad(col: Color, a_top: float, a_bot: float) -> GradientTexture2D:
	var key := "%.4f_%.4f_%.4f_%.3f_%.3f" % [col.r, col.g, col.b, a_top, a_bot]
	if _vgrad_cache.has(key):
		return _vgrad_cache[key]
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, a_top))
	g.set_color(1, Color(col.r, col.g, col.b, a_bot))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 1
	t.height = 256
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	_vgrad_cache[key] = t
	return t


## 1×256 竖直渐变纹理（顶颜色 c_top → 底颜色 c_bot，含 RGB），缓存复用。
## 供「两色渐变面」使用（如骰子面：上亮下暗）。
static var _vgrad2_cache: Dictionary = {}
static func vgrad2(c_top: Color, c_bot: Color) -> GradientTexture2D:
	var key := "%.4f_%.4f_%.4f_%.4f_%.4f_%.4f_%.3f_%.3f" % [
		c_top.r, c_top.g, c_top.b, c_bot.r, c_bot.g, c_bot.b, c_top.a, c_bot.a]
	if _vgrad2_cache.has(key):
		return _vgrad2_cache[key]
	var g := Gradient.new()
	g.set_color(0, c_top)
	g.set_color(1, c_bot)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 1
	t.height = 256
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	_vgrad2_cache[key] = t
	return t


## 256×1 水平渐变纹理（左端透明 → 中央不透明 → 右端透明），用于「金线分隔条」。
## 【★ 修「条形码阴影」】旧版 DividerLine 用 24 段 1.2px 短线拼 sin 包络 → 段间未对齐像素 = 条纹。
static var _hgrad_diamond: GradientTexture2D = null
static func hgrad_line(col: Color, peak: float = 0.8) -> GradientTexture2D:
	var key := "line_%.3f_%.3f_%.3f_%.3f" % [col.r, col.g, col.b, peak]
	if _vgrad_cache.has(key):
		return _vgrad_cache[key]
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.5, Color(col.r, col.g, col.b, peak))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 1
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(1.0, 0.0)
	_vgrad_cache[key] = t
	return t


const FRAME_MARGINS := {}


static func ui_tex(name: String) -> Texture2D:
	if _ui_cache.has(name):
		return _ui_cache[name]
	var t: Texture2D = null
	var p := "res://assets/ui/%s.webp" % name
	if ResourceLoader.exists(p):
		t = load(p)
	_ui_cache[name] = t
	return t


## 线性图标（assets/ui/icon_<name>.webp）
## 【pui_ 前缀例外】本轮接入的 pUI 素材（财 / 法 / 源 / 气 / 行动 / 千纸鹤 / 升级）
## 本身就是彩色立体图标（金元宝、绿气团…），不是单色线性图标，
## 所以它们直接读 assets/ui/pui_*.webp，不走 icon_ 前缀，也**不能**再叠 modulate 染色。
static func icon(name: String) -> Texture2D:
	if name.begins_with("pui_"):
		return ui_tex(name)
	return ui_tex("icon_" + name)


## 图标按钮：圆形暗底 + 金线图标，悬停高亮，tooltip_text 弹出文字介绍
## tint=false：不叠金/灰染色（pUI 的彩色立体图标必须原色）
static func mk_icon_button(icon_name: String, tip: String, diameter: float = 46.0,
		tint: bool = true) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.expand_icon = true
	b.icon = icon(icon_name)
	var pad := int(diameter * (0.14 if not tint else 0.22))
	b.add_theme_constant_override("icon_max_width", int(diameter) - pad * 2)
	var mk := func(bg: Color, edge: Color, w: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = edge
		s.set_border_width_all(w)
		s.set_corner_radius_all(int(diameter * 0.5))
		s.content_margin_left = pad
		s.content_margin_right = pad
		s.content_margin_top = pad
		s.content_margin_bottom = pad
		return s
	b.add_theme_stylebox_override("normal", mk.call(Color(0.05, 0.04, 0.08, 0.88), Color(0.45, 0.40, 0.52), 1))
	b.add_theme_stylebox_override("hover", mk.call(Color(0.10, 0.085, 0.14, 0.95), GOLD, 2))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0.16, 0.13, 0.20, 0.98), GOLD, 2))
	b.add_theme_stylebox_override("disabled", mk.call(Color(0.04, 0.035, 0.06, 0.7), Color(0.25, 0.23, 0.3), 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if tint:
		b.add_theme_color_override("icon_normal_color", Color(0.92, 0.82, 0.55))
		b.add_theme_color_override("icon_hover_color", Color(1.0, 0.92, 0.62))
		b.add_theme_color_override("icon_pressed_color", Color(1.0, 0.95, 0.7))
		b.add_theme_color_override("icon_disabled_color", Color(0.4, 0.38, 0.45))
	else:
		# 【pUI 彩色图标不能用深色 disabled 调制】icon_disabled_color 在 Godot 里是
		# **乘算调制**而不是叠加：金色元宝 × (0.35,0.35,0.4) 直接变成一团近黑，
		# 升级按钮在不可用时就只剩一个黑圆点（实测踩到）。彩色图标只需「压暗一档」，
		# 保留色相和明度差，玩家仍然看得出那是什么。
		# 常态用近似恒等调制（1,1,1 会与白色 hover 无差别，留一点点差距即可），
		# 反馈交给 normal/hover/pressed 三种底板 —— 彩色图标保持原色才认得出。
		b.add_theme_color_override("icon_normal_color", Color(1.0, 1.0, 1.0, 0.90))
		b.add_theme_color_override("icon_hover_color", Color.WHITE)
		b.add_theme_color_override("icon_pressed_color", Color.WHITE)
		b.add_theme_color_override("icon_disabled_color", Color(0.64, 0.62, 0.70))
	attach_ui_sfx(b)
	return b


## 资源药丸：图标 + 数字（财/法/源/行动）
## tint_icon=false 时不对图标染色（pUI 的彩色图标必须原色显示）
static func mk_res_pill(icon_name: String, tip: String, col: Color,
		tint_icon: bool = true) -> PanelContainer:
	var p := PanelContainer.new()
	p.tooltip_text = tip
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.03, 0.07, 0.82)
	s.border_color = Color(col.r, col.g, col.b, 0.5)
	s.set_border_width_all(1)
	s.set_corner_radius_all(14)
	s.content_margin_left = 8
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	p.add_child(h)
	var t := TextureRect.new()
	t.texture = icon(icon_name)
	t.custom_minimum_size = Vector2(22, 22)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if tint_icon:
		t.modulate = col
	h.add_child(t)
	var v := mk_label("0", 16, col)
	h.add_child(v)
	p.set_meta("value_label", v)
	return p


## 读取药丸里的数字 Label
static func pill_value(p: PanelContainer) -> Label:
	return p.get_meta("value_label") as Label


## 生成一个铺满父控件的九宫格边框覆盖层（不拦截鼠标）
static func mk_divider(width: int = 180, height: int = 14, flip := false) -> Control:
	# 简洁渐变金线（替代欧式花纹）
	var d := DividerLine.new()
	d.custom_minimum_size = Vector2(width, height)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.set_meta("flip", flip)
	return d


## 渐变分隔线：两端透明、中央金色小菱形
class DividerLine:
	extends Control
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cy := h * 0.5
		# 【★ 修「条形码阴影」】旧版 24 段 1.2px 短线拼 sin 包络 → 改一次水平渐变纹理
		draw_texture_rect(UITheme.hgrad_line(Color(0.85, 0.70, 0.38), 0.8),
			Rect2(0, cy - 0.6, w, 1.2), false)
		var c := Vector2(w * 0.5, cy)
		var r := h * 0.30
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]),
			Color(0.85, 0.70, 0.38, 0.9))


## 章节标题：分隔线 + 金色标题 + 分隔线
static func section_title(text: String, size: int = 21, line_w: int = 110) -> Control:
	var h := mk_hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(mk_divider(line_w, 12, true))
	var l := mk_label(text, size, GOLD, true)
	h.add_child(l)
	h.add_child(mk_divider(line_w, 12, false))
	return h


## 贴图背景（大厅/战斗），铺满并保持比例裁切
static func bg_rect(name: String, darken: float = 0.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = ui_tex(name)
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if darken > 0.0:
		t.modulate = Color(1.0 - darken, 1.0 - darken, 1.0 - darken)
	return t


# ---------------- 样式盒 ----------------
static func panel_style(bg: Color = PANEL, border: Color = PANEL_LINE, radius: int = 10,
		border_w: int = 1, pad: int = -1, pad_v: int = -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	if pad < 0:
		pad = 12
	if pad_v < 0:
		pad_v = maxi(4, pad - 2)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func flat_style(bg: Color, radius: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	return s


static func glow_style(bg: Color, border: Color, radius: int = 10, width: int = 2, shadow: float = 8.0) -> StyleBoxFlat:
	var s := panel_style(bg, border, radius, width)
	s.shadow_color = Color(border.r, border.g, border.b, 0.45)
	s.shadow_size = int(shadow)
	return s


# ==================================================================== 国风设置面板样式
## 深色磨砂半透明紫黑面板：细金描边 + 双层阴影（外柔光 + 内高光）
##
## 【为什么不用一张贴图】九宫格贴图在高 DPI / 非整数缩放下会糊；
## StyleBoxFlat 的描边与圆角是矢量绘制，任何分辨率下都是锐利的 ——
## 这正是「不要廉价手游塑料质感」最直接的落点。
static func frost_style(bg: Color = Color(0.075, 0.055, 0.115, 0.92),
		border: Color = Color(0.91, 0.76, 0.42, 0.55), radius: int = 14,
		width: int = 1, glow: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.anti_aliasing = true
	s.anti_aliasing_size = 1.0
	# 内高光：把「上边」单独提亮一档，平铺色块立刻有了体积
	s.border_blend = true
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	if glow > 0.0:
		s.shadow_color = Color(0.06, 0.03, 0.10, 0.75)
		s.shadow_size = int(glow)
		s.shadow_offset = Vector2(0, 4)
	return s


## 选中的头像 / 角色卡：细金色发光边框 + 微弱内光晕
static func selected_tile_style(radius: int = 12) -> StyleBoxFlat:
	var s := frost_style(Color(0.13, 0.10, 0.19, 0.95), GOLD, radius, 2, 14.0)
	s.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	s.shadow_size = 16
	return s


## 深色底 + 浅金文字的参数选择框（hover 时描边亮起，暗示可点）
static func style_option_button(b: OptionButton, height: float = 44.0) -> void:
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_font_override("font", font())
	var base := func(fill: Color, edge: Color, w: int, lift: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = fill
		s.border_color = edge
		s.set_border_width_all(w)
		s.set_corner_radius_all(9)
		s.corner_detail = 10
		s.content_margin_left = 14
		s.content_margin_right = 12
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		s.expand_margin_top = float(-lift)
		s.expand_margin_bottom = float(lift)
		return s
	b.add_theme_stylebox_override("normal", base.call(Color(0.055, 0.042, 0.085, 0.95), Color(0.91, 0.76, 0.42, 0.30), 1, 0))
	b.add_theme_stylebox_override("hover", base.call(Color(0.10, 0.078, 0.145, 0.98), Color(0.91, 0.76, 0.42, 0.80), 1, 1))
	b.add_theme_stylebox_override("pressed", base.call(Color(0.14, 0.11, 0.19, 1.0), GOLD, 2, 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.91, 0.84, 0.66))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.76))
	b.add_theme_color_override("font_pressed_color", GOLD)


## 大号金色 CTA：【开始匹配】。金填充 + 上沿浅金高光 + 外发光
static func mk_cta_button(txt: String, size: int = 24, height: float = 62.0) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", title_font())
	b.custom_minimum_size = Vector2(0, height)
	var mk := func(fill: Color, edge: Color, glow: Color, gs: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = fill
		s.border_color = edge
		s.set_border_width_all(1)
		s.set_corner_radius_all(12)
		s.corner_detail = 12
		s.anti_aliasing = true
		s.border_blend = true
		s.shadow_color = glow
		s.shadow_size = gs
		s.shadow_offset = Vector2(0, 3)
		s.content_margin_left = 30
		s.content_margin_right = 30
		return s
	# 「细腻渐变」用三层近似：底色 + 顶部亮边 + 外发光，
	# 比塞一张 GradientTexture2D 更抗缩放（矢量描边不会糊）。
	b.add_theme_stylebox_override("normal", mk.call(Color("d8b25c"), Color("f4e2a8"), Color(GOLD.r, GOLD.g, GOLD.b, 0.34), 14))
	b.add_theme_stylebox_override("hover", mk.call(Color("efc96f"), Color("fff0c0"), Color(GOLD.r, GOLD.g, GOLD.b, 0.55), 20))
	b.add_theme_stylebox_override("pressed", mk.call(Color("b8913f"), Color("e2c079"), Color(GOLD.r, GOLD.g, GOLD.b, 0.25), 8))
	b.add_theme_stylebox_override("disabled", mk.call(Color("2a2438"), Color("40384f"), Color(0, 0, 0, 0), 0))
	b.add_theme_color_override("font_color", Color("221704"))
	b.add_theme_color_override("font_hover_color", Color("160e02"))
	b.add_theme_color_override("font_pressed_color", Color("0d0801"))
	b.add_theme_color_override("font_disabled_color", Color("5a5368"))
	attach_ui_sfx(b)
	return b


## 次级按钮：【开房间】。深色描边、透明填充
static func mk_ghost_button(txt: String, size: int = 18, height: float = 62.0) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", font())
	b.custom_minimum_size = Vector2(0, height)
	var mk := func(fill: Color, edge: Color, w: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = fill
		s.border_color = edge
		s.set_border_width_all(w)
		s.set_corner_radius_all(12)
		s.corner_detail = 12
		s.content_margin_left = 22
		s.content_margin_right = 22
		return s
	b.add_theme_stylebox_override("normal", mk.call(Color(0.055, 0.042, 0.085, 0.80), Color(0.91, 0.76, 0.42, 0.38), 1))
	b.add_theme_stylebox_override("hover", mk.call(Color(0.10, 0.078, 0.145, 0.95), Color(0.91, 0.76, 0.42, 0.85), 2))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0.15, 0.12, 0.20, 1.0), GOLD, 2))
	b.add_theme_stylebox_override("disabled", mk.call(Color(0.05, 0.04, 0.07, 0.6), Color(0.25, 0.23, 0.3), 1))
	b.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62))
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	attach_ui_sfx(b)
	return b


## 极简国风暗纹底：回纹网格 + 交叉点小方块，alpha 极低，只提供「质感」不抢焦点
class Motif extends Control:
	var col := Color(0.91, 0.76, 0.42, 0.055)
	var cell := 46.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var step := maxf(24.0, cell)
		var x := 0.0
		while x <= w:
			draw_line(Vector2(x, 0), Vector2(x, h), col, 1.0)
			x += step
		var y := 0.0
		while y <= h:
			draw_line(Vector2(0, y), Vector2(w, y), col, 1.0)
			y += step
		# 交叉点小方块（回纹的味道）
		var c2 := Color(col.r, col.g, col.b, col.a * 1.8)
		var yy := step
		while yy < h:
			var xx := step
			while xx < w:
				draw_rect(Rect2(xx - 2.0, yy - 2.0, 4.0, 4.0), c2, true)
				xx += step * 2.0
			yy += step


static func motif_overlay() -> Control:
	var m := Motif.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	return m


# ---------------- 主题 ----------------
static func build() -> Theme:
	var t := Theme.new()
	var body := make_font()
	var title := make_title_font()
	t.default_font = body
	t.default_font_size = 18

	# Button
	t.set_stylebox("normal", "Button", panel_style(PANEL_HI, PANEL_LINE, 8))
	var hover := glow_style(Color("2f2742"), GOLD_DIM, 8, 1, 6.0)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", glow_style(Color("3a3050"), GOLD, 8, 2, 8.0))
	t.set_stylebox("disabled", "Button", panel_style(Color("191524"), Color("2a2438"), 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color("5a5368"))
	t.set_constant("h_separation", "Button", 6)

	# Panel
	t.set_stylebox("panel", "PanelContainer", panel_style(PANEL, PANEL_LINE, 10))

	# Label
	t.set_color("font_color", "Label", TEXT)

	# RichTextLabel
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())

	# ScrollContainer / VScrollBar
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color("2e2840")
	bar.set_corner_radius_all(3)
	bar.content_margin_left = 0
	bar.content_margin_right = 0
	t.set_stylebox("scroll", "VScrollBar", flat_style(Color(0, 0, 0, 0.15), 3))
	t.set_stylebox("grabber", "VScrollBar", bar)
	t.set_stylebox("grabber_highlight", "VScrollBar", flat_style(GOLD_DIM, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat_style(GOLD, 3))

	# OptionButton / PopupMenu
	t.set_stylebox("normal", "OptionButton", panel_style(PANEL_HI, PANEL_LINE, 8))
	t.set_stylebox("hover", "OptionButton", panel_style(Color("2f2742"), GOLD_DIM, 8))
	t.set_stylebox("pressed", "OptionButton", panel_style(Color("3a3050"), GOLD, 8))
	t.set_color("font_color", "OptionButton", TEXT)

	# ProgressBar
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color("171325")
	pbg.set_corner_radius_all(6)
	var pfg := StyleBoxFlat.new()
	pfg.bg_color = QI
	pfg.set_corner_radius_all(6)
	t.set_stylebox("background", "ProgressBar", pbg)
	t.set_stylebox("fill", "ProgressBar", pfg)
	t.set_color("font_color", "ProgressBar", TEXT)

	# Tooltip（悬停文字介绍）
	var ttp := StyleBoxFlat.new()
	ttp.bg_color = Color(0.05, 0.04, 0.09, 0.96)
	ttp.border_color = GOLD_DIM
	ttp.set_border_width_all(1)
	ttp.set_corner_radius_all(6)
	ttp.content_margin_left = 10
	ttp.content_margin_right = 10
	ttp.content_margin_top = 7
	ttp.content_margin_bottom = 7
	t.set_stylebox("panel", "TooltipPanel", ttp)
	t.set_color("font_color", "TooltipLabel", TEXT)

	# HSeparator
	var sep := StyleBoxLine.new()
	sep.color = PANEL_LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)

	# CheckBox / CheckButton
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)

	return t


# ---------------- 便捷控件工厂 ----------------
## 播放一个音效。
## 【为什么绕一圈拿节点】UITheme 是 static 工具类，静态函数里引用 autoload 名
## 会受加载顺序影响（工具类可能在 autoload 之前被编译），走 /root/Sfx 最稳。
static func ui_sound(name: String, db: float = 0.0) -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var n := (loop as SceneTree).root.get_node_or_null("Sfx")
		if n != null:
			n.call("play", name, db)


## 给任意 Control 挂上统一的悬停音（幂等，重复调用不会叠两条回调）。
## 【为什么只挂悬停、不挂点击】点击在各调用点都有语义化的音效
## （取牌=翻纸、出牌=落桌、错误=短促否定音…），这里再补一个通用点击音
## 就会变成一按两响。
static func attach_ui_sfx(c: Control) -> void:
	if c == null or c.has_meta("_ui_sfx"):
		return
	c.set_meta("_ui_sfx", true)
	c.mouse_entered.connect(func(): ui_sound("ui_hover", -22.0))


static func mk_label(txt: String, size: int = 18, col: Color = TEXT, use_title: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if use_title:
		l.add_theme_font_override("font", make_title_font())
	return l


static func mk_button(txt: String, size: int = 17) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 36)
	attach_ui_sfx(b)
	return b


## 主行动按钮（开始游戏 / 结束回合等 CTA）：金底深字 + 辉光
static func mk_gold_button(txt: String, size: int = 18) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 44)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("c8a24d")
	normal.set_corner_radius_all(9)
	normal.border_color = GOLD
	normal.set_border_width_all(1)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.shadow_color = Color(0.91, 0.76, 0.42, 0.35)
	normal.shadow_size = 10
	var hov := normal.duplicate() as StyleBoxFlat
	hov.bg_color = Color("e0b95e")
	hov.shadow_size = 14
	var pre := normal.duplicate() as StyleBoxFlat
	pre.bg_color = Color("a8863c")
	var dis := panel_style(Color("241f30"), Color("3a3348"), 9)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", pre)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_color", Color("241805"))
	b.add_theme_color_override("font_hover_color", Color("1a1002"))
	b.add_theme_color_override("font_pressed_color", Color("0f0a02"))
	b.add_theme_color_override("font_disabled_color", Color("5a5368"))
	attach_ui_sfx(b)
	return b


static func mk_panel(bg: Color = PANEL, border: Color = PANEL_LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, border, 10))
	return p


static func mk_vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func mk_hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func title_banner(text: String, sub: String = "") -> Control:
	var box := mk_vbox(2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := mk_label(text, 46, GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.0, 0.9))
	t.add_theme_constant_override("outline_size", 6)
	t.add_theme_color_override("font_shadow_color", Color(0.9, 0.7, 0.3, 0.35))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(t)
	var dl := mk_divider(340, 16)
	box.add_child(dl)
	if sub != "":
		var s := mk_label(sub, 16, TEXT_DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(s)
	return box
