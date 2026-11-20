class_name AvatarBadge
extends Control
## A player's round avatar on the leaderboard: their Reddit snoovatar when the
## page can load it (`Reddit.avatar()`), else the first letter of their name on
## a colour picked from it, so every row has one. INK ring and lip, like the
## rest of the design system.
##
## Inside a Reddit post the server sends the avatar URLs with the board rows;
## elsewhere `url` is "" and the initial is all there is.

const RING := 2.5
const SIDES := 40

var _player := ""
var _texture: Texture2D = null


## `player` names the badge (and picks its colour); `url` is the avatar image,
## "" for none. `px` is the badge's diameter.
func setup(player: String, url: String, px: float = 34.0) -> void:
	_player = player
	custom_minimum_size = Vector2(px, px + 2.0)   # + the lip
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # the 96 px picture drawn small
	if url != "":
		Reddit.avatar(url, _on_avatar)
	queue_redraw()


## True once the avatar image has arrived (tests read this).
func has_picture() -> bool:
	return _texture != null


func _on_avatar(texture: Texture2D) -> void:
	_texture = texture
	queue_redraw()


## The same player always gets the same colour.
static func color_for(player: String) -> Color:
	var colors := [Palette.POP, Palette.GOLD, Palette.TRACK, Palette.BG, Palette.MEDAL_BRONZE]
	return colors[absi(player.hash()) % colors.size()]


func _draw() -> void:
	var r := minf(size.x, size.y - 2.0) * 0.5
	var c := Vector2(size.x * 0.5, r)
	var fill := color_for(_player)
	draw_circle(c + Vector2(0, 2), r, Palette.INK, true, -1.0, true)   # the lip
	draw_circle(c, r, fill, true, -1.0, true)
	if _texture != null:
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in SIDES:
			var d := Vector2.from_angle(TAU * i / SIDES)
			points.append(c + d * (r - RING * 0.5))
			uvs.append(Vector2(0.5, 0.5) + d * 0.5)
		draw_colored_polygon(points, Color.WHITE, uvs, _texture)
	else:
		var font := get_theme_font("font", "Label")
		var font_size := int(r * 1.05)
		var letter := _player.substr(0, 1).to_upper() if _player != "" else "?"
		var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := c.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		draw_string(font, Vector2(c.x - width * 0.5, baseline), letter, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, HudStyle.text_on(fill))
	draw_arc(c, r - RING * 0.5, 0.0, TAU, SIDES + 8, Palette.INK, RING, true)
