# Role-Based Access Control (RBAC)

This document describes the role-permission matrix for the Contoura Labs Gym Management System.

---

## Roles

7 system roles ship with the database:

| ID | Name | Description | System? |
|---|---|---|---|
| 1 | Super Admin | Full system access. Bypasses all permission checks. Cannot be deleted. | ✓ |
| 2 | Owner | Branch owner. Full operational access except system-level settings. | ✓ |
| 3 | Manager | Day-to-day operations management. | ✓ |
| 4 | Receptionist | Front desk — members, attendance, fee collection. | ✓ |
| 5 | Trainer | Member workouts, diet plans, progress tracking. | ✓ |
| 6 | Accountant | Finance, payroll, expenses, reports. | ✓ |
| 7 | Staff | General staff — limited view-only access. | ✓ |

---

## Permissions

79 permission codes organized by module + action.

**Modules**: dashboard, members, memberships, attendance, fees, finance, payroll, staff, masters, workouts, diet, progress, equipment, inventory, reports, branches, settings, users, audit. (The former `trainers` module was merged into `staff` — see `sql/08_phase9_changes.sql`. The `masters` module powers the Master Files screen — see `sql/10_master_files_module.sql`.)

**Actions**: view, add, edit, delete, print, export (varies per module).

Permission codes follow the format `<module>.<action>`, e.g. `members.add`, `fees.print`, `audit.view`.

---

## Default Role-Permission Matrix

### Super Admin (RoleID=1)
**All 78 permissions.** Bypasses all checks in code.

### Owner (RoleID=2)
All permissions **except**:
- `branches.add`, `branches.edit`, `branches.delete` (can only view branches)
- `users.delete`
- `audit.export`

### Manager (RoleID=3)
All permissions **except**:
- `branches.add`, `branches.edit`, `branches.delete`
- `settings.view`, `settings.edit`
- `users.delete`
- `audit.export`

### Receptionist (RoleID=4)
| Module | Permissions |
|---|---|
| Dashboard | view |
| Members | view, add, edit, delete, print, export |
| Memberships | view, add, edit, export |
| Attendance | view, add, edit, delete, export |
| Fees | view, add, edit, print, export |
| Staff | view |
| Masters | view |
| Progress | view, add, edit |
| Reports | view, print |

### Trainer (RoleID=5)
| Module | Permissions |
|---|---|
| Dashboard | view |
| Members | view, add, edit, print, export |
| Attendance | view, add |
| Staff | view |
| Masters | view |
| Workouts | view, add, edit, delete |
| Diet | view, add, edit, delete |
| Progress | view, add, edit, delete |

### Accountant (RoleID=6)
| Module | Permissions |
|---|---|
| Dashboard | view |
| Members | view |
| Fees | view, add, edit, delete, print, export |
| Finance | view, add, edit, delete, export |
| Payroll | view, add, edit, print, export |
| Staff | view |
| Reports | view, print, export |

### Staff (RoleID=7)
| Module | Permissions |
|---|---|
| Dashboard | view |
| Members | view |
| Attendance | view |

---

## Customizing Permissions

Permissions can be edited per role via:

### UI
Settings → Users & Roles → click a role → toggle permissions in the matrix.

### API
```
PUT /api/v1/users/meta/roles/:roleId/permissions
Body: { "permissionIds": [1, 2, 3, ...] }
```

This replaces all permissions for the role with the provided list.

### SQL
```sql
-- Grant a single permission to a role
INSERT INTO RolePermissions (RoleID, PermissionID)
SELECT 3, PermissionID FROM Permissions WHERE Code = 'inventory.add';

-- Revoke a permission
DELETE FROM RolePermissions
WHERE RoleID = 3
  AND PermissionID = (SELECT PermissionID FROM Permissions WHERE Code = 'inventory.add');

-- Replace all permissions for role 3
EXEC sp_RolePermissions_Set @RoleID = 3, @PermissionIDs = '1,2,3,4,5';
```

---

## How RBAC Works in Code

### Backend

Every protected route uses the `verifyJWT` middleware, which loads the user's role + permissions from the DB and attaches them to `req.user`:

```js
req.user = {
  userId, username, fullName, email, roleId, roleName, branchId,
  isSuperAdmin: roleId === 1,
  permissions: ['dashboard.view', 'members.add', ...],
};
```

Then the `requirePermission(code)` middleware checks if the user has the required permission:

```js
router.post('/', verifyJWT, requirePermission('members.add'), audit('CREATE', 'members'), controller);
```

**Super Admin bypass**: `requirePermission` returns `next()` immediately if `req.user.isSuperAdmin` is true.

### Frontend

The `useAuth().hasPermission(code)` helper checks permissions client-side:

```jsx
import Can from '../components/common/Can';
import { PERMISSIONS } from '../constants/permissions';

<Can perm={PERMISSIONS.MEMBERS_ADD}>
  <Button>+ Add Member</Button>
</Can>
```

The sidebar uses the same check to show/hide nav items per role.

---

## Branch Scoping

In addition to role-based permissions, **non-super-admin users are scoped to their own branch**. This is enforced in the backend service layer:

- A receptionist at Branch A cannot see Branch B's members, attendance, or fees.
- A manager at Branch A cannot edit Branch B's staff.
- Only Super Admin can view data across all branches (or filter by a specific branch via `?branchId=`).

This applies to: members, attendance, fees, expenses, income, dashboard stats, dashboard charts.

---

## Audit Logging

Every protected write action (CREATE/UPDATE/DELETE) goes through the `audit(action, module)` middleware, which writes to the `AuditLogs` table after the controller successfully completes:

- **Action**: LOGIN, LOGOUT, LOGIN_FAILED, CREATE, UPDATE, DELETE, SETTINGS_CHANGE, PRINT, EXPORT
- **Module**: the affected module (members, fees, settings, etc.)
- **EntityID**: the affected record's ID
- **Details**: JSON with before/after values (where applicable)
- **IPAddress**: from request headers or socket
- **Location**: from request body (browser geolocation) — optional
- **CreatedAt**: timestamp

Super Admin can view audit logs via `/audit-logs`. Owners can view but not export (per the matrix above).
