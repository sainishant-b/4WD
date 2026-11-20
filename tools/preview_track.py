"""Preview the circuit BEFORE wiring it into Godot.

Uses the same waypoints and the same centre-line math as track_builder.gd
(centripetal Catmull-Rom -> even resample -> relax bends tighter than the road
can follow), and renders the road, walls, checkpoint gates, obstacles and car
start to a PNG so the track shape can be eyeballed.
    python tools/preview_track.py [t1..t7|mp]   one track  -> track_preview.png
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
# Select with: python tools/preview_track.py [t1..t7|mp|all]   (default t1)
TRACKS = {
    # Level 1, Monday, the easiest: wide and flowing; a broad sweep into the infield, a long S up the left.
    "t1": {"waypoints": [
        (936, 676), (1534, 572), (1880, 650), (2100, 1080),
        (2450, 1180), (2720, 820), (3146, 832), (3250, 1300),
        (2990, 1612), (3198, 1924), (2652, 2028), (2080, 1840),
        (1508, 2028), (1014, 1820), (780, 1560), (1200, 1290),
        (780, 1000),
    ], "road_width": 88.0, "checkpoints": 9},
    # Level 2, Tuesday: tight and twisty; a hairpin tongue down into the infield.
    "t2": {"waypoints": [
        (1145, 708), (1700, 681), (2050, 700), (2100, 1150),
        (2240, 1260), (2380, 1150), (2430, 760), (2700, 800),
        (2924, 989), (2690, 1223), (2970, 1457), (2736, 1691),
        (2830, 1925), (2362, 1954), (1941, 1785), (1566, 1972),
        (1192, 1832), (864, 1598), (1098, 1317), (845, 1074),
        (1061, 849),
    ], "road_width": 75.0, "checkpoints": 10},
    # Level 3, Wednesday: narrow esses; an S-shaped loop through the infield.
    "t3": {"waypoints": [
        (1066, 728), (1664, 650), (1950, 760), (1900, 1060),
        (2120, 1260), (2380, 1060), (2330, 760), (2756, 676),
        (3068, 1066), (2704, 1326), (3094, 1638), (2704, 1924),
        (2184, 1846), (1742, 1976), (1300, 1794), (988, 1924),
        (806, 1456), (1196, 1222), (832, 936),
    ], "road_width": 72.0, "checkpoints": 10},
    # Level 4, Thursday: esses along the top, a two-hairpin switchback, a hairpin tongue up from the bottom.
    "t4": {"waypoints": [
        (910, 624), (1235, 520), (1560, 689), (1885, 520),
        (2210, 650), (3029, 728), (3198, 1040), (3068, 1287),
        (2665, 1313), (2327, 1326), (2197, 1424), (2327, 1521),
        (2730, 1534), (3094, 1573), (3224, 1716), (3094, 1859),
        (2808, 1976), (2535, 1807), (2262, 1989), (1820, 1900),
        (1720, 1300), (1560, 1130), (1400, 1300), (1350, 1900),
        (884, 1846), (702, 1495), (910, 1170), (702, 910),
    ], "road_width": 68.0, "checkpoints": 11},
    # Level 5, Friday: two hairpin tongues off the top, esses along the bottom, a double switchback up the left.
    "t5": {"waypoints": [
        (910, 676), (1118, 585), (1352, 741), (1586, 598),
        (1820, 832), (1820, 1235), (1924, 1443), (2028, 1235),
        (2028, 832), (2210, 650), (2500, 620), (2600, 900),
        (2620, 1300), (2760, 1450), (2900, 1300), (2900, 760),
        (3100, 760), (3211, 1000), (3094, 1248), (3224, 1560),
        (3068, 1859), (2795, 1989), (2509, 1820), (2223, 2002),
        (1950, 1872), (1625, 1950), (1391, 1820), (1352, 1365),
        (1222, 1170), (1092, 1365), (1092, 1664), (962, 1833),
        (832, 1664), (741, 1443), (884, 1235), (767, 1027),
    ], "road_width": 64.0, "checkpoints": 13},
    # Level 6, Saturday: a chicane, kinked hairpin rows across the middle, bottom esses, a switchback up the left.
    "t6": {"waypoints": [
        (1150, 575), (1600, 660), (1850, 540), (2250, 600),
        (2700, 560), (3150, 700), (3300, 1000), (3100, 1250),
        (2780, 1170), (2480, 1290), (2220, 1160), (2050, 1300),
        (2180, 1520), (2480, 1580), (2780, 1480), (3100, 1560),
        (3350, 1800), (3150, 2100), (2700, 2150), (2400, 1900),
        (2100, 2150), (1750, 1950), (1450, 2150), (1050, 2100),
        (800, 1850), (850, 1650), (1150, 1570), (1480, 1660),
        (1640, 1500), (1500, 1380), (1200, 1430), (950, 1340),
        (800, 1150), (900, 900), (840, 680),
    ], "road_width": 62.0, "checkpoints": 13},
    # Level 7, Sunday, the hardest: deep top esses, kinked hairpin rows, two tongues along the bottom, a switchback up the left.
    "t7": {"waypoints": [
        (900, 600), (1250, 500), (1500, 700), (1750, 500),
        (2000, 700), (2400, 560), (2800, 600), (3200, 700),
        (3350, 1000), (3200, 1250), (2950, 1140), (2700, 1250),
        (2500, 1060), (2300, 1180), (2400, 1420), (2700, 1500),
        (2950, 1400), (3200, 1520), (3400, 1750), (3250, 2050),
        (2900, 2100), (2700, 1850), (2500, 1650), (2300, 1850),
        (2250, 2150), (1900, 2200), (1600, 2050), (1650, 1700),
        (1500, 1450), (1300, 1600), (1250, 1950), (1000, 2150),
        (750, 1950), (760, 1700), (1050, 1500), (1120, 1250),
        (850, 1150), (760, 900),
    ], "road_width": 60.0, "checkpoints": 14},
    # Multiplayer (hidden): a wide flowing loop so cars race side-by-side and bump.
    "mp": {"waypoints": [
        (700, 400), (1500, 360), (2200, 460),
        (2520, 850), (2350, 1300), (1750, 1560),
        (1050, 1560), (520, 1300), (330, 850), (600, 500),
    ], "road_width": 180.0, "checkpoints": 6},
}
# Level order for the `all` sheet ("mp" is the hidden multiplayer track, left out).
LEVELS = ["t1", "t2", "t3", "t4", "t5", "t6", "t7"]
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
        fig, axes = plt.subplots(3, 3, figsize=(27, 20))
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
