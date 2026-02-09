#!/bin/bash

# ========================================
# Bulk Import - Upload and Monitor Script
# ========================================

MERCHANT_ID="09b45463-3812-42fb-9c7f-9d43b6fd3eb9"
API_URL="https://crm-batch-upload.onrender.com"

# ========================================
# 1. UPLOAD CSV
# ========================================

echo "📤 Uploading CSV..."
RESPONSE=$(curl -X POST ${API_URL}/api/import/purchases \
  -F "file=@USER_FRIENDLY_TEMPLATE.csv" \
  -F "merchant_id=${MERCHANT_ID}" \
  -F "batch_name=My Import $(date +%Y-%m-%d_%H:%M)")

echo "$RESPONSE" | python3 -m json.tool

# Extract batch_id
BATCH_ID=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin).get('batch_id', ''))" 2>/dev/null)

if [ -z "$BATCH_ID" ]; then
  echo "❌ Upload failed or batch_id not found"
  exit 1
fi

echo ""
echo "✅ Upload successful!"
echo "📋 Batch ID: $BATCH_ID"
echo ""

# ========================================
# 2. MONITOR PROGRESS
# ========================================

echo "⏳ Monitoring progress..."
echo "========================================"

COUNTER=0
while true; do
  COUNTER=$((COUNTER + 1))
  
  STATUS=$(curl -s ${API_URL}/api/import/status/${BATCH_ID})
  CURRENT_STATUS=$(echo $STATUS | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', 'unknown'))" 2>/dev/null)
  IMPORTED=$(echo $STATUS | python3 -c "import sys, json; print(json.load(sys.stdin).get('imported_purchases', 0))" 2>/dev/null)
  
  echo "Check #$COUNTER - Status: $CURRENT_STATUS | Imported: $IMPORTED purchases"
  
  if [ "$CURRENT_STATUS" = "completed" ]; then
    echo ""
    echo "✅ ========================================="
    echo "✅ IMPORT COMPLETED SUCCESSFULLY!"
    echo "✅ ========================================="
    echo ""
    echo "$STATUS" | python3 -m json.tool
    break
  elif [ "$CURRENT_STATUS" = "failed" ]; then
    echo ""
    echo "❌ ========================================="
    echo "❌ IMPORT FAILED!"
    echo "❌ ========================================="
    echo ""
    echo "$STATUS" | python3 -m json.tool
    break
  fi
  
  sleep 5
done

echo ""
echo "🎉 Done!"
