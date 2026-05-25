// app/(dashboard)/vacancy/page.tsx
"use client";

import { useMemo, useState, type FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  BriefcaseBusiness,
  FileSearch,
  LockKeyhole,
  Plus,
} from "lucide-react";
import {
  VacancyTable,
  type VacancyStatus,
} from "@/components/vacancy/VacancyTable";
import { VacancyDetailDrawer } from "@/components/vacancy/VacancyDetailDrawer";
import {
  VacancyDataError,
  getVacancySummary,
  listVacancies,
  type VacancyListItem,
} from "@/lib/queries/vacancy";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { MetricCard } from "@/components/shared/MetricCard";
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";

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

const vacancyCapabilities: string[] = [];
const canAddVacancy = vacancyCapabilities.includes("vacancy.add");
const pageSize = 25;

function getErrorKind(error: unknown) {
  return error instanceof VacancyDataError ? error.kind : null;
}

export default function VacancyPage() {
  const [status, setStatus] = useState<VacancyStatus>("open");
  const [searchDraft, setSearchDraft] = useState("");
  const [search, setSearch] = useState("");
  const [agingBucket, setAgingBucket] = useState("");
  const [pipelineStatus, setPipelineStatus] = useState("");
  const [page, setPage] = useState(1);
  const [selectedVacancyId, setSelectedVacancyId] = useState<string | null>(null);

  const queryParams = useMemo(
    () => ({
      status,
      search,
      agingBucket: agingBucket || undefined,
      pipelineStatus: pipelineStatus || undefined,
      page,
      pageSize,
    }),
    [agingBucket, page, pipelineStatus, search, status],
  );

  const summaryQuery = useQuery({
    queryKey: [
      "vacancy-summary",
      status,
      search,
      agingBucket,
      pipelineStatus,
    ],
    queryFn: () => getVacancySummary(queryParams),
    retry: false,
  });

  const listQuery = useQuery({
    queryKey: ["vacancy-list", queryParams],
    queryFn: () => listVacancies(queryParams),
    retry: false,
  });

  const rows = listQuery.data?.data ?? [];
  const totalCount = listQuery.data?.totalCount ?? 0;
  const listErrorKind = getErrorKind(listQuery.error);
  const summaryErrorKind = getErrorKind(summaryQuery.error);
  const errorKind = listErrorKind ?? summaryErrorKind;
  const blocked = errorKind === "access_denied";
  const activeStatusDescription =
    statusTabs.find((tab) => tab.value === status)?.description ?? "Vacancy queue";

  const kpis = [
    {
      label: "Open Vacancies",
      value: summaryQuery.data?.open,
      helper: "Scoped open queue",
    },
    {
      label: "With Applicant",
      value: summaryQuery.data?.withApplicant,
      helper: "Backend pipeline status",
    },
    {
      label: "Pending Review",
      value: summaryQuery.data?.pendingReview,
      helper: "Backend review count",
    },
    {
      label: "Aging Watch",
      value: summaryQuery.data?.agingWatch,
      helper: "Backend aging bucket",
    },
  ];

  function updateStatus(nextStatus: VacancyStatus) {
    setStatus(nextStatus);
    setPage(1);
    setSelectedVacancyId(null);
  }

  function applySearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSearch(searchDraft.trim());
    setPage(1);
    setSelectedVacancyId(null);
  }

  function selectVacancy(row: VacancyListItem) {
    setSelectedVacancyId(row.id);
  }

  function retryVacancyReads() {
    void summaryQuery.refetch();
    void listQuery.refetch();
  }

  function updatePage(nextPage: number) {
    setPage(nextPage);
    setSelectedVacancyId(null);
  }

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-4 p-4 text-gray-900 sm:p-5">
      <AdminPageHeader
        title="Vacancy Management"
        subtitle="Desktop vacancy command center backed by scoped Supabase summary and list RPCs."
        icon={BriefcaseBusiness}
        readOnly={true}
        primaryAction={{
          label: "Add Vacancy",
          onClick: () => {},
          disabled: !canAddVacancy,
          icon: Plus,
        }}
      />

      <section
        aria-label="Vacancy summary"
        className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4"
      >
        {kpis.map((item) => (
          <MetricCard
            key={item.label}
            label={item.label}
            value={item.value}
            helperText={item.helper}
            isLoading={summaryQuery.isLoading}
            isBlocked={blocked}
            isError={summaryQuery.isError}
            errorText="Retryable summary error"
          />
        ))}
      </section>

      <section className="flex min-h-0 flex-1 flex-col gap-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div
            aria-label="Vacancy status filter"
            className="inline-flex rounded-md border border-gray-200 bg-white p-1"
            role="tablist"
          >
            {statusTabs.map((tab) => (
              <button
                aria-selected={status === tab.value}
                className={`rounded px-3 py-1.5 text-xs font-medium ${
                  status === tab.value
                    ? "bg-blue-600 text-white"
                    : "text-gray-600 hover:bg-gray-100"
                }`}
                key={tab.value}
                onClick={() => updateStatus(tab.value)}
                role="tab"
                type="button"
              >
                {tab.label}
              </button>
            ))}
          </div>
          <div className="text-xs text-gray-500">
            Status, search, filters, and pagination are sent to Supabase RPCs.
          </div>
        </div>

        <div className="flex min-h-0 flex-1 flex-col gap-3">
          <AdminFilterBar
            searchPlaceholder="Search code, position title, department, scope"
            searchVal={searchDraft}
            onSearchChange={setSearchDraft}
            onSearchSubmit={applySearch}
            disabled={blocked}
            showApplyButton={true}
            applyLabel="Apply"
            extraActionsSlot={
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-500 hover:bg-gray-50 cursor-not-allowed transition-colors"
                disabled
                type="button"
              >
                <FileSearch className="h-4 w-4" aria-hidden="true" />
                Saved View
              </button>
            }
          >
            <select
              aria-label="Pipeline status filter"
              className="h-9 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
              disabled={blocked}
              onChange={(event) => {
                setPipelineStatus(event.target.value);
                setPage(1);
                setSelectedVacancyId(null);
              }}
              value={pipelineStatus}
            >
              <option value="">All pipeline</option>
              <option value="Open">Open</option>
              <option value="Pipeline">Pipeline</option>
            </select>
            <select
              aria-label="Aging bucket filter"
              className="h-9 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
              disabled={blocked}
              onChange={(event) => {
                setAgingBucket(event.target.value);
                setPage(1);
                setSelectedVacancyId(null);
              }}
              value={agingBucket}
            >
              <option value="">All aging</option>
              <option value="advance">Advance</option>
              <option value="1_15">1-15 days</option>
              <option value="16_30">16-30 days</option>
              <option value="31_60">31-60 days</option>
              <option value="61_120">61-120 days</option>
              <option value="gt121">121+ days</option>
            </select>
          </AdminFilterBar>

          <VacancyTable
            errorKind={listErrorKind}
            isLoading={listQuery.isLoading}
            onPageChange={updatePage}
            onRetry={retryVacancyReads}
            onSelect={selectVacancy}
            page={page}
            pageSize={pageSize}
            rows={rows}
            selectedId={selectedVacancyId}
            status={status}
            statusDescription={activeStatusDescription}
            totalCount={totalCount}
          />
        </div>

        <VacancyDetailDrawer
          vacancyId={selectedVacancyId}
          onClose={() => setSelectedVacancyId(null)}
        />
      </section>

      <section className="rounded-md border border-dashed border-gray-300 bg-gray-50 p-3">
        <div className="flex items-start gap-2 text-sm text-gray-600">
          <LockKeyhole className="mt-0.5 h-4 w-4 text-gray-400" aria-hidden="true" />
          <div>
            Vacancy reads use get_web_vacancy_summary and list_web_vacancies.
            Applicant workflow, approvals, closure, add-vacancy, and other
            mutations remain disabled until backend action RPCs are approved.
          </div>
        </div>
      </section>
    </div>
  );
}
