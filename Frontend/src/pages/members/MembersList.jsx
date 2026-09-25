import { useEffect, useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import api from '../../services/api';
import { useAuth } from '../../context/AuthContext';
import { useToast } from '../../context/ToastContext';
import { formatDate } from '../../utils/format';
import { StatusBadge } from '../../components/common/Badge';
import Pagination from '../../components/common/Pagination';
import Spinner from '../../components/common/Spinner';
import Button from '../../components/common/Button';
import Can from '../../components/common/Can';
import { PERMISSIONS as P } from '../../constants/permissions';

export default function MembersList() {
  const toast = useToast();
  const { hasPermission } =
    useAuth();

  const [rows, setRows] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] =
    useState(1);
  const [total, setTotal] =
    useState(0);
  const [loading, setLoading] =
    useState(true);
  const [search, setSearch] =
    useState('');
  const [status, setStatus] =
    useState('');
  const [
    debouncedSearch,
    setDebouncedSearch
  ] = useState('');

  useEffect(() => {
    const t = setTimeout(
      () =>
        setDebouncedSearch(search),
      400
    );

    return () =>
      clearTimeout(t);
  }, [search]);

  const load = useCallback(
    async () => {
      setLoading(true);

      try {
        const params = {
          page,
          pageSize: 15,
          search:
            debouncedSearch ||
            undefined,
          Status:
            status || undefined
        };

        const res =
          await api.get(
            '/members',
            { params }
          );

        setRows(
          res.data.data
        );

        setTotal(
          res.data.meta.total
        );

        setTotalPages(
          res.data.meta.totalPages
        );
      } catch (err) {
        toast.error(
          'Failed to load members: ' +
            (
              err.response?.data
                ?.error?.message ||
              err.message
            )
        );
      } finally {
        setLoading(false);
      }
    },
    [
      page,
      debouncedSearch,
      status
    ]
  );

  useEffect(() => {
    load();
  }, [load]);

  const handleDelete = async (
    member
  ) => {
    const confirmed =
      window.confirm(
        `Delete ${member.FullName}?`
      );

    if (!confirmed) {
      return;
    }

    try {
      await api.delete(
        `/members/${member.MemberID}`
      );

      toast.success(
        'Member deleted'
      );

      load();
    } catch (err) {
      toast.error(
        err.response?.data?.error
          ?.message ||
          'Unable to delete member'
      );
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">
            Members
          </h1>

          <p className="text-sm text-slate-500 dark:text-slate-400">
            {total} total
          </p>
        </div>

        <Can perm={P.MEMBERS_ADD}>
          <Link to="/members/new">
            <Button variant="primary">
              + Add Member
            </Button>
          </Link>
        </Can>
      </div>

      <div className="card p-4 flex flex-wrap gap-3 items-end">
        <div className="flex-1 min-w-[200px]">
          <label className="label">
            Search
          </label>

          <input
            type="text"
            value={search}
            onChange={(e) => {
              setSearch(
                e.target.value
              );
              setPage(1);
            }}
            placeholder="Name, code, mobile, CNIC…"
            className="input"
          />
        </div>

        <div className="w-44">
          <label className="label">
            Status
          </label>

          <select
            value={status}
            onChange={(e) => {
              setStatus(
                e.target.value
              );
              setPage(1);
            }}
            className="input"
          >
            <option value="">
              All
            </option>

            <option value="Active">
              Active
            </option>

            <option value="Inactive">
              Inactive
            </option>

            <option value="Frozen">
              Frozen
            </option>

            <option value="Expired">
              Expired
            </option>
          </select>
        </div>

        <Button
          variant="secondary"
          onClick={() => {
            setSearch('');
            setStatus('');
            setPage(1);
          }}
        >
          Reset
        </Button>
      </div>

      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-8">
            <Spinner />
          </div>
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Actions</th>
                  <th>Code</th>
                  <th>Name</th>
                  <th>Mobile</th>
                  <th>Trainer</th>
                  <th>Joined</th>
                  <th>Membership Ends</th>
                  <th>Status</th>
                </tr>
              </thead>

              <tbody>
                {rows.length === 0 && (
                  <tr>
                    <td
                      colSpan={8}
                      className="text-center text-slate-400 py-8"
                    >
                      No members found.
                    </td>
                  </tr>
                )}

                {rows.map(
                  (m) => (
                    <tr
                      key={
                        m.MemberID
                      }
                    >
                      <td>
                        <div className="flex items-center gap-2 whitespace-nowrap">
                          <Can
                            perm={
                              P.MEMBERS_VIEW
                            }
                          >
                            <Link
                              to={`/members/${m.MemberID}`}
                              className="text-brand-600 hover:underline text-sm"
                            >
                              View
                            </Link>
                          </Can>

                          <Can
                            perm={
                              P.MEMBERS_EDIT
                            }
                          >
                            <Link
                              to={`/members/${m.MemberID}/edit`}
                              className="text-slate-600 hover:underline dark:text-slate-300 text-sm"
                            >
                              Edit
                            </Link>
                          </Can>

                          <Can
                            perm={
                              P.MEMBERS_DELETE
                            }
                          >
                            <button
                              type="button"
                              onClick={() =>
                                handleDelete(
                                  m
                                )
                              }
                              className="text-red-600 hover:underline text-sm"
                            >
                              Delete
                            </button>
                          </Can>
                        </div>
                      </td>

                      <td className="font-mono text-xs">
                        {m.Code}
                      </td>

                      <td>
                        <Link
                          to={`/members/${m.MemberID}`}
                          className="font-medium text-brand-600 hover:underline"
                        >
                          {m.FullName}
                        </Link>
                      </td>

                      <td>
                        {m.Mobile ||
                          '—'}
                      </td>

                      <td>
                        {m.TrainerName ||
                          '—'}
                      </td>

                      <td>
                        {formatDate(
                          m.JoiningDate
                        )}
                      </td>

                      <td>
                        {m.MembershipEndDate
                          ? formatDate(
                              m.MembershipEndDate
                            )
                          : '—'}
                      </td>

                      <td>
                        <StatusBadge
                          status={
                            m.Status
                          }
                        />
                      </td>
                    </tr>
                  )
                )}
              </tbody>
            </table>
          </div>
        )}

        <div className="px-4">
          <Pagination
            page={page}
            totalPages={
              totalPages
            }
            total={total}
            onChange={setPage}
          />
        </div>
      </div>
    </div>
  );
}