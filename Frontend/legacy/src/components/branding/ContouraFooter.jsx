import { Link } from 'react-router-dom';

export default function ContouraFooter({ variant = 'full' }) {
  if (variant === 'compact') {
    return (
      <span className="text-xs text-slate-500 dark:text-slate-400">
        Developed & Managed by{' '}
        <a href="https://contoura-labs.vercel.app/" target="_blank" rel="noreferrer" className="font-medium text-brand-600 hover:text-brand-700 dark:text-brand-400">
          Contoura Labs
        </a>
      </span>
    );
  }

  return (
    <footer className="mt-auto border-t border-slate-200 dark:border-slate-800 bg-white dark:bg-slate-900">
      <div className="px-6 py-4 flex flex-col md:flex-row items-center justify-between gap-3 text-sm">
        <div className="flex items-center gap-3">
          <img src="/contoura-logo.svg" alt="Contoura Labs" className="h-7 w-auto" />
          <div>
            <div className="font-semibold text-slate-700 dark:text-slate-200">
              Developed & Managed by{' '}
              <a href="https://contoura-labs.vercel.app/" target="_blank" rel="noreferrer" className="text-brand-600 hover:text-brand-700 dark:text-brand-400">
                Contoura Labs
              </a>
            </div>
            <div className="text-xs text-slate-500 dark:text-slate-400">
              <a href="mailto:contouralabs@gmail.com" className="hover:text-brand-600">contouralabs@gmail.com</a>
              {' · '}
              <a href="https://wa.me/923422642366" target="_blank" rel="noreferrer" className="hover:text-brand-600">+92 342 2642366</a>
              {' · '}
              <a href="https://contoura-labs.vercel.app/" target="_blank" rel="noreferrer" className="hover:text-brand-600">contoura-labs.vercel.app</a>
            </div>
          </div>
        </div>
        <div className="text-xs text-slate-400">
          © {new Date().getFullYear()} Contoura Labs. All rights reserved.
        </div>
      </div>
    </footer>
  );
}
