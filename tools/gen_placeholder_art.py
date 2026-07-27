#!/usr/bin/env python3
"""Generate placeholder art for GAO Remake.

Pure stdlib PNG writer -- no Pillow needed. Everything here is throwaway art
meant to be replaced by real assets; regenerate with:

    python3 tools/gen_placeholder_art.py

Emits one 8-tile atlas per biome. Every atlas has the same *semantic* layout, so
the floor generator can paint any biome without knowing which one it is:

    0 floor   1 floor-alt   2 path      3 special
    4 liquid  5 obstacle    6 wall      7 wall-alt

Slots 4-7 are the solid ones (see SOLID_TILES in tools/build_biomes.gd).

Also emits characters, dialogue portraits, props, enemy battlers, and one 16x16
icon per item id in ITEM_ICONS -- which must stay in step with ItemLibrary.ITEMS.
"""

import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "placeholder")

TILE = 16
FRAME = 32
PORTRAIT = 48
BATTLER = 64
ICON = 16


# --- tiny PNG writer -------------------------------------------------------


class Canvas:
    def __init__(self, w, h):
        self.w = w
        self.h = h
        self.px = [[(0, 0, 0, 0)] * w for _ in range(h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def rect(self, x, y, w, h, c):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.set(i, j, c)

    def save(self, name):
        raw = b"".join(
            b"\x00" + b"".join(bytes(p) for p in row) for row in self.px
        )
        path = os.path.join(OUT, name)
        with open(path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n")
            f.write(_chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0)))
            f.write(_chunk(b"IDAT", zlib.compress(raw, 9)))
            f.write(_chunk(b"IEND", b""))
        print("wrote", os.path.relpath(path))


def _chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


# --- colour helpers --------------------------------------------------------


def shade(c, factor):
    return (
        max(0, min(255, int(c[0] * factor))),
        max(0, min(255, int(c[1] * factor))),
        max(0, min(255, int(c[2] * factor))),
        255,
    )


def tint(c, factor):
    return (
        int(c[0] + (255 - c[0]) * factor),
        int(c[1] + (255 - c[1]) * factor),
        int(c[2] + (255 - c[2]) * factor),
        255,
    )


# Each biome is six base colours; every tile shade is derived from them, which
# keeps 10 biomes readable without hand-picking 160 colours.
#            ground             path               liquid             obstacle           stone              accent
BIOMES = {
    "meadow":   ((86, 140, 74),  (150, 116, 78),   (58, 108, 176),   (44, 96, 54),     (150, 150, 158),  (162, 68, 62)),
    "forest":   ((58, 104, 60),  (108, 88, 62),    (48, 92, 120),    (28, 66, 40),     (120, 124, 116),  (96, 74, 48)),
    "cave":     ((78, 72, 82),   (104, 96, 96),    (72, 118, 132),   (58, 54, 62),     (108, 100, 104),  (140, 112, 60)),
    "ruins":    ((116, 112, 96), (146, 140, 120),  (86, 118, 112),   (92, 96, 84),     (158, 152, 138),  (110, 92, 76)),
    "swamp":    ((78, 96, 58),   (96, 88, 60),     (74, 96, 62),     (52, 70, 44),     (104, 104, 88),   (86, 70, 52)),
    "desert":   ((196, 168, 106), (176, 146, 92),  (72, 132, 152),   (150, 122, 74),   (188, 168, 132),  (160, 108, 68)),
    "ice":      ((178, 202, 214), (150, 176, 194), (96, 152, 190),   (140, 176, 196),  (196, 214, 226),  (108, 140, 172)),
    "volcanic": ((72, 58, 56),   (96, 74, 64),     (196, 92, 44),    (58, 46, 46),     (104, 88, 82),    (168, 74, 48)),
    "sky":      ((146, 176, 206), (196, 208, 224), (120, 168, 216),  (168, 184, 204),  (214, 222, 236),  (140, 152, 190)),
    "castle":   ((132, 116, 140), (168, 152, 172), (128, 84, 148),   (96, 84, 104),    (176, 164, 184),  (152, 62, 82)),
}


def tileset(name, palette):
    ground, path, liquid, obstacle, stone, accent = palette
    c = Canvas(TILE * 8, TILE)

    def at(idx, x, y, col):
        c.set(idx * TILE + x, y, col)

    # 0 floor
    c.rect(0, 0, TILE, TILE, shade(ground, 1.0))
    for x, y in ((3, 4), (11, 6), (6, 12), (13, 13), (1, 9)):
        at(0, x, y, shade(ground, 0.82))

    # 1 floor-alt (a tuft, a crack, a pebble -- whatever the biome suggests)
    c.rect(TILE, 0, TILE, TILE, shade(ground, 1.0))
    for x, y in ((6, 8), (7, 7), (8, 8), (7, 9), (9, 6), (5, 6)):
        at(1, x, y, shade(ground, 0.72))

    # 2 path
    c.rect(TILE * 2, 0, TILE, TILE, shade(path, 1.0))
    for x, y in ((2, 3), (9, 5), (5, 10), (12, 12), (14, 2)):
        at(2, x, y, shade(path, 0.85))

    # 3 special (plaza / boss-room flooring)
    c.rect(TILE * 3, 0, TILE, TILE, tint(stone, 0.08))
    for i in range(TILE):
        at(3, i, 0, shade(stone, 0.8))
        at(3, 0, i, shade(stone, 0.8))

    # 4 liquid
    c.rect(TILE * 4, 0, TILE, TILE, shade(liquid, 1.0))
    for x in range(2, 13):
        at(4, x, 5, tint(liquid, 0.22))
        at(4, (x + 4) % TILE, 11, tint(liquid, 0.22))

    # 5 obstacle (tree, boulder, pillar)
    c.rect(TILE * 5, 0, TILE, TILE, shade(ground, 1.0))
    for y in range(1, 11):
        for x in range(2, 14):
            if (x - 8) ** 2 + (y - 6) ** 2 * 1.6 < 34:
                at(5, x, y, shade(obstacle, 1.0) if (x + y) % 3 else tint(obstacle, 0.15))
    c.rect(TILE * 5 + 7, 10, 2, 5, shade(obstacle, 0.6))

    # 6 wall
    c.rect(TILE * 6, 0, TILE, TILE, shade(stone, 0.82))
    dark = shade(stone, 0.62)
    for y in (0, 5, 10, 15):
        for x in range(TILE):
            at(6, x, y, dark)
    for y, off in ((2, 0), (7, 8), (12, 0)):
        for dy in range(-2, 3):
            at(6, off, y + dy, dark)
            at(6, off + 8, y + dy, dark)

    # 7 wall-alt (roof / banded stone)
    c.rect(TILE * 7, 0, TILE, TILE, shade(accent, 1.0))
    for y in range(0, TILE, 4):
        for x in range(TILE):
            at(7, x, y, shade(accent, 0.8))

    c.save("tiles_%s.png" % name)


# --- characters ------------------------------------------------------------

SKIN = (232, 190, 156, 255)
HAIR = (48, 42, 52, 255)
EYE = (28, 28, 34, 255)
BOOT = (60, 52, 48, 255)


def character(name, coat, trim):
    """4 rows (down, up, left, right) x 4 walk frames, 32x32 each."""
    c = Canvas(FRAME * 4, FRAME * 4)
    for row, facing in enumerate(("down", "up", "left", "right")):
        for col in range(4):
            _draw_char(c, col * FRAME, row * FRAME, facing, col, coat, trim)
    c.save(name)


def _draw_char(c, ox, oy, facing, frame, coat, trim):
    def p(x, y, col):
        c.set(ox + x, oy + y, col)

    def box(x, y, w, h, col):
        c.rect(ox + x, oy + y, w, h, col)

    # Legs swing on frames 1 and 3; frames 0 and 2 are the neutral pose.
    swing = (0, 1, 0, -1)[frame]

    box(12, 22, 3, 7 + swing, BOOT)  # left leg
    box(17, 22, 3, 7 - swing, BOOT)  # right leg
    box(11, 13, 10, 10, coat)  # torso
    box(11, 13, 10, 2, trim)  # collar
    box(15, 15, 2, 8, trim)  # front seam
    box(9, 14, 2, 7, coat)  # arms
    box(21, 14, 2, 7, coat)
    box(12, 5, 8, 9, SKIN)  # head
    box(11, 3, 10, 5, HAIR)  # hair

    if facing == "down":
        p(14, 10, EYE)
        p(17, 10, EYE)
    elif facing == "up":
        box(12, 5, 8, 6, HAIR)
    elif facing == "left":
        box(11, 3, 8, 6, HAIR)
        p(13, 10, EYE)
        box(9, 14, 2, 7, trim)
    elif facing == "right":
        box(13, 3, 8, 6, HAIR)
        p(18, 10, EYE)
        box(21, 14, 2, 7, trim)


def portrait(name, coat, trim, hair=HAIR):
    """A 48x48 bust for the dialogue box, framed to sit in the text panel."""
    c = Canvas(PORTRAIT, PORTRAIT)
    c.rect(0, 0, PORTRAIT, PORTRAIT, shade(coat, 0.32))
    c.rect(0, 0, PORTRAIT, 1, shade(coat, 0.6))
    c.rect(0, PORTRAIT - 1, PORTRAIT, 1, shade(coat, 0.6))
    c.rect(0, 0, 1, PORTRAIT, shade(coat, 0.6))
    c.rect(PORTRAIT - 1, 0, 1, PORTRAIT, shade(coat, 0.6))

    c.rect(8, 37, 32, 11, coat)  # shoulders
    c.rect(8, 37, 32, 2, trim)  # collar
    c.rect(22, 39, 4, 9, trim)  # front seam
    c.rect(20, 31, 8, 7, SKIN)  # neck
    c.rect(15, 11, 18, 22, SKIN)  # face
    c.rect(13, 7, 22, 9, hair)  # fringe
    c.rect(13, 7, 3, 20, hair)  # side locks
    c.rect(32, 7, 3, 20, hair)
    c.rect(19, 20, 3, 3, EYE)
    c.rect(27, 20, 3, 3, EYE)
    c.rect(21, 28, 6, 1, shade(SKIN, 0.72))  # mouth
    c.save(name)


# --- battlers --------------------------------------------------------------
#
# One 64x64 front-facing sprite per enemy type, drawn from a handful of shared
# silhouettes. Enemies are data (resources/enemies/*.tres); the silhouette is
# only how they read on screen, so several enemies reuse one.
#           shape       body               accent
BATTLERS = {
    "boar":      ("beast",    (128, 92, 68),   (214, 204, 188)),
    "wolf":      ("beast",    (96, 100, 116),  (226, 232, 240)),
    "nepent":    ("plant",    (86, 148, 76),   (198, 84, 96)),
    "kobold":    ("humanoid", (140, 116, 74),  (188, 72, 60)),
    "lizardman": ("humanoid", (86, 132, 96),   (206, 176, 84)),
    "bat":       ("bat",      (92, 78, 104),   (196, 168, 208)),
    "wraith":    ("wraith",   (78, 82, 116),   (150, 196, 232)),
    "golem":     ("golem",    (122, 118, 126), (172, 148, 96)),
    "drake":     ("drake",    (154, 82, 62),   (236, 176, 96)),
    "illfang":   ("humanoid", (152, 88, 58),   (228, 96, 72)),
}

MENACE = (238, 96, 84, 255)  # every enemy's eye colour -- reads at 64px


def battler(name, shape, body, accent):
    c = Canvas(BATTLER, BATTLER)
    body = shade(body, 1.0)
    dark = shade(body, 0.68)
    light = tint(body, 0.2)
    {
        "beast": _beast,
        "plant": _plant,
        "humanoid": _humanoid,
        "bat": _bat,
        "wraith": _wraith,
        "golem": _golem,
        "drake": _drake,
    }[shape](c, body, dark, light, shade(accent, 1.0))
    _ground_shadow(c)
    c.save("enemy_%s.png" % name)


def _ground_shadow(c):
    for i, (inset, alpha) in enumerate(((6, 70), (10, 45))):
        c.rect(inset, 59 + i, BATTLER - inset * 2, 1, (0, 0, 0, alpha))


def _beast(c, body, dark, light, accent):
    c.rect(10, 30, 36, 18, body)  # barrel
    c.rect(10, 30, 36, 3, light)  # spine highlight
    c.rect(40, 20, 18, 18, body)  # head
    c.rect(40, 20, 18, 3, light)
    c.rect(52, 30, 8, 6, dark)  # snout
    c.rect(54, 24, 3, 6, accent)  # tusk / fang
    for x in (13, 21, 33, 41):  # legs
        c.rect(x, 46, 5, 13, dark)
    c.rect(4, 28, 8, 4, dark)  # tail
    c.rect(46, 26, 4, 3, MENACE)  # eye


def _plant(c, body, dark, light, accent):
    c.rect(26, 40, 12, 19, dark)  # stem
    for y in range(20, 40, 4):  # bulb
        w = 34 - abs(30 - y)
        c.rect(32 - w // 2, y, w, 4, body)
    c.rect(20, 26, 24, 3, light)
    c.rect(24, 30, 16, 6, accent)  # maw
    for x in range(26, 40, 4):
        c.rect(x, 33, 2, 4, (24, 18, 24, 255))  # teeth
    c.rect(24, 22, 4, 3, MENACE)
    c.rect(36, 22, 4, 3, MENACE)
    c.rect(8, 44, 18, 4, dark)  # tendrils
    c.rect(38, 44, 18, 4, dark)


def _humanoid(c, body, dark, light, accent):
    c.rect(24, 22, 16, 22, body)  # torso
    c.rect(24, 22, 16, 3, light)
    c.rect(28, 25, 8, 16, accent)  # tabard
    c.rect(25, 8, 14, 14, body)  # head
    c.rect(23, 6, 18, 4, dark)  # brow ridge
    c.rect(27, 13, 4, 3, MENACE)
    c.rect(33, 13, 4, 3, MENACE)
    c.rect(28, 19, 8, 2, (24, 18, 24, 255))  # jaw
    c.rect(17, 24, 7, 18, body)  # arms
    c.rect(40, 24, 7, 18, body)
    c.rect(24, 44, 7, 15, dark)  # legs
    c.rect(33, 44, 7, 15, dark)
    c.rect(48, 10, 4, 36, (216, 214, 224, 255))  # blade
    c.rect(46, 42, 8, 5, accent)  # hilt


def _bat(c, body, dark, light, accent):
    c.rect(26, 26, 14, 14, body)  # body
    c.rect(26, 26, 14, 3, light)
    for side, direction in ((24, -1), (40, 1)):  # wings, swept back and up
        for step in range(4):
            x = side + direction * step * 6
            c.rect(min(x, x + direction * 6), 26 - step * 4, 6, 12 + step * 2, dark)
    c.rect(28, 18, 4, 8, dark)  # ears
    c.rect(34, 18, 4, 8, dark)
    c.rect(28, 30, 3, 3, MENACE)
    c.rect(35, 30, 3, 3, MENACE)
    c.rect(30, 36, 6, 3, accent)  # fangs
    c.rect(30, 40, 6, 10, dark)


def _wraith(c, body, dark, light, accent):
    for y in range(12, 58):  # a hood that frays into nothing
        half = 4 + (y - 12) // 2
        col = body if y % 6 else dark
        if y > 46 and (y + half) % 3 == 0:
            continue
        c.rect(32 - half, y, half * 2, 1, col)
    c.rect(24, 16, 16, 12, (18, 16, 26, 255))  # face void
    c.rect(26, 21, 5, 4, accent)
    c.rect(34, 21, 5, 4, accent)
    c.rect(12, 30, 10, 4, light)  # reaching hands
    c.rect(42, 30, 10, 4, light)


def _golem(c, body, dark, light, accent):
    c.rect(18, 18, 28, 26, body)  # slab of a torso
    c.rect(18, 18, 28, 4, light)
    c.rect(26, 26, 12, 10, accent)  # core
    c.rect(24, 6, 16, 12, body)  # head
    c.rect(27, 10, 4, 4, MENACE)
    c.rect(34, 10, 4, 4, MENACE)
    c.rect(6, 20, 12, 24, body)  # arms
    c.rect(46, 20, 12, 24, body)
    c.rect(6, 40, 12, 6, dark)  # fists
    c.rect(46, 40, 12, 6, dark)
    c.rect(20, 44, 10, 15, dark)  # legs
    c.rect(34, 44, 10, 15, dark)
    for x, y in ((22, 24), (40, 32), (30, 40)):  # cracks
        c.rect(x, y, 3, 2, dark)


def _drake(c, body, dark, light, accent):
    for side, direction in ((20, -1), (44, 1)):  # wings
        for step in range(6):
            x = side + direction * step * 4
            c.rect(min(x, x + direction * 4), 8 + step * 3, 4, 26 - step * 3, dark)
    c.rect(24, 24, 16, 22, body)  # body
    c.rect(24, 24, 16, 3, light)
    c.rect(27, 30, 10, 12, accent)  # belly
    c.rect(26, 8, 12, 16, body)  # head + neck
    c.rect(36, 14, 12, 7, body)  # snout
    c.rect(38, 16, 8, 3, accent)  # flame in the throat
    c.rect(28, 12, 4, 3, MENACE)
    c.rect(22, 46, 8, 13, dark)  # legs
    c.rect(34, 46, 8, 13, dark)
    c.rect(6, 40, 18, 4, dark)  # tail


# --- props -----------------------------------------------------------------


def chest():
    c = Canvas(FRAME, FRAME)
    body = (140, 96, 48, 255)
    dark = (104, 68, 34, 255)
    gold = (216, 176, 68, 255)
    c.rect(6, 14, 20, 12, body)
    c.rect(6, 10, 20, 5, dark)
    c.rect(6, 14, 20, 1, gold)
    c.rect(14, 16, 4, 5, gold)
    c.rect(6, 25, 20, 1, dark)
    c.save("chest.png")


# --- item icons ------------------------------------------------------------
#
# One 16x16 icon per item (resources/items/*.tres), drawn from six shared
# silhouettes and tinted. Items are data; the silhouette is only how they read
# in the bag grid, so every material is a "shard", "fang" or "pelt" and the
# colour is what tells them apart.
#              shape      colour
ITEM_ICONS = {
    "small_potion":   ("flask",  (206, 76, 92)),
    "health_potion":  ("flask",  (226, 56, 120)),
    "antidote":       ("flask",  (104, 190, 118)),
    "whetstone":      ("shard",  (168, 168, 180)),
    "bronze_sword":   ("sword",  (186, 132, 72)),
    "kobold_blade":   ("sword",  (150, 142, 124)),
    "anneal_blade":   ("sword",  (108, 168, 220)),
    "leather_coat":   ("coat",   (140, 100, 64)),
    "blackwyrm_coat": ("coat",   (66, 70, 96)),
    "guard_ring":     ("ring",   (204, 180, 110)),
    "swift_charm":    ("ring",   (114, 200, 206)),
    "boar_hide":      ("pelt",   (140, 102, 72)),
    "wolf_fang":      ("fang",   (222, 228, 238)),
    "bat_wing":       ("pelt",   (118, 98, 140)),
    "nepent_ovule":   ("shard",  (194, 88, 100)),
    "kobold_fang":    ("fang",   (194, 176, 120)),
    "lizard_scale":   ("pelt",   (94, 148, 110)),
    "drake_scale":    ("fang",   (176, 86, 60)),
    "golem_core":     ("shard",  (172, 148, 96)),
    "spirit_ash":     ("shard",  (150, 196, 232)),
    "map_floor_2":    ("scroll", (212, 196, 156)),
}


def item_icon(name, shape, color):
    c = Canvas(ICON, ICON)
    base = shade(color, 1.0)
    {
        "flask": _icon_flask,
        "sword": _icon_sword,
        "coat": _icon_coat,
        "ring": _icon_ring,
        "shard": _icon_shard,
        "fang": _icon_fang,
        "pelt": _icon_pelt,
        "scroll": _icon_scroll,
    }[shape](c, base, shade(color, 0.62), tint(color, 0.3))
    c.save("item_%s.png" % name)


def _icon_flask(c, base, dark, light):
    glass = (198, 210, 226, 255)
    cork = (146, 108, 66, 255)
    c.rect(6, 0, 4, 2, cork)
    c.rect(6, 2, 4, 4, glass)
    for y in range(6, 15):  # bulb
        half = 3 + min(y - 6, 3)
        c.rect(8 - half, y, half * 2, 1, glass)
    for y in range(9, 14):  # what's in it
        half = 3 + min(y - 9, 2)
        c.rect(8 - half, y, half * 2, 1, base if y % 2 else light)
    c.rect(4, 14, 8, 1, dark)


def _icon_sword(c, base, dark, light):
    steel = (214, 220, 232, 255)
    c.rect(7, 0, 2, 2, steel)  # tip
    c.rect(6, 2, 4, 9, steel)  # blade
    c.rect(6, 2, 1, 9, light)  # the edge catching the light
    c.rect(9, 2, 1, 9, (140, 148, 164, 255))
    c.rect(3, 11, 10, 2, base)  # crossguard
    c.rect(7, 13, 2, 2, dark)  # grip
    c.rect(6, 15, 4, 1, base)  # pommel


def _icon_coat(c, base, dark, light):
    c.rect(4, 3, 8, 11, base)  # torso
    c.rect(2, 4, 2, 7, dark)  # sleeves
    c.rect(12, 4, 2, 7, dark)
    c.rect(4, 3, 8, 2, light)  # collar
    c.rect(7, 5, 2, 9, dark)  # front seam
    c.rect(4, 14, 8, 1, dark)  # hem


def _icon_ring(c, base, dark, light):
    for y in range(5, 15):
        for x in range(3, 14):
            distance = (x - 8) ** 2 + (y - 10) ** 2
            if 8 <= distance <= 22:
                c.set(x, y, base if (x + y) % 3 else dark)
    c.rect(6, 1, 4, 4, light)  # the stone
    c.rect(7, 2, 2, 2, tint(light, 0.5))


def _icon_shard(c, base, dark, light):
    for y in range(1, 15):
        half = 5 - abs(8 - y) // 2
        if half <= 0:
            continue
        c.rect(8 - half, y, half * 2, 1, base if y % 3 else light)
    c.rect(5, 7, 2, 5, dark)  # inner facet


def _icon_fang(c, base, dark, light):
    for y in range(1, 15):
        half = max(1, (15 - y) // 2)
        c.rect(8 - half, y, half * 2, 1, base)
    c.rect(5, 2, 2, 5, light)  # highlight down the outer curve
    c.rect(9, 2, 2, 4, dark)


def _icon_pelt(c, base, dark, light):
    c.rect(3, 4, 10, 9, base)
    c.rect(3, 4, 10, 2, light)
    for x, y in ((1, 2), (12, 2), (1, 11), (12, 11)):  # splayed corners
        c.rect(x, y, 3, 3, base)
    for x, y in ((6, 7), (9, 9), (7, 11)):
        c.rect(x, y, 2, 1, dark)


def _icon_scroll(c, base, dark, light):
    c.rect(3, 3, 10, 10, base)
    c.rect(3, 1, 10, 2, dark)  # rolled top
    c.rect(3, 13, 10, 2, dark)  # rolled bottom
    for y in (5, 7, 9, 11):
        c.rect(5, y, 6, 1, shade(dark, 0.7))
    c.rect(7, 7, 3, 3, light)  # the "you are here"


def boss_gate():
    """A dark archway -- the labyrinth boss door."""
    c = Canvas(FRAME, FRAME)
    stone = (92, 88, 104, 255)
    stone_d = (62, 58, 74, 255)
    glow = (208, 72, 72, 255)
    c.rect(2, 2, 28, 28, stone_d)
    c.rect(4, 4, 24, 26, stone)
    c.rect(8, 8, 16, 22, (20, 16, 26, 255))
    for y in range(10, 30, 4):
        c.rect(10, y, 12, 1, glow)
    c.rect(2, 0, 28, 3, stone_d)
    c.save("boss_gate.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for biome_name, palette in BIOMES.items():
        tileset(biome_name, palette)
    character("player.png", (58, 82, 132, 255), (206, 210, 220, 255))
    character("npc.png", (126, 92, 140, 255), (226, 214, 160, 255))
    portrait("portrait_kirito.png", (58, 82, 132, 255), (206, 210, 220, 255))
    portrait("portrait_argo.png", (124, 96, 66, 255), (208, 176, 108, 255), (152, 118, 72, 255))
    portrait("portrait_nezha.png", (86, 96, 116, 255), (188, 128, 76, 255))
    chest()
    boss_gate()
    for battler_name, (shape, body, accent) in BATTLERS.items():
        battler(battler_name, shape, body, accent)
    for item_name, (shape, color) in ITEM_ICONS.items():
        item_icon(item_name, shape, color)
