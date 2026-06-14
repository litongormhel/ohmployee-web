// app/(dashboard)/vacancy/page.tsx
"use client";

import { useMemo, useState, type FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  BriefcaseBusiness,
  FileSearch,
  LockKeyhole,
  Plus,
  ShieldOff,
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
import { getWebFreezeModeStatus } from "@/lib/queries/freeze";
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
  const [accountId, setAccountId] = useState("");
  const [groupId, setGroupId] = useState("");
  const [urgency, setUrgency] = useState("");
  const [vacantFrom, setVacantFrom] = useState("");
  const [vacantTo, setVacantTo] = useState("");
  const [page, setPage] = useState(1);
  const [selectedVacancyId, setSelectedVacancyId] = useState<string | null>(null);

  const queryParams = useMemo(
    () => ({
      status,
      search,
      agingBucket: agingBucket || undefined,
      accountId: accountId || undefined,
      groupId: groupId || undefined,
      urgency: urgency || undefined,
      vacantFrom: vacantFrom || undefined,
      vacantTo: vacantTo || undefined,
      page,
      pageSize,
    }),
    [accountId, agingBucket, groupId, page, search, status, urgency, vacantFrom, vacantTo],
  );

  const freezeQuery = useQuery({
    queryKey: ["freeze-mode-status"],
    queryFn: getWebFreezeModeStatus,
    retry: false,
    staleTime: 30_000,
  });

  const isFreezeModeActive = freezeQuery.data?.isReadOnlyEmergencyActive === true;

  const summaryQuery = useQuery({
    queryKey: [
      "vacancy-summary",
      status,
      search,
      agingBucket,
      accountId,
      groupId,
      urgency,
      vacantFrom,
      vacantTo,
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
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-gray-900">
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

      {isFreezeModeActive && (
        <div
          role="alert"
          aria-live="assertive"
          className="flex items-start gap-3 rounded-md border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800"
        >
          <ShieldOff className="mt-0.5 h-5 w-5 shrink-0 text-red-600" aria-hidden="true" />
          <div className="flex flex-col gap-0.5">
            <span className="font-semibold">Read-Only Emergency Mode Active</span>
            <span className="text-xs text-red-700">
              All write actions are temporarily disabled system-wide. Supabase backend will reject any mutation attempt.
              {freezeQuery.data?.reason && (
                <> Reason: {freezeQuery.data.reason}.</>
              )}
              {freezeQuery.data?.activatedByName && (
                <> Activated by {freezeQuery.data.activatedByName}.</>
              )}
              {" "}Contact a Super Admin to deactivate this freeze from Freeze Modes.
            </span>
          </div>
        </div>
      )}

      <section
        aria-label="Vacancy summary"
        className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
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
        <div className="flex flex-col gap-2 border-b border-gray-100 pb-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
          <div
            aria-label="Vacancy status filter"
            className="inline-flex rounded-md border border-gray-200 bg-white p-1 shadow-xs"
            role="tablist"
          >
            {statusTabs.map((tab) => (
              <button
                aria-selected={status === tab.value}
                className={`rounded px-4 py-2 text-sm font-semibold transition-all duration-150 ${
                  status === tab.value
                    ? "bg-brand-600 text-white"
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
          <div className="text-sm font-medium text-gray-500">
            Status, search, filters, and pagination are sent to Supabase RPCs.
          </div>
          </div>
          <p className="pl-1 text-sm text-gray-500">
            {activeStatusDescription}
          </p>
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
                className="inline-flex h-10 items-center gap-2 rounded-md border border-gray-200 bg-white px-4 text-sm font-medium text-gray-500 transition-colors hover:bg-gray-50 cursor-not-allowed"
                disabled
                type="button"
              >
                <FileSearch className="h-4 w-4" aria-hidden="true" />
                Saved View
              </button>
            }
          >
            <input
              aria-label="Account ID filter"
              className="h-10 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
              disabled={blocked}
              onChange={(event) => {
                setAccountId(event.target.value);
                setPage(1);
                setSelectedVacancyId(null);
              }}
              placeholder="Account UUID"
              value={accountId}
            />
            <input
              aria-label="Group ID filter"
              className="h-10 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
              disabled={blocked}
              onChange={(event) => {
                setGroupId(event.target.value);
                setPage(1);
                setSelectedVacancyId(null);
              }}
              placeholder="Group UUID"
              value={groupId}
            />
            <select
              aria-label="Aging bucket filter"
              className="h-10 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
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
            <select
              aria-label="Urgency filter"
              className="h-10 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
              disabled={blocked}
              onChange={(event) => {
                setUrgency(event.target.value);
                setPage(1);
                setSelectedVacancyId(null);
              }}
              value={urgency}
            >
              <option value="">All urgency</option>
              <option value="High">High</option>
              <option value="Medium">Medium</option>
              <option value="Normal">Normal</option>
            </select>
            <input
              aria-label="Vacant date from"
              className="h-10 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
              disabled={blocked}
              max={vacantTo || undefined}
              onChange={(event) => {
                setVacantFrom(event.target.value);
                setPage(1);
                setSelectedVacancyId(null);
              }}
              type="date"
              value={vacantFrom}
            />
            <input
              aria-label="Vacant date to"
              className="h-10 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
              disabled={blocked}
              min={vacantFrom || undefined}
              onChange={(event) => {
                setVacantTo(event.target.value);
                setPage(1);
                setSelectedVacancyId(null);
              }}
              type="date"
              value={vacantTo}
            />
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
          isFreezeModeActive={isFreezeModeActive}
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
