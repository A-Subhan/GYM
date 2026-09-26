import { useEffect, useMemo, useState } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { NAV_MODULES } from '../../constants/nav';
import ContouraLogo from '../branding/ContouraLogo';

/**
 * Sidebar with five main modules and nested submenus (module → category → item).
 *
 * Interaction: click a module or category to expand/collapse it. The current
 * sidebar architecture had no hover-menu implementation, so click-to-expand
 * (with auto-expansion of the active trail) is used for stability — no
 * flicker, no stuck menus, no accidental navigation.
 *
 * Permissions: every node keeps its existing permission code; nodes the user
 * cannot see are removed before rendering, and a parent with no visible
 * children disappears automatically. Super Admin behavior is unchanged
 * (hasPermission returns true for everything).
 */

function isAllowed(node, hasPermission) {
  return !node.perm || hasPermission(node.perm);
}

function filterTree(nodes, hasPermission) {
  return nodes
    .filter((n) => isAllowed(n, hasPermission))
    .map((n) => (n.children ? { ...n, children: filterTree(n.children, hasPermission) } : n))
    .filter((n) => !n.children || n.children.length > 0);
}

function containsPath(node, pathname) {
  if (node.to && (pathname === node.to || pathname.startsWith(node.to + '/'))) return true;
  return (node.children || []).some((c) => containsPath(c, pathname));
}

function trailKeys(node, pathname, parents = []) {
  if (node.to && (pathname === node.to || pathname.startsWith(node.to + '/'))) return parents;
  for (const c of node.children || []) {
    const hit = trailKeys(c, pathname, [...parents, node.key || node.label]);
    if (hit) return hit;
  }
  return null;
}

function ModuleIcon({ path }) {
  return (
    <svg className="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" strokeWidth="1.8" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" d={path} />
    </svg>
  );
}

function Chevron({ open }) {
  return (
    <svg
      className={`w-4 h-4 flex-shrink-0 transition-transform duration-200 ${open ? 'rotate-90' : ''}`}
      fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"
    >
      <path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" />
    </svg>
  );
}

export default function Sidebar({ open, onClose }) {
  const { hasPermission, user } = useAuth();
  const location = useLocation();

  const modules = useMemo(() => filterTree(NAV_MODULES, hasPermission), [hasPermission]);

  // keys of open modules/categories; auto-expanded to the active trail on navigation
  const [openKeys, setOpenKeys] = useState(() => new Set());

  useEffect(() => {
    const trail = new Set();
    for (const m of modules) {
      const hit = trailKeys(m, location.pathname);
      if (hit) hit.forEach((k) => trail.add(k));
    }
    setOpenKeys(trail);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.pathname]);

  const toggle = (key) => {
    setOpenKeys((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const leafClass = (isActive) =>
    `flex items-center gap-3 rounded-lg text-sm font-medium transition-colors ${
      isActive
        ? 'bg-brand-600 text-white shadow-sm'
        : 'text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800'
    }`;

  const renderLeaf = (item, indentClass) => (
    <NavLink
      key={item.to}
      to={item.to}
      onClick={onClose}
      className={({ isActive }) => `${leafClass(isActive)} ${indentClass} py-1.5 pr-3`}
    >
      <span className="truncate">{item.label}</span>
    </NavLink>
  );

  const renderCategory = (cat) => {
    const key = cat.label;
    const isOpen = openKeys.has(key);
    const childActive = containsPath(cat, location.pathname);
    return (
      <div key={key}>
        <button
          type="button"
          onClick={() => toggle(key)}
          className={`w-full flex items-center gap-2 pl-9 pr-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
            childActive && !isOpen
              ? 'text-brand-600 dark:text-brand-400'
              : 'text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200'
          }`}
        >
          <span className="truncate flex-1 text-left">{cat.label}</span>
          <Chevron open={isOpen} />
        </button>
        {isOpen && (
          <div className="ml-6 border-l border-slate-200 dark:border-slate-800 my-0.5 space-y-0.5">
            {cat.children.map((leaf) => renderLeaf(leaf, 'pl-3 ml-2'))}
          </div>
        )}
      </div>
    );
  };

  const renderModule = (mod) => {
    // direct navigation item (Dashboard)
    if (!mod.children) {
      const isActive = location.pathname === mod.to || location.pathname.startsWith(mod.to + '/');
      return (
        <div key={mod.key}>
          <NavLink to={mod.to} onClick={onClose} className={({ isActive: a }) => `${leafClass(a)} px-3 py-2`}>
            <ModuleIcon path={mod.icon} />
            <span className="truncate">{mod.label}</span>
          </NavLink>
        </div>
      );
    }

    const isOpen = openKeys.has(mod.key);
    const childActive = containsPath(mod, location.pathname);
    const directItems = mod.children.filter((c) => !c.children);
    const categories = mod.children.filter((c) => c.children);

    return (
      <div key={mod.key}>
        <button
          type="button"
          onClick={() => toggle(mod.key)}
          className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
            childActive && !isOpen
              ? 'bg-brand-50 dark:bg-brand-950/40 text-brand-700 dark:text-brand-300'
              : 'text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800'
          }`}
        >
          <ModuleIcon path={mod.icon} />
          <span className="truncate flex-1 text-left">{mod.label}</span>
          <Chevron open={isOpen} />
        </button>

        {isOpen && (
          <div className="ml-4 border-l border-slate-200 dark:border-slate-800 mt-0.5 mb-1 pl-2 space-y-0.5">
            {directItems.map((leaf) => renderLeaf(leaf, 'pl-3'))}
            {categories.map(renderCategory)}
          </div>
        )}
      </div>
    );
  };

  return (
    <>
      {/* Mobile overlay */}
      {open && (
        <div className="fixed inset-0 z-30 bg-slate-900/40 lg:hidden" onClick={onClose} />
      )}

      <aside
        className={`fixed lg:sticky top-0 z-40 lg:z-auto h-screen w-64 flex-shrink-0 flex flex-col bg-white dark:bg-slate-900 border-r border-slate-200 dark:border-slate-800 transition-transform duration-300 ${
          open ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
        }`}
      >
        <div className="h-16 flex items-center justify-between px-4 border-b border-slate-200 dark:border-slate-800">
          <ContouraLogo />
          <button onClick={onClose} className="lg:hidden text-slate-500 hover:text-slate-700 dark:hover:text-slate-300 text-2xl leading-none">×</button>
        </div>

        <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-1.5">
          {modules.map(renderModule)}
        </nav>

        <div className="px-4 py-3 border-t border-slate-200 dark:border-slate-800">
          <div className="text-xs text-slate-500 dark:text-slate-400">
            Signed in as
            <div className="font-semibold text-slate-700 dark:text-slate-200 truncate">{user?.fullName}</div>
            <div className="text-[11px] text-slate-400">{user?.roleName}</div>
          </div>
        </div>
      </aside>
    </>
  );
}
