import io
import uvicorn
from pathlib import Path
from fastapi import FastAPI, UploadFile, File
from fastapi.responses import HTMLResponse
from ultralytics import YOLO
from PIL import Image

app = FastAPI(title="HydroPulse Visual Checker")

BASE_DIR = Path(__file__).resolve().parent
weights = list(BASE_DIR.glob("**/best.pt"))
if not weights:
    raise FileNotFoundError("Could not locate best.pt weights.")

model = YOLO(str(weights[-1]))

HTML_PAGE = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>HydroPulse Hazard Tester</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #f8fafc; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
    .card { background: #1e293b; padding: 2rem; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); width: 440px; text-align: center; border: 1px solid #334155; }
    h2 { margin-top: 0; color: #38bdf8; font-size: 1.5rem; }
    .upload-box { border: 2px dashed #475569; border-radius: 8px; padding: 1.5rem; cursor: pointer; margin-bottom: 1.5rem; transition: 0.2s; }
    .upload-box:hover { border-color: #38bdf8; background: #1e293b; }
    input[type="file"] { display: none; }
    #preview { max-width: 100%; max-height: 224px; border-radius: 6px; display: none; margin: 1rem auto; border: 2px solid #334155; }
    .badge { display: inline-block; padding: 6px 16px; border-radius: 20px; font-weight: bold; font-size: 0.9rem; text-transform: uppercase; margin-top: 1rem; }
    .badge-dry { background: #065f46; color: #34d399; }
    .badge-puddle { background: #854d0e; color: #facc15; }
    .badge-flooded { background: #991b1b; color: #f87171; }
    .metric-row { display: flex; justify-content: space-between; margin-top: 0.5rem; font-size: 0.85rem; color: #94a3b8; }
    .progress-bg { background: #334155; height: 6px; border-radius: 3px; overflow: hidden; margin-top: 4px; }
    .progress-fill { height: 100%; background: #38bdf8; width: 0%; transition: width 0.3s ease; }
  </style>
</head>
<body>
  <div class="card">
    <h2>Road Hazard Predictor</h2>
    <label class="upload-box" for="fileInput" id="dropArea">
      <div id="uploadPrompt">Click or Drop Road Image Here</div>
      <img id="preview" alt="Preview"/>
      <input type="file" id="fileInput" accept="image/*" />
    </label>
    <div id="results" style="display: none;">
      <div id="badge"></div>
      <div id="bars" style="margin-top: 1.5rem; text-align: left;"></div>
    </div>
  </div>

  <script>
    const fileInput = document.getElementById('fileInput');
    const preview = document.getElementById('preview');
    const prompt = document.getElementById('uploadPrompt');
    const results = document.getElementById('results');
    const badge = document.getElementById('badge');
    const bars = document.getElementById('bars');

    fileInput.addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;

      preview.src = URL.createObjectURL(file);
      preview.style.display = 'block';
      prompt.style.display = 'none';

      const formData = new FormData();
      formData.append('file', file);

      const res = await fetch('/predict', { method: 'POST', body: formData });
      const data = await res.json();

      badge.className = 'badge badge-' + data.prediction;
      badge.innerText = data.prediction + ' (' + (data.confidence * 100).toFixed(1) + '%)';

      bars.innerHTML = '';
      for (const [cls, prob] of Object.entries(data.probabilities)) {
        bars.innerHTML += `
          <div class="metric-row">
            <span>${cls.toUpperCase()}</span>
            <span>${(prob * 100).toFixed(1)}%</span>
          </div>
          <div class="progress-bg">
            <div class="progress-fill" style="width: ${(prob * 100).toFixed(1)}%"></div>
          </div>
        `;
      }
      results.style.display = 'block';
    });
  </script>
</body>
</html>
"""

@app.get("/", response_class=HTMLResponse)
async def index():
    return HTML_PAGE

@app.post("/predict")
async def predict_image(file: UploadFile = File(...)):
    contents = await file.read()
    img = Image.open(io.BytesIO(contents)).convert("RGB")
    res = model.predict(source=img, verbose=False)[0]
    
    top_id = int(res.probs.top1)
    detected_class = str(res.names[top_id]).lower()
    confidence = float(res.probs.top1conf.item())

    probs = {
        res.names[i].lower(): round(float(res.probs.data[i].item()), 4)
        for i in range(len(res.names))
    }

    return {
        "prediction": detected_class,
        "confidence": confidence,
        "probabilities": probs
    }

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)