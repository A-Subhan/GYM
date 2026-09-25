/* End-to-end test for the Master Files module (run: node scripts/test-master-files.js) */
const BASE = process.env.BASE || 'http://localhost:4100/api/v1';

async function req(method, path, { token, body } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch { /* ignore */ }
  return { status: res.status, json };
}

const results = [];
function check(name, cond, extra = '') {
  results.push({ name, pass: !!cond, extra });
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${extra ? '  — ' + extra : ''}`);
}

async function login(username, password) {
  const r = await req('POST', '/auth/login', { body: { username, password } });
  return r.json?.data?.accessToken || null;
}

(async () => {
  const sa = await login('contouralabs', 'contouralabs123');
  check('super admin login', sa);

  /* 1. definitions list */
  let r = await req('GET', '/masters/definitions', { token: sa });
  check('GET definitions', r.status === 200 && Array.isArray(r.json.data) && r.json.data.length >= 3,
    r.json?.data?.map(d => `${d.MasterCode}:${d.Name}`).join(','));

  const desig = r.json.data.find(d => d.Name === 'Designation');
  check('Designation definition exists (code 01)', desig && desig.MasterCode === '01');

  /* 2. items grid */
  r = await req('GET', `/masters/${desig.MasterDefinitionID}/items?page=1&pageSize=5`, { token: sa });
  check('GET items paginated', r.status === 200 && r.json.meta.total >= 6,
    r.json.data.map(i => i.ItemCode).join(','));
  const firstCode = r.json.data[0].ItemCode;
  check('item codes use master prefix', /^01\d{4}$/.test(firstCode), firstCode);

  /* 3. add item — auto code */
  r = await req('POST', `/masters/${desig.MasterDefinitionID}/items`, { token: sa, body: { Name: 'QA Tester' } });
  check('POST item auto-generates code', r.status === 201 && /^01\d{4}$/.test(r.json.data.ItemCode), r.json.data?.ItemCode);
  const itemId = r.json.data.MasterItemID;

  /* 4. duplicate name (case/trim insensitive) */
  r = await req('POST', `/masters/${desig.MasterDefinitionID}/items`, { token: sa, body: { Name: '  qa tester  ' } });
  check('duplicate name rejected 409', r.status === 409, r.json?.error?.message);

  /* 5. rename + status */
  r = await req('PUT', `/masters/items/${itemId}`, { token: sa, body: { Name: 'QA Tester Renamed' } });
  check('PUT item rename', r.status === 200);
  r = await req('PATCH', `/masters/items/${itemId}/status`, { token: sa, body: { IsActive: false } });
  check('PATCH status inactive', r.status === 200);
  r = await req('GET', `/masters/${desig.MasterDefinitionID}/items?status=inactive`, { token: sa });
  check('inactive filter shows it', r.json.data.some(i => i.MasterItemID === itemId));
  r = await req('GET', `/masters/${desig.MasterDefinitionID}/items?status=active`, { token: sa });
  check('active filter hides it', !r.json.data.some(i => i.MasterItemID === itemId));

  /* 6. delete unreferenced */
  r = await req('DELETE', `/masters/items/${itemId}`, { token: sa });
  check('DELETE unreferenced item', r.status === 200);

  /* 7. delete protection — 'Trainer' is assigned to Usman Tariq */
  r = await req('GET', `/masters/${desig.MasterDefinitionID}/items?search=Trainer`, { token: sa });
  const trainer = r.json.data.find(i => i.Name === 'Trainer');
  r = await req('DELETE', `/masters/items/${trainer.MasterItemID}`, { token: sa });
  check('DELETE referenced item blocked 409', r.status === 409 && r.json.error.code === 'DELETE_BLOCKED',
    r.json?.error?.message);
  /* regression: the row must still exist after the blocked delete */
  r = await req('GET', `/masters/${desig.MasterDefinitionID}/items?search=Trainer`, { token: sa });
  check('referenced item still exists after blocked delete', r.json.data.some(i => i.MasterItemID === trainer.MasterItemID && i.Name === 'Trainer'));

  /* 8. search */
  r = await req('GET', `/masters/${desig.MasterDefinitionID}/items?search=${encodeURIComponent('Sweeper')}`, { token: sa });
  check('search by name', r.json.data.length === 1 && r.json.data[0].Name === 'Sweeper');

  /* 9. new definition (Manage Master Files) */
  r = await req('POST', '/masters/definitions', { token: sa, body: { Name: 'Color', MasterCode: '04', Scope: 'Global' } });
  check('POST definition with explicit code', r.status === 201 && r.json.data.MasterCode === '04', r.json.data?.MasterCode);
  const colorId = r.json.data.MasterDefinitionID;

  r = await req('POST', '/masters/definitions', { token: sa, body: { Name: 'Color' } });
  check('duplicate definition name 409', r.status === 409);
  r = await req('POST', '/masters/definitions', { token: sa, body: { Name: 'SizeX', MasterCode: '04' } });
  check('duplicate definition code 409', r.status === 409);

  r = await req('POST', `/masters/${colorId}/items`, { token: sa, body: { Name: 'Red' } });
  check('Color item code 040001', r.json.data?.ItemCode === '040001', r.json.data?.ItemCode);
  r = await req('POST', `/masters/${colorId}/items`, { token: sa, body: { Name: 'Blue' } });
  check('Color item code 040002', r.json.data?.ItemCode === '040002', r.json.data?.ItemCode);
  const redId = (await req('GET', `/masters/${colorId}/items?search=Red`, { token: sa })).json.data[0].MasterItemID;

  r = await req('DELETE', `/masters/definitions/${colorId}`, { token: sa });
  check('definition with items cannot be deleted', r.status === 409, r.json?.error?.message);

  /* 10. branch scope */
  r = await req('POST', '/masters/definitions', { token: sa, body: { Name: 'Shift', Scope: 'Branch' } });
  check('branch-scope definition auto code 05', r.status === 201 && r.json.data.MasterCode === '05', r.json.data?.MasterCode);
  const shiftId = r.json.data.MasterDefinitionID;

  r = await req('POST', `/masters/${shiftId}/items`, { token: sa, body: { Name: 'Morning' } });
  check('branch item without branch rejected 400', r.status === 400, r.json?.error?.message);
  r = await req('POST', `/masters/${shiftId}/items`, { token: sa, body: { Name: 'Morning', BranchID: 1 } });
  check('branch item created for branch 1', r.status === 201 && r.json.data.ItemCode.startsWith('05'), r.json.data?.ItemCode);
  const shiftItemId = r.json.data.MasterItemID;

  /* same name allowed in another branch (different branch scope) */
  r = await req('POST', `/masters/${shiftId}/items`, { token: sa, body: { Name: 'Morning', BranchID: 2 } });
  check('same name OK in another branch', r.status === 201, r.json.data?.ItemCode);
  const shiftItem2 = r.json.data.MasterItemID;

  /* branch filtering for super admin */
  r = await req('GET', `/masters/${shiftId}/items`, { token: sa });
  check('super admin sees all branches', r.json.data.length === 2);
  r = await req('GET', `/masters/${shiftId}/items?BranchID=2`, { token: sa });
  check('super admin branch filter', r.json.data.length === 1 && r.json.data[0].BranchID === 2);

  /* branch filtering for branch user (receptionist, branch 1) */
  const recep = await login('reception.ali', 'reception.ali123');
  check('receptionist login', !!recep);
  r = await req('GET', `/masters/${shiftId}/items`, { token: recep });
  check('branch user sees only own branch', r.status === 200 && r.json.data.length === 1 && r.json.data[0].BranchID === 1,
    `got ${r.json.data.length} rows`);

  /* receptionist has masters.view only — write operations must 403 */
  r = await req('POST', `/masters/${desig.MasterDefinitionID}/items`, { token: recep, body: { Name: 'Nope' } });
  check('receptionist add blocked 403', r.status === 403, r.json?.error?.code);
  r = await req('PATCH', `/masters/items/${shiftItemId}/status`, { token: recep, body: { IsActive: false } });
  check('receptionist status blocked 403', r.status === 403, r.json?.error?.code);
  r = await req('DELETE', `/masters/items/${shiftItemId}`, { token: recep });
  check('receptionist delete blocked 403', r.status === 403, r.json?.error?.code);

  /* manager: add/edit/status allowed, delete not */
  const mgr = await login('manager.sana', 'manager.sana123');
  check('manager login', !!mgr);
  r = await req('POST', `/masters/${shiftId}/items`, { token: mgr, body: { Name: 'Evening', BranchID: 2 } });
  check('manager can add', r.status === 201, r.json.data?.ItemCode);
  const eveId = r.json.data?.MasterItemID;
  r = await req('PUT', `/masters/items/${eveId}`, { token: mgr, body: { Name: 'Evening Shift' } });
  check('manager can edit', r.status === 200);
  r = await req('PATCH', `/masters/items/${eveId}/status`, { token: mgr, body: { IsActive: false } });
  check('manager can toggle status', r.status === 200);
  r = await req('DELETE', `/masters/items/${eveId}`, { token: mgr });
  check('manager delete blocked 403', r.status === 403, r.json?.error?.code);

  /* staff form dropdown flow (what StaffPage does) */
  r = await req('GET', '/masters/definitions', { token: recep });
  const dd = r.json.data.find(d => d.Name.toLowerCase() === 'designation');
  r = await req('GET', `/masters/${dd.MasterDefinitionID}/items?pageSize=200&status=active`, { token: recep });
  check('staff form designation dropdown loads', r.status === 200 && r.json.data.length >= 6);

  /* staff create with a designation from masters still generates staff code */
  r = await req('POST', '/staff', { token: sa, body: { BranchID: 2, DepartmentID: 2, FullName: 'QA Staff MS', JoiningDate: '2026-09-13', Designation: 'Trainer', BaseSalary: 10000, Status: 'Active' } });
  check('staff create with master designation', r.status === 201 && r.json.data.staffCode, r.json.data?.staffCode);
  const qaStaff = r.json.data?.staffId;
  r = await req('GET', '/staff/trainers', { token: sa });
  check('new trainer-designated staff in trainers list', r.json.data.some(t => t.StaffName === 'QA Staff MS'));
  await req('DELETE', `/staff/${qaStaff}`, { token: sa });

  /* cleanup test artifacts */
  await req('DELETE', `/masters/items/${shiftItemId}`, { token: sa });
  await req('DELETE', `/masters/items/${shiftItem2}`, { token: sa });
  await req('DELETE', `/masters/items/${eveId}`, { token: sa });
  await req('DELETE', `/masters/definitions/${shiftId}`, { token: sa });
  await req('DELETE', `/masters/items/${redId}`, { token: sa });
  r = await req('GET', `/masters/${colorId}/items`, { token: sa });
  for (const i of r.json.data) await req('DELETE', `/masters/items/${i.MasterItemID}`, { token: sa });
  await req('DELETE', `/masters/definitions/${colorId}`, { token: sa });
  check('cleanup done', true);

  const failed = results.filter(x => !x.pass);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  process.exit(failed.length ? 1 : 0);
})().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
