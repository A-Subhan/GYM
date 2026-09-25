import { classNames } from '../../utils/format';

export default function Badge({ variant = 'neutral', children }) {
  const variants = {
    success: 'badge-success',
    warning: 'badge-warning',
    danger: 'badge-danger',
    info: 'badge-info',
    neutral: 'badge-neutral',
  };
  return <span className={classNames(variants[variant])}>{children}</span>;
}

export function StatusBadge({ status }) {
  const map = {
    Active: 'success',
    Inactive: 'neutral',
    Frozen: 'info',
    Expired: 'danger',
    Cancelled: 'neutral',
    Paid: 'success',
    Unpaid: 'danger',
    Partial: 'warning',
    Refunded: 'neutral',
    Present: 'success',
    Absent: 'danger',
    Late: 'warning',
    LoggedOut: 'neutral',
  };
  return <Badge variant={map[status] || 'neutral'}>{status}</Badge>;
}
