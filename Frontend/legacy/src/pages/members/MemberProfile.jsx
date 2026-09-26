import {
  useEffect,
  useState
} from 'react';

import {
  useParams,
  Link,
  useNavigate
} from 'react-router-dom';

import api from '../../services/api';

import { useToast } from '../../context/ToastContext';

import {
  formatDate,
  formatCurrency,
  formatDateTime
} from '../../utils/format';

import {
  StatusBadge
} from '../../components/common/Badge';

import Spinner from '../../components/common/Spinner';
import Button from '../../components/common/Button';
import Can from '../../components/common/Can';

import {
  PERMISSIONS as P
} from '../../constants/permissions';

const TABS = [
  'Overview',
  'Payments',
  'Attendance',
  'Memberships',
  'Progress'
];

export default function MemberProfile() {
  const { id } = useParams();
  const navigate =
    useNavigate();

  const toast =
    useToast();

  const [data, setData] =
    useState(null);

  const [loading, setLoading] =
    useState(true);

  const [tab, setTab] =
    useState('Overview');

  const [photoUrl, setPhotoUrl] =
    useState('');

  const loadProfile =
    async () => {
      try {
        const res =
          await api.get(
            `/members/${id}/profile`
          );

        setData(
          res.data.data
        );

        try {
          const photoResponse =
            await api.get(
              `/members/${id}/photo`,
              {
                responseType:
                  'blob'
              }
            );

          setPhotoUrl(
            URL.createObjectURL(
              photoResponse.data
            )
          );
        } catch {
          setPhotoUrl('');
        }
      } catch (err) {
        toast.error(
          'Failed to load member: ' +
            (
              err.response?.data
                ?.error?.message ||
              err.message
            )
        );

        navigate('/members');
      } finally {
        setLoading(false);
      }
    };

  useEffect(() => {
    loadProfile();

    return () => {
      if (photoUrl) {
        URL.revokeObjectURL(
          photoUrl
        );
      }
    };
  }, [id]);

  const handleDelete =
    async () => {
      const confirmed =
        window.confirm(
          `Delete ${data.member.FullName}?`
        );

      if (!confirmed) {
        return;
      }

      try {
        await api.delete(
          `/members/${id}`
        );

        toast.success(
          'Member deleted'
        );

        navigate('/members');
      } catch (err) {
        toast.error(
          err.response?.data?.error
            ?.message ||
            'Unable to delete member'
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

  if (!data) {
    return null;
  }

  const m =
    data.member;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Link
            to="/members"
            className="text-slate-500 hover:text-slate-700 dark:hover:text-slate-300"
          >
            ← Members
          </Link>

          <h1 className="text-2xl font-bold">
            {m.FullName}
          </h1>

          <StatusBadge
            status={m.Status}
          />
        </div>

        <div className="flex gap-2">
          <Can perm={P.MEMBERS_EDIT}>
            <Link
              to={`/members/${m.MemberID}/edit`}
            >
              <Button variant="secondary">
                Edit
              </Button>
            </Link>
          </Can>

          <Can
            perm={
              P.MEMBERS_DELETE
            }
          >
            <Button
              variant="danger"
              onClick={
                handleDelete
              }
            >
              Delete
            </Button>
          </Can>
        </div>
      </div>

      <div className="card p-6 grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="flex flex-col items-center text-center">
          <div className="w-28 h-28 rounded-full overflow-hidden bg-gradient-to-br from-brand-500 to-accent-500 flex items-center justify-center text-white text-3xl font-bold mb-3">
            {photoUrl ? (
              <img
                src={photoUrl}
                alt={m.FullName}
                className="w-full h-full object-cover"
              />
            ) : (
              m.FullName
                ?.split(' ')
                .slice(0, 2)
                .map(
                  (w) => w[0]
                )
                .join('')
            )}
          </div>

          <div className="font-semibold text-lg">
            {m.FullName}
          </div>

          <div className="text-sm text-slate-500">
            {m.Code}
          </div>

          <div className="text-xs text-slate-400 mt-1">
            Member since{' '}
            {formatDate(
              m.JoiningDate
            )}
          </div>
        </div>

        <div className="md:col-span-2 grid grid-cols-2 gap-4 text-sm">
          <Field
            label="Father Name"
            value={m.FatherName}
          />

          <Field
            label="Gender"
            value={m.Gender}
          />

          <Field
            label="DOB"
            value={formatDate(
              m.DOB
            )}
          />

          <Field
            label="CNIC"
            value={m.CNIC}
          />

          <Field
            label="Mobile"
            value={m.Mobile}
          />

          <Field
            label="WhatsApp"
            value={m.WhatsApp}
          />

          <Field
            label="Email"
            value={m.Email}
          />

          <Field
            label="Emergency Contact"
            value={
              m.EmergencyContact
            }
          />

          <Field
            label="Address"
            value={m.Address}
            span={2}
          />

          <Field
            label="Trainer"
            value={m.TrainerName}
          />

          <Field
            label="Branch"
            value={m.BranchName}
          />

          <Field
            label="Height"
            value={
              m.HeightFeet
                ? `${m.HeightFeet} ft`
                : null
            }
          />

          <Field
            label="Weight"
            value={
              m.Weight
                ? `${m.Weight} kg`
                : null
            }
          />

          <Field
            label="Medical Notes"
            value={
              m.MedicalNotes
            }
            span={2}
          />
        </div>
      </div>

      <div className="card overflow-hidden">
        <div className="flex border-b border-slate-200 dark:border-slate-800 overflow-x-auto">
          {TABS.map(
            (t) => (
              <button
                key={t}
                onClick={() =>
                  setTab(t)
                }
                className={`px-5 py-3 text-sm font-medium border-b-2 transition-colors whitespace-nowrap ${
                  tab === t
                    ? 'border-brand-600 text-brand-600'
                    : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300'
                }`}
              >
                {t}
              </button>
            )
          )}
        </div>

        <div className="p-4">
          {tab ===
            'Overview' && (
            <div className="grid md:grid-cols-3 gap-3 text-sm">
              <Stat
                label="Total Payments"
                value={
                  data.payments
                    .length
                }
              />

              <Stat
                label="Total Paid"
                value={formatCurrency(
                  data.payments.reduce(
                    (s, p) =>
                      s +
                      Number(
                        p.Amount ||
                          0
                      ),
                    0
                  )
                )}
              />

              <Stat
                label="Visits (all-time)"
                value={
                  data.attendance
                    .length
                }
              />
            </div>
          )}

          {tab ===
            'Payments' && (
            <Table>
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Amount</th>
                  <th>Method</th>
                  <th>Reference</th>
                  <th>Collected By</th>
                </tr>
              </thead>

              <tbody>
                {data.payments.length ===
                  0 && (
                  <tr>
                    <td
                      colSpan={5}
                      className="text-center text-slate-400 py-6"
                    >
                      No payments yet
                    </td>
                  </tr>
                )}

                {data.payments.map(
                  (p) => (
                    <tr
                      key={
                        p.CollectionID
                      }
                    >
                      <td>
                        {formatDateTime(
                          p.CollectedAt
                        )}
                      </td>

                      <td className="font-semibold text-emerald-600">
                        {formatCurrency(
                          p.Amount
                        )}
                      </td>

                      <td>
                        {
                          p.MethodName
                        }
                      </td>

                      <td className="font-mono text-xs">
                        {p.TransactionRef ||
                          '—'}
                      </td>

                      <td>
                        {p.CollectedByName ||
                          '—'}
                      </td>
                    </tr>
                  )
                )}
              </tbody>
            </Table>
          )}

          {tab ===
            'Attendance' && (
            <Table>
              <thead>
                <tr>
                  <th>
                    Check In
                  </th>
                  <th>
                    Check Out
                  </th>
                  <th>
                    Method
                  </th>
                </tr>
              </thead>

              <tbody>
                {data.attendance.length ===
                  0 && (
                  <tr>
                    <td
                      colSpan={3}
                      className="text-center text-slate-400 py-6"
                    >
                      No attendance recorded
                    </td>
                  </tr>
                )}

                {data.attendance.map(
                  (a) => (
                    <tr
                      key={
                        a.AttendanceID
                      }
                    >
                      <td>
                        {formatDateTime(
                          a.CheckInTime
                        )}
                      </td>

                      <td>
                        {a.CheckOutTime
                          ? formatDateTime(
                              a.CheckOutTime
                            )
                          : '—'}
                      </td>

                      <td>
                        <span className="badge-info">
                          {
                            a.Method
                          }
                        </span>
                      </td>
                    </tr>
                  )
                )}
              </tbody>
            </Table>
          )}

          {tab ===
            'Memberships' && (
            <Table>
              <thead>
                <tr>
                  <th>
                    Plan
                  </th>
                  <th>
                    Start
                  </th>
                  <th>
                    End
                  </th>
                  <th>
                    Amount Paid
                  </th>
                  <th>
                    Status
                  </th>
                </tr>
              </thead>

              <tbody>
                {data.memberships.length ===
                  0 && (
                  <tr>
                    <td
                      colSpan={5}
                      className="text-center text-slate-400 py-6"
                    >
                      No memberships
                    </td>
                  </tr>
                )}

                {data.memberships.map(
                  (mm) => (
                    <tr
                      key={
                        mm.MemberMembershipID
                      }
                    >
                      <td className="font-medium">
                        {
                          mm.PlanName
                        }
                      </td>

                      <td>
                        {formatDate(
                          mm.StartDate
                        )}
                      </td>

                      <td>
                        {formatDate(
                          mm.EndDate
                        )}
                      </td>

                      <td>
                        {formatCurrency(
                          mm.AmountPaid
                        )}
                      </td>

                      <td>
                        <StatusBadge
                          status={
                            mm.Status
                          }
                        />
                      </td>
                    </tr>
                  )
                )}
              </tbody>
            </Table>
          )}

          {tab ===
            'Progress' && (
            <Table>
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Weight</th>
                  <th>BMI</th>
                  <th>Body Fat</th>
                  <th>Waist</th>
                  <th>Chest</th>
                  <th>Notes</th>
                </tr>
              </thead>

              <tbody>
                {data.progress.length ===
                  0 && (
                  <tr>
                    <td
                      colSpan={7}
                      className="text-center text-slate-400 py-6"
                    >
                      No progress entries
                    </td>
                  </tr>
                )}

                {data.progress.map(
                  (p) => (
                    <tr
                      key={
                        p.ProgressID
                      }
                    >
                      <td>
                        {formatDate(
                          p.Date
                        )}
                      </td>

                      <td>
                        {p.Weight
                          ? `${p.Weight} kg`
                          : '—'}
                      </td>

                      <td>
                        {p.BMI ||
                          '—'}
                      </td>

                      <td>
                        {p.BodyFat
                          ? `${p.BodyFat}%`
                          : '—'}
                      </td>

                      <td>
                        {p.Waist ||
                          '—'}
                      </td>

                      <td>
                        {p.Chest ||
                          '—'}
                      </td>

                      <td className="max-w-xs truncate">
                        {p.Notes ||
                          '—'}
                      </td>
                    </tr>
                  )
                )}
              </tbody>
            </Table>
          )}
        </div>
      </div>
    </div>
  );
}

function Field({
  label,
  value,
  span = 1
}) {
  return (
    <div
      className={
        span === 2
          ? 'col-span-2'
          : ''
      }
    >
      <div className="text-xs text-slate-400 uppercase tracking-wide">
        {label}
      </div>

      <div className="font-medium">
        {value || '—'}
      </div>
    </div>
  );
}

function Stat({
  label,
  value
}) {
  return (
    <div className="p-4 rounded-lg bg-slate-50 dark:bg-slate-800/50">
      <div className="text-xs text-slate-400 uppercase tracking-wide">
        {label}
      </div>

      <div className="text-xl font-bold mt-1">
        {value}
      </div>
    </div>
  );
}

function Table({
  children
}) {
  return (
    <div className="table-wrap">
      <table className="table">
        {children}
      </table>
    </div>
  );
}