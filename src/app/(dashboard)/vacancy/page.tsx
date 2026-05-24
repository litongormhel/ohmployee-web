// app/(dashboard)/vacancy/page.tsx
"use client";

import {
  BriefcaseBusiness,
  FileSearch,
  Filter,
  LockKeyhole,
  Plus,
  Search,
} from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import {
  VacancyDetailPanel,
  VacancyTable,
  type VacancyStatus,
} from "@/components/vacancy/VacancyTable";

const statusTabs: Array<{ value: VacancyStatus; label: string; description: string }> = [
  {
    value: "open",
    label: "Open",
    description: "Unfilled vacancy queue",
  },
  {
    value: "with_applicant",
    label: "With Applicant",
    description: "Vacancies with applicant activity",
  },
  {
    value: "rejected",
    label: "Rejected",
    description: "Rejected vacancy movement",
  },
  {
    value: "backout",
    label: "Backout",
    description: "Backout tracking queue",
  },
];

const kpiPlaceholders = [
  { label: "Open Vacancies", helper: "Awaiting scoped KPI contract" },
  { label: "With Applicant", helper: "Awaiting applicant-safe summary" },
  { label: "Pending Review", helper: "Awaiting approval queue contract" },
  { label: "Aging Watch", helper: "Awaiting backend-computed aging" },
];

const vacancyCapabilities: string[] = [];
const canAddVacancy = vacancyCapabilities.includes("vacancy.add");

export default function VacancyPage() {
  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-4 p-4 text-gray-900 sm:p-5">
      <section className="flex flex-wrap items-start justify-between gap-3 border-b border-gray-200 pb-4">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <BriefcaseBusiness className="h-5 w-5 text-blue-600" aria-hidden="true" />
            <h1 className="text-xl font-semibold tracking-normal">Vacancy Management</h1>
            <Badge className="border-blue-200 bg-blue-50 text-blue-700">Shell only</Badge>
          </div>
          <p className="mt-1 max-w-3xl text-sm text-gray-500">
            Desktop vacancy command center prepared for scoped Supabase list,
            detail, applicant, KPI, and action contracts.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            className="inline-flex h-9 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-500 shadow-sm"
            disabled={!canAddVacancy}
            type="button"
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add Vacancy
          </button>
        </div>
      </section>

      <section
        aria-label="Vacancy summary"
        className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4"
      >
        {kpiPlaceholders.map((item) => (
          <div
            className="rounded-md border border-gray-200 bg-white px-3 py-2.5"
            key={item.label}
          >
            <div className="text-xs font-medium uppercase text-gray-500">
              {item.label}
            </div>
            <div className="mt-1 flex items-end justify-between gap-3">
              <div className="text-2xl font-semibold text-gray-400">--</div>
              <Badge className="border-gray-200 bg-gray-50 text-gray-500">
                Pending
              </Badge>
            </div>
            <div className="mt-1 text-xs text-gray-400">{item.helper}</div>
          </div>
        ))}
      </section>

      <Tabs defaultValue="open" className="flex min-h-0 flex-1 flex-col gap-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <TabsList className="rounded-md">
            {statusTabs.map((tab) => (
              <TabsTrigger
                className="rounded px-3 py-1.5 text-xs font-medium"
                key={tab.value}
                value={tab.value}
              >
                {tab.label}
              </TabsTrigger>
            ))}
          </TabsList>
          <div className="text-xs text-gray-500">
            Status controls are structural until the scoped list contract is wired.
          </div>
        </div>

        <div className="grid min-h-0 flex-1 gap-4 xl:grid-cols-[minmax(0,1fr)_360px]">
          <div className="flex min-w-0 flex-col gap-3">
            <div className="flex flex-wrap items-center gap-2 rounded-md border border-gray-200 bg-white p-2">
              <label className="relative min-w-[280px] flex-1">
                <Search
                  className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400"
                  aria-hidden="true"
                />
                <input
                  aria-label="Search vacancies"
                  className="h-9 w-full rounded-md border border-gray-200 bg-gray-50 pl-9 pr-3 text-sm text-gray-500 outline-none"
                  disabled
                  placeholder="Search code, position, department, scope"
                  type="search"
                />
              </label>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-500"
                disabled
                type="button"
              >
                <Filter className="h-4 w-4" aria-hidden="true" />
                Filters
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-500"
                disabled
                type="button"
              >
                <FileSearch className="h-4 w-4" aria-hidden="true" />
                Saved View
              </button>
            </div>

            {statusTabs.map((tab) => (
              <TabsContent
                className="min-h-0 flex-1"
                key={tab.value}
                value={tab.value}
              >
                <VacancyTable
                  status={tab.value}
                  statusDescription={tab.description}
                />
              </TabsContent>
            ))}
          </div>

          <VacancyDetailPanel capabilities={vacancyCapabilities} />
        </div>
      </Tabs>

      <section className="rounded-md border border-dashed border-gray-300 bg-gray-50 p-3">
        <div className="flex items-start gap-2 text-sm text-gray-600">
          <LockKeyhole className="mt-0.5 h-4 w-4 text-gray-400" aria-hidden="true" />
          <div>
            Vacancy data, applicant workflow, KPI totals, and mutations remain
            backend-authoritative and are intentionally not implemented in this
            shell pass.
          </div>
        </div>
      </section>
    </div>
  );
}
