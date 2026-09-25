# API Reference

Base URL: `/api/v1`

All responses use this envelope:

```json
{
  "success": true,
  "data": { ... },
  "message": "OK",
  "meta": { "page": 1, "pageSize": 20, "total": 142, "totalPages": 8 }
}
```

Error responses:

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Validation failed",
    "details": [{ "field": "FullName", "message": "...is required" }]
  }
}
```

**Authentication**: All routes (except `POST /auth/login`, `POST /auth/refresh`) require an `Authorization: Bearer <accessToken>` header.

---

## Auth

### POST /auth/login
Public. Returns access + refresh tokens, user object, and permission codes.

**Body:**
```json
{ "username": "contouralabs", "password": "Contoura@2024", "location": "24.86,67.00" }
```

**Response:**
```json
{
  "success": true,
  "data": {
    "accessToken": "eyJhbGc...",
    "refreshToken": "eyJhbGc...",
    "user": {
      "userId": 1, "username": "contouralabs", "fullName": "Contoura Labs Super Admin",
      "email": "contouralabs@gmail.com", "roleId": 1, "roleName": "Super Admin",
      "branchId": null, "isSuperAdmin": true, "lastLoginAt": "2024-..."
    },
    "permissions": ["dashboard.view", "members.view", "members.add", ...]
  },
  "message": "Login successful"
}
```

### POST /auth/logout
Body: `{ "refreshToken": "..." }`. Invalidates the refresh token in `UserSessions`.

### POST /auth/refresh
Body: `{ "refreshToken": "..." }`. Returns a new `accessToken`.

### POST /auth/change-password
**Auth required.** Body: `{ "currentPassword": "...", "newPassword": "..." }`. Min 8 chars.

### GET /auth/me
Returns the current authenticated user (from JWT).

### GET /auth/my-sessions
Returns the list of login sessions for the current user (IP, user agent, login time, status).

---

## Users & Roles

### GET /users?page=1&pageSize=20&search=&RoleID=&BranchID=
Permission: `users.view`. Branch scoping applies (non-super-admins see only their branch).

### GET /users/:id
Permission: `users.view`.

### POST /users
Permission: `users.add`.
```json
{
  "Username": "new.user", "Email": "user@example.com", "FullName": "New User",
  "Password": "StrongPass1!", "RoleID": 4, "BranchID": 1, "Phone": "+92 300 ..."
}
```

### PUT /users/:id
Permission: `users.edit`. Same fields as POST (without Password).

### DELETE /users/:id
Permission: `users.delete`. Soft-delete. Cannot delete self or super admin.

### GET /users/meta/roles
Returns the 7 system roles.

### GET /users/meta/permissions
Returns all permission codes.

### GET /users/meta/roles/:roleId/permissions
Returns the permissions granted to a role.

### PUT /users/meta/roles/:roleId/permissions
Permission: `users.edit`. Body: `{ "permissionIds": [1, 2, 3, ...] }`.

---

## Branches

### GET /branches?isActive=true
Permission: `branches.view`.

### GET /branches/:id
### POST /branches  (permission: `branches.add`)
```json
{ "Code": "DHA", "Name": "DHA Branch", "Address": "...", "City": "Lahore", "Phone": "...", "Email": "...", "ManagerName": "..." }
```
### PUT /branches/:id  (permission: `branches.edit`)
### DELETE /branches/:id  (permission: `branches.delete`) — soft-delete

---

## Settings

### GET /settings
Returns `{ items: [...], map: { GymName: "...", Currency: "PKR", ... } }`.

### GET /settings/:category
Returns settings filtered by category (general / finance / receipt / theme / backup).

### PUT /settings  (permission: `settings.edit`)
Body: `{ "key": "GymName", "value": "My Gym", "category": "general" }`.

### PUT /settings/bulk  (permission: `settings.edit`)
Body: `{ "items": [{ "key": "...", "value": "...", "category": "..." }] }`.

---

## Dashboard

### GET /dashboard/stats
Returns 13 KPIs in one call: `TotalMembers`, `ActiveMembers`, `ExpiredMembers`, `NewMembers`, `TodayAttendance`, `MonthlyIncome`, `MonthlyExpenses`, `PendingFees`, `SalaryDue`, `RentDue`, `EquipmentUnderMaintenance`, `MembershipExpiryAlerts`.

Branch scoping applies.

### GET /dashboard/charts?months=6
Returns 4 chart series:
- `revenue` — per month
- `expenses` — per month
- `attendance` — last 14 days
- `membershipGrowth` — cumulative per month

---

## Members

### GET /members?page=1&pageSize=15&search=&Status=&TrainerID=&BranchID=
Permission: `members.view`. Branch scoping applies.

Returns member list with: Code, FullName, Mobile, TrainerName, MembershipEndDate, Status.

### GET /members/:id
Returns single member details.

### GET /members/:id/profile
Returns full profile: `{ member, payments, attendance, memberships, progress }`.

### GET /members/:id/payments
### GET /members/:id/attendance?fromDate=&toDate=
### GET /members/:id/memberships
### GET /members/:id/progress

### POST /members  (permission: `members.add`)
```json
{
  "BranchID": 1, "FullName": "John Doe", "FatherName": "...", "Gender": "Male",
  "DOB": "1995-04-12", "CNIC": "...", "Mobile": "...", "WhatsApp": "...",
  "Email": "...", "Address": "...", "EmergencyContact": "...",
  "JoiningDate": "2024-01-01", "TrainerID": 1,
  "HeightFeet": 5, "HeightInches": 9, "Weight": 82.0, "MedicalNotes": "", "Status": "Active"
}
```
Returns `{ MemberID, Code }`.

### PUT /members/:id  (permission: `members.edit`)
### DELETE /members/:id  (permission: `members.delete`)

---

## Memberships

### Plans

#### GET /memberships/plans?isActive=true
#### POST /memberships/plans  (permission: `memberships.add`)
```json
{ "Name": "Monthly", "DurationMonths": 1, "Price": 3000, "JoiningFee": 500, "Discount": 0, "Description": "..." }
```
#### PUT /memberships/plans/:id  (permission: `memberships.edit`)
#### DELETE /memberships/plans/:id  (permission: `memberships.delete`)

### Active Member Memberships

The standalone Active Memberships page and its management endpoints
(`GET/POST /memberships/active`, renew/freeze/cancel) were removed.

A membership plan is now assigned when a **member is created**:
`POST /members` accepts an optional `MembershipPlanID` field, which creates
the `MemberMemberships` row (see `sp_MemberMemberships_Create`).
`MemberMemberships` data is still surfaced on the member profile
(`GET /members/:id/memberships`) and dashboard expiry alerts.

---

## Staff

The former standalone Trainers module was merged into Staff: a staff row
whose **Designation** contains "trainer" (e.g. Trainer / Senior Trainer,
picked from the Designations master) is treated as a trainer everywhere in
the software — the `Trainers` tag row is maintained automatically.

Every staff member also gets an auto-generated **StaffCode** in the form
`<BranchID>/0001` (sequence per branch).

### GET /staff?page=1&pageSize=20&search=&DepartmentID=&Status=&IsTrainer=
Permission: `staff.view`. Rows include `StaffCode`, `IsTrainer`, `TrainerID`,
`Specialization`, `Experience` and `AssignedMembers`.

Designations for the Staff form now come from the Master Files module (see below).

### GET /staff/trainers
Permission: any of `staff.view`, `members.view`, `workouts.view`, `diet.view`.
Lists staff currently tagged as trainer (used by the member / workout / diet
trainer dropdowns).

### GET /staff/departments

### GET /staff/:id

### POST /staff  (permission: `staff.add`)
```json
{ "BranchID": 1, "DepartmentID": 2, "FullName": "Bilal Ahmed", "JoiningDate": "2024-01-01",
  "Designation": "Trainer", "BaseSalary": 50000, "Status": "Active",
  "Specialization": "Strength & Conditioning", "Experience": "5 years" }
```
Limits: FullName/FatherName ≤ 50, Address ≤ 200, Designation ≤ 30, BaseSalary ≤ 9999999.
A `StaffCode` (`<BranchID>/0001`) is generated automatically.

### PUT /staff/:id  (permission: `staff.edit`)
Same fields. Trainer status follows the designation: moving a staff away from
a trainer designation removes the trainer tag and unassigns their members.

### DELETE /staff/:id  (permission: `staff.delete`)
Soft delete; also removes the trainer tag.

### Attendance & leaves
```
GET  /staff/attendance/all?staffId=&fromDate=&toDate=
POST /staff/attendance           { StaffID, Date, CheckIn, CheckOut, Status, Notes }
GET  /staff/leaves/all?staffId=&status=
POST /staff/leaves               { StaffID, LeaveType, StartDate, EndDate, Reason }
PUT  /staff/leaves/:id/status    { Status: "Approved" | "Rejected" }
```

---

## Master Files

Metadata-driven master data (Designation 01, Education 02, Currency 03, …
admins can add more without new screens). Item codes are generated as
`<MasterCode><0001>` (e.g. `010001`) inside a DB transaction — concurrency
safe. Permissions: `masters.view` / `masters.add` / `masters.edit` /
`masters.delete` / `masters.status` (activate/deactivate).

### GET /masters/definitions
All master file definitions with `MasterCode`, `Name`, `Scope`
(`Global` | `Branch`) and `ItemCount`.

### POST /masters/definitions  (permission: `masters.add`)
```json
{ "Name": "Color", "MasterCode": "04", "Scope": "Global" }
```
`MasterCode` is optional — auto-generated when omitted.

### PUT /masters/definitions/:id  (permission: `masters.edit`)
### DELETE /masters/definitions/:id  (permission: `masters.delete`)
Only allowed when the definition has no records.

### GET /masters/:definitionId/items?page=&pageSize=&search=&status=&BranchID=
Paginated grid rows (`ItemCode`, `Name`, `IsActive`, `BranchName?`).
Branch-scope masters are filtered to the caller's branch unless a super
admin passes `?BranchID=`. `status=active|inactive`.

### POST /masters/:definitionId/items  (permission: `masters.add`)
```json
{ "Name": "Bachelor", "BranchID": 2 }
```
`BranchID` is required for Branch-scope masters (forced to the caller's
branch for non-super-admins). The `ItemCode` is generated server-side.

### PUT /masters/items/:id  (permission: `masters.edit`)  `{ "Name": "..." }`
### PATCH /masters/items/:id/status  (permission: `masters.status`)  `{ "IsActive": false }`
Inactive records stay in the DB, disappear from selection dropdowns and keep
showing on records that already reference them.

### DELETE /masters/items/:id  (permission: `masters.delete`)
Referential integrity is enforced in the database: an item still referenced
anywhere (e.g. a Staff row using that Designation) returns
`409 DELETE_BLOCKED` — *"X cannot be deleted because it is currently
assigned to one or more staff records."*

---

## Attendance

### GET /attendance?page=1&pageSize=50&memberId=&date=&fromDate=&toDate=&branchId=
Permission: `attendance.view`.

### GET /attendance/today/count

### POST /attendance/check-in  (permission: `attendance.add`)
The member is validated first — an unknown `memberId` returns
`404 { code: "NOT_FOUND", message: "Member not found. Please select a valid member." }`
instead of a raw foreign-key error.
```json
{ "memberId": 1, "method": "Manual" }
```
`method` can be: `Manual`, `QR`, `Barcode`, `RFID`, `Biometric`.

### POST /attendance/check-out/:id  (permission: `attendance.edit`)
Sets `CheckOutTime` on an open attendance record.

---

## Fees

### GET /fees/payment-methods
Returns: Cash, Bank, Card, JazzCash, EasyPaisa.

### Invoices

#### GET /fees/invoices?page=1&pageSize=20&memberId=&status=&fromDate=&toDate=
#### POST /fees/invoices  (permission: `fees.add`)
```json
{
  "MemberID": 1, "MemberMembershipID": 1,
  "TotalAmount": 28000, "Discount": 0, "LateFee": 0, "Tax": 0,
  "DueDate": "2024-01-17", "Notes": "..."
}
```
Returns `{ InvoiceID, InvoiceNo, NetAmount }`.

### Fee Collections

#### GET /fees/collections?page=1&pageSize=20&memberId=&methodId=&fromDate=&toDate=
#### POST /fees/collections  (permission: `fees.add`)
```json
{
  "MemberID": 1, "InvoiceID": 1,
  "Amount": 28000, "MethodID": 1,
  "TransactionRef": "TR-12345",
  "BranchID": 1, "Notes": "..."
}
```
Updates the linked invoice's `PaidAmount` and `Status` (Unpaid → Partial → Paid).

---

## Finance

### Expenses

#### GET /finance/expenses?page=1&pageSize=50&category=&fromDate=&toDate=
#### POST /finance/expenses  (permission: `finance.add`)
```json
{ "BranchID": 1, "Category": "Rent", "Amount": 150000, "ExpenseDate": "2024-07-01", "Notes": "Monthly rent" }
```
`Category` must be one of: `Salary`, `Rent`, `Electricity`, `Internet`, `Water`, `Maintenance`, `Misc`.

### Income

#### GET /finance/income?page=1&pageSize=50&categoryId=&fromDate=&toDate=
#### POST /finance/income  (permission: `finance.add`)
```json
{ "BranchID": 1, "CategoryID": 2, "Source": "Personal training", "Amount": 5000, "IncomeDate": "2024-08-15", "Notes": "..." }
```

### GET /finance/income-categories
Returns: Membership, Personal Training, Product Sales, Miscellaneous.

---

## Audit Logs

### GET /audit-logs?page=1&pageSize=50&userId=&module=&action=&fromDate=&toDate=
Permission: `audit.view`.

Returns entries with: `UserID`, `UserName`, `Action`, `Module`, `EntityID`, `Details` (JSON), `IPAddress`, `Location`, `CreatedAt`.

---

## Permission Codes

Each module has these actions: `view`, `add`, `edit`, `delete`, `print`, `export` (some have only `view`).

Examples:
- `dashboard.view`
- `members.view`, `members.add`, `members.edit`, `members.delete`, `members.print`, `members.export`
- `fees.view`, `fees.add`, `fees.edit`, `fees.delete`, `fees.print`, `fees.export`
- `settings.view`, `settings.edit`
- `audit.view`, `audit.export`

**Super Admin** (RoleID=1) bypasses all permission checks.

---

## Rate Limits

- `POST /auth/login`: 30 attempts / 15 minutes / IP
- All other `/api/v1/*` routes: 200 requests / minute / IP

Returns 429 with `{ "error": { "code": "RATE_LIMITED", "message": "..." } }` when exceeded.

---

## HTTP Status Codes

| Code | Meaning |
|---|---|
| 200 | Success |
| 201 | Created |
| 400 | Bad request |
| 401 | Not authenticated (token missing/invalid) |
| 403 | Forbidden (lacks permission) |
| 404 | Not found |
| 409 | Duplicate / conflict |
| 422 | Validation error (see details array) |
| 429 | Rate limited |
| 500 | Server error |
