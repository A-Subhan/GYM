import { useEffect, useState } from 'react';
import api from '../../../services/api';

/**
 * Printable report header. Pulls company information from the Finance
 * defaults (Settings) and renders report title / range / print date.
 * The surrounding element must use class "print-area" for print CSS.
 */
export default function PrintHeader({ title, subtitle, children }) {
  const [company, setCompany] = useState({});

  useEffect(() => {
    api.get('/finance/defaults')
      .then((res) => setCompany(res.data.data.parsed.FinanceCompany || {}))
      .catch(() => setCompany({}));
  }, []);

  return (
    <div className="mb-4 pb-3 border-b border-slate-300 text-center">
      {company.logoPath && (
        <img src={company.logoPath} alt="" className="h-10 mx-auto mb-1"
          onError={(e) => { e.currentTarget.style.display = 'none'; }} />
      )}
      <div className="text-lg font-bold">{company.name || 'Contoura Fitness'}</div>
      <div className="text-xs text-slate-500">
        {company.address}{company.phone ? ` · ${company.phone}` : ''}{company.email ? ` · ${company.email}` : ''}
        {company.ntn ? ` · NTN: ${company.ntn}` : ''}
      </div>
      <div className="text-sm font-semibold mt-2">{title}</div>
      {subtitle && <div className="text-xs text-slate-500">{subtitle}</div>}
      {children}
      <div className="text-[10px] text-slate-400 mt-1">
        Printed {new Date().toLocaleString('en-GB')}
      </div>
    </div>
  );
}
