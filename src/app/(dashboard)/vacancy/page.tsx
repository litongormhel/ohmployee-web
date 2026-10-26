// app/(dashboard)/vacancy/page.tsx
"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  Archive,
  Briefcase,
  ChevronDown,
  Download,
  Loader2,
  ShieldOff,
  TrendingUp,
  UserCheck,
  UserMinus,
  RotateCcw,
} from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { AnimatedNumber } from "@/components/shared/AnimatedNumber";
import {
  VacancyTable,
  type VacancyStatus,
} from "@/components/vacancy/VacancyTable";
import { VacancyDetailDrawer } from "@/components/vacancy/VacancyDetailDrawer";
import { VacancyFilterToolbar } from "@/components/vacancy/VacancyFilterToolbar";
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
  EditApplicantModal,
  type EditApplicantTarget,
} from "@/components/vacancy/EditApplicantModal";
import { SavedViewsModal } from "@/components/vacancy/SavedViewsModal";
import {
  useVacancySavedViews,
  type VacancyFilterState,
  type VacancySavedView,
} from "@/components/vacancy/useVacancySavedViews";
import {
  VacancyDataError,
  downloadCsv,
  fetchVacanciesForExport,
  formatGroupName,
  getVacancySummary,
  listVacancies,
  useApproveAllClosureRequests,
  useReviewClosureRequest,
  useWithdrawVacancyClosureRequest,
  type VacancyListItem,
} from "@/lib/queries/vacancy";
import { getWebFreezeModeStatus } from "@/lib/queries/freeze";
import { isVacancyExportRole, useCurrentUser } from "@/lib/auth";
import { canReviewVacancyClosures } from "@/lib/rbac";
import { createClient } from "@/lib/supabase/client";

const statusTabs: Array<{
  value: VacancyStatus;
  label: string;
  icon: typeof Briefcase;
}> = [
  {
    value: "open",
    label: "Open",
    icon: Briefcase,
  },
  {
    value: "pipeline",
    label: "Pipeline",
    icon: TrendingUp,
  },
  {
    value: "hired",
    label: "Hired",
    icon: UserCheck,
  },
  {
    value: "closure",
    label: "Closure",
    icon: Archive,
  },
  {
    value: "failed_backout",
    label: "Failed / Backout",
    icon: UserMinus,
  },
];

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
  const [pageSize, setPageSize] = useState<number>(10);
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
    firstName?: string | null;
    lastName?: string | null;
    middleName?: string | null;
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
  const [isEditApplicantModalOpen, setIsEditApplicantModalOpen] = useState(false);
  const [editApplicantTargetCandidate, setEditApplicantTargetCandidate] = useState<EditApplicantTarget | null>(null);
  const [successToast, setSuccessToast] = useState<{ message: string } | null>(null);
  const [errorToast, setErrorToast] = useState<{ message: string } | null>(null);

  const [isExporting, setIsExporting] = useState(false);
  const [isExportMenuOpen, setIsExportMenuOpen] = useState(false);
  const exportDropdownRef = useRef<HTMLDivElement>(null);

  const { savedViews, saveView, updateView, deleteView } = useVacancySavedViews();
  const [isSavedViewsModalOpen, setIsSavedViewsModalOpen] = useState(false);

  const approveAllClosuresMutation = useApproveAllClosureRequests();
  const reviewClosureMutation = useReviewClosureRequest();
  const withdrawClosureMutation = useWithdrawVacancyClosureRequest();


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
    [accountId, agingBucket, groupId, page, pageSize, search, status, urgency, vacantFrom, vacantTo],
  );

  const currentFilters: VacancyFilterState = useMemo(
    () => ({
      status,
      search,
      accountId,
      groupId,
      agingBucket,
      urgency,
      vacantFrom,
      vacantTo,
    }),
    [status, search, accountId, groupId, agingBucket, urgency, vacantFrom, vacantTo],
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
  const canReviewClosures = useMemo(() => {
    return canReviewVacancyClosures(currentUser);
  }, [currentUser]);
  const canExport = useMemo(() => {
    return isVacancyExportRole(currentUser?.roleKey || currentUser?.roleName);
  }, [currentUser]);

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
        const resolved = formatGroupName(a.groupName, a.name);
        if (resolved && resolved !== "General / Direct" && resolved !== "General/Direct") {
          map.set(a.groupId, resolved);
        }
      }
    }
    // Restrict strictly to Group 1 through Group 5 and Moses HQ
    const allowedGroupPatterns = [/group\s*[1-5]/i, /moses\s*hq/i, /global\s*hq/i];
    return Array.from(map.entries())
      .map(([id, name]) => ({ id, name }))
      .filter((g) => allowedGroupPatterns.some((pattern) => pattern.test(g.name)))
      .sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
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

  function applySearch(event?: FormEvent<HTMLFormElement>) {
    event?.preventDefault();
    setSearch(searchDraft.trim());
    setPage(1);
    setSelectedVacancyId(null);
  }

  function handleClearSearch() {
    setSearchDraft("");
    setSearch("");
    setPage(1);
    setSelectedVacancyId(null);
  }

  function handleApplyAdvancedFilters(filters: {
    agingBucket: string;
    urgency: string;
    vacantFrom: string;
    vacantTo: string;
  }) {
    setAgingBucket(filters.agingBucket);
    setUrgency(filters.urgency);
    setVacantFrom(filters.vacantFrom);
    setVacantTo(filters.vacantTo);
    setPage(1);
    setSelectedVacancyId(null);
  }

  function handleResetAdvancedFilters() {
    setAgingBucket("");
    setUrgency("");
    setVacantFrom("");
    setVacantTo("");
    setPage(1);
    setSelectedVacancyId(null);
  }

  function handleClearAll() {
    setSearchDraft("");
    setSearch("");
    setAccountId("");
    setGroupId("");
    setAgingBucket("");
    setUrgency("");
    setVacantFrom("");
    setVacantTo("");
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
      firstName: row.applicantFirstName,
      lastName: row.applicantLastName,
      middleName: row.applicantMiddleName,
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

  function handleWithdrawClosure(row: VacancyListItem) {
    if (!row.vcode) return;
    if (
      window.confirm(
        `Are you sure you want to withdraw the pending closure request for ${row.vcode}? This will restore normal sourcing and pipeline operations.`,
      )
    ) {
      withdrawClosureMutation.mutate(
        {
          vcode: row.vcode,
          userId: currentUser?.authUserId || currentUser?.profileId || null,
        },
        {
          onSuccess: () => {
            setSuccessToast({
              message: `Closure request for ${row.vcode} withdrawn successfully.`,
            });
            retryVacancyReads();
          },
          onError: (err) => {
            setErrorToast({
              message: err instanceof Error ? err.message : "Failed to withdraw closure request.",
            });
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

  function handleEditApplicant(row: VacancyListItem) {
    setEditApplicantTargetCandidate({
      applicantId: row.applicantId || row.id,
      displayName: row.applicantName || "Candidate",
      firstName: row.applicantFirstName,
      middleName: row.applicantMiddleName,
      lastName: row.applicantLastName,
      contactNumber: row.contactNumber,
      profileEditCount: row.profileEditCount,
      statusLabel: typeof row.pipelineStatus === "string" ? row.pipelineStatus : row.derivedStatus,
      vcode: row.vcode,
      positionTitle: row.position_title,
    });
    setIsEditApplicantModalOpen(true);
  }

  function retryVacancyReads() {
    void summaryQuery.refetch();
    void listQuery.refetch();
  }

  function updatePage(nextPage: number) {
    setPage(nextPage);
    setSelectedVacancyId(null);
  }

  function handleApplySavedView(view: VacancySavedView) {
    setStatus(view.filters.status);
    setSearchDraft(view.filters.search || "");
    setSearch(view.filters.search || "");
    setAccountId(view.filters.accountId || "");
    setGroupId(view.filters.groupId || "");
    setAgingBucket(view.filters.agingBucket || "");
    setUrgency(view.filters.urgency || "");
    setVacantFrom(view.filters.vacantFrom || "");
    setVacantTo(view.filters.vacantTo || "");
    setPage(1);
    setSelectedVacancyId(null);
    setIsSavedViewsModalOpen(false);

    setSuccessToast({
      message: `Applied saved view "${view.name}".`,
    });
    setTimeout(() => {
      setSuccessToast((prev) => (prev?.message.includes(view.name) ? null : prev));
    }, 5000);
  }

  function handleSaveView(name: string, filters: VacancyFilterState) {
    saveView(name, filters);
    setSuccessToast({
      message: `Saved view preset "${name}" successfully.`,
    });
    setTimeout(() => {
      setSuccessToast((prev) => (prev?.message.includes(name) ? null : prev));
    }, 5000);
  }

  function handleUpdateView(id: string, name: string, filters: VacancyFilterState) {
    updateView(id, name, filters);
    setSuccessToast({
      message: `Updated view preset "${name}" with current filters.`,
    });
    setTimeout(() => {
      setSuccessToast((prev) => (prev?.message.includes(name) ? null : prev));
    }, 5000);
  }

  function handleDeleteView(id: string, name: string) {
    deleteView(id);
    setSuccessToast({
      message: `Deleted view preset "${name}".`,
    });
    setTimeout(() => {
      setSuccessToast((prev) => (prev?.message.includes(name) ? null : prev));
    }, 5000);
  }

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (
        exportDropdownRef.current &&
        !exportDropdownRef.current.contains(event.target as Node)
      ) {
        setIsExportMenuOpen(false);
      }
    }
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setIsExportMenuOpen(false);
      }
    }
    if (isExportMenuOpen) {
      document.addEventListener("mousedown", handleClickOutside);
      document.addEventListener("keydown", handleKeyDown);
      return () => {
        document.removeEventListener("mousedown", handleClickOutside);
        document.removeEventListener("keydown", handleKeyDown);
      };
    }
  }, [isExportMenuOpen]);

  async function handleExport(scope: "current_tab" | "all_statuses") {
    setIsExportMenuOpen(false);
    setIsExporting(true);
    setErrorToast(null);

    try {
      const exportFilters = {
        search: search || undefined,
        accountId: accountId || undefined,
        groupId: groupId || undefined,
        aging: agingBucket || undefined,
        urgency: urgency || undefined,
        dateFrom: vacantFrom || undefined,
        dateTo: vacantTo || undefined,
      };

      const result = await fetchVacanciesForExport(scope, status, exportFilters);
      downloadCsv(result.csv, result.filename);

      setSuccessToast({
        message: `Successfully exported ${result.rowCount} records to ${result.filename}`,
      });
      setTimeout(() => {
        setSuccessToast((prev) => (prev?.message.includes(result.filename) ? null : prev));
      }, 6000);
    } catch (err) {
      console.error("[vacancy export error]", err);
      const message = err instanceof Error ? err.message : "Failed to generate CSV export.";
      setErrorToast({ message: `Export failed: ${message}` });
      setTimeout(() => {
        setErrorToast(null);
      }, 6000);
    } finally {
      setIsExporting(false);
    }
  }

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-4 text-text-primary">
      <AdminPageHeader
        categoryTag="ADMIN PANEL"
        moduleName="Vacancy"
        title="Vacancy Management"
        subtitle="Monitor unfilled store vacancies, applicant pipeline, and aging requisitions."
        icon={Briefcase}
        primaryAction={{
          label: summaryQuery.isFetching || listQuery.isFetching ? "Refreshing..." : "Refresh Data",
          icon: RotateCcw,
          onClick: retryVacancyReads,
          disabled: summaryQuery.isFetching || listQuery.isFetching,
        }}
      />

      {isFreezeModeActive && (
        <div
          role="alert"
          aria-live="assertive"
          className="flex items-start gap-3 rounded-md border border-border-default bg-surface-muted px-4 py-3 text-sm text-text-primary"
        >
          <ShieldOff className="mt-0.5 h-5 w-5 shrink-0 text-text-muted" aria-hidden="true" />
          <div className="flex flex-col gap-0.5">
            <span className="font-semibold">Read-Only Emergency Mode Active</span>
            <span className="text-xs text-text-secondary">
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
          className="flex items-center justify-between gap-3 rounded-lg border border-border-default bg-surface-muted px-4 py-3 text-sm text-text-primary shadow-xs animate-in fade-in slide-in-from-top-2 duration-200"
        >
          <div className="flex items-center gap-2">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-brand-50 text-brand-700 font-bold text-xs">
              ✓
            </span>
            <span className="font-medium text-xs sm:text-sm">{successToast.message}</span>
          </div>
          <button
            type="button"
            onClick={() => setSuccessToast(null)}
            className="rounded p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary transition-colors cursor-pointer"
            aria-label="Dismiss notification"
          >
            ✕
          </button>
        </div>
      )}

      {errorToast && (
        <div
          role="alert"
          aria-live="assertive"
          className="flex items-center justify-between gap-3 rounded-lg border border-danger-border bg-danger-bg px-4 py-3 text-sm text-danger-text shadow-xs animate-in fade-in slide-in-from-top-2 duration-200"
        >
          <div className="flex items-center gap-2">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-surface-base text-danger-text font-bold text-xs border border-danger-border">
              ✕
            </span>
            <span className="font-semibold text-xs sm:text-sm">{errorToast.message}</span>
          </div>
          <button
            type="button"
            onClick={() => setErrorToast(null)}
            className="rounded p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary transition-colors cursor-pointer"
            aria-label="Dismiss error notification"
          >
            ✕
          </button>
        </div>
      )}

      {/* Status Tabs Navigation & Export Action */}
      <div
        aria-label="Vacancy status filter"
        className="flex items-center gap-2 rounded-lg border border-border-subtle bg-surface p-2 shadow-2xs"
      >
        <div
          role="tablist"
          className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none min-w-0"
        >
          {statusTabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = status === tab.value;
            const count = tabCounts[tab.value];
            return (
              <button
                key={tab.value}
                aria-selected={isActive}
                className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                  isActive
                    ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                    : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                }`}
                onClick={() => updateStatus(tab.value)}
                role="tab"
                type="button"
              >
                {Icon && (
                  <Icon
                    className={`w-4 h-4 shrink-0 transition-colors ${
                      isActive
                        ? "text-brand-700"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                  />
                )}
                <span>{tab.label}</span>
                <span
                  className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                    isActive
                      ? "bg-brand-600 text-white"
                      : "bg-surface-muted text-text-secondary border border-border-default"
                  }`}
                >
                  {summaryQuery.isLoading ? "–" : <AnimatedNumber value={count} />}
                </span>
              </button>
            );
          })}
        </div>

        {canExport && (
          <div className="ml-auto shrink-0 flex items-center relative" ref={exportDropdownRef}>
            <button
              type="button"
              disabled={isExporting}
              onClick={() => setIsExportMenuOpen((prev) => !prev)}
              aria-expanded={isExportMenuOpen}
              aria-haspopup="menu"
              className="h-9 text-xs font-semibold border border-border-subtle bg-surface hover:bg-surface-hover px-3 flex items-center gap-1.5 rounded-lg text-text-primary transition-colors disabled:opacity-60 disabled:cursor-not-allowed cursor-pointer"
            >
              {isExporting ? (
                <Loader2 className="w-4 h-4 shrink-0 animate-spin text-brand-600" />
              ) : (
                <Download className="w-4 h-4 shrink-0 text-text-secondary" />
              )}
              <span>{isExporting ? "Exporting..." : "Export Data"}</span>
              <ChevronDown
                className={`w-3.5 h-3.5 shrink-0 text-text-muted transition-transform duration-150 ${
                  isExportMenuOpen ? "rotate-180" : ""
                }`}
              />
            </button>

            {isExportMenuOpen && (
              <div
                role="menu"
                aria-label="Export options"
                className="absolute right-0 top-full mt-1.5 w-64 rounded-lg border border-border-subtle bg-surface p-1.5 shadow-lg z-50 animate-in fade-in zoom-in-95 duration-100"
              >
                <button
                  type="button"
                  role="menuitem"
                  onClick={() => handleExport("current_tab")}
                  disabled={isExporting}
                  className="w-full flex flex-col items-start px-3 py-2 text-left rounded-md hover:bg-surface-hover transition-colors group cursor-pointer text-text-primary"
                >
                  <div className="flex items-center justify-between w-full">
                    <span className="text-xs font-semibold group-hover:text-brand-700">
                      Export Current View
                    </span>
                    <span className="font-mono text-[11px] font-medium text-text-muted bg-surface-muted border border-border-default rounded px-1.5 py-0.5">
                      {summaryQuery.isLoading ? "–" : (tabCounts[status] ?? 0)}
                    </span>
                  </div>
                  <span className="text-[11px] text-text-muted mt-0.5">
                    {activeTabLabel} tab ({summaryQuery.isLoading ? "–" : (tabCounts[status] ?? 0)} records)
                  </span>
                </button>

                <div className="my-1 border-t border-border-subtle" />

                <button
                  type="button"
                  role="menuitem"
                  onClick={() => handleExport("all_statuses")}
                  disabled={isExporting}
                  className="w-full flex flex-col items-start px-3 py-2 text-left rounded-md hover:bg-surface-hover transition-colors group cursor-pointer text-text-primary"
                >
                  <div className="flex items-center justify-between w-full">
                    <span className="text-xs font-semibold group-hover:text-brand-700">
                      Export Masterlist
                    </span>
                    <span className="font-mono text-[11px] font-medium text-text-muted bg-surface-muted border border-border-default rounded px-1.5 py-0.5">
                      {summaryQuery.isLoading ? "–" : (summaryQuery.data?.total ?? 0)}
                    </span>
                  </div>
                  <span className="text-[11px] text-text-muted mt-0.5">
                    All Statuses: Open to Failed/Backout
                  </span>
                </button>
              </div>
            )}
          </div>
        )}
      </div>


      {/* Filter Toolbar */}
      <VacancyFilterToolbar
        searchDraft={searchDraft}
        onSearchChange={setSearchDraft}
        onSearchSubmit={applySearch}
        onClearSearch={handleClearSearch}
        accountId={accountId}
        onAccountChange={handleAccountChange}
        accounts={filteredAccounts}
        groupId={groupId}
        onGroupChange={handleGroupChange}
        groups={uniqueGroups}
        agingBucket={agingBucket}
        urgency={urgency}
        vacantFrom={vacantFrom}
        vacantTo={vacantTo}
        onApplyAdvancedFilters={handleApplyAdvancedFilters}
        onResetAdvancedFilters={handleResetAdvancedFilters}
        onClearAll={handleClearAll}
        onOpenSavedViews={() => setIsSavedViewsModalOpen(true)}
        savedViewsCount={savedViews.length}
        disabled={blocked}
      />

      {status === "closure" && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-border-default bg-surface-muted px-4 py-2.5 text-xs text-text-secondary">
          <div className="flex items-center gap-2">
            <Archive className="h-4 w-4 text-text-muted" />
            <span>
              <strong>Closure Queue:</strong> Requisitions flagged for cessation or slot cancellation.
            </span>
          </div>
          {canReviewClosures && (
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
              className="inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface px-3 py-1 font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary disabled:opacity-50 transition shadow-xs cursor-pointer"
            >
              {approveAllClosuresMutation.isPending
                ? "Approving..."
                : "Approve All Pending Closures"}
            </button>
          )}
        </div>
      )}

      <VacancyTable
        errorKind={listErrorKind}
        isLoading={listQuery.isLoading}
        onPageChange={updatePage}
        onPageSizeChange={(newPageSize) => {
          setPageSize(newPageSize);
          setPage(1);
          setSelectedVacancyId(null);
        }}
        onRetry={retryVacancyReads}
        onSelect={selectVacancy}
        onAddApplicant={handleOpenAddApplicant}
        onEditApplicant={handleEditApplicant}
        onAdvancePipeline={handleAdvancePipeline}
        onMarkHired={handleMarkHired}
        onFailBackout={handleFailBackout}
        onReopenVacancy={handleReopenVacancy}
        onRequestClosure={handleRequestClosure}
        onReviewClosure={handleReviewClosure}
        onWithdrawClosure={handleWithdrawClosure}
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
        status={status}
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

      {isEditApplicantModalOpen && editApplicantTargetCandidate && (
        <EditApplicantModal
          isOpen={isEditApplicantModalOpen}
          onClose={() => {
            setIsEditApplicantModalOpen(false);
            setEditApplicantTargetCandidate(null);
          }}
          applicant={editApplicantTargetCandidate}
          onSuccess={(updatedName) => {
            setIsEditApplicantModalOpen(false);
            setEditApplicantTargetCandidate(null);
            setSuccessToast({
              message: `Applicant profile for ${updatedName} updated successfully.`,
            });
            retryVacancyReads();
          }}
        />
      )}

      <SavedViewsModal
        isOpen={isSavedViewsModalOpen}
        onClose={() => setIsSavedViewsModalOpen(false)}
        currentFilters={currentFilters}
        accounts={accounts}
        groups={uniqueGroups}
        savedViews={savedViews}
        onSaveView={handleSaveView}
        onUpdateView={handleUpdateView}
        onDeleteView={handleDeleteView}
        onApplyView={handleApplySavedView}
      />

    </div>
  );
}
