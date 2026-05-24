// app/(dashboard)/vacancy/page.tsx
'use client'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { VacancyTable } from '@/components/vacancy/VacancyTable'
import type { VacancyStatus } from '@/lib/queries/vacancy'

const tabs = [
  { value: 'open', label: 'Open' },
  { value: 'with_applicant', label: 'With Applicant' },
  { value: 'rejected', label: 'Rejected' },
  { value: 'backout', label: 'Backout' },
]

export default function VacancyPage() {
  return (
    <div className="p-6">
      <h1 className="text-xl font-semibold mb-4">Vacancy Management</h1>
      <Tabs defaultValue="open">
        <TabsList>
          {tabs.map(t => <TabsTrigger key={t.value} value={t.value}>{t.label}</TabsTrigger>)}
        </TabsList>
        {tabs.map(t => (
          <TabsContent key={t.value} value={t.value}>
            <VacancyTable status={t.value as VacancyStatus} />
          </TabsContent>
        ))}
      </Tabs>
    </div>
  )
}
