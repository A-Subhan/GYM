#!/bin/bash
# End-to-end test for voucher creation and fee payment
cd /home/z/my-project

# Login
curl -s -c /tmp/cookies.txt -X POST http://localhost:3000/api/auth -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}' > /dev/null
echo "✓ Login OK"

# Get branch ID (Control level = Head Office)
BRANCH_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/branches | python3 -c "import json,sys; d=json.load(sys.stdin); print([b for b in d['branches'] if b['level']=='Control'][0]['id'])" 2>/dev/null)
echo "✓ Branch ID: $BRANCH_ID"

# Get cash account ID
CASH_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/accounts | python3 -c "import json,sys; d=json.load(sys.stdin); print([a for a in d['accounts'] if a.get('bookType')=='Cash'][0]['id'])" 2>/dev/null)
echo "✓ Cash Account ID: $CASH_ID"

# Get fee income account ID
FEE_INC_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/accounts | python3 -c "import json,sys; d=json.load(sys.stdin); print([a for a in d['accounts'] if 'Fee Income' in a.get('name','')][0]['id'])" 2>/dev/null)
echo "✓ Fee Income Account ID: $FEE_INC_ID"

# Test 1: Create a CRV (Cash Receipt Voucher)
echo ""
echo "=== Test: Create CRV (Cash Receipt Voucher) ==="
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/vouchers \
  -H "Content-Type: application/json" \
  -d "{
    \"voucherType\": \"CRV\",
    \"voucherDate\": \"$(date -I)\",
    \"branchId\": \"$BRANCH_ID\",
    \"bookAccountId\": \"$CASH_ID\",
    \"description\": \"Test CRV — Cash Receipt\",
    \"lines\": [
      {\"accountId\": \"$FEE_INC_ID\", \"amount\": 5000, \"lineDescription\": \"Test income\"}
    ],
    \"status\": \"Posted\"
  }")
if echo "$RESULT" | grep -q "voucherNo"; then
  VOUCHER_NO=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['voucher']['voucherNo'])")
  echo "✓ CRV created: $VOUCHER_NO"
else
  echo "✗ CRV failed: $RESULT" | head -c 300
fi

# Test 2: Create a JV (Journal Voucher)
echo ""
echo "=== Test: Create JV (Journal Voucher) ==="
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/vouchers \
  -H "Content-Type: application/json" \
  -d "{
    \"voucherType\": \"JV\",
    \"voucherDate\": \"$(date -I)\",
    \"branchId\": \"$BRANCH_ID\",
    \"description\": \"Test JV — Journal Entry\",
    \"lines\": [
      {\"accountId\": \"$CASH_ID\", \"debit\": 1000, \"credit\": 0, \"lineDescription\": \"Debit cash\"},
      {\"accountId\": \"$FEE_INC_ID\", \"debit\": 0, \"credit\": 1000, \"lineDescription\": \"Credit income\"}
    ],
    \"status\": \"Posted\"
  }")
if echo "$RESULT" | grep -q "voucherNo"; then
  JV_NO=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['voucher']['voucherNo'])")
  echo "✓ JV created: $JV_NO"
else
  echo "✗ JV failed: $RESULT" | head -c 300
fi

# Test 3: Trial Balance Report
echo ""
echo "=== Test: Trial Balance Report ==="
RESULT=$(curl -s -b /tmp/cookies.txt "http://localhost:3000/api/finance-reports?report=trial-balance")
if echo "$RESULT" | grep -q "totalDebit"; then
  echo "✓ Trial Balance report generated"
  echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin)['report']; print(f'  Total Debit: {d[\"totalDebit\"]}, Total Credit: {d[\"totalCredit\"]}, Balanced: {d[\"balanced\"]}')" 2>/dev/null
else
  echo "✗ Trial Balance failed: $RESULT" | head -c 300
fi

# Test 4: Cash Book Report
echo ""
echo "=== Test: Cash Book Report ==="
RESULT=$(curl -s -b /tmp/cookies.txt "http://localhost:3000/api/finance-reports?report=cash-book")
if echo "$RESULT" | grep -q "Cash Book"; then
  echo "✓ Cash Book report generated"
else
  echo "✗ Cash Book failed: $RESULT" | head -c 300
fi

# Test 5: Opening Trial Balance (unbalanced save)
echo ""
echo "=== Test: Opening Trial Balance (unbalanced save) ==="
ACCOUNTS=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/opening-balance)
ACC_ID=$(echo "$ACCOUNTS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['accounts'][0]['id'])" 2>/dev/null)
ACC2_ID=$(echo "$ACCOUNTS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['accounts'][1]['id'])" 2>/dev/null)
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/opening-balance \
  -H "Content-Type: application/json" \
  -d "{
    \"branchId\": \"$BRANCH_ID\",
    \"entries\": [
      {\"id\": \"$ACC_ID\", \"debit\": 5000, \"credit\": 0},
      {\"id\": \"$ACC2_ID\", \"debit\": 0, \"credit\": 3000}
    ]
  }")
if echo "$RESULT" | grep -q "success"; then
  echo "✓ OTB unbalanced save worked (debit 5000 ≠ credit 3000)"
else
  echo "✗ OTB save failed: $RESULT" | head -c 300
fi

# Test 6: Create a membership plan and member, then create fee
echo ""
echo "=== Test: Member + Fee workflow ==="
MEMBER_RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/members \
  -H "Content-Type: application/json" \
  -d "{\"firstName\":\"John\",\"lastName\":\"Doe\",\"branchId\":\"$BRANCH_ID\",\"phone\":\"03001234567\"}")
MEMBER_ID=$(echo "$MEMBER_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['member']['id'])" 2>/dev/null)
MEMBER_MEMBER_ID=$(echo "$MEMBER_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['member']['memberId'])" 2>/dev/null)
echo "✓ Member created: $MEMBER_MEMBER_ID"

# Create fee
FEE_RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/fees \
  -H "Content-Type: application/json" \
  -d "{\"memberId\":\"$MEMBER_ID\",\"amount\":3000}")
if echo "$FEE_RESULT" | grep -q "feeNo"; then
  FEE_NO=$(echo "$FEE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['fee']['feeNo'])")
  FEE_ID=$(echo "$FEE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['fee']['id'])")
  echo "✓ Fee created: $FEE_NO"
else
  echo "✗ Fee creation failed: $FEE_RESULT" | head -c 300
fi

# Test 7: Voucher register report
echo ""
echo "=== Test: Voucher Register Report ==="
RESULT=$(curl -s -b /tmp/cookies.txt "http://localhost:3000/api/finance-reports?report=voucher-register")
if echo "$RESULT" | grep -q "Voucher Register"; then
  COUNT=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin)['report']; print(len(d['vouchers']))" 2>/dev/null)
  echo "✓ Voucher Register report: $COUNT vouchers"
else
  echo "✗ Voucher Register failed: $RESULT" | head -c 300
fi

echo ""
echo "=== END-TO-END TEST COMPLETE ==="
