// components/SearchFilter.tsx
'use client'
export function SearchFilter({ onSearch }: { onSearch: (q: string) => void }) {
  return (
    <div className="flex gap-2 mb-4">
      <input
        className="border rounded px-3 py-1.5 text-sm w-64 focus:outline-none focus:ring-1 focus:ring-blue-400"
        placeholder="Search by name, vcode, position..."
        onChange={e => onSearch(e.target.value)}
      />
    </div>
  )
}