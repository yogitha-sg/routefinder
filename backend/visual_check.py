import os
from pathlib import Path
from ultralytics import YOLO
from PIL import Image, ImageDraw, ImageFont

BASE_DIR = Path(__file__).resolve().parent

# Find the latest best.pt
weights = list(BASE_DIR.glob("**/best.pt"))
if not weights:
    print("[ERROR] Could not find best.pt.")
    exit(1)

model_path = weights[-1]
print(f"Loading model: {model_path}")
model = YOLO(str(model_path))

# Output directory for annotated test images
output_dir = BASE_DIR / "visual_results"
output_dir.mkdir(parents=True, exist_ok=True)

# Color accents for each detected hazard
COLOR_MAP = {
    "dry": (46, 204, 113),       # Green
    "puddle": (241, 196, 15),     # Amber / Yellow
    "flooded": (231, 76, 60)      # Red
}

classes = ["dry", "puddle", "flooded"]
target_split = BASE_DIR / "val" if (BASE_DIR / "val").exists() else BASE_DIR / "train"

saved_previews = []

for cls_name in classes:
    class_folder = target_split / cls_name
    test_files = list(class_folder.glob("*.jpg"))
    if not test_files:
        continue

    # Pick the first image of each category
    img_file = test_files[0]

    # Run inference
    results = model.predict(source=str(img_file), verbose=False)
    top_id = int(results[0].probs.top1)
    predicted_label = results[0].names[top_id]
    conf = float(results[0].probs.top1conf.item()) * 100

    # Draw label overlay
    img = Image.open(img_file).convert("RGB")
    draw = ImageDraw.Draw(img)

    banner_text = f"{predicted_label.upper()} ({conf:.1f}%)"
    accent_color = COLOR_MAP.get(predicted_label, (255, 255, 255))

    # Top banner background
    draw.rectangle([(0, 0), (224, 32)], fill=(20, 24, 33))
    draw.rectangle([(0, 30), (224, 32)], fill=accent_color)
    draw.text((8, 8), banner_text, fill=accent_color)

    # Save labeled output
    out_file = output_dir / f"check_{cls_name}.jpg"
    img.save(out_file, quality=95)
    saved_previews.append(out_file)
    print(f"Saved: {out_file.name} -> Actual: {cls_name} | Predicted: {predicted_label} ({conf:.1f}%)")

print(f"\nAll annotated samples saved to: {output_dir}")

# Automatically open the generated preview images in Windows
for preview_img in saved_previews:
    os.startfile(str(preview_img))