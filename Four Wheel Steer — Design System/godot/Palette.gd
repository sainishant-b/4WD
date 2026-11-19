# Four Wheel Steer — color tokens for GDScript / procedural drawing.
# Autoload this (Project Settings → Autoload, name "Palette") then use
# Palette.GOLD, Palette.TRACK, etc. in _draw(), Polygon2D colors, shaders.
class_name FWSPalette
extends Node

# ---- Backgrounds ----
const BLACK         := Color("07090f")
const BG            := Color("0b0f17")
const BG_RAISED     := Color("121826")

# ---- Surfaces ----
const SURFACE       := Color("161d2b")
const SURFACE_RAISED:= Color("202a3c")
const SURFACE_INSET := Color("0e131e")

# ---- Strokes ----
const STROKE        := Color("2a3346")
const STROKE_STRONG := Color("3c4a63")

# ---- Hero gold ----
const GOLD          := Color("ffc21a")
const GOLD_BRIGHT   := Color("ffd24d")
const GOLD_DEEP     := Color("e0a200")

# ---- Player blue ----
const BLUE          := Color("2fa8ff")
const BLUE_BRIGHT   := Color("5bc0ff")
const BLUE_DEEP     := Color("1b7ad0")

# ---- Status ----
const SUCCESS       := Color("2fd27a")
const WARNING       := Color("ffa53d")
const DANGER        := Color("ff4d58")
const DANGER_DEEP   := Color("de3340")

# ---- Medals ----
const MEDAL_GOLD    := Color("ffc21a")
const MEDAL_SILVER  := Color("c9d4e2")
const MEDAL_BRONZE  := Color("d08a4f")

# ---- Text ----
const TEXT          := Color("f2f6fc")
const TEXT_MUTED    := Color("93a0b4")
const TEXT_DIM      := Color("5c6a7e")
const TEXT_ON_GOLD  := Color("0b0f17")
const TEXT_ON_BLUE  := Color("07090f")

# ---- Racetrack ----
const TRACK         := Color("1f8f4e")
const TRACK_EDGE    := Color("15663a")

# ---- HUD scrims (float text over the bright track) ----
const HUD_SCRIM         := Color(0.027, 0.035, 0.059, 0.82) # rgba(7,9,15,.82)
const HUD_SCRIM_STRONG  := Color(0.027, 0.035, 0.059, 0.92)
