import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { formatCurrency } from '../../utils/format';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import Spinner from '../../components/common/Spinner';

export default function MembershipPlans() {
  const toast = useToast();

  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState(null);

  const [form, setForm] = useState({
    Name: '',
    DurationMonths: 1,
    Price: 0,
    JoiningFee: 0,
    Discount: 0,
    Description: '',
    IsActive: true,
  });

  const [errors, setErrors] = useState({});

  const load = useCallback(async () => {
    setLoading(true);

    try {
      const res = await api.get('/memberships/plans');
      setRows(res.data.data || []);
    } catch (err) {
      toast.error(
        err.response?.data?.error?.message ||
        'Failed to load plans'
      );
    } finally {
      setLoading(false);
    }
  }, [toast]);

  useEffect(() => {
    load();
  }, [load]);

  const openNew = () => {
    setEditing(null);

    setForm({
      Name: '',
      DurationMonths: 1,
      Price: 0,
      JoiningFee: 0,
      Discount: 0,
      Description: '',
      IsActive: true,
    });

    setErrors({});
    setModalOpen(true);
  };

  const openEdit = (p) => {
    setEditing(p.PlanID);

    setForm({
      Name: p.Name || '',
      DurationMonths: Number(p.DurationMonths ?? 0),
      Price: Number(p.Price ?? 0),
      JoiningFee: Number(p.JoiningFee ?? 0),
      Discount: Number(p.Discount ?? 0),
      Description: p.Description || '',
      IsActive: Boolean(p.IsActive),
    });

    setErrors({});
    setModalOpen(true);
  };

  const updateField = (field, value) => {
    setForm((prev) => ({
      ...prev,
      [field]: value,
    }));

    setErrors((prev) => ({
      ...prev,
      [field]: '',
    }));
  };

  const validate = () => {
    const newErrors = {};

    const name = form.Name.trim();
    const duration = Number(form.DurationMonths);
    const price = Number(form.Price);
    const joiningFee = Number(form.JoiningFee);
    const discount = Number(form.Discount);
    const description = form.Description.trim();

    if (!name) {
      newErrors.Name = 'Plan name is required';
    } else if (name.length < 2) {
      newErrors.Name = 'Plan name must be at least 2 characters';
    } else if (name.length > 60) {
      newErrors.Name = 'Plan name cannot exceed 60 characters';
    }

    if (!Number.isInteger(duration) || duration < 0 || duration > 120) {
      newErrors.DurationMonths =
        'Duration must be between 0 and 120 months';
    }

    if (!Number.isInteger(price) || price < 0 || price > 9999999) {
      newErrors.Price =
        'Price must be a whole number between 0 and 9,999,999';
    }

    if (
      !Number.isInteger(joiningFee) ||
      joiningFee < 0 ||
      joiningFee > 9999999
    ) {
      newErrors.JoiningFee =
        'Joining fee must be a whole number between 0 and 9,999,999';
    }

    if (
      !Number.isFinite(discount) ||
      discount < 0 ||
      discount > 100
    ) {
      newErrors.Discount =
        'Discount must be between 0 and 100';
    }

    if (description.length > 200) {
      newErrors.Description =
        'Description cannot exceed 200 characters';
    }

    setErrors(newErrors);

    return Object.keys(newErrors).length === 0;
  };

  const save = async (e) => {
    e.preventDefault();

    if (!validate()) {
      toast.error('Please fix the validation errors');
      return;
    }

    const payload = {
      Name: form.Name.trim(),
      DurationMonths: Number(form.DurationMonths),
      Price: Number(form.Price),
      JoiningFee: Number(form.JoiningFee),
      Discount: Number(form.Discount),
      Description: form.Description.trim() || null,
      IsActive: Boolean(form.IsActive),
    };

    try {
      if (editing) {
        await api.put(
          `/memberships/plans/${editing}`,
          payload
        );

        toast.success('Plan updated');
      } else {
        await api.post(
          '/memberships/plans',
          payload
        );

        toast.success('Plan created');
      }

      setModalOpen(false);
      setErrors({});
      await load();
    } catch (err) {
      toast.error(
        err.response?.data?.error?.message ||
        'Save failed'
      );
    }
  };

  const remove = async (id) => {
    if (
      !window.confirm(
        'Delete this membership plan? This action will only work if the plan has never been used.'
      )
    ) {
      return;
    }

    try {
      await api.delete(`/memberships/plans/${id}`);

      toast.success('Plan deleted');

      await load();
    } catch (err) {
      toast.error(
        err.response?.data?.error?.message ||
        'Delete failed'
      );
    }
  };

  if (loading) {
    return (
      <Spinner
        size="lg"
        className="mt-20"
      />
    );
  }

  return (
    <div className="space-y-4">

      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">
          Membership Plans
        </h1>

        <Button onClick={openNew}>
          + New Plan
        </Button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">

        {rows.map((p) => (
          <div
            key={p.PlanID}
            className="card p-5"
          >

            <div className="flex items-start justify-between">

              <div>
                <div className="text-lg font-semibold">
                  {p.Name}
                </div>

                <div className="text-xs text-slate-500">
                  {p.DurationMonths === 0
                    ? 'Lifetime'
                    : `${p.DurationMonths} month${
                        p.DurationMonths > 1 ? 's' : ''
                      }`}
                </div>
              </div>

              <span
                className={`badge ${
                  p.IsActive
                    ? 'badge-success'
                    : 'badge-neutral'
                }`}
              >
                {p.IsActive ? 'Active' : 'Inactive'}
              </span>

            </div>

            <div className="mt-3 text-2xl font-bold text-brand-600">
              {formatCurrency(p.Price)}
            </div>

            {p.JoiningFee > 0 && (
              <div className="text-xs text-slate-500">
                + {formatCurrency(p.JoiningFee)} joining fee
              </div>
            )}

            {p.Discount > 0 && (
              <div className="text-xs text-emerald-600 mt-1">
                {p.Discount}% discount
              </div>
            )}

            {p.Description && (
              <p className="text-sm text-slate-600 dark:text-slate-300 mt-3">
                {p.Description}
              </p>
            )}

            <div className="flex gap-2 mt-4">

              <Button
                variant="secondary"
                size="sm"
                onClick={() => openEdit(p)}
              >
                Edit
              </Button>

              <Button
                variant="ghost"
                size="sm"
                onClick={() => remove(p.PlanID)}
                className="text-red-600"
              >
                Delete
              </Button>

            </div>

          </div>
        ))}

        {rows.length === 0 && (
          <div className="col-span-full text-center text-slate-400 py-8">
            No plans yet.
          </div>
        )}

      </div>

      <Modal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        title={editing ? 'Edit Plan' : 'New Plan'}
      >

        <form
          onSubmit={save}
          className="space-y-3"
        >

          <div>
            <label className="label">
              Name *
            </label>

            <input
              type="text"
              className={`input ${
                errors.Name ? 'border-red-500' : ''
              }`}
              value={form.Name}
              maxLength={60}
              onChange={(e) =>
                updateField('Name', e.target.value)
              }
              required
            />

            <div className="flex justify-between mt-1">
              <span className="text-xs text-red-500">
                {errors.Name}
              </span>

              <span className="text-xs text-slate-400">
                {form.Name.length}/60
              </span>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">

            <div>
              <label className="label">
                Duration
              </label>

              <input
                type="number"
                min="0"
                max="120"
                step="1"
                className={`input ${
                  errors.DurationMonths
                    ? 'border-red-500'
                    : ''
                }`}
                value={form.DurationMonths}
                onChange={(e) =>
                  updateField(
                    'DurationMonths',
                    e.target.value
                  )
                }
                required
              />

              <div className="text-xs text-slate-400 mt-1">
                0 = Lifetime
              </div>

              {errors.DurationMonths && (
                <div className="text-xs text-red-500 mt-1">
                  {errors.DurationMonths}
                </div>
              )}
            </div>

            <div>
              <label className="label">
                Price *
              </label>

              <input
                type="text"
                inputMode="numeric"
                pattern="[0-9]*"
                className={`input ${
                  errors.Price ? 'border-red-500' : ''
                }`}
                value={form.Price}
                onChange={(e) => {
                  const value = e.target.value.replace(
                    /[^0-9]/g,
                    ''
                  );

                  updateField(
                    'Price',
                    value === '' ? '' : Number(value)
                  );
                }}
                required
              />

              {errors.Price && (
                <div className="text-xs text-red-500 mt-1">
                  {errors.Price}
                </div>
              )}
            </div>

            <div>
              <label className="label">
                Joining Fee
              </label>

              <input
                type="text"
                inputMode="numeric"
                pattern="[0-9]*"
                className={`input ${
                  errors.JoiningFee
                    ? 'border-red-500'
                    : ''
                }`}
                value={form.JoiningFee}
                onChange={(e) => {
                  const value = e.target.value.replace(
                    /[^0-9]/g,
                    ''
                  );

                  updateField(
                    'JoiningFee',
                    value === '' ? '' : Number(value)
                  );
                }}
              />

              {errors.JoiningFee && (
                <div className="text-xs text-red-500 mt-1">
                  {errors.JoiningFee}
                </div>
              )}
            </div>

            <div>
              <label className="label">
                Discount %
              </label>

              <input
                type="text"
                inputMode="decimal"
                className={`input ${
                  errors.Discount
                    ? 'border-red-500'
                    : ''
                }`}
                value={form.Discount}
                onChange={(e) => {
                  let value = e.target.value;

                  value = value.replace(
                    /[^0-9.]/g,
                    ''
                  );

                  const parts = value.split('.');

                  if (parts.length > 2) {
                    value =
                      parts[0] +
                      '.' +
                      parts.slice(1).join('');
                  }

                  updateField(
                    'Discount',
                    value === '' ? '' : value
                  );
                }}
              />

              <div className="text-xs text-slate-400 mt-1">
                Decimals allowed, e.g. 5.5
              </div>

              {errors.Discount && (
                <div className="text-xs text-red-500 mt-1">
                  {errors.Discount}
                </div>
              )}
            </div>

          </div>

          <div>
            <label className="label">
              Description
            </label>

            <textarea
              className={`input ${
                errors.Description
                  ? 'border-red-500'
                  : ''
              }`}
              rows="3"
              maxLength={200}
              value={form.Description}
              onChange={(e) =>
                updateField(
                  'Description',
                  e.target.value
                )
              }
            />

            <div className="flex justify-between mt-1">

              <span className="text-xs text-red-500">
                {errors.Description}
              </span>

              <span className="text-xs text-slate-400">
                {form.Description.length}/200
              </span>

            </div>
          </div>

          {editing && (
            <div>
              <label className="label">
                Status
              </label>

              <select
                className="input"
                value={form.IsActive ? 'true' : 'false'}
                onChange={(e) =>
                  updateField(
                    'IsActive',
                    e.target.value === 'true'
                  )
                }
              >
                <option value="true">
                  Active
                </option>

                <option value="false">
                  Inactive
                </option>
              </select>
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2">

            <Button
              type="button"
              variant="secondary"
              onClick={() => setModalOpen(false)}
            >
              Cancel
            </Button>

            <Button type="submit">
              {editing ? 'Update' : 'Create'}
            </Button>

          </div>

        </form>

      </Modal>

    </div>
  );
}