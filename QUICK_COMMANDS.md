# Quick Command Reference

## 📤 Upload CSV

### Simple Upload:
```bash
curl -X POST https://crm-batch-upload.onrender.com/api/import/purchases \
  -F "file=@myfile.csv" \
  -F "merchant_id=09b45463-3812-42fb-9c7f-9d43b6fd3eb9" \
  -F "batch_name=My Import"
```

### With Date Stamp:
```bash
curl -X POST https://crm-batch-upload.onrender.com/api/import/purchases \
  -F "file=@purchases.csv" \
  -F "merchant_id=09b45463-3812-42fb-9c7f-9d43b6fd3eb9" \
  -F "batch_name=Import $(date +%Y-%m-%d)"
```

---

## 📊 Check Progress

### Single Check:
```bash
curl https://crm-batch-upload.onrender.com/api/import/status/BATCH_ID
```

### Formatted Output:
```bash
curl -s https://crm-batch-upload.onrender.com/api/import/status/BATCH_ID | python3 -m json.tool
```

### Monitor Until Complete:
```bash
BATCH_ID="your-batch-id"

while true; do
  STATUS=$(curl -s https://crm-batch-upload.onrender.com/api/import/status/$BATCH_ID)
  echo "$STATUS" | python3 -m json.tool
  
  if echo "$STATUS" | grep -q '"completed"\|"failed"'; then
    break
  fi
  
  echo "⏳ Still processing..."
  sleep 5
done
```

---

## 📋 List All Imports:
```bash
curl https://crm-batch-upload.onrender.com/api/import/list/09b45463-3812-42fb-9c7f-9d43b6fd3eb9
```

---

## 🏥 Health Check:
```bash
curl https://crm-batch-upload.onrender.com/health
```

---

## 🚀 Automated Script:

Use the provided script:
```bash
chmod +x UPLOAD_COMMANDS.sh
./UPLOAD_COMMANDS.sh
```

**Edit the script to change:**
- File name (line with `-F "file=@..."`
- Merchant ID
- Batch name

---

## 💡 Tips:

### Save Batch ID for Later:
```bash
BATCH_ID=$(curl -X POST ... | python3 -c "import sys, json; print(json.load(sys.stdin)['batch_id'])")
echo $BATCH_ID > last_batch_id.txt
```

### Check Last Import:
```bash
BATCH_ID=$(cat last_batch_id.txt)
curl -s https://crm-batch-upload.onrender.com/api/import/status/$BATCH_ID | python3 -m json.tool
```

### Pretty Print:
```bash
# Add to your .bashrc or .zshrc
alias import-status='curl -s https://crm-batch-upload.onrender.com/api/import/status/$1 | python3 -m json.tool'

# Then use:
import-status BATCH_ID
```

---

**All commands ready to use!** 📋
