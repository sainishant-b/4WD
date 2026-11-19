"""Preview the circuit BEFORE wiring it into Godot.

Uses the same waypoints and the same centre-line math as track_builder.gd
(centripetal Catmull-Rom -> even resample -> relax bends tighter than the road
can follow), and renders the road, walls, checkpoint gates, obstacles and car
start to a PNG so the track shape can be eyeballed.
    python tools/preview_track.py [t1..t5|mp]   one track  -> track_preview.png
    python tools/preview_track.py all           all levels -> docs/tracks_overview.png
"""
import math
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon as MplPolygon

# --- Track presets (keep in sync with game_data.gd) -------------------------
# Select with: python tools/preview_track.py [t1..t5|mp|all]   (default t1)
TRACKS = {
    # Level 1: medium-width, flowing with one tight right-hand pair.
    "t1": {"waypoints": [
        (720, 520), (1180, 440), (1620, 540), (2060, 450),
        (2420, 640), (2500, 1000), (2300, 1240), (2460, 1480),
        (2040, 1560), (1600, 1440), (1160, 1560), (780, 1400),
        (600, 1040), (560, 720),
    ], "road_width": 88.0, "checkpoints": 8},
    # Level 2: the tight twisty circuit.
    "t2": {"waypoints": [
        (881, 545), (1493, 524), (1925, 567),
        (2249, 761), (2069, 941), (2285, 1121), (2105, 1301),
        (2177, 1481), (1817, 1503), (1493, 1373), (1205, 1517),
        (917, 1409), (665, 1229), (845, 1013), (650, 826), (816, 653),
    ], "road_width": 75.0, "checkpoints": 9},
    # Level 3: narrow, with deeper esses on both sides.
    "t3": {"waypoints": [
        (820, 560), (1280, 500), (1700, 580), (2120, 520),
        (2360, 820), (2080, 1020), (2380, 1260), (2080, 1480),
        (1680, 1420), (1340, 1520), (1000, 1380), (760, 1480),
        (620, 1120), (920, 940), (640, 720),
    ], "road_width": 72.0, "checkpoints": 9},
    # Level 4: esses along the top, a tight two-hairpin switchback, a chicane along the bottom, esses up the left.
    "t4": {"waypoints": [
        (700, 480), (950, 400), (1200, 530), (1450, 400),
        (1700, 500), (2330, 560), (2460, 800), (2360, 990),
        (2050, 1010), (1790, 1020), (1690, 1095), (1790, 1170),
        (2100, 1180), (2380, 1210), (2480, 1320), (2380, 1430),
        (2160, 1520), (1950, 1390), (1740, 1530), (1400, 1440),
        (1000, 1520), (680, 1420), (540, 1150), (700, 900),
        (540, 700),
    ], "road_width": 68.0, "checkpoints": 10},
    # Level 5: esses into a narrow inlet with a hairpin at its foot, esses along the bottom, a double switchback, a kink up the left.
    "t5": {"waypoints": [
        (700, 520), (860, 450), (1040, 570), (1220, 460),
        (1400, 640), (1400, 950), (1480, 1110), (1560, 950),
        (1560, 640), (1700, 500), (2000, 460), (2300, 520),
        (2470, 720), (2380, 960), (2480, 1200), (2360, 1430),
        (2150, 1530), (1930, 1400), (1710, 1540), (1500, 1440),
        (1250, 1500), (1070, 1400), (1040, 1050), (940, 900),
        (840, 1050), (840, 1280), (740, 1410), (640, 1280),
        (570, 1110), (680, 950), (590, 790),
    ], "road_width": 64.0, "checkpoints": 12},
    # Multiplayer (hidden): a wide flowing loop so cars race side-by-side and bump.
    "mp": {"waypoints": [
        (700, 400), (1500, 360), (2200, 460),
        (2520, 850), (2350, 1300), (1750, 1560),
        (1050, 1560), (520, 1300), (330, 850), (600, 500),
    ], "road_width": 180.0, "checkpoints": 6},
}
# Level order for the `all` sheet ("mp" is the hidden multiplayer track, left out).
LEVELS = ["t1", "t2", "t3", "t4", "t5"]
LEGEND = "red line = start/finish    green = gates (numbered in order)    blue arrow = car start"
# Keep these in step with the constants in scripts/track_builder.gd.
SPLINE_STEPS = 48     # spline evaluations per waypoint segment
SPACING = 10.0        # px between centre-line points
BEND_MARGIN = 24.0    # tightest bend radius = half the road width + this
RELAX_PASSES = 400
RELAX_SPREAD = 3
START_BACK = 60.0     # px behind the start line where the car spawns


def centripetal(p0, p1, p2, p3, u):
    """Centripetal Catmull-Rom (Barry-Goldman form): no overshoot or kinks."""
    t0 = 0.0
    t1 = t0 + math.sqrt(max(math.dist(p0, p1), 1e-4))
    t2 = t1 + math.sqrt(max(math.dist(p1, p2), 1e-4))
    t3 = t2 + math.sqrt(max(math.dist(p2, p3), 1e-4))
    t = t1 + (t2 - t1) * u

    def lerp(a, b, ta, tb):
        w = (t - ta) / (tb - ta)
        return (a[0] + (b[0] - a[0]) * w, a[1] + (b[1] - a[1]) * w)
    a1, a2, a3 = lerp(p0, p1, t0, t1), lerp(p1, p2, t1, t2), lerp(p2, p3, t2, t3)
    b1, b2 = lerp(a1, a2, t0, t2), lerp(a2, a3, t1, t3)
    return lerp(b1, b2, t1, t2)


def spline_point(pts, t):
    """The raw spline at t (0..1 = once round the waypoints)."""
    n = len(pts)
    f = (t % 1.0) * n
    i = int(f) % n
    return centripetal(pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n], f - math.floor(f))


def resample(poly, spacing):
    """Evenly spaced copy of a closed polyline."""
    n = len(poly)
    total = sum(math.dist(poly[i], poly[(i + 1) % n]) for i in range(n))
    count = max(8, round(total / spacing))
    step = total / count
    out = []
    seg, seg_start, seg_len = 0, 0.0, math.dist(poly[0], poly[1])
    for k in range(count):
        d = k * step
        while seg_start + seg_len < d and seg < n - 1:
            seg_start += seg_len
            seg += 1
            seg_len = math.dist(poly[seg], poly[(seg + 1) % n])
        w = 0.0 if seg_len < 1e-9 else (d - seg_start) / seg_len
        a, b = poly[seg], poly[(seg + 1) % n]
        out.append((a[0] + (b[0] - a[0]) * w, a[1] + (b[1] - a[1]) * w))
    return out


def bend_radius(a, b, c):
    cross = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
    if cross < 1e-9:
        return float("inf")
    return math.dist(a, b) * math.dist(b, c) * math.dist(c, a) / (2.0 * cross)


def relax(poly, min_radius):
    """Ease every bend tighter than min_radius; the rest of the line stays put."""
    pts = list(poly)
    for it in range(RELAX_PASSES):
        n = len(pts)
        tight = [bend_radius(pts[i - 1], pts[i], pts[(i + 1) % n]) < min_radius for i in range(n)]
        if not any(tight):
            break
        new = list(pts)
        for i in range(n):
            if any(tight[(i + k) % n] for k in range(-RELAX_SPREAD, RELAX_SPREAD + 1)):
                a, b = pts[i - 1], pts[(i + 1) % n]
                new[i] = (pts[i][0] + 0.5 * ((a[0] + b[0]) * 0.5 - pts[i][0]),
                          pts[i][1] + 0.5 * ((a[1] + b[1]) * 0.5 - pts[i][1]))
        pts = new
        if it % 8 == 7:
            pts = resample(pts, SPACING)
    return pts


def centerline(pts, road_width):
    total = len(pts) * SPLINE_STEPS
    dense = [spline_point(pts, i / total) for i in range(total)]
    line = relax(resample(dense, SPACING), road_width / 2.0 + BEND_MARGIN)
    return resample(line, SPACING)


def nearest(poly, p):
    return min(range(len(poly)), key=lambda i: math.dist(poly[i], p))


def offsets(samples, hw):
    n = len(samples)
    left, right = [], []
    for i in range(n):
        a, b = samples[(i - 1) % n], samples[(i + 1) % n]
        tx, ty = b[0] - a[0], b[1] - a[1]
        L = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / L, tx / L
        px, py = samples[i]
        left.append((px + nx * hw, py + ny * hw))
        right.append((px - nx * hw, py - ny * hw))
    return left, right


def draw_track(ax, track, detail=1.0):
    """Draws one circuit on `ax`; `detail` < 1 shrinks markers and labels for the overview.
    Returns the number of centre-line points."""
    waypoints = track["waypoints"]
    road_width = track["road_width"]
    checkpoints = track["checkpoints"]
    hw = road_width / 2.0
    samples = centerline(waypoints, road_width)
    left, right = offsets(samples, hw)
    n = len(samples)

    xs = [p[0] for p in samples]
    ys = [p[1] for p in samples]
    # Colors mirror the design palette: navy field, green road, gold lane line.
    ax.set_facecolor("#0b0f17")  # field (Palette.BG)

    road = left + right[::-1] + [left[0]]
    ax.add_patch(MplPolygon(road, closed=True, facecolor="#1f8f4e", edgecolor="none"))  # Palette.TRACK
    # The polygon above leaves the last segment of the loop unfilled; close it.
    ax.add_patch(MplPolygon([left[-1], left[0], right[0], right[-1]], closed=True, facecolor="#1f8f4e", edgecolor="none"))
    ax.plot([p[0] for p in left] + [left[0][0]], [p[1] for p in left] + [left[0][1]], color="#f2f6fc", lw=1.5 * detail)
    ax.plot([p[0] for p in right] + [right[0][0]], [p[1] for p in right] + [right[0][1]], color="#f2f6fc", lw=1.5 * detail)
    ax.plot(xs + [xs[0]], ys + [ys[0]], color="#ffc21a", lw=1, ls="--", alpha=0.6)

    for j in range(checkpoints):
        idx = nearest(samples, spline_point(waypoints, j / checkpoints))
        cx, cy = samples[idx]
        a, b = samples[(idx - 1) % n], samples[(idx + 1) % n]
        tx, ty = b[0] - a[0], b[1] - a[1]
        L = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / L, tx / L
        col = "#ff4d58" if j == 0 else "#2fd27a"
        ax.plot([cx - nx * hw, cx + nx * hw], [cy - ny * hw, cy + ny * hw], color=col, lw=4 * detail)
        ax.text(cx, cy, str(j + 1), color="white", ha="center", va="center",
                fontsize=12 * max(detail, 0.75), fontweight="bold")

    # Obstacles (cones ^, ramps >, walls = bar across the lane), if any are defined.
    for ob in track.get("obstacles", []):
        oi = nearest(samples, spline_point(waypoints, ob.get("t", 0.0)))
        oa, obp = samples[(oi - 1) % n], samples[(oi + 1) % n]
        otx, oty = obp[0] - oa[0], obp[1] - oa[1]
        oL = math.hypot(otx, oty) or 1.0
        onx, ony = -oty / oL, otx / oL
        ox = samples[oi][0] + onx * ob.get("offset", 0.0)
        oy = samples[oi][1] + ony * ob.get("offset", 0.0)
        ot = ob.get("type", "")
        if ot == "cone":
            ax.plot([ox], [oy], marker="^", color="#ff8c2a", markersize=11 * detail)
        elif ot == "ramp":
            ax.plot([ox], [oy], marker=">", color="#ffc21a", markersize=15 * detail)
        elif ot == "wall":
            j = ob.get("jut", 70.0) / 2.0
            ax.plot([ox - onx * j, ox + onx * j], [oy - ony * j, oy + ony * j], color="#ff4d58", lw=7 * detail)

    # Car start: ON the centre line, START_BACK px behind the line (matches track_builder.gd).
    si = (nearest(samples, spline_point(waypoints, 0.0)) - round(START_BACK / SPACING)) % n
    sx, sy = samples[si]
    pa, pb = samples[(si - 1) % n], samples[(si + 1) % n]
    ux, uy = pb[0] - pa[0], pb[1] - pa[1]
    L = math.hypot(ux, uy) or 1.0
    ux, uy = ux / L, uy / L
    ax.plot([sx], [sy], marker="o", color="#2fa8ff", markersize=9 * detail)
    ax.annotate("", xy=(sx + ux * 90, sy + uy * 90), xytext=(sx, sy),
                arrowprops=dict(color="#2fa8ff", width=3 * detail, headwidth=12 * detail))

    ax.set_aspect("equal")
    ax.invert_yaxis()  # Godot is y-down: small y = top
    return n


def main():
    sel = sys.argv[1] if len(sys.argv) > 1 else "t1"
    root = os.path.join(os.path.dirname(__file__), "..")

    if sel == "all":
        fig, axes = plt.subplots(2, 3, figsize=(27, 13.5))
        fig.patch.set_facecolor("#0b0f17")
        for ax, (number, key) in zip(axes.flat, enumerate(LEVELS, start=1)):
            track = TRACKS[key]
            n = draw_track(ax, track, detail=0.6)
            extra = ""
            kinds = sorted({ob.get("type", "") for ob in track.get("obstacles", [])})
            if kinds:
                extra = "   " + " + ".join(k + "s" for k in kinds)
            ax.set_title("Level %d   road %d px   lap %d px%s" % (number, track["road_width"], round(n * SPACING), extra),
                         color="#f2f6fc", fontsize=13)
            ax.set_xticks([])
            ax.set_yticks([])
            for spine in ax.spines.values():
                spine.set_color("#2a3346")
        for ax in list(axes.flat)[len(LEVELS):]:
            ax.set_visible(False)   # spare panels in the grid
        fig.suptitle(LEGEND, color="#93a0b4", fontsize=13, y=0.04)
        out = os.path.join(root, "docs", "tracks_overview.png")
        fig.savefig(out, dpi=80, bbox_inches="tight", facecolor=fig.get_facecolor())
        print("wrote", os.path.abspath(out))
        return

    track = TRACKS.get(sel, TRACKS["t1"])
    fig, ax = plt.subplots(figsize=(13, 8.5))
    n = draw_track(ax, track)
    ax.set_title("Circuit preview  (red = start/finish, green = gates)")
    out = os.path.join(root, "track_preview.png")
    fig.savefig(out, dpi=90, bbox_inches="tight")
    print("wrote", os.path.abspath(out), " samples:", n)
    print("WAYPOINTS =", track["waypoints"])


if __name__ == "__main__":
    main()
