// app/(dashboard)/vacancy/page.tsx
"use client";

import { useMemo, useState, type FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  BriefcaseBusiness,
  FileSearch,
  LockKeyhole,
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
import { useCurrentUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";

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

  const currentUser = useCurrentUser();

  const accountsQuery = useQuery({
    queryKey: ["vacancy-accounts", currentUser?.accountScope],
    queryFn: async () => {
      if (!currentUser) return [];
      const { mode, ids } = currentUser.accountScope;
      if (mode === "none") return [];

      const supabase = createClient();
      let query = supabase
        .from("accounts")
        .select(`
          id,
          account_name,
          group_id,
          groups (
            group_name
          )
        `)
        .eq("is_active", true);

      if (mode === "scoped" && ids.length > 0) {
        query = query.in("id", ids);
      }

      const { data, error } = await query.order("account_name");
      if (error) {
        console.error("Error fetching accounts:", error);
        return [];
      }
      return (data ?? []).map((row) => ({
        id: row.id as string,
        name: row.account_name as string,
        groupId: row.group_id as string | null,
        groupName: Array.isArray(row.groups)
          ? ((row.groups[0] as unknown as Record<string, unknown>)?.group_name as string | null)
          : row.groups && typeof row.groups === "object"
          ? ((row.groups as unknown as Record<string, unknown>).group_name as string | null)
          : null,
      }));
    },
    enabled: !!currentUser,
    staleTime: 60_000,
  });

  const accounts = useMemo(() => accountsQuery.data ?? [], [accountsQuery.data]);

  const uniqueGroups = useMemo(() => {
    const map = new Map<string, string>();
    for (const a of accounts) {
      if (a.groupId && a.groupName) {
        map.set(a.groupId, a.groupName);
      }
    }
    return Array.from(map.entries()).map(([id, name]) => ({ id, name }));
  }, [accounts]);

  const filteredAccounts = useMemo(() => {
    if (!groupId) return accounts;
    return accounts.filter((a) => a.groupId === groupId);
  }, [accounts, groupId]);

  const kpis = [
    {
      label: "Open Vacancies",
      value: summaryQuery.data?.open,
      helper: "Active unfilled positions",
    },
    {
      label: "With Applicant",
      value: summaryQuery.data?.withApplicant,
      helper: "Active candidate pipeline",
    },
    {
      label: "Pending Review",
      value: summaryQuery.data?.pendingReview,
      helper: "Awaiting candidate review",
    },
    {
      label: "Aging Watch",
      value: summaryQuery.data?.agingWatch,
      helper: "Open over 30 days",
    },
  ];

  function updateStatus(nextStatus: VacancyStatus) {
    setStatus(nextStatus);
    setPage(1);
    setSelectedVacancyId(null);
  }

  function handleAccountChange(newAccountId: string) {
    setAccountId(newAccountId);
    setPage(1);
    setSelectedVacancyId(null);
  }

  function handleGroupChange(newGroupId: string) {
    setGroupId(newGroupId);
    setPage(1);
    setSelectedVacancyId(null);
    if (newGroupId && accountId) {
      const match = accounts.find((a) => a.id === accountId);
      if (match && match.groupId !== newGroupId) {
        setAccountId("");
      }
    }
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
        subtitle="Monitor unfilled store vacancies, applicant pipeline, and aging requisitions."
        icon={BriefcaseBusiness}
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
            Real-time store requisitions and candidate pipeline.
          </div>
          </div>
          <p className="pl-1 text-sm text-gray-500">
            {activeStatusDescription}
          </p>
        </div>

        <div className="flex min-h-0 flex-1 flex-col gap-3">
          <AdminFilterBar
            searchPlaceholder="Search code, position, outlet, applicant, HRCO..."
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
            <select
              aria-label="Account filter"
              className="h-10 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
              disabled={blocked}
              onChange={(event) => handleAccountChange(event.target.value)}
              value={accountId}
            >
              <option value="">All accounts</option>
              {filteredAccounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {account.name}
                </option>
              ))}
            </select>
            <select
              aria-label="Group filter"
              className="h-10 rounded-md border border-gray-200 bg-white px-3 text-sm text-gray-600 outline-none focus:border-blue-300"
              disabled={blocked}
              onChange={(event) => handleGroupChange(event.target.value)}
              value={groupId}
            >
              <option value="">All groups</option>
              {uniqueGroups.map((group) => (
                <option key={group.id} value={group.id}>
                  {group.name}
                </option>
              ))}
            </select>
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
            Vacancy requisitions and headcount quotas are managed through Plantilla. Applicant status updates and quota amendments reflect automatically.
          </div>
        </div>
      </section>
    </div>
  );
}
