from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random

W, H = 1920, 1080

img = Image.new('RGBA', (W, H), (2, 4, 10, 255))
draw = ImageDraw.Draw(img)

# tło gradient
def draw_gradient(image):
    for y in range(H):
        r = int(5 + (y / H) * 2)
        g = int(8 + (y / H) * 4)
        b = int(18 + (y / H) * 8)
        draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

draw_gradient(img)

# gwiazdy
random.seed(42)
stars = [(random.randint(0, W-1), random.randint(0, H-1), random.randint(60, 200)) for _ in range(350)]
for x, y, a in stars:
    draw.point((x, y), fill=(255, 255, 255, a))

# planeta z prawej strony
planet = Image.new('RGBA', (600, 600), (0, 0, 0, 0))
pd = ImageDraw.Draw(planet)
for r in range(300, 0, -1):
    alpha = int(255 * (r / 300))
    color = (40 + int(r/10), 20 + int(r/20), 60 + int(r/8), min(alpha, 180))
    pd.ellipse([300-r, 300-r, 300+r, 300+r], fill=color)
img.paste(planet, (W-250, H-500), planet)

# fonty
try:
    f_title = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 120)
    f_sub = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 72)
    f_tag = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 44)
    f_req = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 32)
    f_red = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 48)
except:
    f_title = f_sub = f_tag = f_req = f_red = ImageFont.load_default()

# napis główny
draw.text((80, 120), "OSF Autonomous", font=f_title, fill=(255, 255, 255, 255))
draw.text((80, 280), "NPC Interactions", font=f_sub, fill=(180, 200, 230, 255))
draw.text((80, 400), "Give your idle crew a life of their own.", font=f_tag, fill=(200, 200, 200, 255))

# wymagania
draw.text((80, 640), "Requires: SFSE + OSF Animation + OSFUI", font=f_req, fill=(170, 170, 170, 255))

# czerwony pasek 18+
draw.rectangle([0, H-100, W, H], fill=(139, 0, 0, 255))
text = "Adult / NSFW Content (18+)"
bbox = draw.textbbox((0, 0), text, font=f_red)
tw = bbox[2] - bbox[0]
th = bbox[3] - bbox[1]
draw.text(((W - tw) // 2, H - 100 + (100 - th) // 2), text, font=f_red, fill=(255, 255, 255, 255))

img.save("G:/Starfield/release/OSFAutonomous/banner_new.png", "PNG")
print("saved")
