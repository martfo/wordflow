"""Generate the WordFlow app icon: a river of words."""
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np

S = 1024
MARGIN = 74
RADIUS = int((S - 2 * MARGIN) * 0.2237)


def load_font(size, bold=True):
    candidates = [
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            continue
    return ImageFont.load_default()


def vgrad(top, bot):
    t = np.linspace(0, 1, S).reshape(S, 1, 1)
    arr = np.array(top).reshape(1, 1, 3) * (1 - t) + np.array(bot).reshape(1, 1, 3) * t
    return np.repeat(arr.astype("uint8"), S, axis=1)


def hgrad(left, right):
    t = np.linspace(0, 1, S).reshape(1, S, 1)
    arr = np.array(left).reshape(1, 1, 3) * (1 - t) + np.array(right).reshape(1, 1, 3) * t
    return np.repeat(arr.astype("uint8"), S, axis=0)


# --- background: soft sky with a gentle centre glow, rounded square ---
bg = vgrad((236, 245, 255), (196, 222, 250)).astype("float32")
yy, xx = np.mgrid[0:S, 0:S]
glow = np.exp(-(((xx - S * 0.5) ** 2 + (yy - S * 0.42) ** 2) / (2 * (S * 0.42) ** 2)))
bg += (glow[:, :, None] * np.array([18, 12, 6]).reshape(1, 1, 3))
bg_rgb = Image.fromarray(np.clip(bg, 0, 255).astype("uint8"), "RGB").convert("RGBA")
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([MARGIN, MARGIN, S - MARGIN, S - MARGIN],
                                       radius=RADIUS, fill=255)
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
icon.paste(bg_rgb, (0, 0), mask)


# --- the river geometry: a gentle S flowing left -> right, narrow to wide ---
def centerline(x):
    t = x / S
    return S * 0.5 + math.sin(t * math.pi * 1.7 + 0.5) * S * 0.135


def halfwidth(x):
    t = x / S
    base = S * (0.055 + 0.07 * t)
    # taper to a narrow source at the very left so the river "begins"
    ramp = min(1.0, (x - (MARGIN + 26)) / (S * 0.14))
    return base * (0.35 + 0.65 * max(0.0, ramp))


x0, x1 = MARGIN + 26, S - MARGIN - 26
xs = list(range(x0, x1))
top_edge = [(x, centerline(x) - halfwidth(x)) for x in xs]
bot_edge = [(x, centerline(x) + halfwidth(x)) for x in xs]
band_poly = top_edge + bot_edge[::-1]

band_mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(band_mask).polygon(band_poly, fill=255)
band_mask = band_mask.filter(ImageFilter.GaussianBlur(1.5))
band_mask = Image.composite(band_mask, Image.new("L", (S, S), 0), mask)  # clip to rounded rect

# river fill: blue -> teal, plus a soft top highlight for a little depth
river_rgb = Image.fromarray(hgrad((60, 156, 255), (16, 196, 170)), "RGB").convert("RGBA")

# a soft drop shadow beneath the river for lift (drawn first)
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sh_src = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sh_src.paste(Image.new("RGBA", (S, S), (26, 66, 120, 110)), (0, 0), band_mask)
sh_src = sh_src.filter(ImageFilter.GaussianBlur(16))
icon.alpha_composite(sh_src, (0, 22))
# the river on top
icon.paste(river_rgb, (0, 0), band_mask)

# --- current streamlines (white, translucent, wavy) ---
stream = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(stream)
for k, alpha, w in [(-0.45, 70, 7), (0.0, 95, 9), (0.5, 60, 6)]:
    pts = [(x, centerline(x) + k * halfwidth(x)) for x in xs[::3]]
    sd.line(pts, fill=(255, 255, 255, alpha), width=w, joint="curve")
stream = stream.filter(ImageFilter.GaussianBlur(1.2))
stream.putalpha(Image.composite(stream.getchannel("A"), Image.new("L", (S, S), 0), band_mask))
icon = Image.alpha_composite(icon, stream)

# --- words flowing along the current, spaced so they never collide ---
# A quiet phrase carried downstream. Each word is sized to the river's local
# width and laid end to end with clear water between.
phrase = ["words", "flow", "into", "ideas", "and", "stories"]
x = x0 + int(S * 0.02)
gap = int(S * 0.028)
for word in phrase:
    fs = int(max(34, min(1.35 * halfwidth(x + 40), 96)))
    font = load_font(fs)
    bbox = font.getbbox(word)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    if x + tw > x1 - int(S * 0.02):
        break
    xc = x + tw / 2
    yc = centerline(xc)
    slope = (centerline(xc + 6) - centerline(xc - 6)) / 12.0
    angle = -math.degrees(math.atan(slope))
    pad = 14
    tile = Image.new("RGBA", (tw + 2 * pad, th + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(tile).text((pad - bbox[0], pad - bbox[1]), word, font=font,
                              fill=(255, 255, 255, 245))
    tile = tile.rotate(angle, expand=True, resample=Image.BICUBIC)
    icon.alpha_composite(tile, (int(xc - tile.width / 2), int(yc - tile.height / 2)))
    x += tw + gap

# --- gentle inner border for definition ---
border = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(border).rounded_rectangle(
    [MARGIN, MARGIN, S - MARGIN, S - MARGIN], radius=RADIUS, outline=(255, 255, 255, 120), width=3)
icon = Image.alpha_composite(icon, border)

icon.save("icon_master.png")
print("wrote icon_master.png")
