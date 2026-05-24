// components/vacancy/VacancyTable.tsx
'use client'
import { useQuery } from '@tanstack/react-query'
import { getVacancies, VacancyStatus } from '@/lib/queries/vacancy'
import { Badge } from '@/components/ui/badge'

export function VacancyTable({ status }: { status: VacancyStatus }) {
  const { data, isLoading } = useQuery({
    queryKey: ['vacancy', status],
    queryFn: () => getVacancies(status).then(r => r.data),
  })

  if (isLoading) return <p className="text-sm text-gray-400 mt-4">Loading...</p>

  return (
    <div className="mt-4 rounded-lg border">
      <table className="w-full text-sm">
        <thead className="bg-gray-50 text-gray-500 text-left">
          <tr>
            <th className="p-3">Vcode</th>
            <th className="p-3">Position</th>
            <th className="p-3">Department</th>
            <th className="p-3">Status</th>
          </tr>
        </thead>
        <tbody>
          {data?.map(v => (
            <tr key={v.id} className="border-t hover:bg-gray-50">
              <td className="p-3 font-mono text-xs">{v.vcode}</td>
              <td className="p-3">{v.position}</td>
              <td className="p-3">{v.department}</td>
              <td className="p-3"><Badge>{v.status}</Badge></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
