import { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { useToast } from '../../context/ToastContext';

export default function Login() {
  const { login, user } = useAuth();
  const toast = useToast();
  const navigate = useNavigate();
  const location = useLocation();
  const redirectTo = location.state?.from || '/dashboard';

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPwd, setShowPwd] = useState(false);
  const [remember, setRemember] = useState(true);
  const [loading, setLoading] = useState(false);
  const [location2, setLocation2] = useState(null);

  useEffect(() => {
    if (user) navigate(redirectTo, { replace: true });
  }, [user]);

  // Capture geolocation (best-effort, used for audit log)
  useEffect(() => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => setLocation2(`${pos.coords.latitude.toFixed(4)},${pos.coords.longitude.toFixed(4)}`),
      () => setLocation2(null),
      { timeout: 3000, maximumAge: 60000 }
    );
  }, []);

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!username || !password) return toast.error('Please enter username and password');
    setLoading(true);
    try {
      const u = await login({ username, password, location: location2 });
      toast.success(`Welcome back, ${u.fullName.split(' ')[0]}!`);
      navigate(redirectTo, { replace: true });
    } catch (err) {
      const msg = err.response?.data?.error?.message || 'Login failed. Check your credentials.';
      toast.error(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-stretch bg-slate-50 dark:bg-slate-950">
      {/* Left panel — branding */}
      <div className="hidden lg:flex flex-1 bg-gradient-to-br from-brand-700 via-brand-600 to-accent-600 text-white p-12 flex-col justify-between">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-white/15 backdrop-blur flex items-center justify-center">
            <span className="text-2xl font-bold">C</span>
          </div>
          <div>
            <div className="text-xl font-semibold leading-tight">Contoura Labs</div>
            <div className="text-xs text-white/70">Gym Management System</div>
          </div>
        </div>

        <div>
          <h1 className="text-4xl font-bold leading-tight mb-4">
            Run your gym<br />like a champion.
          </h1>
          <p className="text-white/80 max-w-md text-lg">
            Members, memberships, attendance, fees, finance, payroll, trainers, inventory, reports — all in one professional dashboard.
          </p>
          <div className="grid grid-cols-2 gap-4 mt-8 max-w-md text-sm">
            {['Multi-branch', 'Role-based access', 'Audit logging', 'Dark / Light mode', 'Export to Excel / PDF', 'QR / Biometric ready'].map((f) => (
              <div key={f} className="flex items-center gap-2">
                <span className="text-accent-300">✓</span> {f}
              </div>
            ))}
          </div>
        </div>

        <div className="text-xs text-white/60">
          Developed & Managed by{' '}
          <a href="https://contoura-labs.vercel.app/" target="_blank" rel="noreferrer" className="font-medium underline">Contoura Labs</a>
          {' · '}
          <a href="mailto:contouralabs@gmail.com" className="underline">contouralabs@gmail.com</a>
          {' · '}
          <a href="https://wa.me/923422642366" target="_blank" rel="noreferrer" className="underline">+92 342 2642366</a>
        </div>
      </div>

      {/* Right panel — login form */}
      <div className="flex-1 flex items-center justify-center p-6">
        <div className="w-full max-w-sm">
          <div className="flex lg:hidden items-center justify-center mb-6 gap-2">
            <img src="/contoura-logo.svg" alt="Contoura Labs" className="h-9" />
          </div>

          <h2 className="text-2xl font-bold mb-1">Sign in to your account</h2>
          <p className="text-sm text-slate-500 dark:text-slate-400 mb-6">Welcome back. Please enter your details.</p>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="label">Username</label>
              <input
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                className="input"
                placeholder="e.g. contouralabs"
                autoFocus
                autoComplete="username"
              />
            </div>

            <div>
              <label className="label">Password</label>
              <div className="relative">
                <input
                  type={showPwd ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="input pr-10"
                  placeholder="••••••••"
                  autoComplete="current-password"
                />
                <button
                  type="button"
                  onClick={() => setShowPwd((v) => !v)}
                  className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-slate-400 hover:text-slate-600 dark:hover:text-slate-200"
                  aria-label={showPwd ? 'Hide password' : 'Show password'}
                >
                  {showPwd ? '🙈' : '👁'}
                </button>
              </div>
            </div>

            <div className="flex items-center justify-between text-sm">
              <label className="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} className="rounded border-slate-300" />
                Remember me
              </label>
              <button type="button" className="text-brand-600 hover:text-brand-700 dark:text-brand-400" onClick={() => toast.info('Forgot password: contact your administrator.')}>
                Forgot password?
              </button>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="btn-primary w-full py-2.5"
            >
              {loading ? (
                <span className="flex items-center gap-2">
                  <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
                  Signing in…
                </span>
              ) : 'Sign in'}
            </button>
          </form>

          <div className="mt-6 p-3 rounded-lg bg-slate-100 dark:bg-slate-800 text-xs text-slate-600 dark:text-slate-300">
            <div className="font-semibold mb-1">Demo accounts (password: <code className="px-1 bg-white dark:bg-slate-900 rounded">Demo@1234</code>)</div>
            <div className="grid grid-cols-2 gap-x-3 gap-y-0.5">
              <span>owner.ahmed</span><span>manager.sana</span>
              <span>reception.ali</span><span>trainer.bilal</span>
              <span>acc.fatima</span><span>staff.zohaib</span>
            </div>
            <div className="mt-2 pt-2 border-t border-slate-200 dark:border-slate-700">
              Super admin: <code className="px-1 bg-white dark:bg-slate-900 rounded">contouralabs / Contoura@2024</code>
            </div>
          </div>

          <div className="mt-6 text-center text-xs text-slate-400">
            Powered by{' '}
            <a href="https://contoura-labs.vercel.app/" target="_blank" rel="noreferrer" className="font-medium text-brand-600 hover:underline">Contoura Labs</a>
          </div>
        </div>
      </div>
    </div>
  );
}
