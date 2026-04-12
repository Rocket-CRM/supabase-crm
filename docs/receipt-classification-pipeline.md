# Receipt Classification Pipeline — Complete Guide

## Architecture

```
receipt.jpg
     │
     ▼
┌──────────────────────────────┐
│  Model 1: Object Detection   │  Roboflow API
│  "Where are the zones?"      │  Detects: store_header, transaction_info, items_list, total
└──────────────────────────────┘
     │
     │  Returns bounding box coordinates for each zone
     │
     ▼
┌──────────────────────────────┐
│  Crop store_header zone      │  Runs locally (Python + PIL)
│  using x/y/width/height      │  No API call, just image math
└──────────────────────────────┘
     │
     │  Produces a small image of just the store header
     │
     ▼
┌──────────────────────────────┐
│  Model 2: Classification     │  Roboflow API
│  "Which store is this?"      │  Returns: store name + confidence
└──────────────────────────────┘
     │
     ▼
  Result: valid receipt + store identified
```

---

## Phase 1: Collect Receipt Images

### What this does
You need real receipt photos to train the models. The more variety (different stores, lighting, angles, formats), the better the model generalizes.

### Steps
1. Gather 200+ receipt photos from different stores
2. Mix of formats: branded (logos), plain text, thermal paper, A4 invoices
3. Include photos taken at different angles, lighting, distances
4. Create a project folder:

```bash
mkdir -p receipt-pipeline/receipt_images
```

5. Put all receipt images in `receipt-pipeline/receipt_images/`

---

## Phase 2: Train Model 1 — Zone Detection

### What this does
Model 1 learns to find 4 specific zones on any receipt image, regardless of which store it's from. It returns bounding box coordinates (position + size) for each zone it finds.

### The 4 zone labels

| Label | What to box | Purpose |
|---|---|---|
| `store_header` | Logo, store name, address, tax ID — entire top section | Crop this for Model 2 |
| `transaction_info` | Receipt #, date, time, POS, staff, operator | Validates it's a real transaction |
| `items_list` | All line items with prices and discounts | Validates it's a real receipt |
| `total` | Total amount, payment method, quantity count | Validates there's a transaction amount |

### Steps

#### 2.1 — Create Roboflow project
1. Go to https://app.roboflow.com
2. Click **Create New Project**
3. Project Name: `receipt-zone-detection`
4. Project Type: **Object Detection**
5. Click Create

#### 2.2 — Upload images
1. In the project, click **Upload**
2. Drag all images from `receipt_images/` into the upload area
3. Click **Save and Continue**

#### 2.3 — Annotate images (draw bounding boxes)
For each image, draw 4 bounding boxes:

```
┌──────────────────────────────┐
│ ┌──────────────────────────┐ │
│ │  H&M                     │ │
│ │  H&M Future Park Rangsit │ │  ← store_header
│ │  HTHAI (THAILAND) Co.    │ │
│ │  TAX ID: 0-10-5-554-...  │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │  Receipt: 00001016...    │ │
│ │  POS: 101604 Date:29/11  │ │  ← transaction_info
│ │  Staff: 200134 Time:15:48│ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │  Terryband Pola    129   │ │
│ │  Black Fr 50%     -64.50 │ │  ← items_list
│ │  Hairclip Bryan    129   │ │
│ │  Black Fr 50%     -64.50 │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │  Total           1,128   │ │  ← total
│ │  VISA THB        1,128   │ │
│ └──────────────────────────┘ │
└──────────────────────────────┘
```

Repeat for all images. After ~30-50 images, Roboflow Label Assist starts suggesting boxes automatically.

#### 2.4 — Generate dataset version
1. Click **Generate** in left sidebar
2. Preprocessing: Auto-Orient ON, Resize to 640x640
3. Augmentation: Brightness -15% to +15%, Noise up to 2%
4. Click **Generate**

#### 2.5 — Train
1. Click **Train**
2. Select **Roboflow 3.0 Object Detection (Fast)**
3. Click **Start Training**
4. Wait for training to complete (~30-60 min)

#### 2.6 — Get API details
Go to **Deploy** tab. Save these values:
- API URL: `https://detect.roboflow.com/receipt-zone-detection/1`
- API Key: `your_api_key`

---

## Phase 3: Batch Crop Store Headers

### What this does
Runs Model 1 on all your receipt images, finds the `store_header` zone on each one, crops that region, and saves it as a separate image. These cropped images become the training data for Model 2.

### Steps

#### 3.1 — Install Python dependencies

```bash
pip install requests pillow
```

#### 3.2 — Create the batch crop script

Save as `receipt-pipeline/batch_crop.py`:

```python
import requests
import glob
import os
from PIL import Image

# ── Config ──────────────────────────────────────────
ROBOFLOW_API_KEY = "YOUR_API_KEY"
DETECT_URL = "https://detect.roboflow.com/YOUR_PROJECT/YOUR_VERSION"
INPUT_DIR = "./receipt_images"
OUTPUT_DIR = "./cropped_headers"
MIN_CONFIDENCE = 0.5
# ────────────────────────────────────────────────────

os.makedirs(OUTPUT_DIR, exist_ok=True)


def detect_zones(image_path):
    with open(image_path, "rb") as f:
        resp = requests.post(
            DETECT_URL,
            params={"api_key": ROBOFLOW_API_KEY},
            files={"file": f},
        )
    return resp.json()


def crop_box(image_path, pred):
    img = Image.open(image_path)
    x, y, w, h = pred["x"], pred["y"], pred["width"], pred["height"]
    pad_x, pad_y = w * 0.1, h * 0.1
    left = max(0, x - w/2 - pad_x)
    top = max(0, y - h/2 - pad_y)
    right = min(img.width, x + w/2 + pad_x)
    bottom = min(img.height, y + h/2 + pad_y)
    return img.crop((left, top, right, bottom))


processed = 0
skipped = 0

for path in glob.glob(f"{INPUT_DIR}/*.*"):
    name = os.path.basename(path)
    result = detect_zones(path)

    header = None
    for p in result.get("predictions", []):
        if p["class"] == "store_header" and p["confidence"] > MIN_CONFIDENCE:
            header = p
            break

    if header is None:
        print(f"SKIP  {name} (no store_header found)")
        skipped += 1
        continue

    cropped = crop_box(path, header)
    out = os.path.join(OUTPUT_DIR, f"crop_{name}")
    cropped.save(out)
    processed += 1
    print(f"OK    {name} -> {out}")

print(f"\nDone. Cropped: {processed}, Skipped: {skipped}")
```

#### 3.3 — Run it

```bash
cd receipt-pipeline
python batch_crop.py
```

Output:
```
OK    img_001.jpg -> ./cropped_headers/crop_img_001.jpg
OK    img_002.jpg -> ./cropped_headers/crop_img_002.jpg
SKIP  img_003.jpg (no store_header found)
OK    img_004.jpg -> ./cropped_headers/crop_img_004.jpg
...
Done. Cropped: 187, Skipped: 13
```

---

## Phase 4: Sort Crops by Store

### What this does
You manually look at each cropped header image and put it in a folder named after the store. Roboflow reads folder names as class labels, so this is how you label the training data for Model 2.

### Steps

#### 4.1 — Create store folders

```bash
cd cropped_headers
mkdir hm 7eleven bigc tops lotus makro unknown
```

Create one folder per store you want to classify.

#### 4.2 — Sort images

Open `cropped_headers/` in Finder. Look at each crop, drag it into the matching store folder.

Result:
```
cropped_headers/
  ├── hm/              (50+ images)
  ├── 7eleven/         (50+ images)
  ├── bigc/            (40+ images)
  ├── tops/            (35+ images)
  ├── lotus/           (30+ images)
  ├── makro/           (25+ images)
  └── unknown/         (anything unrecognizable)
```

Aim for 30-50+ images per store.

---

## Phase 5: Train Model 2 — Store Classification

### What this does
Model 2 learns to identify which store a cropped header image belongs to. It only sees the header (logo, name, address), not the full receipt. This focused input makes classification accurate even for plain-text receipts.

### Steps

#### 5.1 — Create Roboflow project
1. Go to https://app.roboflow.com
2. Click **Create New Project**
3. Project Name: `receipt-store-classifier`
4. Project Type: **Classification → Single-Label**
5. Click Create

#### 5.2 — Upload sorted crops
1. Click **Upload**
2. Drag the **entire `cropped_headers/` folder** (with subfolders) into the upload area
3. Roboflow reads subfolder names as class labels automatically
4. Click **Save and Continue**

#### 5.3 — Generate dataset version
1. Click **Generate**
2. Preprocessing: Auto-Orient ON, Resize to 224x224
3. Augmentation: Brightness -15% to +15%, Noise up to 2%, Rotation -5 to +5 degrees
4. Click **Generate**

#### 5.4 — Train
1. Click **Train**
2. Select **Roboflow 3.0 Classification (Fast)**
3. Click **Start Training**
4. Wait for training to complete (~15-30 min)

#### 5.5 — Get API details
Go to **Deploy** tab. Save these values:
- API URL: `https://classify.roboflow.com/receipt-store-classifier/1`
- API Key: same key as before

---

## Phase 6: Run the Full Pipeline

### What this does
This is the production script. For any new receipt image, it:
1. Calls Model 1 to detect zones (validates it's a receipt)
2. Crops the store header locally
3. Calls Model 2 to classify which store
4. Returns a decision: approved / review / rejected

### Steps

#### 6.1 — Create the pipeline script

Save as `receipt-pipeline/receipt_pipeline.py`:

```python
import requests
import os
import sys
import tempfile
from PIL import Image

# ── Config ──────────────────────────────────────────
ROBOFLOW_API_KEY = "YOUR_API_KEY"
DETECT_URL = "https://detect.roboflow.com/YOUR_DETECTION_PROJECT/YOUR_VERSION"
CLASSIFY_URL = "https://classify.roboflow.com/YOUR_CLASSIFICATION_PROJECT/YOUR_VERSION"
MIN_ZONE_CONFIDENCE = 0.5
MIN_STORE_CONFIDENCE = 0.7
# ────────────────────────────────────────────────────


def detect_zones(image_path):
    with open(image_path, "rb") as f:
        resp = requests.post(
            DETECT_URL,
            params={"api_key": ROBOFLOW_API_KEY},
            files={"file": f},
        )
    return resp.json()


def crop_box(image_path, pred):
    img = Image.open(image_path)
    x, y, w, h = pred["x"], pred["y"], pred["width"], pred["height"]
    pad_x, pad_y = w * 0.1, h * 0.1
    left = max(0, x - w/2 - pad_x)
    top = max(0, y - h/2 - pad_y)
    right = min(img.width, x + w/2 + pad_x)
    bottom = min(img.height, y + h/2 + pad_y)
    return img.crop((left, top, right, bottom))


def classify_header(cropped_image):
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        cropped_image.save(tmp.name)
        with open(tmp.name, "rb") as f:
            resp = requests.post(
                CLASSIFY_URL,
                params={"api_key": ROBOFLOW_API_KEY},
                files={"file": f},
            )
        os.unlink(tmp.name)
    return resp.json()


def process(image_path):
    print(f"Step 1: Detecting zones...")
    zones = detect_zones(image_path)
    preds = zones.get("predictions", [])
    found = {p["class"] for p in preds if p["confidence"] > MIN_ZONE_CONFIDENCE}

    print(f"  Zones found: {sorted(found)}")

    if "store_header" not in found:
        return {"status": "rejected", "reason": "no store header detected"}

    if "items_list" not in found or "total" not in found:
        return {"status": "suspicious", "reason": "missing items_list or total"}

    header_pred = next(
        p for p in preds
        if p["class"] == "store_header" and p["confidence"] > MIN_ZONE_CONFIDENCE
    )

    print(f"Step 2: Cropping store header...")
    cropped = crop_box(image_path, header_pred)

    print(f"Step 3: Classifying store...")
    result = classify_header(cropped)
    top = result["predictions"][0]

    print(f"  Store: {top['class']} (confidence: {top['confidence']:.2f})")

    if top["confidence"] >= MIN_STORE_CONFIDENCE:
        status = "approved"
    elif top["confidence"] >= 0.4:
        status = "review"
    else:
        status = "unknown_store"

    return {
        "status": status,
        "store": top["class"],
        "store_confidence": round(top["confidence"], 3),
        "zones_found": sorted(found),
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python receipt_pipeline.py <image_path>")
        sys.exit(1)

    result = process(sys.argv[1])
    print(f"\n{'='*40}")
    print(f"RESULT:")
    for k, v in result.items():
        print(f"  {k}: {v}")
```

#### 6.2 — Run it

```bash
python receipt_pipeline.py ./test_receipt.jpg
```

Output:
```
Step 1: Detecting zones...
  Zones found: ['items_list', 'store_header', 'total', 'transaction_info']
Step 2: Cropping store header...
Step 3: Classifying store...
  Store: hm (confidence: 0.94)

========================================
RESULT:
  status: approved
  store: hm
  store_confidence: 0.94
  zones_found: ['items_list', 'store_header', 'total', 'transaction_info']
```

---

## Summary — What Happens at Each Phase

| Phase | What You Do | What It Produces | Time |
|---|---|---|---|
| 1. Collect images | Gather 200+ receipt photos | `receipt_images/` folder | varies |
| 2. Train Model 1 | Annotate zones in Roboflow, train | Object Detection API endpoint | 3-5 hours |
| 3. Batch crop | Run `batch_crop.py` on terminal | `cropped_headers/` folder with header crops | 10 min |
| 4. Sort crops | Drag crops into store folders in Finder | Labeled training data for Model 2 | 30 min |
| 5. Train Model 2 | Upload folders to Roboflow, train | Classification API endpoint | 30 min |
| 6. Run pipeline | Run `receipt_pipeline.py` per receipt | approved / review / rejected + store name | 1-2 sec |

---

## Adding New Stores Later

1. Collect 30-50 receipt photos from the new store
2. Run `batch_crop.py` on just those new images
3. Put the crops in a new store folder
4. Upload to the Model 2 Roboflow project
5. Retrain Model 2

Model 1 does not change. No code changes needed.
