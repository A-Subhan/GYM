import { classNames } from '../../utils/format';

export default function Button({ variant = 'primary', size = 'md', className, children, ...props }) {
  const variants = {
    primary: 'btn-primary',
    secondary: 'btn-secondary',
    danger: 'btn-danger',
    ghost: 'btn-ghost',
  };
  const sizes = {
    sm: 'text-sm px-3 py-1.5',
    md: '',
    lg: 'text-base px-5 py-2.5',
  };
  return (
    <button className={classNames(variants[variant], sizes[size], className)} {...props}>
      {children}
    </button>
  );
}
