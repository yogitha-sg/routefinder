import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import shutil

BASE_DIR = Path(__file__).resolve().parent
TRAIN_DIR = BASE_DIR / "train"
VAL_DIR = BASE_DIR / "val"

# Clean out old images to avoid mixed patterns
for p in [TRAIN_DIR, VAL_DIR]:
    if p.exists():
        shutil.rmtree(p)

def make_dry_road():
    # Matte dark asphalt with white/yellow center lines
    img_arr = np.random.normal(50, 8, (224, 224, 3)).clip(20, 80).astype(np.uint8)
    img = Image.fromarray(img_arr)
    draw = ImageDraw.Draw(img)
    # Clear lane divider
    color = (240, 240, 240) if np.random.rand() > 0.5 else (240, 200, 30)
    draw.line([(112, 0), (112, 224)], fill=color, width=6)
    return img

def make_puddle_road():
    # Dry road background with distinct, high-contrast glossy puddle reflections
    img = make_dry_road()
    draw = ImageDraw.Draw(img)
    # Bright reflective water pool
    for _ in range(np.random.randint(2, 5)):
        x = np.random.randint(30, 150)
        y = np.random.randint(30, 150)
        w = np.random.randint(40, 75)
        h = np.random.randint(25, 55)
        # Specular sky reflection color
        puddle_col = (np.random.randint(140, 190), np.random.randint(170, 220), np.random.randint(210, 255))
        draw.ellipse([x, y, x + w, y + h], fill=puddle_col)
    return img.filter(ImageFilter.GaussianBlur(radius=1))

def make_flooded_road():
    # Submerged deep water: turbid brown/murky deep water dominating the entire surface
    if np.random.rand() > 0.5:
        # Muddy urban flood water
        base = np.array([120, 95, 55])
    else:
        # Deep murky stormy water
        base = np.array([45, 75, 110])
    
    noise = np.random.normal(0, 10, (224, 224, 3)).astype(np.int16)
    img_arr = np.clip(base + noise, 0, 255).astype(np.uint8)
    img = Image.fromarray(img_arr)
    draw = ImageDraw.Draw(img)
    # Surface flood waves and ripples
    for _ in range(12):
        y = np.random.randint(10, 214)
        x_start = np.random.randint(0, 60)
        x_end = np.random.randint(160, 224)
        draw.line([(x_start, y), (x_end, y + np.random.randint(-4, 4))], fill=(215, 225, 235), width=2)
    return img

def generate_dataset():
    print("Generating distinct, high-contrast hazard dataset...")
    for split, count in [(TRAIN_DIR, 50), (VAL_DIR, 15)]:
        for cls_name, generator in [("dry", make_dry_road), ("puddle", make_puddle_road), ("flooded", make_flooded_road)]:
            folder = split / cls_name
            folder.mkdir(parents=True, exist_ok=True)
            for i in range(count):
                img = generator()
                img.save(folder / f"{cls_name}_{i:03d}.jpg", "JPEG", quality=95)
            print(f"[{split.name.upper()}] Generated {count} images for '{cls_name}'")

if __name__ == "__main__":
    generate_dataset()
    print("\nDataset ready! Run: python train_hazard_model.py")