class_name FXLayer
extends Control
## 全屏特效层：飘字 / 粒子爆发 / 扩散光环 / 攻击光束 / 屏幕震动 / 全屏闪光
## ------------------------------------------------------------------
## 用法：作为战斗界面最顶层子节点（PRESET_FULL_RECT，不拦截鼠标）。
## 所有坐标为「屏幕全局坐标」，内部自动转本地。
## 所有特效遵循 CardView.effects_enabled 全局开关。


# ==================================================================== 粒子爆发
class Burst extends Control:
	var parts: Array = []   ## {pos, vel, life, max_life, col, size, grav}
	var _t := 0.0

	func setup(ps: Array) -> void:
		parts = ps
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		var alive := false
		for p in parts:
			if p["life"] > 0.0:
				alive = true
				p["life"] -= delta
				p["vel"] = p["vel"] * (1.0 - delta * 2.2) + Vector2(0, p["grav"]) * delta
				p["pos"] += p["vel"] * delta
		if not alive:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		for p in parts:
			if p["life"] <= 0.0:
				continue
			var k: float = clampf(p["life"] / p["max_life"], 0.0, 1.0)
			var c: Color = p["col"]
			c.a = k * k
			var r: float = p["size"] * (0.5 + 0.5 * k)
			draw_circle(p["pos"], r, c)
			# 运动拖尾
			var tail: Vector2 = p["pos"] - p["vel"] * 0.03
			c.a *= 0.5
			draw_line(tail, p["pos"], c, maxf(1.0, r * 0.8))


# ==================================================================== 扩散光环
class Ring extends Control:
	var center := Vector2.ZERO
	var col := Color.WHITE
	var max_r := 70.0
	var dur := 0.45
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_t / dur, 0.0, 1.0)
		var r: float = 8.0 + (max_r - 8.0) * (1.0 - pow(1.0 - k, 2.2))
		var c := col
		c.a = (1.0 - k) * 0.9
		draw_arc(center, r, 0, TAU, 40, c, 2.5)
		c.a = (1.0 - k) * 0.35
		draw_arc(center, r * 0.72, 0, TAU, 32, c, 1.5)


# ==================================================================== 攻击光束
class Beam extends Control:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var col := Color.WHITE
	var dur := 0.28
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_t / dur, 0.0, 1.0)
		var head: Vector2 = from.lerp(to, ease(k * 1.6, 0.6))
		var c := col
		c.a = (1.0 - k * 0.6)
		draw_line(from, head, c, 4.0)
		var c2 := Color(1, 1, 1, c.a * 0.8)
		draw_line(from, head, c2, 1.5)
		draw_circle(head, 5.0 * (1.0 - k) + 2.0, c2)


# ==================================================================== 法术阵 / 斩击
class Sigil extends Control:
	var center := Vector2.ZERO
	var col := Color.WHITE
	var max_r := 84.0
	var dur := 0.62
	var _t := 0.0
	var _runes := 8

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_t / dur, 0.0, 1.0)
		var a: float = (1.0 - k) * (1.0 - k)
		var r: float = max_r * (0.45 + 0.55 * (1.0 - pow(1.0 - k, 2.0)))
		var rot: float = k * 1.7
		var c := Color(col.r, col.g, col.b, a * 0.85)
		draw_arc(center, r, rot, rot + TAU, 48, c, 2.4)
		draw_arc(center, r * 0.74, -rot * 1.5, -rot * 1.5 + TAU, 40, Color(col.r, col.g, col.b, a * 0.5), 1.4)
		var c2 := Color(1, 1, 1, a * 0.9)
		for i in _runes:
			var ang: float = rot + TAU * float(i) / float(_runes)
			var p: Vector2 = center + Vector2(cos(ang), sin(ang)) * r
			draw_circle(p, 3.0 * (1.0 - k * 0.5), c2)
		# 中心竖光
		draw_line(center - Vector2(0, r * 0.7), center + Vector2(0, r * 0.7), Color(col.r, col.g, col.b, a * 0.45), 3.0)


class Slash extends Control:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var col := Color.WHITE
	var dur := 0.34
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_t / dur, 0.0, 1.0)
		var a: float = (1.0 - k)
		var mid: Vector2 = from.lerp(to, ease(k * 1.35, 0.55))
		var dir: Vector2 = (to - from).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var nrm := Vector2(-dir.y, dir.x)
		var c := Color(col.r, col.g, col.b, a * 0.95)
		# 新月刃：两段弧线组成的月牙
		var span := 62.0
		var pts_a := PackedVector2Array()
		var pts_b := PackedVector2Array()
		for i in 13:
			var t: float = float(i) / 12.0
			var off: float = (t - 0.5) * span
			var bow: float = sin(t * PI) * 26.0
			var p: Vector2 = mid + nrm * off + dir * bow
			pts_a.append(p)
			pts_b.append(p - nrm * (6.0 + 8.0 * sin(t * PI)))
		draw_polyline(pts_a, c, 3.2)
		draw_polyline(pts_b, Color(1, 1, 1, a * 0.75), 1.6)
		for i in pts_a.size() - 1:
			draw_line(pts_a[i], pts_b[i], Color(col.r, col.g, col.b, a * 0.28), 1.0)
		draw_circle(mid + dir * 30.0, 6.0 * a + 1.0, Color(1, 1, 1, a * 0.7))


# ==================================================================== 书法单字（道具特效）
## 巨大书法单字：像印章一样「砸」在目标上。
## 【为什么用 Label 而不是 draw_char】Godot 的 draw_char 走的是底层字形接口，
## 拿不到 UITheme 缓存好的古风衬线字体，中文会掉成豆腐块；
## 把字放进 Label + make_title_font() 才拿得到正确的字形与描边。
class CalGlyph extends Control:
	var text := "降"
	var col := Color.WHITE
	var dur := 1.15
	var _t := 0.0
	var _lbl: Label
	var _ink: float = 0.0

	func setup(gpos: Vector2, side: float) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 330
		size = Vector2(side, side)
		pivot_offset = size * 0.5
		_lbl = Label.new()
		_lbl.text = text
		_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lbl.add_theme_font_override("font", UITheme.make_title_font())
		_lbl.add_theme_font_size_override("font_size", int(side * 0.78))
		_lbl.add_theme_color_override("font_color", col)
		_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.0, 1.0))
		_lbl.add_theme_constant_override("outline_size", int(side * 0.045))
		_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_lbl)
		# 印章式入场：从 3.2 倍骤然收束到 1.0，回弹一点点
		scale = Vector2(3.2, 3.2)
		rotation = -0.20
		modulate.a = 0.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "modulate:a", 1.0, 0.10)
		tw.tween_property(self, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "rotation", 0.0, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		# 落地后轻微抖动，像墨还在渗
		if _t > 0.26 and _t < 0.62:
			_ink = 1.0
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var k: float = clampf(_t / dur, 0.0, 1.0)
		var a := 1.0 - clampf((k - 0.60) / 0.40, 0.0, 1.0)
		# 背后一道横向笔痕：从左向右扫开，是「书法」而不是「一个贴图字」的关键
		var grow: float = ease(clampf(k / 0.30, 0.0, 1.0), 0.35)
		var half: float = size.x * 0.72 * grow
		var th: float = size.x * 0.055 * (1.0 - k * 0.55)
		draw_line(c - Vector2(half, 0), c + Vector2(half, 0), Color(col.r, col.g, col.b, 0.24 * a), th)
		draw_line(c - Vector2(half, 0), c + Vector2(half, 0), Color(1, 1, 1, 0.20 * a), th * 0.30)
		# 四角飞白
		var fly: float = size.x * 0.10 * grow
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var p: Vector2 = c + Vector2(size.x * 0.30, size.y * 0.30) * s
			draw_circle(p, fly * 0.16 * a, Color(col.r, col.g, col.b, 0.5 * a))


# ==================================================================== 金刚钺砸落
## 巨钺自天而降：屏外高速落下 → 命中静止 → 抬走淡出。
## 用道具目录里的专用素材（assets/ui/fx_axe.webp）。
class AxeSmash extends Control:
	var target := Vector2.ZERO
	var tex: Texture2D
	var dur := 1.35
	var _t := 0.0
	var _hit := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		z_index = 328

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		if not _hit and _t >= 0.40:
			_hit = true
		queue_redraw()

	func _draw() -> void:
		if tex == null:
			return
		var side := minf(size.x, 760.0) * 0.62
		# 位移曲线：0.40s 内从 -1.5 个屏高砸到目标点，用 EASE_IN 加速（越落越快）
		var k: float = clampf(_t / 0.40, 0.0, 1.0)
		var drop: float = pow(k, 2.6)
		var y: float = target.y - size.y * 1.6 * (1.0 - drop)
		var x: float = target.x
		if _hit:
			# 命中后的余震
			x += sin((_t - 0.40) * 62.0) * 5.0 * maxf(0.0, 1.0 - (_t - 0.40) / 0.5)
		var fade: float = 1.0
		if _t > 0.86:
			fade = 1.0 - clampf((_t - 0.86) / 0.49, 0.0, 1.0)
		var r := Rect2(Vector2(x - side * 0.5, y - side * 0.5), Vector2(side, side))
		# 下落残影（读起来才有「高速砸下」的重量）
		if not _hit:
			for i in 3:
				var yy: float = y - side * (0.42 + float(i) * 0.30)
				draw_texture_rect(tex, Rect2(Vector2(r.position.x + i * 2.0, yy), r.size),
					false, Color(1, 1, 1, 0.14 * fade))
		draw_texture_rect(tex, r, false, Color(1, 1, 1, fade))
		# 命中瞬间：竖直白闪 + 地面冲击弧
		if _hit:
			var kt: float = clampf((_t - 0.40) / 0.42, 0.0, 1.0)
			var a: float = (1.0 - kt) * 0.85
			draw_line(Vector2(target.x, 0), Vector2(target.x, target.y), Color(1, 0.94, 0.72, a * 0.5), 6.0)
			draw_arc(Vector2(target.x, target.y + side * 0.34),
				20.0 + 300.0 * ease(kt, 0.4), PI * 1.05, PI * 1.95, 46,
				Color(1, 0.88, 0.55, a * 0.7), 3.0)


# ==================================================================== 升级光柱
## 自下而上的金色光柱 + 底部光圈。「升级」是本作最贵的一次投入（财/法/源），
## 之前只有一条 20px 的飘字，玩家根本感觉不到自己刚做了什么。
class Pillar extends Control:
	var center := Vector2.ZERO
	var col := Color.WHITE
	var width := 170.0
	var height := 560.0
	var dur := 1.05
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		z_index = 326

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_t / dur, 0.0, 1.0)
		var a: float = 1.0
		if k < 0.20:
			a = k / 0.20
		elif k > 0.62:
			a = 1.0 - (k - 0.62) / 0.38
		var half: float = width * 0.5 * (0.45 + 1.05 * ease(k, 0.4))
		# 【★ 修「条形码」】旧版用 36 条离散横条拼光柱，条间 +1.6 重叠 →
		# 半透明叠出条纹。现在把光柱画成**一个梯形多边形**（顶点带宽变化），
		# 再用一张竖直渐变纹理叠加做「上淡下浓」的衰减 —— 连续、无条带。
		# 光柱本体：底宽 = 2*half，顶宽 = 2*half*0.58（上窄下宽的光锥）
		var bw: float = half
		var tw: float = half * 0.58
		var pts := PackedVector2Array([
			Vector2(center.x - bw, center.y),
			Vector2(center.x + bw, center.y),
			Vector2(center.x + tw, center.y - height),
			Vector2(center.x - tw, center.y - height),
		])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, a * 0.34))
		# 竖直渐变叠一层（下浓上透），让光柱有「离地越远越淡」的真实感
		var grad_rect := Rect2(center.x - bw, center.y - height, bw * 2.0, height)
		draw_texture_rect(UITheme.vgrad(col, 0.0, 1.0), grad_rect, false,
			Color(1, 1, 1, a * 0.28))
		draw_rect(Rect2(center.x - 3.0, center.y - height, 6.0, height), Color(1, 1, 1, a * 0.32))
		draw_arc(center, half * 1.55, PI, TAU, 44, Color(col.r, col.g, col.b, a * 0.75), 3.0, true)
		draw_arc(center, half * 2.15, PI, TAU, 44, Color(col.r, col.g, col.b, a * 0.35), 1.6, true)


# ==================================================================== 技能序列帧（Q版）
## 由 tools/build_fx_pack.py 把 4.116个Q版技能特效序列帧 的选中效果横向拼成长图，
## 运行期只改 region 逐帧播放。见 data/fx_manifest.json。
##
## 【为什么要换掉程序化特效】原来每个 fx 都是一圈光环 + 一堆圆点粒子，
## 22 种技能看起来只是「换了个颜色」；用户导入了成套 Q 版手绘特效，
## 每一种都有明确的形状（剑气的弧、雷的枝、火的团），辨识度完全不同。
class SheetFX extends Control:
	var tex: Texture2D
	var fw := 1.0
	var fh := 1.0
	var frames := 1
	var dur := 0.6
	var anchor := Vector2.ZERO      ## 底边中点（本地坐标）：效果"落"在目标上
	var k := 1.0
	var _t := 0.0

	func setup(p_tex: Texture2D, p_fw: float, p_fh: float, p_frames: int,
			p_dur: float, p_anchor: Vector2, p_k: float) -> void:
		tex = p_tex
		fw = p_fw
		fh = p_fh
		frames = maxi(1, p_frames)
		dur = maxf(0.05, p_dur)
		anchor = p_anchor
		k = p_k
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var idx := clampi(int(_t / dur * float(frames)), 0, frames - 1)
		var w := fw * k
		var h := fh * k
		var pos := anchor - Vector2(w * 0.5, h)
		draw_texture_rect_region(tex, Rect2(pos, Vector2(w, h)),
			Rect2(float(idx) * fw, 0.0, fw, fh))


# ==================================================================== 主体
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 300


# ---------------- 序列帧清单（静态缓存，全场景共用一份） ----------------
static var _sheet_manifest: Dictionary = {}
static var _sheet_tex: Dictionary = {}


static func sheet_manifest() -> Dictionary:
	if not _sheet_manifest.is_empty():
		return _sheet_manifest
	if not ResourceLoader.exists("res://data/fx_manifest.json"):
		return {}
	var f := FileAccess.open("res://data/fx_manifest.json", FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_sheet_manifest = d
	return _sheet_manifest


## 这个 fx 有没有对应的 Q 版序列帧（UITest 用它核对 22 种技能全覆盖）
static func has_sheet(fx: String) -> bool:
	return sheet_manifest().has(fx)


## 播放 Q 版序列帧。返回 false = 没有这组素材，调用方回落到程序化特效。
func play_sheet(fx: String, gpos: Vector2) -> bool:
	var m := sheet_manifest()
	if not m.has(fx):
		return false
	var info: Dictionary = m[fx]
	var path := str(info.get("file", ""))
	var tex: Texture2D = null
	if _sheet_tex.has(path):
		tex = _sheet_tex[path]
	elif ResourceLoader.exists(path):
		tex = load(path) as Texture2D
		_sheet_tex[path] = tex
	if tex == null:
		return false
	var fw := float(info.get("fw", 1.0))
	var fh := float(info.get("fh", 1.0))
	# 原素材尺寸差异极大（金币 56px、剑气 354px），必须归一化，
	# 否则同一场对局里有的特效大得像全屏、有的小得看不见。
	# 规则：把最大边压到 200px 附近，再夹在 0.6~3.0 倍之间。
	var k := clampf(200.0 / maxf(fw, fh), 0.6, 3.0)
	var node := SheetFX.new()
	node.setup(tex, fw, fh, int(info.get("frames", 1)), float(info.get("dur", 0.62)),
		_local(gpos), k)
	add_child(node)
	return true


func _local(gpos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * gpos


## 飘字：伤害数字 / 提示，向上漂移渐隐
func float_text(gpos: Vector2, text: String, col: Color = UITheme.GOLD, size: int = 26) -> void:
	if not CardView.effects_enabled:
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_font_override("font", UITheme.make_title_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 320
	add_child(l)
	var p := _local(gpos)
	l.position = p - Vector2(l.get_combined_minimum_size().x * 0.5, 20)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.14).set_delay(0.16)
	tw.tween_property(l, "position:y", l.position.y - 46.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.62)
	tw.tween_callback(l.queue_free)


## 粒子爆发：起乩 / 合成 / 拔除
func burst(gpos: Vector2, col: Color, count: int = 16, speed: float = 170.0, size: float = 3.2) -> void:
	if not CardView.effects_enabled:
		return
	var b := Burst.new()
	var ps: Array = []
	for i in count:
		var ang := randf() * TAU
		var sp := speed * (0.35 + randf() * 0.75)
		var life := 0.45 + randf() * 0.4
		ps.append({
			"pos": _local(gpos),
			"vel": Vector2(cos(ang), sin(ang)) * sp,
			"life": life, "max_life": life,
			"col": col.lerp(Color(1, 1, 1), randf() * 0.35),
			"size": size * (0.7 + randf() * 0.6),
			"grav": 60.0,
		})
	add_child(b)
	b.setup(ps)


## 扩散光环：治疗 / 召唤 / 升级
func ring(gpos: Vector2, col: Color = UITheme.GOLD, max_r: float = 70.0) -> void:
	if not CardView.effects_enabled:
		return
	var r := Ring.new()
	r.center = _local(gpos)
	r.col = col
	r.max_r = max_r
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(r)


## 攻击光束：从攻击者射向目标
func beam(from_g: Vector2, to_g: Vector2, col: Color = UITheme.QI) -> void:
	if not CardView.effects_enabled:
		return
	var b := Beam.new()
	b.from = _local(from_g)
	b.to = _local(to_g)
	b.col = col
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(b)


## 法术阵：召唤 / 封印 / 魂魄 / 拔除用
func sigil(gpos: Vector2, col: Color = UITheme.GOLD, max_r: float = 84.0) -> void:
	if not CardView.effects_enabled:
		return
	var s := Sigil.new()
	s.center = _local(gpos)
	s.col = col
	s.max_r = max_r
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(s)


## 斩击：从 from 划向 to 的月牙刃
func slash(from_g: Vector2, to_g: Vector2, col: Color = UITheme.GOLD) -> void:
	if not CardView.effects_enabled:
		return
	var s := Slash.new()
	s.from = _local(from_g)
	s.to = _local(to_g)
	s.col = col
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(s)


## 升级：金色光柱冲起 + 「升」字 + 气上限飘字
func upgrade_burst(gpos: Vector2, qi_max: int) -> void:
	if not CardView.effects_enabled or gpos == Vector2.ZERO:
		return
	var p := Pillar.new()
	p.center = _local(gpos + Vector2(0, 40))
	p.col = UITheme.GOLD
	add_child(p)
	calligraphy("升", gpos + Vector2(0, -40), UITheme.GOLD, 236.0)
	ring(gpos, Color("ffe6a8"), 170.0)
	for i in 12:
		burst(gpos + Vector2(randf_range(-70.0, 70.0), randf_range(20.0, 90.0)),
			Color("ffe9b0"), 8, 150.0, 3.0)
	shake(get_parent() as Control, 9.0)
	flash_screen(Color(1.0, 0.90, 0.60, 0.16), 0.34)
	float_text(gpos + Vector2(0, -140), "【人】升级 · 气上限 %d" % qi_max, UITheme.GOLD, 26)


## 书法单字：道具「降」/「封」的招牌演出。红色朱砂 / 金色。
func calligraphy(text: String, gpos: Vector2, col: Color = UITheme.CINNABAR, side: float = 300.0) -> void:
	if not CardView.effects_enabled or gpos == Vector2.ZERO:
		return
	var g := CalGlyph.new()
	g.text = text
	g.col = col
	var p := _local(gpos)
	g.position = p - Vector2(side, side) * 0.5
	g.setup(p, side)
	add_child(g)
	# 单字落下自带一下低频震动，不给「这就是个贴图」的机会
	shake(get_parent() as Control, 8.0)
	burst(gpos, col.lerp(Color(1, 1, 1), 0.35), 26, 260.0, 4.0)
	ring(gpos, col, 120.0)
	flash_screen(Color(col.r, col.g, col.b, 0.13), 0.26)


## 金刚钺砸落：巨钺自天而降，命中后地面炸开
func axe_smash(gpos: Vector2) -> void:
	if not CardView.effects_enabled or gpos == Vector2.ZERO:
		return
	var a := AxeSmash.new()
	a.target = _local(gpos)
	a.tex = UITheme.ui_tex("fx_axe")
	add_child(a)
	# 命中时刻（0.40s）与 AxeSmash 内部曲线对齐，敲在这里才有「同步」的手感
	var timer := get_tree().create_timer(0.40)
	timer.timeout.connect(func():
		burst(gpos, UITheme.GOLD, 34, 330.0, 5.0)
		ring(gpos, Color("ffe6a8"), 200.0)
		sigil(gpos, UITheme.GOLD, 130.0)
		shake(get_parent() as Control, 15.0)
		flash_screen(Color(1.0, 0.90, 0.62, 0.18), 0.30))


## 八卦镜读数：在「对应玩家的方向」用大号白色书法汉字报出【地】手牌数量。
## entries = [{ "pos": Vector2, "count": int, "name": String }]
## 【只在本地玩家使用时调用】——需求明确「只向该玩家提示」，
## 所以这个函数的调用方必须先判 pid == human.pid，否则等于把对手的手牌公开广播。
func reveal_marks(entries: Array) -> void:
	if not CardView.effects_enabled:
		return
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.z_index = 340
	add_child(holder)
	for e in entries:
		var pos: Vector2 = _local(e["pos"])
		var n := int(e["count"])
		var card := Panel.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.03, 0.07, 0.80)
		sb.border_color = Color(0.90, 0.78, 0.46, 0.85)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		card.add_theme_stylebox_override("panel", sb)
		card.size = Vector2(132, 168)
		card.position = pos - card.size * 0.5
		holder.add_child(card)

		var num := Label.new()
		num.text = cn_num(n)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.add_theme_font_override("font", UITheme.make_title_font())
		num.add_theme_font_size_override("font_size", 86)
		num.add_theme_color_override("font_color", Color(0.97, 0.96, 0.92))
		num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		num.add_theme_constant_override("outline_size", 7)
		num.position = Vector2(6, -6)
		num.size = Vector2(card.size.x - 12, 116)
		card.add_child(num)

		var cap := Label.new()
		cap.text = "地 ×%d · %s" % [n, str(e.get("name", ""))]
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_override("font", UITheme.font())
		cap.add_theme_font_size_override("font_size", 14)
		cap.add_theme_color_override("font_color", UITheme.GOLD)
		cap.position = Vector2(6, 114)
		cap.size = Vector2(card.size.x - 12, 22)
		card.add_child(cap)

		card.scale = Vector2(0.6, 0.6)
		card.pivot_offset = card.size * 0.5
		card.modulate.a = 0.0
		var tw := holder.create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.16)
		tw.tween_property(card, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.set_parallel(false)
		tw.tween_interval(1.9)
		tw.tween_property(card, "modulate:a", 0.0, 0.45)
	# 2.9s 后整块收走
	var t := get_tree().create_timer(2.9)
	t.timeout.connect(func():
		if is_instance_valid(holder):
			holder.queue_free())


## 阿拉伯数字 → 汉字（繁体数字字形与简体一致：一二三四…十）
static func cn_num(n: int) -> String:
	if n <= 0:
		return "零"
	var d := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	if n < 10:
		return d[n]
	if n == 10:
		return "十"
	if n < 20:
		return "十" + d[n % 10]
	var t := int(n / 10)
	var o := n % 10
	return d[t] + "十" + ("" if o == 0 else d[o])


## 技能特效统一入口：BattleScreen 只调这一个，具体视觉按 fx 名分发。
## gpos  = 目标点（通常是施法者卡面中心）
## from  = 施法起点（默认等于 gpos，斩击类会从左上斜劈）
func play_fx(fx: String, gpos: Vector2, col: Color = UITheme.GOLD,
		from_g: Vector2 = Vector2.ZERO) -> void:
	if not CardView.effects_enabled or gpos == Vector2.ZERO:
		return
	# ---- Q 版序列帧优先：有素材就直接播它，不再叠程序化粒子/光环 ----
	# 【为什么不叠加】用户此前明确否掉过「莫名其妙的光效」；序列帧本身
	# 已经是完整演出，再套一圈光环只会互相打架、还把画面冲白。
	# 只有重击/地动/咆哮这三类额外保留屏幕震动 —— 序列帧只有画面，没有"手感"。
	if play_sheet(fx, gpos):
		match fx:
			"quake":
				shake(get_parent() as Control, 9.0)
			"smash", "roar", "clash":
				shake(get_parent() as Control, 6.0)
		return
	var origin: Vector2 = from_g if from_g != Vector2.ZERO else gpos
	match fx:
		"slash":
			slash(origin + Vector2(-150, -90), gpos + Vector2(60, 60), col)
			burst(gpos, col, 14, 220.0, 3.0)
		"smash", "clash":
			burst(gpos, col, 22, 260.0, 4.0)
			ring(gpos, col, 96.0)
			shake(get_parent() as Control, 6.0)
		"quake":
			ring(gpos, col, 220.0)
			burst(gpos, col, 30, 300.0, 4.4)
			shake(get_parent() as Control, 9.0)
		"fire":
			burst(gpos, Color("ff8b3d"), 28, 250.0, 4.2)
			ring(gpos, Color("ff6a2a"), 110.0)
			sigil(gpos, Color("ffb066"), 70.0)
		"bolt":
			beam(gpos + Vector2(0, -230), gpos, Color("9fd8ff"))
			burst(gpos, Color("bfe6ff"), 18, 240.0, 3.4)
			flash_screen(Color(0.7, 0.85, 1.0, 0.10), 0.24)
		"freeze":
			ring(gpos, Color("a8e0ff"), 96.0)
			sigil(gpos, Color("cfefff"), 66.0)
			burst(gpos, Color("d8f2ff"), 16, 160.0, 3.0)
		"wind":
			ring(gpos, Color("d8f4ea"), 130.0)
			burst(gpos, Color("cfeee6"), 24, 280.0, 3.2)
		"heal":
			ring(gpos, Color("7fe0a8"), 82.0)
			sigil(gpos, Color("9ff0c0"), 58.0)
			burst(gpos + Vector2(0, 26), Color("a8f0c4"), 18, 120.0, 3.0)
		"shield":
			ring(gpos, Color("8fc8ff"), 90.0)
			ring(gpos + Vector2(0, -6), Color("d6ecff"), 62.0)
			burst(gpos, Color("bfe0ff"), 14, 150.0, 3.0)
		"purge":
			sigil(gpos, Color("c0392b"), 92.0)
			burst(gpos, Color("e0604a"), 26, 240.0, 4.0)
			shake(get_parent() as Control, 7.0)
		"poison":
			burst(gpos, Color("8fbf6a"), 22, 170.0, 3.6)
			ring(gpos, Color("6f9f4a"), 96.0)
		"soul":
			sigil(gpos, Color("b39ce8"), 88.0)
			burst(gpos, Color("8e6fd0"), 22, 190.0, 3.4)
		"moon":
			ring(gpos, Color("b9b0e8"), 140.0)
			sigil(gpos, Color("d5cff5"), 76.0)
		"revive":
			sigil(gpos, Color("9ff0c0"), 92.0)
			ring(gpos, Color("c8ffe0"), 130.0)
			burst(gpos, Color("dfffe8"), 26, 150.0, 3.2)
		"summon":
			sigil(gpos, UITheme.GOLD, 96.0)
			ring(gpos, Color("ffe6a8"), 120.0)
			burst(gpos, UITheme.GOLD, 26, 220.0, 3.8)
		"buff":
			ring(gpos, UITheme.GOLD, 88.0)
			burst(gpos + Vector2(0, 30), Color("ffe9b0"), 20, 130.0, 3.0)
		"seal":
			sigil(gpos, Color("d0c8b0"), 80.0)
			burst(gpos, Color("b8b0a0"), 16, 150.0, 3.0)
		"chain":
			ring(gpos, Color("9fd0d8"), 100.0)
			burst(gpos, Color("cfecf0"), 18, 170.0, 3.0)
		"coin":
			burst(gpos, Color("ffd76a"), 20, 170.0, 3.4)
			ring(gpos, Color("ffe9a8"), 72.0)
		"arrow":
			beam(origin + Vector2(-190, -70), gpos + Vector2(40, 30), Color("e8e0c8"))
			burst(gpos, Color("f2ecd8"), 14, 200.0, 3.0)
		"roar":
			ring(gpos, Color("e07050"), 180.0)
			burst(gpos, Color("ff9a6a"), 30, 280.0, 4.2)
			shake(get_parent() as Control, 8.0)
		"draw":
			ring(gpos, Color("a8c8e8"), 60.0)
			burst(gpos, Color("cfe2f5"), 12, 140.0, 2.6)
		"dice":
			ring(gpos, UITheme.GOLD, 76.0)
			burst(gpos, Color("ffe6a8"), 16, 180.0, 3.2)
		_:
			ring(gpos, col, 78.0)
			burst(gpos, col, 16, 180.0, 3.2)


## 屏幕震动：作用于传入的容器（通常是战斗根节点）
## 【为什么必须回到 home 而不是 Vector2.ZERO】被震的 _world 是**锚点定位**的容器
## （offset 16,8），强行 tween 它的 position 会把 offset 一起改掉；
## 若归零到 (0,0)，震完整个战斗版面就永久向左上偏移 16px —— 用户报的
## 「画面左移」就是它。所以先记下原位，震完回到原位。
func shake(target: Control, strength: float = 7.0, dur: float = 0.32) -> void:
	if not CardView.effects_enabled or target == null:
		return
	var home: Vector2 = target.position
	var tw := create_tween()
	var steps := 7
	for i in steps:
		var k := 1.0 - float(i) / float(steps)
		var off := home + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)) * k
		tw.tween_property(target, "position", off, dur / float(steps))
	tw.tween_property(target, "position", home, 0.05)


## 全屏闪光（胜负手 / 大招）
func flash_screen(col: Color = Color(1, 0.9, 0.6, 0.18), dur: float = 0.3) -> void:
	if not CardView.effects_enabled:
		return
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 0.0, dur)
	tw.tween_callback(r.queue_free)


## 掷骰动画：中央骰子翻滚 ~1s 后停在 final_value，随后回调
## 拜神 / 敬鬼的点数展示用。动画期间拦截点击。
func dice_roll(final_value: int, on_done: Callable = Callable()) -> void:
	final_value = clampi(final_value, 1, 6)
	if not CardView.effects_enabled:
		if on_done.is_valid():
			on_done.call()
		return
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.add_child(dim)
	var d := DiceView.new()
	d.value = final_value
	d.size = Vector2(132, 132)
	d.pivot_offset = d.size * 0.5
	blocker.add_child(d)
	await resize_or_frame(blocker)
	d.position = blocker.size * 0.5 - d.size * 0.5
	d.start_roll()
	var tw := create_tween()
	tw.tween_property(dim, "color:a", 0.45, 0.2)
	await d.roll_done
	await get_tree().create_timer(0.55).timeout
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(d, "modulate:a", 0.0, 0.28)
	tw2.tween_property(dim, "color:a", 0.0, 0.28)
	tw2.set_parallel(false)
	tw2.tween_callback(blocker.queue_free)
	if on_done.is_valid():
		on_done.call()


func resize_or_frame(c: Control) -> void:
	if c.size != Vector2.ZERO:
		return
	await get_tree().process_frame


## 3D 观感骰子（圆角立方体 + 点数 + 翻滚/落地弹跳）
class DiceView:
	extends Control
	signal roll_done
	var value := 6
	var _show := 1
	var _t := 0.0
	var _rolling := true
	var _swap := 0.0

	func start_roll() -> void:
		_rolling = true
		_t = 0.0
		scale = Vector2(0.3, 0.3)
		rotation = -0.6
		modulate.a = 0.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "modulate:a", 1.0, 0.18)

	func _process(delta: float) -> void:
		_t += delta
		if _rolling:
			_swap += delta
			if _swap >= 0.075:
				_swap = 0.0
				_show = randi_range(1, 6)
			rotation = sin(_t * 9.0) * 0.22 * maxf(0.0, 1.0 - _t / 0.95)
			position.y += sin(_t * 22.0) * 0.35
			if _t >= 1.0:
				_rolling = false
				_show = value
				# 落地弹跳
				var tw := create_tween()
				tw.tween_property(self, "scale", Vector2(1.18, 0.86), 0.08)
				tw.tween_property(self, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
				tw.tween_callback(func(): roll_done.emit())
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := 22.0
		# 底影
		draw_circle(Vector2(w * 0.5, h + 8), w * 0.42, Color(0, 0, 0, 0.4))
		# 立方体面（圆角矩形近似：九宫画法）
		var face := Rect2(Vector2.ZERO, size)
		var col_top := Color(0.96, 0.92, 0.82)
		var col_bot := Color(0.82, 0.76, 0.62)
		# 垂直渐变（【★ 修「条形码阴影」】旧版 24 条离散横条堆渐变 → 改一次渐变纹理）
		draw_texture_rect(UITheme.vgrad2(col_top, col_bot),
			Rect2(0, 0, w, h), false)
		# 圆角描边
		_round_outline(face, Color(0.72, 0.58, 0.28), 3.0, r)
		_round_outline(face.grow(-4), Color(0.9, 0.8, 0.55, 0.5), 1.2, r - 3)
		# 点数
		var pips := _pip_layout(_show)
		var pip_r := w * 0.085
		for p in pips:
			var c := Vector2(w * 0.5 + p.x * w * 0.26, h * 0.5 + p.y * h * 0.26)
			draw_circle(c + Vector2(1.5, 2), pip_r, Color(0.2, 0.1, 0.08, 0.55))
			draw_circle(c, pip_r, Color(0.35, 0.12, 0.10))

	func _pip_layout(v: int) -> Array:
		match v:
			1: return [Vector2.ZERO]
			2: return [Vector2(-1, -1), Vector2(1, 1)]
			3: return [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]
			4: return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
			5: return [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)]
			6: return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]
		return []

	## 【★ 修「毛刺边缘」】圆角 8 段 + 直边无 AA → 折角；改为自适应段数 + 全 AA。
	func _round_outline(rect: Rect2, col: Color, width: float, r: float) -> void:
		var x0 := rect.position.x
		var y0 := rect.position.y
		var x1 := rect.end.x
		var y1 := rect.end.y
		var seg := clampi(int(r * 1.6) + 8, 10, 24)
		draw_line(Vector2(x0 + r, y0), Vector2(x1 - r, y0), col, width, true)
		draw_line(Vector2(x0 + r, y1), Vector2(x1 - r, y1), col, width, true)
		draw_line(Vector2(x0, y0 + r), Vector2(x0, y1 - r), col, width, true)
		draw_line(Vector2(x1, y0 + r), Vector2(x1, y1 - r), col, width, true)
		draw_arc(Vector2(x0 + r, y0 + r), r, PI, PI * 1.5, seg, col, width, true)
		draw_arc(Vector2(x1 - r, y0 + r), r, PI * 1.5, TAU, seg, col, width, true)
		draw_arc(Vector2(x1 - r, y1 - r), r, 0, PI * 0.5, seg, col, width, true)
		draw_arc(Vector2(x0 + r, y1 - r), r, PI * 0.5, PI, seg, col, width, true)
