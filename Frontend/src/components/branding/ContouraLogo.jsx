import { Link } from 'react-router-dom';

export default function ContouraLogo({ showText = true, className = '', dark = false }) {
  return (
    <Link to="/dashboard" className={`flex items-center gap-2 ${className}`}>
      <img src="/contoura-logo.svg" alt="Contoura Labs" className="h-9 w-auto" />
      {!showText && <span className="sr-only">Contoura Labs</span>}
    </Link>
  );
}
