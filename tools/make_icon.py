# Erzeugt Resources/AppIcon.png (1024x1024). Benötigt: pip install pillow
from PIL import Image, ImageDraw, ImageFilter
S = 2048; k = S / 1024
def r(v): return int(v * k)
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Hintergrund-Verlauf
grad = Image.new("RGBA", (S, S))
px = grad.load()
c1, c2 = (28, 22, 78), (150, 48, 150)
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([r(100), r(100), r(924), r(924)], radius=r(185), fill=255)
img.paste(grad, (0, 0), mask)

# weiches Licht unten rechts
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([r(450), r(500), r(1000), r(1050)], fill=(255, 140, 90, 90))
glow = glow.filter(ImageFilter.GaussianBlur(r(70)))
layer = Image.new("RGBA", (S, S), (0, 0, 0, 0)); layer.paste(glow, (0, 0), mask)
img = Image.alpha_composite(img, layer)

# Island (bündig am oberen Rand)
isl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(isl)
d.rounded_rectangle([r(230), r(20), r(794), r(360)], radius=r(120), fill=(0, 0, 0, 255))
# Timer-Ring
cx, cy, rr = r(365), r(232), r(52)
d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(70, 70, 70, 255), width=r(16))
d.arc([cx - rr, cy - rr, cx + rr, cy + rr], start=-90, end=170, fill=(255, 149, 0, 255), width=r(16))
# Text-Balken
d.rounded_rectangle([r(470), r(205), r(700), r(232)], radius=r(14), fill=(255, 255, 255, 255))
d.rounded_rectangle([r(470), r(252), r(620), r(272)], radius=r(10), fill=(140, 140, 150, 255))
layer = Image.new("RGBA", (S, S), (0, 0, 0, 0)); layer.paste(isl, (0, 0), mask)
img = Image.alpha_composite(img, layer)

# Datei-Kacheln (File Shelf)
t = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(t)
for i, x in enumerate([260, 430, 600]):
    d.rounded_rectangle([r(x), r(520), r(x + 140), r(660)], radius=r(34), fill=(255, 255, 255, 60 + i * 20))
img = Image.alpha_composite(img, t)

img.resize((1024, 1024), Image.LANCZOS).save("Resources/AppIcon.png")
