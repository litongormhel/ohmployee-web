// app/(dashboard)/vacancy/page.tsx
"use client";

import { useMemo, useState, type FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  Archive,
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
  AddApplicantModal,
  type VacancyContextSummary,
} from "@/components/vacancy/AddApplicantModal";
import { AdvancePipelineModal } from "@/components/vacancy/AdvancePipelineModal";
import { MarkHiredModal } from "@/components/vacancy/MarkHiredModal";
import { FailBackoutModal } from "@/components/vacancy/FailBackoutModal";
import { ReopenVacancyModal } from "@/components/vacancy/ReopenVacancyModal";
import { RequestVacancyClosureModal } from "@/components/vacancy/RequestVacancyClosureModal";
import { EditHiredDateModal } from "@/components/vacancy/EditHiredDateModal";
import {
  VacancyDataError,
  getVacancySummary,
  listVacancies,
  useApproveAllClosureRequests,
  useReviewClosureRequest,
  type VacancyListItem,
} from "@/lib/queries/vacancy";
import { getWebFreezeModeStatus } from "@/lib/queries/freeze";
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";
import { useCurrentUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";

const statusTabs: Array<{ value: VacancyStatus; label: string }> = [
  {
    value: "open",
    label: "Open",
  },
  {
    value: "pipeline",
    label: "Pipeline",
  },
  {
    value: "hired",
    label: "Hired",
  },
  {
    value: "closure",
    label: "Closure",
  },
  {
    value: "failed_backout",
    label: "Failed / Backout",
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
  const [endorseTargetVacancy, setEndorseTargetVacancy] = useState<VacancyContextSummary | null>(null);
  const [isAddApplicantModalOpen, setIsAddApplicantModalOpen] = useState(false);
  const [isAdvanceModalOpen, setIsAdvanceModalOpen] = useState(false);
  const [advanceTargetCandidate, setAdvanceTargetCandidate] = useState<{
    id: string;
    fullName: string;
    contactNumber?: string | null;
    status: string;
    vcode: string;
    positionTitle?: string | null;
  } | null>(null);
  const [isMarkHiredModalOpen, setIsMarkHiredModalOpen] = useState(false);
  const [markHiredTargetCandidate, setMarkHiredTargetCandidate] = useState<{
    id: string;
    fullName: string;
    contactNumber?: string | null;
    vcode: string;
    positionTitle?: string | null;
  } | null>(null);
  const [isFailBackoutModalOpen, setIsFailBackoutModalOpen] = useState(false);
  const [failBackoutTargetCandidate, setFailBackoutTargetCandidate] = useState<{
    id: string;
    fullName: string;
    status: string;
    vcode: string;
    positionTitle?: string | null;
  } | null>(null);
  const [isReopenModalOpen, setIsReopenModalOpen] = useState(false);
  const [reopenTargetVacancy, setReopenTargetVacancy] = useState<{
    vcode: string;
    positionTitle?: string | null;
    storeName?: string | null;
    accountName?: string | null;
  } | null>(null);
  const [isClosureModalOpen, setIsClosureModalOpen] = useState(false);
  const [closureTargetVacancy, setClosureTargetVacancy] = useState<{
    vcode: string;
    positionTitle?: string | null;
    storeName?: string | null;
  } | null>(null);
  const [isEditHiredDateModalOpen, setIsEditHiredDateModalOpen] = useState(false);
  const [editHiredDateTargetCandidate, setEditHiredDateTargetCandidate] = useState<{
    id: string;
    fullName: string;
    vcode: string;
    hiredDate?: string | null;
  } | null>(null);
  const [successToast, setSuccessToast] = useState<{ message: string } | null>(null);

  const approveAllClosuresMutation = useApproveAllClosureRequests();
  const reviewClosureMutation = useReviewClosureRequest();

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

  const summaryParams = useMemo(
    () => ({
      search,
      agingBucket: agingBucket || undefined,
      accountId: accountId || undefined,
      groupId: groupId || undefined,
      urgency: urgency || undefined,
      vacantFrom: vacantFrom || undefined,
      vacantTo: vacantTo || undefined,
      page: 1,
      pageSize: 1,
    }),
    [accountId, agingBucket, groupId, search, urgency, vacantFrom, vacantTo],
  );

  const summaryQuery = useQuery({
    queryKey: [
      "vacancy-summary",
      search,
      agingBucket,
      accountId,
      groupId,
      urgency,
      vacantFrom,
      vacantTo,
    ],
    queryFn: () => getVacancySummary(summaryParams),
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

  const tabCounts: Record<VacancyStatus, number> = useMemo(() => {
    const summary = summaryQuery.data;
    return {
      open: summary?.open ?? 0,
      pipeline: summary?.pipeline ?? 0,
      hired: summary?.hired ?? 0,
      closure: summary?.closure ?? 0,
      failed_backout: summary?.failedBackout ?? 0,
      with_applicant: summary?.pipeline ?? 0,
      rejected: summary?.rejected ?? 0,
      backout: summary?.backout ?? 0,
    };
  }, [summaryQuery.data]);

  const activeTabLabel =
    statusTabs.find((tab) => tab.value === status)?.label ?? "Open";

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

  function handleOpenAddApplicant(row: VacancyListItem) {
    setEndorseTargetVacancy({
      vcode: row.vcode,
      positionTitle: row.position_title,
      storeName: row.storeName,
      accountName: row.accountName,
      groupName: row.groupName,
      hrcoName: row.hrcoName,
    });
    setIsAddApplicantModalOpen(true);
  }

  function handleCandidateEndorsed(candidateName: string) {
    setSuccessToast({
      message: `Applicant "${candidateName}" endorsed successfully into vacancy ${endorseTargetVacancy?.vcode}. Requisition moved to Pipeline.`,
    });
    setTimeout(() => {
      setSuccessToast((prev) => (prev?.message.includes(candidateName) ? null : prev));
    }, 6000);
  }

  function handleAdvancePipeline(row: VacancyListItem) {
    setAdvanceTargetCandidate({
      id: row.applicantId || row.id,
      fullName: row.applicantName || "Candidate",
      contactNumber: row.contactNumber,
      status: (typeof row.pipelineStatus === "string" ? row.pipelineStatus : null) || "pipeline",
      vcode: row.vcode,
      positionTitle: row.position_title,
    });
    setIsAdvanceModalOpen(true);
  }

  function handleMarkHired(row: VacancyListItem) {
    setMarkHiredTargetCandidate({
      id: row.applicantId || row.id,
      fullName: row.applicantName || "Candidate",
      contactNumber: row.contactNumber,
      vcode: row.vcode,
      positionTitle: row.position_title,
    });
    setIsMarkHiredModalOpen(true);
  }

  function handleFailBackout(row: VacancyListItem) {
    setFailBackoutTargetCandidate({
      id: row.applicantId || row.id,
      fullName: row.applicantName || "Candidate",
      status: (typeof row.pipelineStatus === "string" ? row.pipelineStatus : null) || "pipeline",
      vcode: row.vcode,
      positionTitle: row.position_title,
    });
    setIsFailBackoutModalOpen(true);
  }

  function handleReopenVacancy(row: VacancyListItem) {
    setReopenTargetVacancy({
      vcode: row.vcode,
      positionTitle: row.position_title,
      storeName: row.storeName,
      accountName: row.accountName,
    });
    setIsReopenModalOpen(true);
  }

  function handleRequestClosure(row: VacancyListItem) {
    setClosureTargetVacancy({
      vcode: row.vcode,
      positionTitle: row.position_title,
      storeName: row.storeName,
    });
    setIsClosureModalOpen(true);
  }

  function handleReviewClosure(row: VacancyListItem, decision: "Approved" | "Rejected") {
    if (!row.closureRequestId) {
      // If closure request ID is not present, open closure details modal
      handleRequestClosure(row);
      return;
    }
    const actionLabel = decision === "Approved" ? "approve and close" : "reject closure request for";
    if (window.confirm(`Are you sure you want to ${actionLabel} ${row.vcode}?`)) {
      reviewClosureMutation.mutate(
        {
          requestId: row.closureRequestId,
          status: decision,
          reviewedBy: currentUser?.displayName || "Operations Admin",
          vcode: row.vcode,
        },
        {
          onSuccess: () => {
            setSuccessToast({
              message: `Closure request for ${row.vcode} ${decision.toLowerCase()} successfully.`,
            });
            retryVacancyReads();
          },
        },
      );
    }
  }

  function handleEditHiredDate(row: VacancyListItem) {
    setEditHiredDateTargetCandidate({
      id: row.applicantId || row.id,
      fullName: row.applicantName || "Candidate",
      vcode: row.vcode,
      hiredDate: row.hiredDate,
    });
    setIsEditHiredDateModalOpen(true);
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
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-4 text-gray-900">
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

      {successToast && (
        <div
          role="status"
          aria-live="polite"
          className="flex items-center justify-between gap-3 rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800 shadow-sm animate-in fade-in slide-in-from-top-2 duration-200"
        >
          <div className="flex items-center gap-2">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-emerald-100 text-emerald-700 font-bold text-xs">
              ✓
            </span>
            <span className="font-medium text-xs sm:text-sm">{successToast.message}</span>
          </div>
          <button
            type="button"
            onClick={() => setSuccessToast(null)}
            className="rounded p-1 text-emerald-600 hover:bg-emerald-100 hover:text-emerald-900 transition-colors"
            aria-label="Dismiss notification"
          >
            ✕
          </button>
        </div>
      )}

      {/* Unified workbench card: Status tabs & Filter toolbar */}
      <div className="flex flex-col gap-3 rounded-lg border border-border-default bg-surface-card p-3 shadow-xs">
        {/* Status Tabs Navigation */}
        <div
          aria-label="Vacancy status filter"
          className="flex flex-wrap items-center gap-2"
          role="tablist"
        >
          {statusTabs.map((tab) => {
            const isActive = status === tab.value;
            const count = tabCounts[tab.value];
            return (
              <button
                key={tab.value}
                aria-selected={isActive}
                className={`inline-flex items-center gap-2 rounded-full px-3.5 py-1.5 text-xs font-semibold transition-all duration-150 ${
                  isActive
                    ? "bg-slate-900 text-white shadow-xs"
                    : "border border-gray-200 bg-white text-gray-600 hover:border-gray-300 hover:bg-gray-50 hover:text-gray-900"
                }`}
                onClick={() => updateStatus(tab.value)}
                role="tab"
                type="button"
              >
                <span>{tab.label}</span>
                <span
                  className={`inline-flex items-center justify-center rounded-full px-2 py-0.5 text-[11px] font-bold ${
                    isActive
                      ? "bg-white/20 text-white"
                      : "border border-gray-200/80 bg-gray-100 text-gray-600"
                  }`}
                >
                  {summaryQuery.isLoading ? "–" : count}
                </span>
              </button>
            );
          })}
        </div>

        {/* Filter Bar Controls */}
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
      </div>

      {status === "closure" && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-slate-200 bg-slate-50 px-4 py-2.5 text-xs text-slate-700">
          <div className="flex items-center gap-2">
            <Archive className="h-4 w-4 text-slate-500" />
            <span>
              <strong>Closure Queue:</strong> Requisitions flagged for cessation or slot cancellation.
            </span>
          </div>
          <button
            type="button"
            disabled={approveAllClosuresMutation.isPending || rows.length === 0}
            onClick={() => {
              if (
                window.confirm(
                  "Are you sure you want to approve all pending vacancy closure requests? This will close matching requisitions.",
                )
              ) {
                approveAllClosuresMutation.mutate(undefined, {
                  onSuccess: () => {
                    setSuccessToast({
                      message: "All pending closure requests approved successfully.",
                    });
                    retryVacancyReads();
                  },
                });
              }
            }}
            className="inline-flex items-center gap-1.5 rounded-md border border-slate-300 bg-white px-3 py-1 font-semibold text-slate-700 hover:bg-slate-100 disabled:opacity-50 transition shadow-xs"
          >
            {approveAllClosuresMutation.isPending
              ? "Approving..."
              : "Approve All Pending Closures"}
          </button>
        </div>
      )}

      <VacancyTable
        errorKind={listErrorKind}
        isLoading={listQuery.isLoading}
        onPageChange={updatePage}
        onRetry={retryVacancyReads}
        onSelect={selectVacancy}
        onAddApplicant={handleOpenAddApplicant}
        onAdvancePipeline={handleAdvancePipeline}
        onMarkHired={handleMarkHired}
        onFailBackout={handleFailBackout}
        onReopenVacancy={handleReopenVacancy}
        onRequestClosure={handleRequestClosure}
        onReviewClosure={handleReviewClosure}
        onEditHiredDate={handleEditHiredDate}
        page={page}
        pageSize={pageSize}
        rows={rows}
        selectedId={selectedVacancyId}
        status={status}
        statusDescription={activeTabLabel}
        totalCount={totalCount}
      />

      <VacancyDetailDrawer
        vacancyId={selectedVacancyId}
        onClose={() => setSelectedVacancyId(null)}
        isFreezeModeActive={isFreezeModeActive}
      />

      {isAddApplicantModalOpen && endorseTargetVacancy && (
        <AddApplicantModal
          isOpen={isAddApplicantModalOpen}
          onClose={() => {
            setIsAddApplicantModalOpen(false);
            setEndorseTargetVacancy(null);
          }}
          vacancy={endorseTargetVacancy}
          onSuccess={handleCandidateEndorsed}
        />
      )}

      {isAdvanceModalOpen && advanceTargetCandidate && (
        <AdvancePipelineModal
          isOpen={isAdvanceModalOpen}
          onClose={() => {
            setIsAdvanceModalOpen(false);
            setAdvanceTargetCandidate(null);
          }}
          applicant={advanceTargetCandidate}
          onSuccess={() => {
            setIsAdvanceModalOpen(false);
            setAdvanceTargetCandidate(null);
            setSuccessToast({
              message: `Applicant pipeline stage advanced successfully.`,
            });
            retryVacancyReads();
          }}
        />
      )}

      {isMarkHiredModalOpen && markHiredTargetCandidate && (
        <MarkHiredModal
          isOpen={isMarkHiredModalOpen}
          onClose={() => {
            setIsMarkHiredModalOpen(false);
            setMarkHiredTargetCandidate(null);
          }}
          applicant={markHiredTargetCandidate}
          onSuccess={(workerName) => {
            setIsMarkHiredModalOpen(false);
            setMarkHiredTargetCandidate(null);
            setSuccessToast({
              message: `Candidate ${workerName} marked as hired and deployed successfully! Requisition moved to Hired queue.`,
            });
            retryVacancyReads();
          }}
        />
      )}

      {isFailBackoutModalOpen && failBackoutTargetCandidate && (
        <FailBackoutModal
          isOpen={isFailBackoutModalOpen}
          onClose={() => {
            setIsFailBackoutModalOpen(false);
            setFailBackoutTargetCandidate(null);
          }}
          applicant={failBackoutTargetCandidate}
          onSuccess={() => {
            setIsFailBackoutModalOpen(false);
            setFailBackoutTargetCandidate(null);
            setSuccessToast({
              message: `Applicant status updated. Vacancy slot returned to Open pooling queue.`,
            });
            retryVacancyReads();
          }}
        />
      )}

      {isReopenModalOpen && reopenTargetVacancy && (
        <ReopenVacancyModal
          isOpen={isReopenModalOpen}
          onClose={() => {
            setIsReopenModalOpen(false);
            setReopenTargetVacancy(null);
          }}
          vacancy={reopenTargetVacancy}
          onSuccess={() => {
            setIsReopenModalOpen(false);
            setReopenTargetVacancy(null);
            setSuccessToast({
              message: `Vacancy slot ${reopenTargetVacancy.vcode} reopened successfully into the Open queue.`,
            });
            retryVacancyReads();
          }}
        />
      )}

      {isClosureModalOpen && closureTargetVacancy && (
        <RequestVacancyClosureModal
          isOpen={isClosureModalOpen}
          onClose={() => {
            setIsClosureModalOpen(false);
            setClosureTargetVacancy(null);
          }}
          vacancy={closureTargetVacancy}
          onSuccess={() => {
            setIsClosureModalOpen(false);
            setClosureTargetVacancy(null);
            setSuccessToast({
              message: `Closure request submitted for vacancy ${closureTargetVacancy.vcode}. Moved to Closure review queue.`,
            });
            retryVacancyReads();
          }}
        />
      )}

      {isEditHiredDateModalOpen && editHiredDateTargetCandidate && (
        <EditHiredDateModal
          isOpen={isEditHiredDateModalOpen}
          onClose={() => {
            setIsEditHiredDateModalOpen(false);
            setEditHiredDateTargetCandidate(null);
          }}
          applicant={editHiredDateTargetCandidate}
          onSuccess={() => {
            setIsEditHiredDateModalOpen(false);
            setEditHiredDateTargetCandidate(null);
            setSuccessToast({
              message: `Hired date updated successfully. 15-day display window recalibrated.`,
            });
            retryVacancyReads();
          }}
        />
      )}

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
