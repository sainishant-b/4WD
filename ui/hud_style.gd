class_name HudStyle
extends RefCounted
## Shared look of the menus and the in-race overlay ("Cobalt & Sun"): solid
## cream panels with a 3 px INK outline and a hard INK lip underneath (drawn
## below the panel's rect), over a soft navy shadow. Also the glow / vignette
## textures used for shading, the cobalt striped menu backdrop, title and
## "sticker" label styles, and the controls legend. Every colour derives from a
## Palette token; nothing here introduces a new one.
##
##   panel.add_theme_stylebox_override("panel", HudStyle.panel())
##   HudStyle.style_sticker(label, Palette.GOLD)
##
## It also holds `feather()`, the edge smoothing for solid world shapes. The
## Compatibility renderer has no 2D multisampling and `Polygon2D.antialiased`
## does nothing in it, so a filled polygon's edge is otherwise a staircase.

const RADIUS := 16
const OUTLINE := 3            # px of INK round every raised thing
const LIP := 5                # px of hard INK lip under a raised panel
const STRIPE := 28.0          # px: width of one backdrop stripe ...
const STRIPE_PERIOD := 56.0   # ... and the distance between stripes (both across them)
const CHEQUER := 22.0         # px: height of the chequered strip (two rows of squares)

# Line icons as SVG path data on a 24 x 24 grid, for `icon()`.
const ICON_ARROW := "M5 12h13M13 6l6 6-6 6"
const ICON_BACK := "M15 6l-6 6 6 6"
const ICON_RETRY := "M4 12a8 8 0 1 0 2.3-5.7M4 4v4h4"
const ICON_BOARD := "M4 20h16M6 20v-6h4v6M10 20V8h4v12M14 20v-9h4v9"
const ICON_CLOCK := "M12 3a9 9 0 1 1 0 18a9 9 0 1 1 0-18zM12 7v5l3 2"

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
static var _icons := {}


## A raised cream panel: INK outline, a hard INK lip below it and a soft shadow
## under that. `pressed` = pushed in (a darker face, almost no lip).
static func panel(radius: int = RADIUS, pressed := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var lip := 1 if pressed else LIP
	sb.bg_color = Palette.SURFACE_INSET if pressed else Palette.SURFACE
	sb.border_color = Palette.INK
	sb.set_border_width_all(OUTLINE)
	sb.border_width_bottom = OUTLINE + lip
	sb.expand_margin_bottom = lip
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(Palette.BLACK, 0.3 if pressed else 0.45)
	sb.shadow_size = 4 if pressed else 10
	sb.shadow_offset = Vector2(0, 2 if pressed else 6)
	sb.set_content_margin_all(12)
	sb.anti_aliasing = true
	return sb


## A well sunk into a cream card: a darker face with a shaded top edge.
static func inset(radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.SURFACE_INSET
	sb.border_color = Palette.STROKE
	sb.border_width_top = OUTLINE
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	sb.anti_aliasing = true
	return sb


## A menu card (level select) for Button state `state`: a raised cream panel
## that lifts on hover, sinks when pressed and fades when locked.
static func card(state: String = "normal") -> StyleBoxFlat:
	var sb := panel(RADIUS, state == "pressed")
	if state == "hover":
		sb.bg_color = Palette.SURFACE_RAISED
		sb.shadow_size = 13
	elif state == "disabled":
		sb.bg_color = Color(Palette.SURFACE, 0.62)
		sb.border_color = Color(Palette.INK, 0.7)
		sb.shadow_color = Color(Palette.BLACK, 0.2)
	return sb


## A small filled chip (medal, NEW BEST, streak ...): `color` face, INK rim
## and a 2 px lip.
static func chip(color: Color) -> StyleBoxFlat:
	var sb := pill(color)
	sb.border_color = Palette.INK
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	sb.expand_margin_bottom = 2
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	return sb


## Dark text for a light chip, white for a dark one.
static func text_on(color: Color) -> Color:
	return Palette.TEXT_ON_GOLD if color.get_luminance() > 0.45 else Palette.TEXT_ON_POP


## A label on a filled chip tilted a few degrees, like a sticker slapped on
## (the DAY n tag on Today's Circuit). Containers reset a child's rotation, so
## the tilted label sits in a plain holder sized to it.
static func tag(text: String, color: Color, font_size: int = 16) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", text_on(color))
	var box := chip(color)
	box.set_corner_radius_all(10)
	box.set_border_width_all(OUTLINE)
	box.border_width_bottom = OUTLINE + 2
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 3.0
	l.add_theme_stylebox_override("normal", box)
	l.rotation = deg_to_rad(-3.0)
	holder.add_child(l)
	var fit := func() -> void:
		var need := l.get_combined_minimum_size()
		holder.custom_minimum_size = need
		l.size = need
		l.pivot_offset = need * 0.5
	l.minimum_size_changed.connect(fit)
	l.ready.connect(fit)
	return holder


## A line icon (`path_d`, SVG path data on a 24 x 24 grid, stroked round) in
## `color`, `px` pixels square, for a Button's `icon` or a TextureRect. Cached.
static func icon(path_d: String, color: Color, px: int = 24, stroke: float = 3.0) -> Texture2D:
	var key := "%s|%s|%d|%.2f" % [path_d, color.to_html(), px, stroke]
	if _icons.has(key):
		return _icons[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">' \
		+ '<path d="%s" fill="none" stroke="#%s" stroke-width="%.2f" stroke-linecap="round" stroke-linejoin="round"/></svg>' \
		% [path_d, color.to_html(false), stroke]
	var img := Image.new()
	img.load_svg_from_string(svg, px / 24.0)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## A chequered strip, two rows of squares under an INK rule, along the bottom
## edge of `screen` (Today's Circuit).
static func add_chequer(screen: Control) -> void:
	var strip := Control.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -(CHEQUER + OUTLINE)
	strip.offset_bottom = 0.0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.draw.connect(func() -> void:
		var cell := CHEQUER * 0.5
		strip.draw_rect(Rect2(0, 0, strip.size.x, OUTLINE), Palette.INK)
		var x := 0
		while x * cell < strip.size.x:
			for row in 2:
				var light := (x + row) % 2 == 0
				strip.draw_rect(
					Rect2(x * cell, OUTLINE + row * cell, cell, cell),
					Palette.TEXT_LIGHT if light else Palette.INK
				)
			x += 1
	)
	screen.add_child(strip)


## A screen title straight on the cobalt backdrop: white letters standing on a
## hard INK shadow. `on_card` = a heading on a cream card instead: plain ink.
static func style_title(label: Label, on_card := false) -> void:
	if on_card:
		label.add_theme_color_override("font_color", Palette.TEXT)
		return
	label.add_theme_color_override("font_color", Palette.TEXT_LIGHT)
	label.add_theme_color_override("font_shadow_color", Palette.INK)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_constant_override("shadow_outline_size", 1)


## A coloured word that has to read on cream (medal titles, gold headings):
## `color` letters with an INK outline and a hard INK shadow, like a sticker.
static func style_sticker(label: Label, color: Color, outline: int = 8) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Palette.INK)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_shadow_color", Palette.INK)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", maxi(2, outline / 2))
	label.add_theme_constant_override("shadow_outline_size", outline)


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
## as little thumb pads (two = both pads, in the pads' own red and gold).
## Actions named in `omit` (e.g. "FRONT") are left out; `extra` entries (same
## shape as the legends, e.g. [["H"], "HIDE"]) are added at the end.
## `text_color` is the action words' colour: ink on a cream panel, TEXT_LIGHT
## on the backdrop.
static func controls_legend(touch: bool, per_row: int, font_size: int, omit: Array = [], text_color: Color = Palette.TEXT, extra: Array = []) -> Control:
	var entries: Array = []
	for entry in (TOUCH_LEGEND if touch else KEYBOARD_LEGEND):
		if not omit.has(entry[1]):
			entries.append(entry)
	entries.append_array(extra)
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
			var tint := Palette.TEXT_LIGHT_MUTED
			if touch and caps.size() > 1:
				tint = Palette.POP if k == 0 else Palette.GOLD
			pair.add_child(cap(String(caps[k]), font_size, touch, tint))
		var action := Label.new()
		action.text = String(entries[i][1])
		action.add_theme_font_size_override("font_size", font_size)
		action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		style_panel_label(action, text_color)
		pair.add_child(action)
		row.add_child(pair)
	return rows


## One cap of the legend: a cream key cap with an INK rim and a deep front face
## (keyboard), or a round deep-blue thumb pad ringed in `tint` (touch), holding
## a letter or a drawn arrow ("<" ">" "^" "v", or "<>" for a pad slid either way).
static func cap(token: String, font_size: int, round_pad: bool, tint: Color) -> Control:
	var key := PanelContainer.new()
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = true
	if round_pad:
		sb.bg_color = Palette.BG_RAISED
		sb.border_color = tint
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(999)
		sb.set_content_margin_all(0)
		sb.shadow_color = Palette.INK
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(0, 2)
	else:
		sb.bg_color = Palette.SURFACE
		sb.border_color = Palette.INK
		sb.set_border_width_all(2)
		sb.border_width_bottom = 5   # the key's front face
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 7.0
		sb.content_margin_right = 7.0
		sb.content_margin_top = 1.0
		sb.content_margin_bottom = 3.0
	key.add_theme_stylebox_override("panel", sb)
	var ink := Palette.TEXT_LIGHT if round_pad else Palette.TEXT

	var arrows := {
		"<": [Vector2.LEFT], ">": [Vector2.RIGHT], "^": [Vector2.UP], "v": [Vector2.DOWN],
		"<>": [Vector2.LEFT, Vector2.RIGHT],
	}
	if arrows.has(token):
		var dirs: Array = arrows[token]
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var side := font_size + 10.0
		icon.custom_minimum_size = Vector2(side, side) if round_pad else Vector2(font_size, font_size * 1.3)
		icon.draw.connect(func() -> void:
			var r := font_size * (0.22 if dirs.size() > 1 else 0.32)
			for dir: Vector2 in dirs:
				# A pair of arrows sits apart, one either side of the middle.
				var c := icon.size * 0.5 + (dir * font_size * 0.36 if dirs.size() > 1 else Vector2.ZERO)
				var across := Vector2(-dir.y, dir.x)
				var pts := PackedVector2Array([
					c + dir * r, c - dir * r * 0.8 + across * r, c - dir * r * 0.8 - across * r,
				])
				icon.draw_colored_polygon(pts, ink)
				pts.append(pts[0])
				icon.draw_polyline(pts, ink, 1.0, true)
		)
		key.add_child(icon)
	else:
		var letter := Label.new()
		letter.text = token
		letter.add_theme_font_size_override("font_size", font_size)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		style_panel_label(letter, ink)
		key.add_child(letter)
	return key


## Draws a soft round glow (or, with a dark colour, a soft shadow) on `item`.
static func draw_glow(item: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	item.draw_texture_rect(
		glow(), Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color
	)


## The shared menu background: saturated cobalt with wide diagonal stripes a
## shade darker. Call it first in a screen's `_build()`.
static func add_backdrop(screen: Control) -> void:
	var bg := Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(func() -> void:
		var area := Rect2(Vector2.ZERO, bg.size)
		bg.draw_rect(area, Palette.BG)
		# Stripes run up to the right at 45 degrees; `step` is the period along x.
		var step := STRIPE_PERIOD * sqrt(2.0)
		var reach := area.size.y + STRIPE * 2.0
		var x := 0.0
		while x < area.size.x + reach:
			var top := Vector2(x + STRIPE, -STRIPE)
			bg.draw_line(top, top + Vector2(-reach, reach), Palette.BG_STRIPE, STRIPE, true)
			x += step
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


## A label meant to sit ON a panel: no outline, so the glyphs stay crisp.
static func style_panel_label(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)


## A label that floats over the track: an INK halo instead of a hard outline.
## Small text (`small` = true) gets only a thin rim, which stays legible; the
## wider soft halo suits big text and turns to smudge under a caption.
static func style_floating_label(label: Label, color: Color, small := false) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(Palette.INK, 0.85))
	label.add_theme_constant_override("outline_size", 3 if small else 5)
	label.add_theme_color_override("font_shadow_color", Color(Palette.BLACK, 0.0 if small else 0.5))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0 if small else 3)
	label.add_theme_constant_override("shadow_outline_size", 0 if small else 8)
