import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import DataTable from '../../components/common/DataTable';
import { formatDate, formatCurrency } from '../../utils/format';
import Can from '../../components/common/Can';
import { exportToCSV } from '../../utils/export';

export default function InventoryPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [suppliers, setSuppliers] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [meta, setMeta] = useState({});
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [lowStockOnly, setLowStockOnly] = useState(false);
  const [tab, setTab] = useState('items');
  const [txns, setTxns] = useState([]);
  const [itemModal, setItemModal] = useState(false);
  const [txnModal, setTxnModal] = useState(false);
  const [supplierModal, setSupplierModal] = useState(false);
  const [editing, setEditing] = useState(null);
  const [itemForm, setItemForm] = useState({});
  const [txnForm, setTxnForm] = useState({ ItemID: '', Type: 'Purchase', Qty: 1, UnitPrice: 0, SupplierID: '', TxnDate: new Date().toISOString().slice(0,10), Notes: '' });
  const [supplierForm, setSupplierForm] = useState({ Name: '', Contact: '', Phone: '', Email: '', Address: '' });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [i, s, t] = await Promise.all([
        api.get('/inventory', { params: { page, pageSize: 50, search: search || undefined, category: categoryFilter || undefined, lowStock: lowStockOnly ? 'true' : undefined } }),
        api.get('/inventory/suppliers'),
        api.get('/inventory/transactions/all', { params: { pageSize: 100 } }),
      ]);
      setRows(i.data.data);
      setTotal(i.data.meta.total);
      setTotalPages(Math.ceil((i.data.meta.total || 0) / 50));
      setMeta(i.data.meta);
      setSuppliers(s.data.data);
      setTxns(t.data.data);
    } catch (err) { toast.error('Failed to load inventory'); }
    finally { setLoading(false); }
  }, [page, search, categoryFilter, lowStockOnly]);

  useEffect(() => { load(); }, [load]);

  const openItem = (item = null) => {
    if (item) { setEditing(item.ItemID); setItemForm({ Name: item.Name, Category: item.Category, SKU: item.SKU || '', StockQty: item.StockQty, ReorderLevel: item.ReorderLevel, SalePrice: item.SalePrice, PurchasePrice: item.PurchasePrice, IsActive: item.IsActive }); }
    else { setEditing(null); setItemForm({ Name: '', Category: 'Supplement', SKU: '', StockQty: 0, ReorderLevel: 5, SalePrice: 0, PurchasePrice: 0, IsActive: true }); }
    setItemModal(true);
  };

  const saveItem = async (e) => {
    e.preventDefault();
    try {
      const payload = { ...itemForm, StockQty: Number(itemForm.StockQty), ReorderLevel: Number(itemForm.ReorderLevel), SalePrice: Number(itemForm.SalePrice), PurchasePrice: Number(itemForm.PurchasePrice) };
      if (editing) await api.put(`/inventory/${editing}`, payload);
      else await api.post('/inventory', payload);
      toast.success('Saved'); setItemModal(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); }
  };

  const removeItem = async (id) => {
    if (!confirm('Delete this item?')) return;
    try { await api.delete(`/inventory/${id}`); toast.success('Deleted'); load(); }
    catch (err) { toast.error('Failed'); }
  };

  const openTxn = () => { setTxnForm({ ItemID: rows[0]?.ItemID || '', Type: 'Purchase', Qty: 1, UnitPrice: 0, SupplierID: '', TxnDate: new Date().toISOString().slice(0,10), Notes: '' }); setTxnModal(true); };

  const saveTxn = async (e) => {
    e.preventDefault();
    try {
      await api.post('/inventory/transactions', { ...txnForm, ItemID: Number(txnForm.ItemID), Qty: Number(txnForm.Qty), UnitPrice: Number(txnForm.UnitPrice), SupplierID: txnForm.SupplierID ? Number(txnForm.SupplierID) : null });
      toast.success('Transaction recorded'); setTxnModal(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); }
  };

  const saveSupplier = async (e) => {
    e.preventDefault();
    try {
      await api.post('/inventory/suppliers', supplierForm);
      toast.success('Supplier added'); setSupplierModal(false); setSupplierForm({ Name: '', Contact: '', Phone: '', Email: '', Address: '' }); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); }
  };

  const columns = [
    { key: 'Name', label: 'Item', render: (i) => <div><div className="font-medium">{i.Name}</div><div className="text-xs text-slate-400">{i.Category} · {i.SKU || 'no SKU'}</div></div> },
    { key: 'StockQty', label: 'Stock', render: (i) => <span className={i.IsLowStock ? 'text-red-600 font-semibold' : ''}>{i.StockQty} {i.IsLowStock && '⚠'}</span> },
    { key: 'ReorderLevel', label: 'Reorder At' },
    { key: 'SalePrice', label: 'Sale Price', render: (i) => formatCurrency(i.SalePrice) },
    { key: 'PurchasePrice', label: 'Purchase Price', render: (i) => formatCurrency(i.PurchasePrice) },
    { key: 'actions', label: '', render: (i) => (
      <div className="flex gap-2 text-sm">
        <Can perm="inventory.edit"><button onClick={() => openItem(i)} className="text-brand-600 hover:underline">Edit</button></Can>
        <Can perm="inventory.delete"><button onClick={() => removeItem(i.ItemID)} className="text-red-600 hover:underline">Delete</button></Can>
      </div>
    ) },
  ];

  return (
    <div className="space-y-4">
      <PageHeader title="Inventory" subtitle={`${total} items · ${meta.LowStockCount || 0} low stock · Value: ${formatCurrency(meta.InventoryValue || 0)}`}
        actions={
          <Can perm="inventory.add">
            <div className="flex gap-2">
              <Button variant="ghost" onClick={() => setSupplierModal(true)}>+ Supplier</Button>
              <Button variant="secondary" onClick={openTxn}>+ Transaction</Button>
              <Button onClick={() => openItem()}>+ Add Item</Button>
            </div>
          </Can>
        } />

      <div className="card overflow-hidden">
        <div className="flex border-b border-slate-200 dark:border-slate-800">
          {['items','transactions','suppliers'].map((t) => (
            <button key={t} onClick={() => setTab(t)} className={`px-5 py-3 text-sm font-medium border-b-2 capitalize ${tab === t ? 'border-brand-600 text-brand-600' : 'border-transparent text-slate-500 hover:text-slate-700'}`}>{t}</button>
          ))}
        </div>

        {tab === 'items' && (
          <>
            <div className="p-4 flex flex-wrap gap-3 items-end">
              <div className="flex-1 min-w-[200px]"><input placeholder="Search name, SKU…" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} className="input" /></div>
              <select value={categoryFilter} onChange={(e) => { setCategoryFilter(e.target.value); setPage(1); }} className="input w-40"><option value="">All Categories</option><option>Supplement</option><option>Drink</option><option>Accessory</option></select>
              <label className="flex items-center gap-2 text-sm cursor-pointer"><input type="checkbox" checked={lowStockOnly} onChange={(e) => { setLowStockOnly(e.target.checked); setPage(1); }} /> Low stock only</label>
              <Button variant="ghost" onClick={() => exportToCSV(rows, 'inventory.csv')}>Export CSV</Button>
            </div>
            <DataTable columns={columns} rows={rows} loading={loading} pagination={{ page, totalPages, total }} onPageChange={setPage} />
          </>
        )}

        {tab === 'transactions' && (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Date</th><th>Item</th><th>Type</th><th>Qty</th><th>Unit Price</th><th>Supplier</th><th>Notes</th></tr></thead>
              <tbody>
                {txns.length === 0 && <tr><td colSpan={7} className="text-center text-slate-400 py-8">No transactions</td></tr>}
                {txns.map((t) => (
                  <tr key={t.TxnID}>
                    <td>{formatDate(t.TxnDate)}</td>
                    <td className="font-medium">{t.ItemName}</td>
                    <td><span className={`badge ${t.Type === 'Sale' ? 'badge-success' : t.Type === 'Purchase' ? 'badge-info' : 'badge-warning'}`}>{t.Type}</span></td>
                    <td>{t.Qty}</td>
                    <td>{formatCurrency(t.UnitPrice)}</td>
                    <td>{t.SupplierName || '—'}</td>
                    <td className="max-w-xs truncate">{t.Notes || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {tab === 'suppliers' && (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Name</th><th>Contact</th><th>Phone</th><th>Email</th><th>Address</th><th>Status</th></tr></thead>
              <tbody>
                {suppliers.length === 0 && <tr><td colSpan={6} className="text-center text-slate-400 py-8">No suppliers</td></tr>}
                {suppliers.map((s) => (
                  <tr key={s.SupplierID}>
                    <td className="font-medium">{s.Name}</td>
                    <td>{s.Contact || '—'}</td>
                    <td>{s.Phone || '—'}</td>
                    <td>{s.Email || '—'}</td>
                    <td className="max-w-xs truncate">{s.Address || '—'}</td>
                    <td><span className={`badge ${s.IsActive ? 'badge-success' : 'badge-neutral'}`}>{s.IsActive ? 'Active' : 'Inactive'}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <Modal open={itemModal} onClose={() => setItemModal(false)} title={editing ? 'Edit Item' : 'New Item'}>
        <form onSubmit={saveItem} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><label className="label">Name *</label><input className="input" value={itemForm.Name} onChange={(e) => setItemForm({...itemForm, Name: e.target.value})} required /></div>
            <div><label className="label">Category *</label><select className="input" value={itemForm.Category} onChange={(e) => setItemForm({...itemForm, Category: e.target.value})}><option>Supplement</option><option>Drink</option><option>Accessory</option></select></div>
            <div><label className="label">SKU</label><input className="input" value={itemForm.SKU} onChange={(e) => setItemForm({...itemForm, SKU: e.target.value})} /></div>
            <div><label className="label">Stock Qty</label><input type="number" step="0.01" className="input" value={itemForm.StockQty} onChange={(e) => setItemForm({...itemForm, StockQty: e.target.value})} /></div>
            <div><label className="label">Reorder Level</label><input type="number" step="0.01" className="input" value={itemForm.ReorderLevel} onChange={(e) => setItemForm({...itemForm, ReorderLevel: e.target.value})} /></div>
            <div><label className="label">Sale Price</label><input type="number" step="0.01" className="input" value={itemForm.SalePrice} onChange={(e) => setItemForm({...itemForm, SalePrice: e.target.value})} /></div>
            <div><label className="label">Purchase Price</label><input type="number" step="0.01" className="input" value={itemForm.PurchasePrice} onChange={(e) => setItemForm({...itemForm, PurchasePrice: e.target.value})} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setItemModal(false)}>Cancel</Button><Button type="submit">{editing ? 'Update' : 'Create'}</Button></div>
        </form>
      </Modal>

      <Modal open={txnModal} onClose={() => setTxnModal(false)} title="New Transaction">
        <form onSubmit={saveTxn} className="space-y-3">
          <div><label className="label">Item *</label><select className="input" value={txnForm.ItemID} onChange={(e) => setTxnForm({...txnForm, ItemID: e.target.value})} required>{rows.map((i) => <option key={i.ItemID} value={i.ItemID}>{i.Name} (Stock: {i.StockQty})</option>)}</select></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Type *</label><select className="input" value={txnForm.Type} onChange={(e) => setTxnForm({...txnForm, Type: e.target.value})}><option>Purchase</option><option>Sale</option><option>Adjustment</option></select></div>
            <div><label className="label">Qty *</label><input type="number" step="0.01" className="input" value={txnForm.Qty} onChange={(e) => setTxnForm({...txnForm, Qty: e.target.value})} required /></div>
            <div><label className="label">Unit Price</label><input type="number" step="0.01" className="input" value={txnForm.UnitPrice} onChange={(e) => setTxnForm({...txnForm, UnitPrice: e.target.value})} /></div>
            <div><label className="label">Date</label><input type="date" className="input" value={txnForm.TxnDate} onChange={(e) => setTxnForm({...txnForm, TxnDate: e.target.value})} /></div>
            <div className="col-span-2"><label className="label">Supplier</label><select className="input" value={txnForm.SupplierID} onChange={(e) => setTxnForm({...txnForm, SupplierID: e.target.value})}><option value="">— None —</option>{suppliers.map((s) => <option key={s.SupplierID} value={s.SupplierID}>{s.Name}</option>)}</select></div>
            <div className="col-span-2"><label className="label">Notes</label><input className="input" value={txnForm.Notes} onChange={(e) => setTxnForm({...txnForm, Notes: e.target.value})} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setTxnModal(false)}>Cancel</Button><Button type="submit">Save</Button></div>
        </form>
      </Modal>

      <Modal open={supplierModal} onClose={() => setSupplierModal(false)} title="New Supplier">
        <form onSubmit={saveSupplier} className="space-y-3">
          <div><label className="label">Name *</label><input className="input" value={supplierForm.Name} onChange={(e) => setSupplierForm({...supplierForm, Name: e.target.value})} required /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Contact</label><input className="input" value={supplierForm.Contact} onChange={(e) => setSupplierForm({...supplierForm, Contact: e.target.value})} /></div>
            <div><label className="label">Phone</label><input className="input" value={supplierForm.Phone} onChange={(e) => setSupplierForm({...supplierForm, Phone: e.target.value})} /></div>
            <div><label className="label">Email</label><input type="email" className="input" value={supplierForm.Email} onChange={(e) => setSupplierForm({...supplierForm, Email: e.target.value})} /></div>
            <div className="col-span-2"><label className="label">Address</label><input className="input" value={supplierForm.Address} onChange={(e) => setSupplierForm({...supplierForm, Address: e.target.value})} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setSupplierModal(false)}>Cancel</Button><Button type="submit">Add</Button></div>
        </form>
      </Modal>
    </div>
  );
}
