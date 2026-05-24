// app/(dashboard)/vacancy/page.tsx
"use client";

import { useMemo, useState, type FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  BriefcaseBusiness,
  FileSearch,
  Filter,
  LockKeyhole,
  Plus,
  Search,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  VacancyDetailPanel,
  VacancyTable,
  type VacancyStatus,
} from "@/components/vacancy/VacancyTable";
import {
  VacancyDataError,
  getVacancySummary,
  listVacancies,
  type VacancyListItem,
} from "@/lib/queries/vacancy";

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
  const selectedVacancy =
    rows.find((row) => row.id === selectedVacancyId) ?? null;
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
      <section className="flex flex-wrap items-start justify-between gap-3 border-b border-gray-200 pb-4">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <BriefcaseBusiness className="h-5 w-5 text-blue-600" aria-hidden="true" />
            <h1 className="text-xl font-semibold tracking-normal">Vacancy Management</h1>
            <Badge className="border-blue-200 bg-blue-50 text-blue-700">
              Read only
            </Badge>
          </div>
          <p className="mt-1 max-w-3xl text-sm text-gray-500">
            Desktop vacancy command center backed by scoped Supabase summary and
            list RPCs.
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
        {kpis.map((item) => (
          <div
            className="rounded-md border border-gray-200 bg-white px-3 py-2.5"
            key={item.label}
          >
            <div className="text-xs font-medium uppercase text-gray-500">
              {item.label}
            </div>
            <div className="mt-1 flex items-end justify-between gap-3">
              <div className="text-2xl font-semibold text-gray-900">
                {summaryQuery.isLoading ? "--" : item.value ?? 0}
              </div>
              <Badge
                className={
                  blocked
                    ? "border-red-200 bg-red-50 text-red-700"
                    : "border-gray-200 bg-gray-50 text-gray-500"
                }
              >
                {blocked ? "Blocked" : "RPC"}
              </Badge>
            </div>
            <div className="mt-1 text-xs text-gray-400">
              {summaryQuery.isError && !blocked
                ? "Retryable summary error"
                : item.helper}
            </div>
          </div>
        ))}
      </section>

      <section className="flex min-h-0 flex-1 flex-col gap-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div
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

        <div className="grid min-h-0 flex-1 gap-4 xl:grid-cols-[minmax(0,1fr)_360px]">
          <div className="flex min-w-0 flex-col gap-3">
            <form
              className="flex flex-wrap items-center gap-2 rounded-md border border-gray-200 bg-white p-2"
              onSubmit={applySearch}
            >
              <label className="relative min-w-[280px] flex-1">
                <Search
                  className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400"
                  aria-hidden="true"
                />
                <input
                  aria-label="Search vacancies"
                  className="h-9 w-full rounded-md border border-gray-200 bg-gray-50 pl-9 pr-3 text-sm text-gray-700 outline-none focus:border-blue-300"
                  disabled={blocked}
                  onChange={(event) => setSearchDraft(event.target.value)}
                  placeholder="Search code, position title, department, scope"
                  type="search"
                  value={searchDraft}
                />
              </label>
              <select
                aria-label="Pipeline status filter"
                className="h-9 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600"
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
                className="h-9 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600"
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
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-700 disabled:text-gray-400"
                disabled={blocked}
                type="submit"
              >
                <Filter className="h-4 w-4" aria-hidden="true" />
                Apply
              </button>
              <button
                className="inline-flex h-9 items-center gap-2 rounded-md border border-gray-200 bg-white px-3 text-sm font-medium text-gray-500"
                disabled
                type="button"
              >
                <FileSearch className="h-4 w-4" aria-hidden="true" />
                Saved View
              </button>
            </form>

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

          <VacancyDetailPanel vacancy={selectedVacancy} />
        </div>
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
