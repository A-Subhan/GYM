import { db } from '../src/lib/db'
import { hashPassword } from '../src/lib/hash'
import { PERMISSIONS, SYSTEM_ROLE_PERMISSIONS } from '../src/lib/permissions'

async function main() {
  console.log('Seeding database...')

  // 1. Permissions
  for (const p of PERMISSIONS) {
    await db.permission.upsert({
      where: { code: p.code },
      update: { module: p.module, action: p.action, description: (p as any).description ?? null },
      create: { code: p.code, module: p.module, action: p.action, description: (p as any).description ?? null },
    })
  }
  console.log(`  ✓ ${PERMISSIONS.length} permissions`)

  // 2. System Roles + RolePermissions
  for (const [roleName, permCodes] of Object.entries(SYSTEM_ROLE_PERMISSIONS)) {
    const role = await db.role.upsert({
      where: { name: roleName },
      update: { isSystem: true },
      create: { name: roleName, isSystem: true, description: `${roleName} role (system)` },
    })
    const perms = await db.permission.findMany({ where: { code: { in: permCodes as string[] } } })
    await db.rolePermission.deleteMany({ where: { roleId: role.id } })
    for (const p of perms) {
      await db.rolePermission.create({ data: { roleId: role.id, permissionId: p.id } })
    }
  }
  console.log(`  ✓ ${Object.keys(SYSTEM_ROLE_PERMISSIONS).length} system roles`)

  // 3. Company — name left unlocked so the Defaults page performs the one-time set + lock
  const company = await db.company.upsert({
    where: { companyId: 'CTR-01' },
    update: {},
    create: {
      companyId: 'CTR-01',
      name: '',
      nameLocked: false,
      address: 'Main Boulevard, Karachi',
      phone: '+92 21 0000000',
      email: 'info@contouragym.com',
      accountingType: 'FIFO',
    },
  })
  console.log(`  ✓ Company ${company.companyId}`)

  // 4. Branch (root Control node)
  const branch = await db.branch.upsert({
    where: { code: 'BR-001' },
    update: {},
    create: { code: 'BR-001', name: 'Head Office', nodeType: 'Control', city: 'Karachi', phone: '+92 21 0000000', email: 'hq@contouragym.com' },
  })
  console.log(`  ✓ Branch ${branch.code}`)

  // 5. Admin User
  const adminRole = await db.role.findUnique({ where: { name: 'Super Admin' } })
  if (!adminRole) throw new Error('Super Admin role missing')
  const existing = await db.user.findUnique({ where: { username: 'admin' } })
  if (!existing) {
    await db.user.create({
      data: {
        username: 'admin',
        fullName: 'System Administrator',
        email: 'admin@contouragym.com',
        passwordHash: hashPassword('admin123'),
        roleId: adminRole.id,
        branchId: branch.id,
        accessibleBranchIds: '*',
        isActive: true,
      },
    })
    console.log('  ✓ admin user created (password: admin123)')
  } else {
    await db.user.update({
      where: { id: existing.id },
      data: { passwordHash: hashPassword('admin123'), isActive: true, roleId: adminRole.id, accessibleBranchIds: '*' },
    })
    console.log('  ✓ admin user updated with verified hash')
  }

  // 6. COA root heads + detail accounts — table `charts`, id = account code
  const rootHeads = [
    { code: '01', name: 'Assets', accountType: 'Asset', isControl: true, isDetail: false },
    { code: '02', name: 'Liabilities', accountType: 'Liability', isControl: true, isDetail: false },
    { code: '03', name: 'Capital / Equity', accountType: 'Equity', isControl: true, isDetail: false },
    { code: '04', name: 'Revenue', accountType: 'Revenue', isControl: true, isDetail: false },
    { code: '05', name: 'Expense', accountType: 'Expense', isControl: true, isDetail: false },
  ]
  for (const h of rootHeads) {
    await db.chart.upsert({
      where: { id: h.code },
      update: {},
      create: { id: h.code, name: h.name, accountType: h.accountType, isControl: h.isControl, isDetail: h.isDetail, branchId: branch.id },
    })
  }
  const assets = await db.chart.findUnique({ where: { id: '01' } })
  if (assets) {
    const details = [
      { id: '01001', name: 'Cash in Hand', accountType: 'Asset', bookType: 'Cash', accountTag: 'Cash' },
      { id: '01002', name: 'Bank — Current A/C', accountType: 'Asset', bookType: 'Bank', accountTag: 'Bank', bankName: 'HBL', bankAccountNo: '0000000000000000' },
      { id: '01003', name: 'Membership Receivable', accountType: 'Asset', accountTag: 'Customer' },
      { id: '01004', name: 'Equipment Supplier', accountType: 'Asset', accountTag: 'Vendor', contactName: 'ABC Supplies', phone: '+92 21 9999999', paymentTerms: 'Net 30' },
    ]
    for (const d of details) {
      await db.chart.upsert({
        where: { id: d.id },
        update: {},
        create: { ...d, isControl: false, isDetail: true, parentId: assets.id, branchId: branch.id },
      })
    }
  }
  const rev = await db.chart.findUnique({ where: { id: '04' } })
  if (rev) {
    const details = [
      { id: '04001', name: 'Membership Fee Income', accountType: 'Revenue' },
      { id: '04002', name: 'POS Sales Income', accountType: 'Revenue' },
    ]
    for (const d of details) {
      await db.chart.upsert({
        where: { id: d.id },
        update: {},
        create: { ...d, isControl: false, isDetail: true, parentId: rev.id, branchId: branch.id },
      })
    }
  }
  const lia = await db.chart.findUnique({ where: { id: '02' } })
  if (lia) {
    await db.chart.upsert({
      where: { id: '02001' },
      update: {},
      create: { id: '02001', name: 'Sales Tax Payable', accountType: 'Liability', isControl: false, isDetail: true, parentId: lia.id, branchId: branch.id },
    })
  }
  console.log('  ✓ charts (COA) root heads + default detail accounts')

  // 7. Default Tax Heads
  for (const code of ['001', '002']) {
    const exists = await db.taxHead.findFirst({ where: { code, branchId: branch.id } })
    if (!exists) {
      await db.taxHead.create({
        data: {
          code,
          shortName: code === '001' ? 'ST-00' : 'ST-18',
          name: code === '001' ? 'Sales Tax 0%' : 'Sales Tax 18%',
          taxType: 'Sales',
          rate: code === '001' ? 0 : 18,
          branchId: branch.id,
          isActive: true,
        },
      })
    }
  }
  console.log('  ✓ default tax heads')

  // 8. Account Mappings (per-branch account mapping tab of Defaults)
  const cash = await db.chart.findUnique({ where: { id: '01001' } })
  const bank = await db.chart.findUnique({ where: { id: '01002' } })
  const feeIncome = await db.chart.findUnique({ where: { id: '04001' } })
  const posIncome = await db.chart.findUnique({ where: { id: '04002' } })
  const taxPayable = await db.chart.findUnique({ where: { id: '02001' } })
  const feeReceivable = await db.chart.findUnique({ where: { id: '01003' } })

  const mappings: Array<{ key: string; accountId?: string }> = []
  if (cash) mappings.push({ key: 'cashAccount', accountId: cash.id })
  if (bank) mappings.push({ key: 'bankAccount', accountId: bank.id })
  if (feeIncome) mappings.push({ key: 'feeIncome', accountId: feeIncome.id })
  if (posIncome) mappings.push({ key: 'posIncome', accountId: posIncome.id })
  if (taxPayable) mappings.push({ key: 'taxAccount', accountId: taxPayable.id })
  if (feeReceivable) mappings.push({ key: 'feeReceivable', accountId: feeReceivable.id })
  if (cash) mappings.push({ key: 'posCash', accountId: cash.id })
  if (bank) mappings.push({ key: 'posBank', accountId: bank.id })

  for (const m of mappings) {
    if (!m.accountId) continue
    const existing = await db.accountMapping.findFirst({ where: { key: m.key, branchId: null } })
    if (!existing) await db.accountMapping.create({ data: { key: m.key, accountId: m.accountId, branchId: null } })
    else await db.accountMapping.update({ where: { id: existing.id }, data: { accountId: m.accountId } })
  }
  console.log(`  ✓ ${mappings.length} account mappings`)

  // 9. Financial Year
  const year = await db.financialYear.upsert({
    where: { name: 'FY-2025' },
    update: {},
    create: { name: 'FY-2025', startDate: new Date('2025-01-01'), endDate: new Date('2025-12-31'), isActive: true },
  })
  for (let m = 0; m < 12; m++) {
    const start = new Date(2025, m, 1)
    const end = new Date(2025, m + 1, 0, 23, 59, 59)
    await db.accountingPeriod.upsert({
      where: { id: `${year.id}-${m+1}` },
      update: {},
      create: { id: `${year.id}-${m+1}`, financialYearId: year.id, name: `2025-${String(m+1).padStart(2, '0')}`, startDate: start, endDate: end },
    })
  }
  console.log('  ✓ financial year + periods')

  // 10. Default membership plans
  for (const [code, name, days, amount] of [
    ['MP-001', 'Monthly', 30, 3000],
    ['MP-002', 'Quarterly', 90, 8000],
    ['MP-003', 'Annual', 365, 30000],
  ] as const) {
    await db.membershipPlan.upsert({
      where: { code },
      update: {},
      create: { code, name, durationDays: days, amount, description: `${name} plan` },
    })
  }
  console.log('  ✓ default membership plans')

  // 11. Default shifts
  for (const [id, name, ti, to, days] of [
    ['shift-morning-default', 'Morning', '06:00', '14:00', 'Mon,Tue,Wed,Thu,Fri,Sat'],
    ['shift-evening-default', 'Evening', '14:00', '22:00', 'Mon,Tue,Wed,Thu,Fri,Sat'],
    ['shift-general-default', 'General', '09:00', '17:00', 'Mon,Tue,Wed,Thu,Fri'],
  ] as const) {
    await db.shift.upsert({
      where: { id },
      update: {},
      create: { id, name, timeIn: ti, timeOut: to, workingDays: days, branchId: branch.id },
    })
  }
  console.log('  ✓ default shifts')

  // 12. Leave types — LeaveType table removed; now MasterFile(masterType='LeaveType')
  for (const lt of [
    { name: 'Casual', allowedDays: 10, isPaid: true },
    { name: 'Sick', allowedDays: 10, isPaid: true },
    { name: 'Paid', allowedDays: 5, isPaid: true },
    { name: 'Unpaid', allowedDays: 0, isPaid: false },
  ]) {
    const extra = JSON.stringify(lt)
    await db.masterFile.upsert({
      where: { masterType_name: { masterType: 'LeaveType', name: lt.name } },
      update: { extra },
      create: { masterType: 'LeaveType', code: lt.name.toUpperCase().slice(0, 3), name: lt.name, extra, isActive: true },
    })
  }
  console.log('  ✓ leave types (master files)')

  // 13. Allowances
  for (const a of [
    { name: 'Fuel', description: 'Fuel allowance', isStatutory: false },
    { name: 'House Rent', description: 'House rent allowance', isStatutory: false },
    { name: 'SESSI', description: 'Sindh Employees Social Security Institution', isStatutory: true },
    { name: 'EOBI', description: 'Employees Old-Age Benefits Institution', isStatutory: true },
  ]) {
    await db.allowance.upsert({ where: { name: a.name }, update: {}, create: a })
  }
  console.log('  ✓ allowances')

  // 14. Default trainer staff
  const existingTrainer = await db.staff.findFirst({ where: { employeeId: 'EMP-0001' } })
  if (!existingTrainer) {
    await db.staff.create({
      data: {
        employeeId: 'EMP-0001',
        firstName: 'Imran',
        lastName: 'Khan',
        phone: '03001234567',
        email: 'imran@contouragym.com',
        joiningDate: new Date('2025-01-01'),
        department: 'Trainers',
        designation: 'Senior Trainer',
        isTrainer: true,
        branchId: branch.id,
        shiftId: 'shift-morning-default',
        basicSalary: 40000,
      },
    })
    console.log('  ✓ default trainer (EMP-0001)')
  }

  // 15. Payroll master file defaults (earnings / deductions heads)
  for (const p of [
    { code: 'PMF-001', name: 'Basic Salary', type: 'Earning', calcType: 'Fixed', amount: 0, isActive: true },
    { code: 'PMF-002', name: 'Fuel Allowance', type: 'Earning', calcType: 'Fixed', amount: 0, isActive: true },
    { code: 'PMF-003', name: 'House Rent Allowance', type: 'Earning', calcType: 'Fixed', amount: 0, isActive: true },
    { code: 'PMF-004', name: 'Overtime', type: 'Earning', calcType: 'Percent', amount: 0, isActive: true },
    { code: 'PMF-005', name: 'SESSI', type: 'Deduction', calcType: 'Percent', amount: 6, isActive: true },
    { code: 'PMF-006', name: 'EOBI', type: 'Deduction', calcType: 'Fixed', amount: 1000, isActive: true },
    { code: 'PMF-007', name: 'Advance Recovery', type: 'Deduction', calcType: 'Fixed', amount: 0, isActive: true },
  ]) {
    await db.payrollMasterFile.upsert({
      where: { code: p.code },
      update: {},
      create: p,
    })
  }
  console.log('  ✓ payroll master file defaults')

  console.log('\n✅ Seed complete. Login: admin / admin123')
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1) })

// 16. Universal Master Files defaults
async function seedMasterFiles() {
  const defaults: Record<string, string[]> = {
    Department: ['Management', 'Operations', 'Trainers', 'Reception', 'Housekeeping', 'Finance', 'Sales'],
    Designation: ['Manager', 'Trainer', 'Receptionist', 'Accountant', 'Cleaner', 'Salesperson'],
    Education: ['Matric', 'Intermediate', 'Bachelor', 'Master', 'Certification'],
    Currency: ['PKR', 'USD', 'EUR', 'GBP'],
    Equipment: ['Treadmill', 'Exercise Bike', 'Elliptical', 'Rowing Machine', 'Dumbbells', 'Bench Press', 'Squat Rack', 'Leg Press'],
    CardTypes: ['Credit Card', 'Debit Card'],
    Banks: ['HBL', 'UBL', 'MCB', 'Allied Bank', 'Bank Alfalah', 'Meezan Bank'],
  }
  for (const [type, names] of Object.entries(defaults)) {
    for (let i = 0; i < names.length; i++) {
      const code = String(i + 1).padStart(3, '0')
      const existing = await db.masterFile.findUnique({ where: { masterType_name: { masterType: type, name: names[i] } } })
      if (!existing) {
        await db.masterFile.create({ data: { masterType: type, code, name: names[i], isActive: true } })
      }
    }
  }
  console.log('  ✓ universal master file defaults')
}
await seedMasterFiles()

// 17. Trainer Specializations
async function seedTrainerSpecs() {
  const specs = ['Weight Loss', 'Muscle Building', 'Strength Training', 'Bodybuilding', 'Functional Training', 'Cardio', 'Cross Training', 'Other']
  for (const s of specs) {
    const existing = await db.masterFile.findUnique({ where: { masterType_name: { masterType: 'TrainerSpecializations', name: s } } })
    if (!existing) {
      const code = String(specs.indexOf(s) + 1).padStart(3, '0')
      await db.masterFile.create({ data: { masterType: 'TrainerSpecializations', code, name: s, isActive: true } })
    }
  }
  console.log('  ✓ trainer specializations')
}
await seedTrainerSpecs()

// 18. Food Items
async function seedFoodItems() {
  const foods = [
    { code: 'FOOD-0001', name: 'Chicken Breast', category: 'Protein', calories: 165, protein: 31, carbs: 0, fat: 3.6, servingSize: '100g', unit: 'g' },
    { code: 'FOOD-0002', name: 'Brown Rice', category: 'Carbs', calories: 216, protein: 5, carbs: 45, fat: 1.8, servingSize: '1 cup', unit: 'cup' },
    { code: 'FOOD-0003', name: 'Eggs', category: 'Protein', calories: 155, protein: 13, carbs: 1.1, fat: 11, servingSize: '2 eggs', unit: 'piece' },
    { code: 'FOOD-0004', name: 'Banana', category: 'Fruit', calories: 105, protein: 1.3, carbs: 27, fat: 0.4, servingSize: '1 medium', unit: 'piece' },
  ]
  for (const f of foods) {
    const existing = await db.foodItem.findUnique({ where: { code: f.code } })
    if (!existing) await db.foodItem.create({ data: f })
  }
  console.log('  ✓ food items')
}
await seedFoodItems()
