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

  // 3. Company (with fbr field now)
  const company = await db.company.upsert({
    where: { companyId: 'CTR-01' },
    update: {},
    create: {
      companyId: 'CTR-01',
      name: 'Contoura Gym',
      address: 'Main Boulevard, Karachi',
      phone: '+92 21 0000000',
      email: 'info@contouragym.com',
      accountingType: 'FIFO',
      strn: 'STRN-000000',
      ntn: 'NTN-000000',
      fbr: 'FBR-000000',
    },
  })
  console.log(`  ✓ Company ${company.companyId}`)

  // 4. Branch (Company hierarchy: Company → Control (Head Office) → Detail (Branches))
  // Create the Company-level branch
  const companyBranch = await db.branch.upsert({
    where: { code: 'CO-001' },
    update: {},
    create: { code: 'CO-001', name: 'Contoura Group', city: 'Karachi', phone: '+92 21 0000000', email: 'info@contouragroup.com', level: 'Company' },
  })
  // Create the Control-level (Head Office) branch
  const headOffice = await db.branch.upsert({
    where: { code: 'BR-001' },
    update: { level: 'Control', parentId: companyBranch.id, strn: 'STRN-HO', ntn: 'NTN-HO', fbr: 'FBR-HO' },
    create: {
      code: 'BR-001',
      name: 'Head Office',
      city: 'Karachi',
      phone: '+92 21 0000000',
      email: 'hq@contouragym.com',
      level: 'Control',
      parentId: companyBranch.id,
      strn: 'STRN-HO',
      ntn: 'NTN-HO',
      fbr: 'FBR-HO',
    },
  })
  console.log(`  ✓ Branch hierarchy: ${companyBranch.name} → ${headOffice.name}`)

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
        branchId: headOffice.id,
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

  // 6. COA root heads + detail accounts (now in Charts table)
  const rootHeads = [
    { code: '01', name: 'Assets', accountType: 'Asset', accountTag: 'Asset', bookType: 'General', isControl: true, isDetail: false },
    { code: '02', name: 'Liabilities', accountType: 'Liability', accountTag: 'Liability', bookType: 'General', isControl: true, isDetail: false },
    { code: '03', name: 'Capital / Equity', accountType: 'Equity', accountTag: 'Equity', bookType: 'General', isControl: true, isDetail: false },
    { code: '04', name: 'Revenue', accountType: 'Revenue', accountTag: 'Income', bookType: 'General', isControl: true, isDetail: false },
    { code: '05', name: 'Expense', accountType: 'Expense', accountTag: 'Expense', bookType: 'General', isControl: true, isDetail: false },
  ]
  for (const h of rootHeads) {
    const existing = await db.charts.findFirst({ where: { code: h.code, branchId: headOffice.id } })
    if (!existing) await db.charts.create({ data: { ...h, branchId: headOffice.id } })
  }
  const assets = await db.charts.findFirst({ where: { code: '01', branchId: headOffice.id } })
  if (assets) {
    let cashAcc = await db.charts.findFirst({ where: { code: '01001', branchId: headOffice.id } })
    if (!cashAcc) cashAcc = await db.charts.create({ data: { code: '01001', name: 'Cash in Hand', accountType: 'Asset', bookType: 'Cash', accountTag: 'Cash', isControl: false, isDetail: true, parentId: assets.id, branchId: headOffice.id } })
    let bankAcc = await db.charts.findFirst({ where: { code: '01002', branchId: headOffice.id } })
    if (!bankAcc) bankAcc = await db.charts.create({ data: { code: '01002', name: 'Bank — Current A/C', accountType: 'Asset', bookType: 'Bank', accountTag: 'Bank', isControl: false, isDetail: true, parentId: assets.id, bankName: 'HBL', bankAccountNo: '0000000000000000', branchId: headOffice.id } })
    let recvAcc = await db.charts.findFirst({ where: { code: '01003', branchId: headOffice.id } })
    if (!recvAcc) recvAcc = await db.charts.create({ data: { code: '01003', name: 'Membership Receivable', accountType: 'Asset', bookType: 'General', accountTag: 'Customer', isControl: false, isDetail: true, parentId: assets.id, branchId: headOffice.id } })
  }
  const rev = await db.charts.findFirst({ where: { code: '04', branchId: headOffice.id } })
  if (rev) {
    let feeInc = await db.charts.findFirst({ where: { code: '04001', branchId: headOffice.id } })
    if (!feeInc) feeInc = await db.charts.create({ data: { code: '04001', name: 'Membership Fee Income', accountType: 'Revenue', bookType: 'General', accountTag: 'Income', isControl: false, isDetail: true, parentId: rev.id, branchId: headOffice.id } })
    let posInc = await db.charts.findFirst({ where: { code: '04002', branchId: headOffice.id } })
    if (!posInc) posInc = await db.charts.create({ data: { code: '04002', name: 'POS Sales Income', accountType: 'Revenue', bookType: 'General', accountTag: 'Income', isControl: false, isDetail: true, parentId: rev.id, branchId: headOffice.id } })
  }
  const lia = await db.charts.findFirst({ where: { code: '02', branchId: headOffice.id } })
  if (lia) {
    let taxPay = await db.charts.findFirst({ where: { code: '02001', branchId: headOffice.id } })
    if (!taxPay) taxPay = await db.charts.create({ data: { code: '02001', name: 'Sales Tax Payable', accountType: 'Liability', bookType: 'General', accountTag: 'Tax', isControl: false, isDetail: true, parentId: lia.id, branchId: headOffice.id } })
  }
  console.log('  ✓ COA root heads + default detail accounts (Charts)')

  // 7. Default Tax Heads
  for (const code of ['001', '002']) {
    const exists = await db.taxHead.findFirst({ where: { code, branchId: headOffice.id } })
    if (!exists) {
      await db.taxHead.create({
        data: {
          code,
          shortName: code === '001' ? 'ST-00' : 'ST-18',
          name: code === '001' ? 'Sales Tax 0%' : 'Sales Tax 18%',
          taxType: 'Sales',
          rate: code === '001' ? 0 : 18,
          branchId: headOffice.id,
          isActive: true,
        },
      })
    }
  }
  console.log('  ✓ default tax heads')

  // 8. Account Mappings
  const cash = await db.charts.findFirst({ where: { code: '01001', branchId: headOffice.id } })
  const bank = await db.charts.findFirst({ where: { code: '01002', branchId: headOffice.id } })
  const feeIncome = await db.charts.findFirst({ where: { code: '04001', branchId: headOffice.id } })
  const posIncome = await db.charts.findFirst({ where: { code: '04002', branchId: headOffice.id } })
  const taxPayable = await db.charts.findFirst({ where: { code: '02001', branchId: headOffice.id } })
  const feeReceivable = await db.charts.findFirst({ where: { code: '01003', branchId: headOffice.id } })

  const mappings: Array<{ key: string; accountId: string; branchId?: string }> = []
  if (cash) mappings.push({ key: 'cashAccount', accountId: cash.id })
  if (bank) mappings.push({ key: 'bankAccount', accountId: bank.id })
  if (feeIncome) mappings.push({ key: 'feeIncome', accountId: feeIncome.id })
  if (posIncome) mappings.push({ key: 'posIncome', accountId: posIncome.id })
  if (taxPayable) mappings.push({ key: 'taxAccount', accountId: taxPayable.id })
  if (feeReceivable) mappings.push({ key: 'feeReceivable', accountId: feeReceivable.id })
  if (cash) mappings.push({ key: 'posCash', accountId: cash.id })
  if (bank) mappings.push({ key: 'posBank', accountId: bank.id })

  for (const m of mappings) {
    const existing = m.branchId
      ? await db.accountMapping.findUnique({ where: { branchId_key: { branchId: m.branchId, key: m.key } } })
      : await db.accountMapping.findFirst({ where: { key: m.key, branchId: null } })
    if (!existing) await db.accountMapping.create({ data: { key: m.key, accountId: m.accountId, branchId: m.branchId ?? null } })
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

  // 10. Finance Defaults (FIFO type, COA level detailing 3, not locked yet)
  const existingDefaults = await db.financeDefaults.findFirst()
  if (!existingDefaults) {
    await db.financeDefaults.create({
      data: {
        financeType: 'FIFO',
        coaLevelDetailing: 3,
        coaLevelLocked: false,
      },
    })
  }
  console.log('  ✓ finance defaults')

  // 11. Default membership plans (new code format: MonthYear/00001)
  for (const [code, name, days, amount] of [
    ['2509/00001', 'Monthly', 30, 3000],
    ['2509/00002', 'Quarterly', 90, 8000],
    ['2509/00003', 'Annual', 365, 30000],
  ] as const) {
    await db.membershipPlan.upsert({
      where: { code },
      update: {},
      create: { code, name, durationDays: days, amount, description: `${name} plan` },
    })
  }
  console.log('  ✓ default membership plans')

  // 12. Default shifts
  for (const [id, name, ti, to, days] of [
    ['shift-morning-default', 'Morning', '06:00', '14:00', 'Mon,Tue,Wed,Thu,Fri,Sat'],
    ['shift-evening-default', 'Evening', '14:00', '22:00', 'Mon,Tue,Wed,Thu,Fri,Sat'],
    ['shift-general-default', 'General', '09:00', '17:00', 'Mon,Tue,Wed,Thu,Fri'],
  ] as const) {
    await db.shift.upsert({
      where: { id },
      update: {},
      create: { id, name, timeIn: ti, timeOut: to, workingDays: days, branchId: headOffice.id },
    })
  }
  console.log('  ✓ default shifts')

  // 13. Leave Types via PayrollMasterFile (NOT separate LeaveType table)
  for (const lt of [
    { name: 'Casual', code: '001' },
    { name: 'Sick', code: '002' },
    { name: 'Paid', code: '003' },
    { name: 'Unpaid', code: '004' },
  ]) {
    const exists = await db.payrollMasterFile.findUnique({ where: { masterType_code: { masterType: 'LeaveType', code: lt.code } } })
    if (!exists) {
      await db.payrollMasterFile.create({
        data: { masterType: 'LeaveType', code: lt.code, name: lt.name, description: `${lt.name} leave`, isActive: true },
      })
    }
  }
  console.log('  ✓ leave types (PayrollMasterFile)')

  // 14. Allowances
  for (const a of [
    { name: 'Fuel', description: 'Fuel allowance', isStatutory: false },
    { name: 'House Rent', description: 'House rent allowance', isStatutory: false },
    { name: 'SESSI', description: 'Sindh Employees Social Security Institution', isStatutory: true },
    { name: 'EOBI', description: 'Employees Old-Age Benefits Institution', isStatutory: true },
  ]) {
    await db.allowance.upsert({ where: { name: a.name }, update: {}, create: a })
  }
  console.log('  ✓ allowances')

  console.log('\n✅ Seed complete. Login: admin / admin123')
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1) })
