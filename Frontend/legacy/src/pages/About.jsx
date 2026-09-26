import ContouraFooter from '../components/branding/ContouraFooter';

export default function AboutPage() {
  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <h1 className="text-2xl font-bold">About Contoura Labs</h1>

      <div className="card p-8 text-center">
        <img src="/contoura-logo.svg" alt="Contoura Labs" className="h-16 mx-auto mb-4" />
        <h2 className="text-2xl font-bold">Contoura Labs</h2>
        <p className="text-slate-500 dark:text-slate-400 mt-2 mb-6">Software studio building professional tools for businesses.</p>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
          <a href="mailto:contouralabs@gmail.com" className="block p-4 rounded-lg bg-slate-50 dark:bg-slate-800/50 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors">
            <div className="text-xs uppercase tracking-wide text-slate-400 mb-1">Email</div>
            <div className="font-medium text-brand-600">contouralabs@gmail.com</div>
          </a>
          <a href="https://wa.me/923422642366" target="_blank" rel="noreferrer" className="block p-4 rounded-lg bg-slate-50 dark:bg-slate-800/50 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors">
            <div className="text-xs uppercase tracking-wide text-slate-400 mb-1">WhatsApp</div>
            <div className="font-medium text-brand-600">+92 342 2642366</div>
          </a>
          <a href="https://contoura-labs.vercel.app/" target="_blank" rel="noreferrer" className="block p-4 rounded-lg bg-slate-50 dark:bg-slate-800/50 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors">
            <div className="text-xs uppercase tracking-wide text-slate-400 mb-1">Website</div>
            <div className="font-medium text-brand-600">contoura-labs.vercel.app</div>
          </a>
        </div>
      </div>

      <div className="card p-6">
        <h3 className="font-semibold mb-3">About This Software</h3>
        <p className="text-sm text-slate-600 dark:text-slate-300 leading-relaxed mb-3">
          The <strong>Contoura Labs Gym Management System</strong> is a complete, production-ready application designed for gym owners who need a professional, secure, and easy-to-deploy solution. It handles the entire lifecycle of gym operations: from member onboarding and membership renewals, through daily attendance and fee collection, all the way to payroll, finance reports, and audit logs.
        </p>
        <p className="text-sm text-slate-600 dark:text-slate-300 leading-relaxed mb-3">
          The system is built with role-based access control so every staff member — receptionist, trainer, accountant, manager, owner — sees exactly the modules and actions their role permits. Every login, every member change, every payment, every settings update is recorded in the audit log with IP and location, giving owners a complete trail of activity.
        </p>
        <p className="text-sm text-slate-600 dark:text-slate-300 leading-relaxed">
          Built on Microsoft SQL Server 2022 with stored procedures for all data access (no inline SQL — SQL-injection-safe by design), an Express.js REST API secured with JWT and rate-limiting, and a React single-page frontend with Tailwind CSS for a clean, modern, fully responsive UI. Deployable to a single Windows server via IIS, or to any Node-capable host.
        </p>
      </div>

      <div className="card p-6">
        <h3 className="font-semibold mb-3">Tech Stack</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
          {[
            ['Frontend', 'React 18 + Vite + Tailwind CSS'],
            ['Backend', 'Node.js + Express'],
            ['Database', 'Microsoft SQL Server 2022'],
            ['Auth', 'JWT + bcrypt + RBAC'],
            ['API', 'REST with stored procedures'],
            ['Charts', 'Recharts'],
            ['Server', 'IIS / PM2'],
            ['Security', 'Helmet + CORS + Rate limiting'],
          ].map(([k, v]) => (
            <div key={k} className="p-3 rounded-lg bg-slate-50 dark:bg-slate-800/50">
              <div className="text-xs uppercase tracking-wide text-slate-400 mb-1">{k}</div>
              <div className="font-medium text-sm">{v}</div>
            </div>
          ))}
        </div>
      </div>

      <ContouraFooter />
    </div>
  );
}
