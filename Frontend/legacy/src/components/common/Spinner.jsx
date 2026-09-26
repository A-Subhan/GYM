export default function Spinner({ size = 'md', className }) {
  const sizes = { sm: 'w-4 h-4', md: 'w-8 h-8', lg: 'w-12 h-12' };
  return (
    <div className={`flex items-center justify-center ${className || ''}`}>
      <div className={`${sizes[size]} border-4 border-brand-500 border-t-transparent rounded-full animate-spin`}></div>
    </div>
  );
}
