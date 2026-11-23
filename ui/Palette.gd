# fourwd — color tokens for GDScript / procedural drawing.
# Autoloaded as "Palette" (see project.godot) — use Palette.GOLD, Palette.TRACK,
# etc. in _draw(), Polygon2D colors, shaders. (Also usable as FWSPalette.GOLD.)
#
# Theme: "Cobalt & Sun" (2026-11-20). A saturated cobalt backdrop, solid cream
# cards and panels, sun-yellow primary, red-orange "pop" secondary, and a deep
# navy INK that outlines every raised thing and draws the hard lip under it.
# Text on a cream card is TEXT (dark ink); text straight on the cobalt backdrop
# or the race field is TEXT_LIGHT.
class_name FWSPalette
extends Node

# ---- Backgrounds ----
const BLACK         := Color("0a143f")   # deepest navy: soft shadows, tyres, dark chequer squares
const INK           := Color("0d1b55")   # outlines and the hard lip under raised things
const BG            := Color("2346e0")   # cobalt: the menu backdrop
const BG_STRIPE     := Color("203fca")   # the backdrop's diagonal stripes
const BG_RAISED     := Color("122370")   # deep "screen" wells: track maps, thumb-pad wells
const FIELD         := Color("0f1f63")   # the race ground

# ---- Surfaces (cream cards and HUD panels) ----
const SURFACE       := Color("fff4dc")
const SURFACE_RAISED:= Color("fffcf5")   # hover
const SURFACE_INSET := Color("ede3cd")   # wells sunk into a card

# ---- Strokes ----
const STROKE        := Color("d6cdb9")   # hairlines and inset shading on cream
const STROKE_STRONG := Color("8f8778")   # minor ticks, locked things

# ---- Hero gold (sun) ----
const GOLD          := Color("ffc400")
const GOLD_BRIGHT   := Color("ffd64d")
const GOLD_DEEP     := Color("cc9d00")

# ---- Pop (red-orange): the player's car, the secondary button, the left pad ----
const POP           := Color("d9301a")
const POP_BRIGHT    := Color("e15948")
const POP_DEEP      := Color("ae2615")

# ---- Status ----
const SUCCESS       := Color("2fd27a")
const WARNING       := Color("ffa53d")
const DANGER        := Color("ff3b3b")
const DANGER_DEEP   := Color("c81e2a")

# ---- Medals ----
const MEDAL_GOLD    := Color("ffc21a")
const MEDAL_SILVER  := Color("d3dbe6")
const MEDAL_BRONZE  := Color("e0955a")

# ---- Text ----
const TEXT             := Color("0c184c")   # on cream cards, panels, ghost buttons
const TEXT_MUTED       := Color("575a74")
const TEXT_DIM         := Color("92919b")
const TEXT_LIGHT       := Color("ffffff")   # on the cobalt backdrop and the race field
const TEXT_LIGHT_MUTED := Color("d6defc")
const TEXT_ON_GOLD     := Color("0b1543")
const TEXT_ON_POP      := Color("ffffff")

# ---- Racetrack ----
const TRACK         := Color("1f9a4f")
const TRACK_EDGE    := Color("17703a")
const KERB          := Color("d9301a")   # alternates with white outside each wall
# The race itself is a night circuit (2026-11-22): dark asphalt under warm lamp
# light, with glowing limit lines. TRACK stays the green of the maps and menus.
const ROAD          := Color("2b3163")   # asphalt
const ROAD_EDGE     := Color("20254d")   # the darker strip beside each wall
const ROAD_CROWN    := Color("353c72")   # the lifted middle of the road
const LAMP          := Color("ffd98a")   # warm light pools from the track lamps

# ---- HUD scrims (dim the race behind a dialog) ----
const HUD_SCRIM         := Color(0.039, 0.078, 0.247, 0.72) # BLACK at 72%
const HUD_SCRIM_STRONG  := Color(0.039, 0.078, 0.247, 0.86)
