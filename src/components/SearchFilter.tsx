// components/SearchFilter.tsx
'use client'
export function SearchFilter({ onSearch }: { onSearch: (q: string) => void }) {
  return (
    <div className="flex gap-2 mb-4">
      <input
        className="border border-[var(--border-subtle)] bg-[var(--card)] text-[var(--foreground)] rounded px-3 py-1.5 text-sm w-64 focus:outline-hidden focus:ring-1 focus:ring-[var(--primary)]"
        placeholder="Search by name, vcode, position..."
        onChange={e => onSearch(e.target.value)}
      />
    </div>
  )
}