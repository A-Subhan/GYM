import { Link } from 'react-router-dom';
import ContouraFooter from '../components/branding/ContouraFooter';

export default function NotFound() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-slate-50 dark:bg-slate-950 p-6">
      <img src="/contoura-logo.svg" alt="Contoura Labs" className="h-12 mb-6" />
      <h1 className="text-6xl font-bold text-slate-300 dark:text-slate-700">404</h1>
      <p className="text-xl mt-2 mb-6">Page not found</p>
      <Link to="/" className="btn-primary">Back to Dashboard</Link>
      <div className="mt-12"><ContouraFooter variant="compact" /></div>
    </div>
  );
}
