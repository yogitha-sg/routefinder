from pathlib import Path
from ultralytics import YOLO

BASE_DIR = Path(__file__).resolve().parent

# Find best.pt
weight_files = list(BASE_DIR.glob("**/best.pt"))
if not weight_files:
    print("[ERROR] best.pt not found.")
    exit(1)

model_path = weight_files[-1]
print(f"Loading weights from: {model_path}\n")
model = YOLO(str(model_path))

classes = ["dry", "puddle", "flooded"]
target_split = BASE_DIR / "val" if (BASE_DIR / "val").exists() else BASE_DIR / "train"

print(f"{'Actual':<12} | {'Predicted':<12} | {'Confidence':<10} | {'Status'}")
print("-" * 50)

for cls_name in classes:
    class_folder = target_split / cls_name
    sample_images = list(class_folder.glob("*.jpg"))[:2]  # test 2 of each class

    for img_path in sample_images:
        results = model.predict(source=str(img_path), verbose=False)
        top_id = int(results[0].probs.top1)
        predicted_label = results[0].names[top_id]
        conf = float(results[0].probs.top1conf.item()) * 100

        status = "PASS" if cls_name == predicted_label else "FAIL"
        print(f"{cls_name:<12} | {predicted_label:<12} | {conf:>6.1f}%    | {status}")