"""Generate the WordFlow app icon: a clean river flowing corner to corner
(top-left to bottom-right), with the word WordFlow carried along its current."""
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np

S = 1024
MARGIN = 74
RADIUS = int((S - 2 * MARGIN) * 0.2237)


def find_font_spec():
    """A clean bold brand face: Avenir Next Bold, then SF Pro, then Helvetica Neue.
    Returns (path, index)."""
    wanted = [
        ("/System/Library/Fonts/Avenir Next.ttc", ["Bold", "Demi Bold", "Heavy"]),
        ("/System/Library/Fonts/SFNSDisplay.ttf", ["Bold", "Heavy"]),
        ("/System/Library/Fonts/SFNS.ttf", ["Bold"]),
        ("/System/Library/Fonts/HelveticaNeue.ttc", ["Bold"]),
        ("/System/Library/Fonts/Helvetica.ttc", ["Bold"]),
    ]
    for path, weights in wanted:
        for index in range(0, 14):
            try:
                f = ImageFont.truetype(path, 64, index=index)
            except Exception:
                break
            try:
                family, style = f.getname()
            except Exception:
                continue
            if any(w.lower() == style.lower() for w in weights):
                print(f"font: {family} {style}  ({path}#{index})")
                return path, index
    return "/System/Library/Fonts/Helvetica.ttc", 1


FONT_PATH, FONT_INDEX = find_font_spec()


def font_at(size):
    return ImageFont.truetype(FONT_PATH, int(size), index=FONT_INDEX)


# --- background: soft sky with a gentle centre glow, rounded square ---
yy, xx = np.mgrid[0:S, 0:S]
ty = (yy / (S - 1))[:, :, None]
bg = (np.array([236, 245, 255]).reshape(1, 1, 3) * (1 - ty)
      + np.array([198, 223, 250]).reshape(1, 1, 3) * ty).astype("float32")
glow = np.exp(-(((xx - S * 0.5) ** 2 + (yy - S * 0.5) ** 2) / (2 * (S * 0.44) ** 2)))
bg += glow[:, :, None] * np.array([16, 11, 6]).reshape(1, 1, 3)
bg_rgb = Image.fromarray(np.clip(bg, 0, 255).astype("uint8"), "RGB").convert("RGBA")
rr_mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(rr_mask).rounded_rectangle([MARGIN, MARGIN, S - MARGIN, S - MARGIN],
                                          radius=RADIUS, fill=255)
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
icon.paste(bg_rgb, (0, 0), rr_mask)

# --- river centreline: corner to corner with a gentle S, anchored at both
#     corners so the composition stays balanced ---
pad = 44
start = np.array([MARGIN + pad, MARGIN + pad], dtype="float64")
end = np.array([S - MARGIN - pad, S - MARGIN - pad], dtype="float64")
D = end - start
n_hat = np.array([-D[1], D[0]]) / np.linalg.norm(D)
AMP = S * 0.130


def centre(t):
    return start + t * D + n_hat * (AMP * math.sin(2 * math.pi * t) * math.sin(math.pi * t))


def halfwidth(t):
    return S * (0.072 + 0.016 * t)


N = 2000
ts = np.linspace(0, 1, N)
pts = np.array([centre(t) for t in ts])
seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
arc = np.concatenate([[0.0], np.cumsum(seg)])
total_arc = float(arc[-1])

# clean band with rounded caps
top_edge, bot_edge = [], []
for i in range(N):
    tang = pts[min(i + 1, N - 1)] - pts[max(i - 1, 0)]
    tang = tang / (np.linalg.norm(tang) + 1e-9)
    nrm = np.array([-tang[1], tang[0]])
    hw = halfwidth(ts[i])
    top_edge.append(tuple(pts[i] + nrm * hw))
    bot_edge.append(tuple(pts[i] - nrm * hw))
band = Image.new("L", (S, S), 0)
bd = ImageDraw.Draw(band)
bd.polygon(top_edge + bot_edge[::-1], fill=255)
for endc, t in ((pts[0], 0.0), (pts[-1], 1.0)):
    hw = halfwidth(t)
    bd.ellipse([endc[0] - hw, endc[1] - hw, endc[0] + hw, endc[1] + hw], fill=255)
band = band.filter(ImageFilter.GaussianBlur(1.2))
band = Image.composite(band, Image.new("L", (S, S), 0), rr_mask)

# river fill: blue -> teal along the flow direction
g = np.clip(((xx - MARGIN) + (yy - MARGIN)) / (2.0 * (S - 2 * MARGIN)), 0, 1)[:, :, None]
c1, c2 = np.array([46, 141, 250]), np.array([16, 192, 166])
river = (c1.reshape(1, 1, 3) * (1 - g) + c2.reshape(1, 1, 3) * g).astype("uint8")
river_rgb = Image.fromarray(river, "RGB").convert("RGBA")

# soft drop shadow, then the river
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sh.paste(Image.new("RGBA", (S, S), (24, 62, 116, 105)), (0, 0), band)
sh = sh.filter(ImageFilter.GaussianBlur(18))
icon.alpha_composite(sh, (6, 20))
icon.paste(river_rgb, (0, 0), band)

# subtle upper sheen (soft, no hard lines)
sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sheen).line([tuple(p) for p in pts[::4]], fill=(255, 255, 255, 38),
                           width=int(halfwidth(0.5) * 0.85), joint="curve")
sheen = sheen.filter(ImageFilter.GaussianBlur(26))
sheen.putalpha(Image.composite(sheen.getchannel("A"), Image.new("L", (S, S), 0), band))
icon.alpha_composite(sheen)

# --- WordFlow flowing along the current ---
word = "WordFlow"
TRACK = 1.12  # letter tracking along the path


def word_len(size):
    f = font_at(size)
    return sum(f.getlength(ch) for ch in word) * TRACK


# size the word to span ~62% of the river
target = total_arc * 0.62
lo, hi = 40.0, 260.0
for _ in range(26):
    mid = (lo + hi) / 2
    if word_len(mid) > target:
        hi = mid
    else:
        lo = mid
size = lo
font = font_at(size)
advances = [font.getlength(ch) * TRACK for ch in word]
span = sum(advances)


def point_angle(s):
    s = min(max(s, 0.0), total_arc)
    i = min(max(int(np.searchsorted(arc, s)), 1), N - 1)
    f = (s - arc[i - 1]) / (arc[i] - arc[i - 1] + 1e-9)
    p = pts[i - 1] * (1 - f) + pts[i] * f
    tang = pts[i] - pts[i - 1]
    return p, math.degrees(math.atan2(tang[1], tang[0]))


s = (total_arc - span) / 2.0
for ch, adv in zip(word, advances):
    p, ang = point_angle(s + adv / 2.0)
    tile = Image.new("RGBA", (int(adv) + 40, int(size * 1.6) + 40), (0, 0, 0, 0))
    td = ImageDraw.Draw(tile)
    bbox = font.getbbox(ch)
    cx = tile.width / 2 - (bbox[0] + bbox[2]) / 2
    cy = tile.height / 2 - (bbox[1] + bbox[3]) / 2
    td.text((cx + 2, cy + 3), ch, font=font, fill=(20, 60, 110, 90))  # soft shadow
    td.text((cx, cy), ch, font=font, fill=(255, 255, 255, 250))
    tile = tile.rotate(-ang, expand=True, resample=Image.BICUBIC)
    icon.alpha_composite(tile, (int(p[0] - tile.width / 2), int(p[1] - tile.height / 2)))
    s += adv

# gentle inner border for definition
ImageDraw.Draw(icon).rounded_rectangle(
    [MARGIN, MARGIN, S - MARGIN, S - MARGIN], radius=RADIUS, outline=(255, 255, 255, 110), width=3)

icon.save("icon_master.png")
print("wrote icon_master.png")
