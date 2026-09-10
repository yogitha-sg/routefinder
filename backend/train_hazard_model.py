import os
from pathlib import Path
from ultralytics import YOLO

def train():
    current_dir = Path(__file__).resolve().parent
    train_dir = current_dir / "train"

    # Validate classes and images
    valid_exts = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
    print(f"Checking dataset at: {current_dir}")

    total_images = 0
    if train_dir.exists():
        for class_dir in train_dir.iterdir():
            if class_dir.is_dir():
                images = [f for f in class_dir.iterdir() if f.suffix.lower() in valid_exts]
                print(f" -> Found class '{class_dir.name}': {len(images)} images")
                total_images += len(images)

    if total_images == 0:
        print("\nERROR: No valid images found inside .\\train\\<class>\\ folders!")
        print("Please copy your .jpg images into: train/dry, train/flooded, train/puddle")
        return

    print(f"\nTotal training images found: {total_images}. Starting YOLO training...")
    
    model = YOLO("yolov8n-cls.pt")
    model.train(
        data=str(current_dir),
        epochs=30,
        imgsz=224,
        batch=16,
        project="runs",
        name="routefinder_hazard_cls"
    )

if __name__ == "__main__":
    train()