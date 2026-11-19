## Four Wheel Steer — Godot 4 setup

Two files here:

- `four_wheel_steer_theme.tres` — a Godot 4 `Theme` resource (Button + variants, Panel
  surfaces, HSlider) built from the design tokens.
- `Palette.gd` — every color token as GDScript constants, for the procedural bits the
  theme can't cover (the moving track, speedometer `_draw()`, car polygons, the HUD
  checkpoint arrow).

### 1. Install

1. Copy both files into your project, e.g. `res://ui/`.
2. Copy the two fonts (download from fonts.google.com, weights 400/500/600/700):
   - **Chakra Petch** → `res://ui/fonts/ChakraPetch-Bold.ttf` (display/UI/HUD)
   - **Barlow** → `res://ui/fonts/Barlow-Regular.ttf` (body copy)

### 2. Assign the fonts to the theme

The `.tres` ships **without** embedded fonts so it loads cleanly. Add them once:

- Open `four_wheel_steer_theme.tres` in the editor → in the Theme panel, set the
  **Default Font** to `ChakraPetch-Bold.ttf`. That gives every Button/Label the display
  face. For body paragraphs, set those specific `Label`s' font to Barlow (or add a
  `LabelBody` type variation with `font = Barlow`).

Or in code:

```gdscript
var theme := preload("res://ui/four_wheel_steer_theme.tres")
theme.default_font = preload("res://ui/fonts/ChakraPetch-Bold.ttf")
```

### 3. Apply it

Set the theme on your root `Control` (it cascades to all children), or as the project
default: **Project → Project Settings → GUI → Theme → Custom**.

### 4. Use the variants

The base `Button` is the **gold primary**. For the others, set `theme_type_variation`
on the node:

| Want | Node | `theme_type_variation` |
|---|---|---|
| Gold CTA (Play, Got it) | Button | *(none)* |
| Blue action (How to Play) | Button | `ButtonSecondary` |
| Outline (Settings, Back) | Button | `ButtonGhost` |
| Quit / destructive | Button | `ButtonDanger` |
| Card / settings panel | PanelContainer | *(none)* |
| Panel with gold stripe | PanelContainer | `PanelStripe` |
| Dialog (Pause/Results) | PanelContainer | `PanelModal` |
| Slider track well | PanelContainer | `PanelInset` |

```gdscript
$PlayButton.text = "Play"                       # gold, no variation
$SettingsButton.theme_type_variation = "ButtonGhost"
$QuitButton.theme_type_variation = "ButtonDanger"
$PausePanel.theme_type_variation = "PanelModal"
```

> **Touch targets:** give mobile Buttons/Sliders a `custom_minimum_size.y` of **48–56**
> (the lg CTA). The GAS/REV pads and steering sliders are 72–96px.

### 5. Steering slider (front/rear wheels)

Use an `HSlider` with `min_value = -1, max_value = 1, value = 0` so the grabber rests at
center. Make it taller for thumbs: `custom_minimum_size = Vector2(0, 72)`. Tint the fill
per axle in code:

```gdscript
var fill := slider.get_theme_stylebox("grabber_area").duplicate()
fill.bg_color = Palette.BLUE   # front wheels (gold for rear)
slider.add_theme_stylebox_override("grabber_area", fill)
```

### 6. The procedural pieces (use `Palette.gd`)

- **Moving track:** a scrolling `TextureRect`/`ColorRect` in `Palette.TRACK` with
  `Palette.TRACK_EDGE` rumble strips; scroll its UV/region each frame.
- **Speedometer:** a `Control` with `_draw()` — `draw_arc(center, r, start, end, ...)`
  for the `Palette.SURFACE_INSET` track and the `Palette.GOLD` value arc, a needle
  `draw_line`, ticks, and a center value `Label`.
- **HUD readouts:** wrap each in a `PanelInset` (or a `StyleBoxFlat` with
  `bg_color = Palette.HUD_SCRIM`) so text floats over the bright track; add
  `font_outline` (size 4, `Palette.BLACK`) to hero timer/speed `Label`s.
- **Checkpoint arrow:** a `Polygon2D` in `Palette.GOLD` with a `Line2D` outline in
  `Palette.BG`, rotated toward the next gate, pinned to a screen edge.
- **Countdown / GO:** a center `Label` (Chakra Petch ~132) driven by a `Timer`; gold for
  GO, `font_outline` on the numbers; pop-in via an `AnimationPlayer` scale tween.
- **Cars:** `Polygon2D`s — blue body `Palette.BLUE`, gold nose `Palette.GOLD`, four wheel
  rects you rotate independently (the whole point of the game).

### 7. Responsive

Desktop opens landscape (16:9), mobile runs portrait (9:16). Build screens with Control
**anchors** + `HBox`/`VBox` containers and swap the layout container on orientation
change — don't hard-code positions. The full reference layouts (both aspects) are in
the design system's `ui_kits/game/`.
