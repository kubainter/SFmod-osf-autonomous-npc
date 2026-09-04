import os
import glob
import random
from PIL import Image, ImageDraw, ImageFont

BASE_DIR = r"G:\Starfield\release\OSFAutonomous"
OUT_DIR = os.path.join(BASE_DIR, "promo_output")
os.makedirs(OUT_DIR, exist_ok=True)

# List of screenshots to process
SCREENSHOTS = [
    ("Zrzut ekranu 2026-09-01 145025.png", "promo_01_mess_hall", 0.165),
    ("Zrzut ekranu 2026-09-01 144712.png", "promo_02_crew_quarters", 0.155),
    ("Zrzut ekranu 2026-09-02 150356.png", "promo_03_medical_bay", 0.155),
    ("Zrzut ekranu 2026-09-02 190853.png", "promo_04_corridor", 0.175),
]

def create_banner(width, banner_height):
    """Creates a high quality banner matching the approved style."""
    red_height = int(banner_height * 0.38)
    dark_height = banner_height - red_height
    
    banner = Image.new("RGBA", (width, banner_height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(banner)
    
    # 1. Dark cosmic gradient
    for y in range(dark_height):
        progress = y / max(1, dark_height)
        r = int(5 + progress * 4)
        g = int(8 + progress * 6)
        b = int(18 + progress * 10)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))
        
    # Subtle top edge glow (Starfield cyan/blue accent)
    draw.line([(0, 0), (width, 0)], fill=(70, 130, 200, 180), width=2)
    
    # Random subtle stars in the dark section
    random.seed(42)
    for _ in range(int(width * 0.12)):
        sx = random.randint(0, width - 1)
        sy = random.randint(3, max(4, dark_height - 2))
        sa = random.randint(70, 220)
        draw.point((sx, sy), fill=(255, 255, 255, sa))
        
    # 2. Red bar (Adult / NSFW Content 18+)
    draw.rectangle([0, dark_height, width, banner_height], fill=(150, 8, 12, 255))
    draw.line([(0, dark_height), (width, dark_height)], fill=(200, 40, 45, 255), width=1)
    
    # Fonts
    font_paths = [
        ("C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/segoeui.ttf"),
        ("segoeuib.ttf", "segoeui.ttf"),
    ]
    f_title = None
    f_sub = None
    f_red = None
    for bold_p, reg_p in font_paths:
        try:
            f_title = ImageFont.truetype(bold_p, int(dark_height * 0.40))
            f_sub = ImageFont.truetype(reg_p, int(dark_height * 0.28))
            f_red = ImageFont.truetype(bold_p, int(red_height * 0.48))
            break
        except Exception:
            continue
            
    if f_title is None:
        f_title = f_sub = f_red = ImageFont.load_default()
        
    # 3. Typography in dark section
    title_text = "OSF Autonomous"
    tag_text = "Give your idle crew a life of their own."
    
    margin_x = int(width * 0.04)
    y_title = int(dark_height * 0.18)
    draw.text((margin_x, y_title), title_text, font=f_title, fill=(255, 255, 255, 255))
    
    tb = draw.textbbox((margin_x, y_title), title_text, font=f_title)
    tag_x = tb[2] + int(width * 0.02)
    y_sub = int(dark_height * 0.26)
    draw.text((tag_x, y_sub), f"—  {tag_text}", font=f_sub, fill=(190, 215, 245, 240))
    
    # 4. Typography in red section
    red_text = "Adult / NSFW Content (18+)"
    rtb = draw.textbbox((0, 0), red_text, font=f_red)
    rt_w = rtb[2] - rtb[0]
    rt_h = rtb[3] - rtb[1]
    draw.text(((width - rt_w) // 2, dark_height + (red_height - rt_h) // 2 - 2), red_text, font=f_red, fill=(255, 255, 255, 255))
    
    return banner

def process_screenshots():
    print(f"Rozpoczynam przetwarzanie zrzutów ekranu w: {BASE_DIR}")
    for filename, out_name, ratio in SCREENSHOTS:
        in_path = os.path.join(BASE_DIR, filename)
        if not os.path.exists(in_path):
            print(f"[OSTRZEŻENIE] Brak pliku: {in_path}")
            continue
            
        img = Image.open(in_path).convert("RGBA")
        W, H = img.size
        
        # Clean up any watch dial peeking in medical bay specifically
        if "150356" in filename:
            floor_patch = img.crop((85, 995, 335, 1045))
            img.paste(floor_patch, (85, 1055))
            
        banner_h = int(H * ratio)
        banner = create_banner(W, banner_h)
        
        # Composite banner at bottom
        img.alpha_composite(banner, (0, H - banner_h))
        
        # Save PNG (lossless) and JPG (optimized for Nexus web gallery)
        out_png = os.path.join(OUT_DIR, f"{out_name}.png")
        out_jpg = os.path.join(OUT_DIR, f"{out_name}.jpg")
        
        rgb_img = img.convert("RGB")
        rgb_img.save(out_png, "PNG")
        rgb_img.save(out_jpg, "JPEG", quality=95)
        
        print(f"[OK] Wygenerowano: {out_name}.png i {out_name}.jpg ({W}x{H})")

    print(f"\nGotowe! Wszystkie pliki zapisano w katalogu: {OUT_DIR}")

if __name__ == "__main__":
    process_screenshots()
