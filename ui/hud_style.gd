class_name HudStyle
extends RefCounted
## Shared look of the in-race overlay (HUD panels, mini map, speed gauge, thumb
## pads): translucent "glass" panels with a hairline rim and a soft shadow, plus
## the glow / vignette textures used for shading. Every colour derives from a
## Palette token; nothing here introduces a new one.
##
##   panel.add_theme_stylebox_override("panel", HudStyle.glass())
##   HudStyle.draw_glow(canvas_item, centre, radius, Color(Palette.GOLD, 0.4))
##
## It also holds `feather()`, the edge smoothing for solid world shapes. The
## Compatibility renderer has no 2D multisampling and `Polygon2D.antialiased`
## does nothing in it, so a filled polygon's edge is otherwise a staircase.

const RADIUS := 14
const BACKDROP_GRID := 48.0   # px between the menu backdrop's grid lines

# The controls, as (key caps, action) pairs. "<" ">" "^" "v" are drawn arrows.
const KEYBOARD_LEGEND := [
	[["W", "S"], "DRIVE"], [["A", "D"], "FRONT"], [["<", ">"], "REAR"],
	[["SHIFT"], "BOOST"], [["SPACE"], "DRIFT"], [["ESC"], "PAUSE"],
]
# On touch a cap is a thumb pad pushed up or pulled down; two caps = both pads.
const TOUCH_LEGEND := [
	[["^"], "DRIVE"], [["^", "^"], "BOOST"], [["v"], "DRIFT"], [["v", "v"], "BRAKE"],
]

static var _glow: GradientTexture2D
static var _vignette: GradientTexture2D
static var _rim: GradientTexture2D


## A translucent rounded panel. `alpha` is how solid the fill is.
static func glass(radius: int = RADIUS, alpha: float = 0.78) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.BG_RAISED, alpha)
	sb.border_color = Color(Palette.TEXT, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(Palette.BLACK, 0.4)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb


## A menu card (level select): a dark raised tile with a strip of `accent`
## colour along its top. `state` is the Button state it is drawn for.
static func card(accent: Color, state: String = "normal") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.SURFACE
	if state == "hover":
		sb.bg_color = Palette.SURFACE_RAISED
	elif state == "pressed":
		sb.bg_color = Palette.SURFACE_INSET
	elif state == "disabled":
		sb.bg_color = Color(Palette.SURFACE, 0.55)
	sb.border_color = accent
	sb.border_width_top = 4
	sb.set_corner_radius_all(RADIUS)
	sb.shadow_color = Color(Palette.BLACK, 0.5 if state != "disabled" else 0.25)
	sb.shadow_size = 14 if state == "hover" else 10
	sb.shadow_offset = Vector2(0, 2 if state == "pressed" else 5)
	sb.anti_aliasing = true
	return sb


## Gives a screen title depth: a soft dark drop shadow under the gold letters.
static func style_title(label: Label) -> void:
	label.add_theme_color_override("font_color", Palette.GOLD)
	label.add_theme_color_override("font_shadow_color", Color(Palette.BLACK, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("shadow_outline_size", 6)


## A solid rounded bar (boost fill, pause-icon bars, ...).
static func pill(color: Color, radius: int = 999) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


## White disc that fades smoothly to clear at its rim. Tint it when drawing.
static func glow() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0)])
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
	return _glow


## Clear in the middle, darkening toward the corners; stretched over the screen.
static func vignette() -> Texture2D:
	if _vignette == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([
			Color(Palette.BLACK, 0.0), Color(Palette.BLACK, 0.0), Color(Palette.BLACK, 0.5),
		])
		_vignette = GradientTexture2D.new()
		_vignette.gradient = g
		_vignette.fill = GradientTexture2D.FILL_RADIAL
		_vignette.fill_from = Vector2(0.5, 0.5)
		_vignette.fill_to = Vector2(1.0, 1.0)
		_vignette.width = 256
		_vignette.height = 256
	return _vignette


## White frame, clear in the middle and solid at the corners. Tint it and fade
## it for a full-screen flash (the wall-hit warning).
static func rim() -> Texture2D:
	if _rim == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
		_rim = GradientTexture2D.new()
		_rim.gradient = g
		_rim.fill = GradientTexture2D.FILL_RADIAL
		_rim.fill_from = Vector2(0.5, 0.5)
		_rim.fill_to = Vector2(1.0, 1.0)
		_rim.width = 256
		_rim.height = 256
	return _rim


## The controls as rows of "cap + action" pairs, `per_row` pairs to a row, in
## the bold display face. Keyboard keys are drawn as key caps; touch gestures
## as little thumb pads (two = both pads, in the pads' own blue and gold).
static func controls_legend(touch: bool, per_row: int, font_size: int) -> Control:
	var entries: Array = TOUCH_LEGEND if touch else KEYBOARD_LEGEND
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = null
	for i in entries.size():
		if i % per_row == 0:
			row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", roundi(font_size * 1.25))
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.add_child(row)
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 5)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caps: Array = entries[i][0]
		for k in caps.size():
			var tint := Palette.TEXT_MUTED
			if touch and caps.size() > 1:
				tint = Palette.BLUE if k == 0 else Palette.GOLD
			pair.add_child(_cap(String(caps[k]), font_size, touch, tint))
		var action := Label.new()
		action.text = String(entries[i][1])
		action.add_theme_font_size_override("font_size", font_size)
		action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		style_panel_label(action, Palette.TEXT)
		pair.add_child(action)
		row.add_child(pair)
	return rows


## One cap of the legend: a key cap with its front face (keyboard) or a round
## thumb pad ringed in `tint` (touch), holding a letter or a drawn arrow.
static func _cap(token: String, font_size: int, round_pad: bool, tint: Color) -> Control:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = true
	if round_pad:
		sb.bg_color = Color(Palette.BG_RAISED, 0.9)
		sb.border_color = tint
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(999)
		sb.set_content_margin_all(0)
	else:
		sb.bg_color = Palette.SURFACE_RAISED
		sb.border_color = Palette.STROKE_STRONG
		sb.set_border_width_all(1)
		sb.border_width_bottom = 3   # the key's front face
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 7.0
		sb.content_margin_right = 7.0
		sb.content_margin_top = 1.0
		sb.content_margin_bottom = 3.0
	cap.add_theme_stylebox_override("panel", sb)

	var arrows := {"<": Vector2.LEFT, ">": Vector2.RIGHT, "^": Vector2.UP, "v": Vector2.DOWN}
	if arrows.has(token):
		var dir: Vector2 = arrows[token]
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var side := font_size + 10.0
		icon.custom_minimum_size = Vector2(side, side) if round_pad else Vector2(font_size, font_size * 1.3)
		icon.draw.connect(func() -> void:
			var c := icon.size * 0.5
			var r := font_size * 0.32
			var across := Vector2(-dir.y, dir.x)
			var pts := PackedVector2Array([
				c + dir * r, c - dir * r * 0.8 + across * r, c - dir * r * 0.8 - across * r,
			])
			icon.draw_colored_polygon(pts, Palette.TEXT)
			pts.append(pts[0])
			icon.draw_polyline(pts, Palette.TEXT, 1.0, true)
		)
		cap.add_child(icon)
	else:
		var letter := Label.new()
		letter.text = token
		letter.add_theme_font_size_override("font_size", font_size)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		style_panel_label(letter, Palette.TEXT)
		cap.add_child(letter)
	return cap


## Draws a soft round glow (or, with a dark colour, a soft shadow) on `item`.
static func draw_glow(item: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	item.draw_texture_rect(
		glow(), Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color
	)


## The shared menu background: the navy field with the same faint grid the
## track sits on, a wash of the two brand colours, and darkened corners. Call
## it first in a screen's `_build()`.
static func add_backdrop(screen: Control) -> void:
	var bg := Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(func() -> void:
		var area := Rect2(Vector2.ZERO, bg.size)
		bg.draw_rect(area, Palette.BG)
		var line := Color(Palette.STROKE, 0.3)
		var x := fmod(area.size.x * 0.5, BACKDROP_GRID)
		while x < area.size.x:
			bg.draw_line(Vector2(x, 0), Vector2(x, area.size.y), line, 1.0, true)
			x += BACKDROP_GRID
		var y := fmod(area.size.y * 0.5, BACKDROP_GRID)
		while y < area.size.y:
			bg.draw_line(Vector2(0, y), Vector2(area.size.x, y), line, 1.0, true)
			y += BACKDROP_GRID
		var reach := maxf(area.size.x, area.size.y) * 0.6
		draw_glow(bg, area.size * Vector2(0.1, 0.08), reach, Color(Palette.BLUE, 0.13))
		draw_glow(bg, area.size * Vector2(0.92, 0.96), reach, Color(Palette.GOLD, 0.08))
		bg.draw_texture_rect(vignette(), area, false)
	)
	screen.add_child(bg)


## Smooths the edge of an opaque Polygon2D by tracing it with a thin
## anti-aliased line in the same colour. Skip translucent shapes: the line
## would overlap the fill and show as a darker rim.
static func feather(shape: Polygon2D) -> void:
	var rim := Line2D.new()
	rim.points = shape.polygon
	rim.closed = true
	rim.width = 1.5
	rim.default_color = shape.color
	rim.antialiased = true
	shape.add_child(rim)


## A label meant to sit ON a glass panel: no outline, so the glyphs stay crisp.
static func style_panel_label(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)


## A label that floats over the track: a dark halo instead of a hard outline.
## Small text (`small` = true) gets only a thin rim, which stays legible; the
## wider soft halo suits big text and turns to smudge under a caption.
static func style_floating_label(label: Label, color: Color, small := false) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(Palette.BLACK, 0.6))
	label.add_theme_constant_override("outline_size", 3 if small else 4)
	label.add_theme_color_override("font_shadow_color", Color(Palette.BLACK, 0.0 if small else 0.45))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0 if small else 2)
	label.add_theme_constant_override("shadow_outline_size", 0 if small else 8)
