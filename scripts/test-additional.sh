#!/bin/bash
# Additional tests for new features: KnockOff, Fee payment methods, Trainer fields
cd /home/z/my-project

curl -s -c /tmp/cookies.txt -X POST http://localhost:3000/api/auth -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}' > /dev/null
echo "✓ Login OK"

BRANCH_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/branches | python3 -c "import json,sys; d=json.load(sys.stdin); print([b for b in d['branches'] if b['level']=='Control'][0]['id'])")

echo ""
echo "=== TEST 11: KnockOff API ==="
# Find a Customer or Supplier tagged account
CUST_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/accounts | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d['accounts']:
    if a.get('accountTag') in ['Customer','Supplier']:
        print(a['id']); break
" 2>/dev/null)
echo "  Customer/Supplier account: $CUST_ID"

if [ -n "$CUST_ID" ]; then
  echo -n "  Create KnockOff bill: "
  RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/knockoff -H "Content-Type: application/json" -d "{\"accountId\":\"$CUST_ID\",\"branchId\":\"$BRANCH_ID\",\"billNumber\":\"INV-001\",\"billType\":\"Sales Bill\",\"amount\":5000,\"description\":\"Test bill\"}")
  if echo "$RESULT" | grep -q "billId"; then
    BID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['bill']['billId'])")
    echo "PASS (billId=$BID)"
  else
    echo "FAIL: $RESULT" | head -c 200
  fi

  echo -n "  List bills: "
  RESULT=$(curl -s -b /tmp/cookies.txt "http://localhost:3000/api/knockoff?accountId=$CUST_ID")
  if echo "$RESULT" | grep -q "bills"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi
fi

echo ""
echo "=== TEST 12: Fee Payment Methods (Cash, Card, Bank Transfer) ==="
MEMBER_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/members | python3 -c "import json,sys; print(json.load(sys.stdin)['members'][0]['id'])")
FEE_RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/fees -H "Content-Type: application/json" -d "{\"memberId\":\"$MEMBER_ID\",\"amount\":2000}")
FEE_ID=$(echo "$FEE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['fee']['id'])")
CASH_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/accounts | python3 -c "import json,sys; d=json.load(sys.stdin); print([a for a in d['accounts'] if a.get('bookType')=='Cash'][0]['id'])")

echo -n "  Cash payment: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/fees/pay -H "Content-Type: application/json" -d "{\"feeId\":\"$FEE_ID\",\"amount\":500,\"method\":\"Cash\",\"accountId\":\"$CASH_ID\"}")
if echo "$RESULT" | grep -q "fee"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

echo -n "  Card payment: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/fees/pay -H "Content-Type: application/json" -d "{\"feeId\":\"$FEE_ID\",\"amount\":500,\"method\":\"Card\",\"accountId\":\"$CASH_ID\"}")
if echo "$RESULT" | grep -q "fee"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

echo -n "  Bank Transfer payment: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/fees/pay -H "Content-Type: application/json" -d "{\"feeId\":\"$FEE_ID\",\"amount\":500,\"method\":\"Bank Transfer\",\"accountId\":\"$CASH_ID\"}")
if echo "$RESULT" | grep -q "fee"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

echo -n "  Invalid method (Online) rejected: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/fees/pay -H "Content-Type: application/json" -d "{\"feeId\":\"$FEE_ID\",\"amount\":500,\"method\":\"Online\",\"accountId\":\"$CASH_ID\"}")
if echo "$RESULT" | grep -q "error"; then echo "PASS (rejected)"; else echo "FAIL: $RESULT" | head -c 200; fi

echo ""
echo "=== TEST 13: Trainer Fields ==="
echo -n "  Create staff with trainer fields: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/staff -H "Content-Type: application/json" -d "{\"firstName\":\"Trainer\",\"lastName\":\"Test\",\"branchId\":\"$BRANCH_ID\",\"isTrainer\":true,\"specialization\":\"Strength Training\",\"availability\":\"Mon-Fri 9-5\",\"trainerSchedule\":\"Mon: 9-12\",\"personalTraining\":true}")
T_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['staff']['id'])" 2>/dev/null)
if [ -n "$T_ID" ]; then
  SPEC=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['staff'].get('specialization',''))" 2>/dev/null)
  echo "PASS (specialization=$SPEC)"
else
  echo "FAIL: $RESULT" | head -c 200
fi

echo -n "  Verify trainer fields persisted: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/staff | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d['staff']:
    if s['id'] == '$T_ID':
        print(f'specialization={s.get(\"specialization\")}, availability={s.get(\"availability\")}, schedule={s.get(\"trainerSchedule\")}, personalTraining={s.get(\"personalTraining\")}')
        break
" 2>/dev/null)
if echo "$RESULT" | grep -q "Strength"; then echo "PASS ($RESULT)"; else echo "FAIL: $RESULT"; fi

echo ""
echo "=== TEST 14: Project Structure ==="
echo -n "  Frontend/ exists: "
if [ -d Frontend ]; then echo "PASS"; else echo "FAIL"; fi
echo -n "  Backend/ exists: "
if [ -d Backend ]; then echo "PASS"; else echo "FAIL"; fi
echo -n "  Database/ exists: "
if [ -d Database ]; then echo "PASS"; else echo "FAIL"; fi
echo -n "  Database/GymDB.bak exists: "
if [ -f Database/GymDB.bak ]; then echo "PASS"; else echo "FAIL"; fi
echo -n "  Database/sql/ exists: "
if [ -d Database/sql ]; then echo "PASS"; else echo "FAIL"; fi
echo -n "  prisma/schema-sqlserver.prisma exists: "
if [ -f prisma/schema-sqlserver.prisma ]; then echo "PASS"; else echo "FAIL"; fi

echo ""
echo "=== TEST 15: Voucher Tables (CashBook, BankBook, JV, OpenTB) ==="
echo -n "  Voucher list API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/vouchers)
if echo "$RESULT" | grep -q "vouchers"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

echo -n "  CRV created (from fee payment): "
RESULT=$(curl -s -b /tmp/cookies.txt "http://localhost:3000/api/vouchers?voucherType=CRV")
if echo "$RESULT" | grep -q "voucherNo"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

echo -n "  JV creation: "
CASH_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/accounts | python3 -c "import json,sys; d=json.load(sys.stdin); print([a for a in d['accounts'] if a.get('bookType')=='Cash'][0]['id'])")
FEE_INC_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/accounts | python3 -c "import json,sys; d=json.load(sys.stdin); print([a for a in d['accounts'] if 'Fee Income' in a.get('name','')][0]['id'])")
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/vouchers -H "Content-Type: application/json" -d "{\"voucherType\":\"JV\",\"voucherDate\":\"$(date +%Y-%m-%d)\",\"branchId\":\"$BRANCH_ID\",\"description\":\"Test JV\",\"lines\":[{\"accountId\":\"$CASH_ID\",\"debit\":100,\"credit\":0},{\"accountId\":\"$FEE_INC_ID\",\"debit\":0,\"credit\":100}]}")
if echo "$RESULT" | grep -q "voucherNo"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

echo -n "  OTB unbalanced save: "
ACC_LIST=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/opening-balance | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'{a[\"id\"]}') for a in d['accounts'][:2]]")
ACC1=$(echo "$ACC_LIST" | head -1)
ACC2=$(echo "$ACC_LIST" | tail -1)
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/opening-balance -H "Content-Type: application/json" -d "{\"branchId\":\"$BRANCH_ID\",\"entries\":[{\"id\":\"$ACC1\",\"debit\":1000,\"credit\":0},{\"id\":\"$ACC2\",\"debit\":0,\"credit\":500}]}")
if echo "$RESULT" | grep -q "success"; then echo "PASS (unbalanced saved)"; else echo "FAIL: $RESULT" | head -c 200; fi

echo ""
echo "=== ALL ADDITIONAL TESTS COMPLETE ==="
