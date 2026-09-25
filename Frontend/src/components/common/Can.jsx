import { useAuth } from '../../context/AuthContext';

/**
 * Render children only if the current user has the given permission code.
 * Super Admin always passes.
 */
export default function Can({ perm, children, fallback = null }) {
  const { hasPermission } = useAuth();
  if (!perm || hasPermission(perm)) return children;
  return fallback;
}
