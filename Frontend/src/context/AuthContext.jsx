import { createContext, useContext, useEffect, useState, useCallback } from 'react';
import api from '../services/api';

const AuthContext = createContext();

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [permissions, setPermissions] = useState([]);
  const [loading, setLoading] = useState(true);

  // On mount: try to restore session from localStorage
  useEffect(() => {
    const token = localStorage.getItem('accessToken');
    const savedUser = localStorage.getItem('user');
    const savedPerms = localStorage.getItem('permissions');
    if (token && savedUser) {
      try {
        setUser(JSON.parse(savedUser));
        setPermissions(savedPerms ? JSON.parse(savedPerms) : []);
      } catch (e) {
        localStorage.removeItem('accessToken');
        localStorage.removeItem('refreshToken');
        localStorage.removeItem('user');
        localStorage.removeItem('permissions');
      }
    }
    setLoading(false);
  }, []);

  const login = useCallback(async ({ username, password, location }) => {
    const res = await api.post('/auth/login', { username, password, location });
    const { accessToken, refreshToken, user, permissions } = res.data.data;
    localStorage.setItem('accessToken', accessToken);
    localStorage.setItem('refreshToken', refreshToken);
    localStorage.setItem('user', JSON.stringify(user));
    localStorage.setItem('permissions', JSON.stringify(permissions));
    setUser(user);
    setPermissions(permissions);
    return user;
  }, []);

  const logout = useCallback(async () => {
    const refreshToken = localStorage.getItem('refreshToken');
    try {
      await api.post('/auth/logout', { refreshToken });
    } catch (_) { /* ignore — server may already be down */ }
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
    localStorage.removeItem('user');
    localStorage.removeItem('permissions');
    setUser(null);
    setPermissions([]);
  }, []);

  const hasPermission = useCallback(
    (code) => {
      if (!user) return false;
      if (user.isSuperAdmin) return true;
      return permissions.includes(code);
    },
    [user, permissions]
  );

  const value = { user, permissions, loading, login, logout, hasPermission, setUser };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  return useContext(AuthContext);
}
