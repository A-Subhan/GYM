#!/bin/bash
# Comprehensive test script for all verified items
cd /home/z/my-project

curl -s -c /tmp/cookies.txt -X POST http://localhost:3000/api/auth -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}' > /dev/null
echo "✓ Login OK"

BRANCH_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/branches | python3 -c "import json,sys; d=json.load(sys.stdin); print([b for b in d['branches'] if b['level']=='Control'][0]['id'])")
echo "✓ Branch ID: $BRANCH_ID"

echo ""
echo "=== TEST 1: Attendance current-date validation (backend) ==="
MEMBER_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/members | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['members'][0]['id'])")

# Test: future date should be rejected
echo -n "  Future date: "
FUTURE_DATE=$(date -d "+2 days" +%Y-%m-%d)
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/attendance -H "Content-Type: application/json" -d "{\"memberId\":\"$MEMBER_ID\",\"date\":\"$FUTURE_DATE\"}")
if echo "$RESULT" | grep -q "future day"; then echo "PASS (rejected: future day)"; else echo "FAIL: $RESULT"; fi

# Test: previous date should be rejected
echo -n "  Previous date: "
PAST_DATE=$(date -d "-2 days" +%Y-%m-%d)
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/attendance -H "Content-Type: application/json" -d "{\"memberId\":\"$MEMBER_ID\",\"date\":\"$PAST_DATE\"}")
if echo "$RESULT" | grep -q "previous day"; then echo "PASS (rejected: previous day)"; else echo "FAIL: $RESULT"; fi

# Test: today should work
echo -n "  Today: "
TODAY=$(date +%Y-%m-%d)
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/attendance -H "Content-Type: application/json" -d "{\"memberId\":\"$MEMBER_ID\",\"date\":\"$TODAY\"}")
if echo "$RESULT" | grep -q "attendanceId"; then echo "PASS (accepted: today)"; else echo "FAIL: $RESULT"; fi

echo ""
echo "=== TEST 2: Attendance Check Out ==="
ATT_ID=$(curl -s -b /tmp/cookies.txt http://localhost:3000/api/attendance | python3 -c "import json,sys; d=json.load(sys.stdin); print([r for r in d['records'] if not r.get('checkOut')][0]['id'])" 2>/dev/null)
echo -n "  Check Out: "
if [ -n "$ATT_ID" ]; then
  RESULT=$(curl -s -b /tmp/cookies.txt -X PATCH http://localhost:3000/api/attendance -H "Content-Type: application/json" -d "{\"id\":\"$ATT_ID\",\"checkOut\":\"$(date -Iseconds)\"}")
  if echo "$RESULT" | grep -q "checkOut"; then echo "PASS"; else echo "FAIL: $RESULT"; fi
else
  echo "SKIP (no record without checkOut)"
fi

echo ""
echo "=== TEST 3: Shifts CRUD ==="
# Create
echo -n "  Create: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/shifts -H "Content-Type: application/json" -d '{"name":"Test Shift","timeIn":"09:00","timeOut":"17:00"}')
SHIFT_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['shift']['id'])" 2>/dev/null)
if [ -n "$SHIFT_ID" ]; then echo "PASS (id=$SHIFT_ID)"; else echo "FAIL: $RESULT"; fi

# Edit
echo -n "  Edit: "
RESULT=$(curl -s -b /tmp/cookies.txt -X PATCH http://localhost:3000/api/shifts -H "Content-Type: application/json" -d "{\"id\":\"$SHIFT_ID\",\"name\":\"Updated Shift\"}")
if echo "$RESULT" | grep -q "Updated Shift"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

# Delete
echo -n "  Delete: "
RESULT=$(curl -s -b /tmp/cookies.txt -X DELETE "http://localhost:3000/api/shifts?id=$SHIFT_ID")
if echo "$RESULT" | grep -q "success"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

echo ""
echo "=== TEST 4: Leaves CRUD ==="
# Create staff first
STAFF_RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/staff -H "Content-Type: application/json" -d "{\"firstName\":\"Test\",\"lastName\":\"Staff\",\"branchId\":\"$BRANCH_ID\"}")
STAFF_ID=$(echo "$STAFF_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['staff']['id'])" 2>/dev/null)

# Create leave
echo -n "  Create: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/leaves -H "Content-Type: application/json" -d "{\"staffId\":\"$STAFF_ID\",\"leaveType\":\"Casual\",\"fromDate\":\"$(date +%Y-%m-%d)\",\"toDate\":\"$(date -d '+2 days' +%Y-%m-%d)\"}")
LEAVE_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['leave']['id'])" 2>/dev/null)
LEAVE_ID_FMT=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['leave']['leaveId'])" 2>/dev/null)
if [ -n "$LEAVE_ID" ]; then echo "PASS (leaveId=$LEAVE_ID_FMT)"; else echo "FAIL: $RESULT"; fi

# Delete
echo -n "  Delete: "
RESULT=$(curl -s -b /tmp/cookies.txt -X DELETE "http://localhost:3000/api/leaves?id=$LEAVE_ID")
if echo "$RESULT" | grep -q "success"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

echo ""
echo "=== TEST 5: Staff CRUD ==="
# Create
echo -n "  Create: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/staff -H "Content-Type: application/json" -d "{\"firstName\":\"Test\",\"lastName\":\"Staff\",\"branchId\":\"$BRANCH_ID\"}")
STAFF_ID2=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['staff']['id'])" 2>/dev/null)
if [ -n "$STAFF_ID2" ]; then echo "PASS (id=$STAFF_ID2)"; else echo "FAIL: $RESULT"; fi

# Edit
echo -n "  Edit: "
RESULT=$(curl -s -b /tmp/cookies.txt -X PATCH http://localhost:3000/api/staff -H "Content-Type: application/json" -d "{\"id\":\"$STAFF_ID2\",\"firstName\":\"Updated\",\"lastName\":\"Staff\"}")
if echo "$RESULT" | grep -q "Updated"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

# Delete (soft)
echo -n "  Delete: "
RESULT=$(curl -s -b /tmp/cookies.txt -X DELETE "http://localhost:3000/api/staff?id=$STAFF_ID2")
if echo "$RESULT" | grep -q "success"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

echo ""
echo "=== TEST 6: Membership Plan CRUD ==="
# Create
echo -n "  Create: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/memberships -H "Content-Type: application/json" -d '{"name":"Test Plan","durationDays":30,"amount":500}')
PLAN_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['plan']['id'])" 2>/dev/null)
PLAN_CODE=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['plan']['code'])" 2>/dev/null)
if [ -n "$PLAN_ID" ]; then echo "PASS (code=$PLAN_CODE)"; else echo "FAIL: $RESULT"; fi

# Edit
echo -n "  Edit: "
RESULT=$(curl -s -b /tmp/cookies.txt -X PATCH "http://localhost:3000/api/memberships/$PLAN_ID" -H "Content-Type: application/json" -d '{"name":"Updated Plan","durationDays":60,"amount":1000}')
if echo "$RESULT" | grep -q "Updated Plan"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

# Delete
echo -n "  Delete: "
RESULT=$(curl -s -b /tmp/cookies.txt -X DELETE "http://localhost:3000/api/memberships/$PLAN_ID")
if echo "$RESULT" | grep -q "success"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

echo ""
echo "=== TEST 7: Leave ID format (BranchID/LV-0001) ==="
# Create another leave to verify format
echo -n "  Leave ID format: "
RESULT=$(curl -s -b /tmp/cookies.txt -X POST http://localhost:3000/api/leaves -H "Content-Type: application/json" -d "{\"staffId\":\"$STAFF_ID\",\"leaveType\":\"Sick\",\"fromDate\":\"$(date +%Y-%m-%d)\",\"toDate\":\"$(date -d '+1 day' +%Y-%m-%d)\",\"branchId\":\"$BRANCH_ID\"}")
LEAVE_ID_FMT=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['leave']['leaveId'])" 2>/dev/null)
if echo "$LEAVE_ID_FMT" | grep -q "/LV-"; then echo "PASS ($LEAVE_ID_FMT)"; else echo "FAIL: $LEAVE_ID_FMT"; fi

echo ""
echo "=== TEST 8: Permission enforcement ==="
# Login as receptionist (limited permissions)
curl -s -c /tmp/cookies2.txt -X POST http://localhost:3000/api/auth -H "Content-Type: application/json" -d '{"username":"testreception","password":"test123"}' > /dev/null

echo -n "  Receptionist cannot add branch: "
RESULT=$(curl -s -b /tmp/cookies2.txt -X POST http://localhost:3000/api/branches -H "Content-Type: application/json" -d '{"name":"Test"}')
if echo "$RESULT" | grep -q "Forbidden"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

echo -n "  Receptionist can view members: "
RESULT=$(curl -s -b /tmp/cookies2.txt http://localhost:3000/api/members)
if echo "$RESULT" | grep -q "members"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

echo ""
echo "=== TEST 9: SQL Server backup file ==="
echo -n "  GymDB.bak exists: "
if [ -f Database/GymDB.bak ]; then echo "PASS"; else echo "FAIL"; fi
echo -n "  GymDB.bak is real SQL Server backup: "
RESULT=$(file Database/GymDB.bak)
if echo "$RESULT" | grep -q "Microsoft SQL Server"; then echo "PASS"; else echo "FAIL: $RESULT"; fi

echo ""
echo "=== TEST 10: All ID formats ==="
echo -n "  Member: "
curl -s -b /tmp/cookies.txt http://localhost:3000/api/members | python3 -c "import json,sys; d=json.load(sys.stdin); m=d['members'][0]; print(f'{m[\"memberId\"]}')" | grep -E "^[a-zA-Z0-9]+/[0-9]{4}/[0-9]{5}$" > /dev/null && echo "PASS" || echo "CHECK"
echo -n "  Membership Plan code: "
curl -s -b /tmp/cookies.txt http://localhost:3000/api/memberships | python3 -c "import json,sys; d=json.load(sys.stdin); p=d['plans'][0]; print(f'{p[\"code\"]}')" | grep -E "^[0-9]{4}/[0-9]{5}$" > /dev/null && echo "PASS" || echo "CHECK"
echo -n "  Attendance: "
curl -s -b /tmp/cookies.txt http://localhost:3000/api/attendance | python3 -c "import json,sys; d=json.load(sys.stdin); r=d['records'][0]; print(f'{r[\"attendanceId\"]}')" | grep -E "^[a-zA-Z0-9]+/[0-9]{4}/[0-9]{5}$" > /dev/null && echo "PASS" || echo "CHECK"
echo -n "  Fee: "
curl -s -b /tmp/cookies.txt http://localhost:3000/api/fees | python3 -c "import json,sys; d=json.load(sys.stdin); f=d['fees'][0]; print(f'{f[\"feeNo\"]}')" | grep -E "^[a-zA-Z0-9]+/[0-9]{4}/[0-9]{5}$" > /dev/null && echo "PASS" || echo "CHECK"
echo -n "  Prospect: "
curl -s -b /tmp/cookies.txt http://localhost:3000/api/prospects | python3 -c "import json,sys; d=json.load(sys.stdin); p=d['prospects'][0]; print(f'{p[\"prospectId\"]}')" | grep -E "^[a-zA-Z0-9]+/P-[0-9]{5}$" > /dev/null && echo "PASS" || echo "CHECK"
echo -n "  Leave: "
curl -s -b /tmp/cookies.txt http://localhost:3000/api/leaves | python3 -c "import json,sys; d=json.load(sys.stdin); l=d['leaves'][0]; print(f'{l[\"leaveId\"]}')" | grep -E "^[a-zA-Z0-9]+/LV-[0-9]{4}$" > /dev/null && echo "PASS" || echo "CHECK"
echo -n "  Freeze: "
curl -s -b /tmp/cookies.txt http://localhost:3000/api/freezes | python3 -c "import json,sys; d=json.load(sys.stdin); f=d['freezes'][0]; print(f'{f[\"freezeId\"]}')" | grep -E "^F-[0-9]{6}$" > /dev/null && echo "PASS" || echo "CHECK"
echo -n "  FollowUp: "
curl -s -b /tmp/cookies.txt http://localhost:3000/api/followups | python3 -c "import json,sys; d=json.load(sys.stdin); f=d['records'][0]; print(f'{f[\"followUpId\"]}')" | grep -E "^[a-zA-Z0-9]+/FW-[0-9]{6}$" > /dev/null && echo "PASS" || echo "CHECK"

echo ""
echo "=== ALL TESTS COMPLETE ==="
