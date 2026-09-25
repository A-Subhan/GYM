#!/bin/bash
# Test script for Contoura Gym ERP
# Starts dev server, runs API tests, reports results

cd /home/z/my-project

# Kill any existing dev server
pkill -f "next" 2>/dev/null
sleep 2

# Start dev server with nohup and setsid to fully detach
setsid nohup bun run dev > /tmp/dev.log 2>&1 &
DEVPID=$!
echo "Dev PID: $DEVPID"

# Wait for server to be ready
for i in $(seq 1 30); do
  if curl -s http://localhost:3000/api/auth -X POST -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}' -c /tmp/cookies.txt 2>/dev/null | grep -q "Login successful"; then
    echo "✓ Server ready, login OK"
    break
  fi
  sleep 2
done

# Run all tests
echo ""
echo "=== TEST RESULTS ==="

# Test 1: Company
echo -n "1. Company API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/company)
if echo "$RESULT" | grep -q "Contoura Gym"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

# Test 2: Accounts (Charts)
echo -n "2. Accounts (Charts) API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/accounts)
COUNT=$(echo "$RESULT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['accounts']))" 2>/dev/null)
if [ "$COUNT" -gt "5" ] 2>/dev/null; then echo "PASS ($COUNT accounts)"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 3: Branches (hierarchy)
echo -n "3. Branches (hierarchy) API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/branches)
if echo "$RESULT" | grep -q "Contoura Group" && echo "$RESULT" | grep -q "Head Office"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 4: Finance Defaults
echo -n "4. Finance Defaults API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/finance-defaults)
if echo "$RESULT" | grep -q "financeType" && echo "$RESULT" | grep -q "coaLevelDetailing"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 5: Vouchers (list across 4 tables)
echo -n "5. Vouchers (4 tables) API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/vouchers)
if echo "$RESULT" | grep -q "vouchers"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 6: Fees
echo -n "6. Fees API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/fees)
if echo "$RESULT" | grep -q "fees"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 7: Gym Master Files (Equipment)
echo -n "7. GymMasterFiles (Equipment) API: "
RESULT=$(curl -s -b /tmp/cookies.txt "http://localhost:3000/api/gym-master-files?type=Equipment")
if echo "$RESULT" | grep -q "records"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 8: Payroll Master Files (LeaveType)
echo -n "8. PayrollMasterFiles (LeaveType) API: "
RESULT=$(curl -s -b /tmp/cookies.txt "http://localhost:3000/api/payroll-master-files?type=LeaveType")
if echo "$RESULT" | grep -q "Casual"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 9: Finance Reports
echo -n "9. Finance Reports API: "
RESULT=$(curl -s -b /tmp/cookies.txt "http://localhost:3000/api/finance-reports")
if echo "$RESULT" | grep -q "trial-balance"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 10: Opening Balance
echo -n "10. Opening Balance API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/opening-balance)
if echo "$RESULT" | grep -q "accounts"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 11: Account Mappings
echo -n "11. Account Mappings API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/account-mappings)
if echo "$RESULT" | grep -q "mappings"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 12: Users (with userPermissions)
echo -n "12. Users API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/users)
if echo "$RESULT" | grep -q "userPermissions"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 13: COA required validation (should reject missing fields)
echo -n "13. COA validation (reject missing fields): "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/accounts -H "Content-Type: application/json" -d '{"name":"Test"}')
if echo "$RESULT" | grep -q "required"; then echo "PASS (validation works)"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 14: Create a member (new ID format)
echo -n "14. Member creation (new ID format): "
BRANCH_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/branches | python3 -c "import json,sys; d=json.load(sys.stdin); print([b for b in d['branches'] if b['level']=='Control'][0]['id'])" 2>/dev/null)
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/members -H "Content-Type: application/json" -d "{\"firstName\":\"Test\",\"lastName\":\"Member\",\"branchId\":\"$BRANCH_ID\"}")
if echo "$RESULT" | grep -q "memberId" && echo "$RESULT" | grep -q "/"; then
  MEMBER_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['member']['memberId'])" 2>/dev/null)
  echo "PASS (memberId=$MEMBER_ID)"
else
  echo "FAIL: $RESULT" | head -c 200
fi

# Test 15: Dashboard
echo -n "15. Dashboard API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/dashboard)
if echo "$RESULT" | grep -q "stats"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

# Test 16: Knockoff (billwise)
echo -n "16. Knockoff API: "
RESULT=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/knockoff)
if echo "$RESULT" | grep -q "billTypes"; then echo "PASS"; else echo "FAIL: $RESULT" | head -c 200; fi

echo ""
echo "=== TEST SUMMARY ==="
echo "Dev server PID: $DEVPID"
echo "Check /tmp/dev.log for server logs"
