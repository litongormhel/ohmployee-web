"use client";

import React, { useCallback, useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Clock,
  FileText,
  Filter,
  Loader2,
  RefreshCw,
  Search,
  ShieldAlert,
  Users2,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import {
  getRoleLevel,
  isOwner,
  normalizeRole,
  AppRole,
} from "@/lib/rbac";
import { Modal } from "@/components/shared/Modal";
import { TablePagination } from "@/components/shared/TablePagination";
import {
  GhostEmployeeCase,
  submitGhostVerificationNote,
  updateGhostCaseStatus,
  useGhostEmployeesQuery,
} from "@/lib/queries/dataControl";
import { useQueryClient } from "@tanstack/react-query";

export interface GhostDetectionCenterModalProps {
  isOpen: boolean;
  onClose: () => void;
  initialAccount?: string | null;
}

type TabCategory = "open" | "type_a" | "type_b" | "breached" | "resolved";

export function GhostDetectionCenterModal({
  isOpen,
  onClose,
  initialAccount,
}: GhostDetectionCenterModalProps) {
  const currentUser = useCurrentUser();
  const queryClient = useQueryClient();

  const roleName = currentUser?.roleName ?? currentUser?.roleKey ?? "Viewer";
  const role = normalizeRole(roleName);
  const roleLevel = getRoleLevel(currentUser);
  const isSuperAdmin = roleLevel >= 100 || isOwner(currentUser);
  const isHeadAdmin = roleLevel >= 90;
  const isEncoder = role === AppRole.ENCODER;
  const canMutateStatus = isSuperAdmin || isHeadAdmin || isEncoder;

  // Filters & Tabs
  const [activeTab, setActiveTab] = useState<TabCategory>("open");
  const [selectedAccount, setSelectedAccount] = useState<string>(initialAccount || "ALL");
  const [searchQuery, setSearchQuery] = useState("");
  const [currentPage, setCurrentPage] = useState(1);
  const PAGE_SIZE = 12;

  // Selected Case for Action / Triage
  const [activeCase, setActiveCase] = useState<GhostEmployeeCase | null>(null);
  const [isActionModalOpen, setIsActionModalOpen] = useState(false);
  const [newVerificationNote, setNewVerificationNote] = useState("");
  const [targetStatus, setTargetStatus] = useState<
    "Cleared" | "For Encoding" | "Confirmed Ghost" | "For Termination" | "Under Investigation"
  >("Under Investigation");
  const [actionRemarks, setActionRemarks] = useState("");
  const [assignedEncoderName, setAssignedEncoderName] = useState("");
  const [isSubmittingAction, setIsSubmittingAction] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  // Query Ghost cases
  const statusCategory = activeTab === "resolved" ? "resolved" : "all";
  const ghostTypeFilter =
    activeTab === "type_a" ? "Type A" : activeTab === "type_b" ? "Type B" : undefined;

  const {
    data: allCases = [],
    isLoading,
    refetch,
    isRefetching,
  } = useGhostEmployeesQuery({
    account: selectedAccount !== "ALL" ? selectedAccount : undefined,
    statusCategory,
    ghostType: ghostTypeFilter,
  });

  // Unique Accounts for Dropdown
  const uniqueAccounts = useMemo(() => {
    const set = new Set<string>();
    allCases.forEach((c) => {
      if (c.account) set.add(c.account);
    });
    return Array.from(set).sort();
  }, [allCases]);

  // SLA Calculation Helpers
  const [currentTimestamp] = useState(() => Date.now());

  const getAgeHours = useCallback(
    (createdAt: string) => {
      const created = new Date(createdAt).getTime();
      return Math.max(0, (currentTimestamp - created) / (1000 * 60 * 60));
    },
    [currentTimestamp]
  );

  const isBreachedSla = useCallback(
    (createdAt: string, status: string) => {
      const isClosed = ["Cleared", "Resolved", "Auto Resolved", "Confirmed Ghost", "For Termination"].includes(
        status
      );
      if (isClosed) return false;
      return getAgeHours(createdAt) > 7 * 24; // > 7 days (1 week)
    },
    [getAgeHours]
  );

  // KPI Metrics
  const metrics = useMemo(() => {
    let openCount = 0;
    let typeACount = 0;
    let typeBCount = 0;
    let breachedCount = 0;
    let resolvedCount = 0;

    allCases.forEach((c) => {
      const isClosed = ["Cleared", "Resolved", "Auto Resolved", "Confirmed Ghost", "For Termination"].includes(
        c.status
      );
      if (!isClosed) {
        openCount++;
        if (c.ghostType === "Type A") typeACount++;
        if (c.ghostType === "Type B") typeBCount++;
        if (isBreachedSla(c.createdAt, c.status)) breachedCount++;
      } else {
        resolvedCount++;
      }
    });

    return { openCount, typeACount, typeBCount, breachedCount, resolvedCount };
  }, [allCases, isBreachedSla]);

  // Tab Filtering & Search
  const filteredCases = useMemo(() => {
    return allCases.filter((item) => {
      const isClosed = ["Cleared", "Resolved", "Auto Resolved", "Confirmed Ghost", "For Termination"].includes(
        item.status
      );

      if (activeTab === "open" && isClosed) return false;
      if (activeTab === "type_a" && (isClosed || item.ghostType !== "Type A")) return false;
      if (activeTab === "type_b" && (isClosed || item.ghostType !== "Type B")) return false;
      if (activeTab === "breached" && !isBreachedSla(item.createdAt, item.status)) return false;
      if (activeTab === "resolved" && !isClosed) return false;

      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase().trim();
        const matchesNo = item.employeeNo.toLowerCase().includes(q);
        const matchesName = item.fullName.toLowerCase().includes(q);
        const matchesAccount = (item.account || "").toLowerCase().includes(q);
        const matchesStore = (item.storeName || "").toLowerCase().includes(q);
        if (!matchesNo && !matchesName && !matchesAccount && !matchesStore) return false;
      }

      return true;
    });
  }, [allCases, activeTab, isBreachedSla, searchQuery]);

  // Pagination
  const totalPages = Math.max(1, Math.ceil(filteredCases.length / PAGE_SIZE));
  const safePage = Math.min(currentPage, totalPages);
  const paginatedCases = useMemo(() => {
    const startIndex = (safePage - 1) * PAGE_SIZE;
    return filteredCases.slice(startIndex, startIndex + PAGE_SIZE);
  }, [filteredCases, safePage]);

  // Handle Action Trigger
  const handleOpenActionModal = (c: GhostEmployeeCase) => {
    setActiveCase(c);
    setNewVerificationNote("");
    setTargetStatus(
      c.status === "Under Investigation" || c.status === "For Encoding" ? c.status : "Under Investigation"
    );
    setActionRemarks(c.resolutionRemarks || "");
    setAssignedEncoderName(c.assignedEncoder || "");
    setActionError(null);
    setIsActionModalOpen(true);
  };

  const handleExecuteAction = async () => {
    if (!activeCase) return;
    setIsSubmittingAction(true);
    setActionError(null);

    try {
      const authorName = currentUser?.displayName || currentUser?.email || "Operations Actor";
      const authorRole = roleName;

      // 1. If verification note provided, submit it
      if (newVerificationNote.trim()) {
        await submitGhostVerificationNote({
          caseId: activeCase.id,
          note: newVerificationNote.trim(),
          authorName,
          authorRole,
        });
      }

      // 2. If user has mutation rights and changed status / remarks
      if (canMutateStatus && targetStatus !== activeCase.status) {
        if (!actionRemarks.trim()) {
          throw new Error("Remarks / operational explanation is required when changing status.");
        }
        await updateGhostCaseStatus({
          caseId: activeCase.id,
          status: targetStatus,
          actorName,
          actorRole,
          remarks: actionRemarks.trim(),
          assignedEncoder: targetStatus === "For Encoding" ? assignedEncoderName.trim() : undefined,
        });
      }

      await queryClient.invalidateQueries({ queryKey: ["ghost-employees"] });
      setIsActionModalOpen(false);
      setActiveCase(null);
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Failed to execute triage action.");
    } finally {
      setIsSubmittingAction(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={
        <div className="flex items-center gap-2.5">
          <ShieldAlert className="h-5 w-5 text-brand-primary" />
          <span>Ghost Employees Detection Center</span>
        </div>
      }
      subtitle="Weekly MIKA biometric discrepancy monitoring, Type A/B anomaly classification, and 1-week resolution SLA"
      maxWidthClass="max-w-6xl"
      footer={
        <div className="flex items-center justify-between w-full">
          <div className="flex items-center gap-2 text-xs text-text-muted">
            <span>SLA Target: 1 Week (7 Days)</span>
            <span>•</span>
            <span>Trigger: MIKA Approved Ingestion</span>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl border border-border-default bg-surface-primary px-4 py-2 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer"
          >
            Close
          </button>
        </div>
      }
    >
      <div className="space-y-5">
        {/* KPI Strip */}
        <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
          <div
            onClick={() => setActiveTab("open")}
            className={`p-3 rounded-xl border transition cursor-pointer ${
              activeTab === "open"
                ? "bg-brand-primary/10 border-brand-primary/40 shadow-xs"
                : "bg-surface-muted/50 border-border-subtle hover:bg-surface-hover/50"
            }`}
          >
            <span className="text-xs text-text-secondary block font-medium">Open Cases</span>
            <span className="text-xl font-bold font-mono text-text-primary mt-1 block">
              {metrics.openCount}
            </span>
          </div>

          <div
            onClick={() => setActiveTab("type_a")}
            className={`p-3 rounded-xl border transition cursor-pointer ${
              activeTab === "type_a"
                ? "bg-amber-500/10 border-amber-500/40 shadow-xs"
                : "bg-surface-muted/50 border-border-subtle hover:bg-surface-hover/50"
            }`}
          >
            <span className="text-xs text-amber-500 block font-medium">Type A (Unregistered)</span>
            <span className="text-xl font-bold font-mono text-amber-500 mt-1 block">
              {metrics.typeACount}
            </span>
          </div>

          <div
            onClick={() => setActiveTab("type_b")}
            className={`p-3 rounded-xl border transition cursor-pointer ${
              activeTab === "type_b"
                ? "bg-rose-500/10 border-rose-500/40 shadow-xs"
                : "bg-surface-muted/50 border-border-subtle hover:bg-surface-hover/50"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-xs text-rose-500 font-medium">Type B (Inactive)</span>
              <span className="rounded-full bg-rose-500/20 text-rose-400 text-[10px] px-1.5 py-0.2 font-bold">
                CRITICAL
              </span>
            </div>
            <span className="text-xl font-bold font-mono text-rose-500 mt-1 block">
              {metrics.typeBCount}
            </span>
          </div>

          <div
            onClick={() => setActiveTab("breached")}
            className={`p-3 rounded-xl border transition cursor-pointer ${
              activeTab === "breached"
                ? "bg-red-500/15 border-red-500/50 shadow-xs"
                : "bg-surface-muted/50 border-border-subtle hover:bg-surface-hover/50"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-xs text-red-400 font-medium">Breached SLA (&gt;7d)</span>
              {metrics.breachedCount > 0 && (
                <span className="relative flex h-2 w-2">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"></span>
                  <span className="relative inline-flex rounded-full h-2 w-2 bg-red-500"></span>
                </span>
              )}
            </div>
            <span className="text-xl font-bold font-mono text-red-400 mt-1 block">
              {metrics.breachedCount}
            </span>
          </div>

          <div
            onClick={() => setActiveTab("resolved")}
            className={`p-3 rounded-xl border transition cursor-pointer ${
              activeTab === "resolved"
                ? "bg-emerald-500/10 border-emerald-500/40 shadow-xs"
                : "bg-surface-muted/50 border-border-subtle hover:bg-surface-hover/50"
            }`}
          >
            <span className="text-xs text-emerald-500 block font-medium">Resolved History</span>
            <span className="text-xl font-bold font-mono text-emerald-500 mt-1 block">
              {metrics.resolvedCount}
            </span>
          </div>
        </div>

        {/* Filter Strip */}
        <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3">
          {/* Tabs */}
          <div className="flex items-center gap-1 overflow-x-auto no-scrollbar border-b border-border-subtle pb-1">
            <button
              type="button"
              onClick={() => {
                setActiveTab("open");
                setCurrentPage(1);
              }}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition cursor-pointer ${
                activeTab === "open"
                  ? "bg-brand-primary text-white shadow-2xs"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              All Open ({metrics.openCount})
            </button>
            <button
              type="button"
              onClick={() => {
                setActiveTab("type_a");
                setCurrentPage(1);
              }}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition cursor-pointer ${
                activeTab === "type_a"
                  ? "bg-amber-600 text-white shadow-2xs"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              Type A ({metrics.typeACount})
            </button>
            <button
              type="button"
              onClick={() => {
                setActiveTab("type_b");
                setCurrentPage(1);
              }}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition cursor-pointer ${
                activeTab === "type_b"
                  ? "bg-rose-600 text-white shadow-2xs"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              Type B Inactive ({metrics.typeBCount})
            </button>
            <button
              type="button"
              onClick={() => {
                setActiveTab("breached");
                setCurrentPage(1);
              }}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition cursor-pointer ${
                activeTab === "breached"
                  ? "bg-red-600 text-white shadow-2xs"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              Breached SLA ({metrics.breachedCount})
            </button>
            <button
              type="button"
              onClick={() => {
                setActiveTab("resolved");
                setCurrentPage(1);
              }}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition cursor-pointer ${
                activeTab === "resolved"
                  ? "bg-emerald-600 text-white shadow-2xs"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              Resolved ({metrics.resolvedCount})
            </button>
          </div>

          {/* Account Selector & Search */}
          <div className="flex items-center gap-2">
            <div className="relative min-w-[160px]">
              <select
                aria-label="Filter ghost employees by account"
                value={selectedAccount}
                onChange={(e) => {
                  setSelectedAccount(e.target.value);
                  setCurrentPage(1);
                }}
                className="w-full rounded-xl border border-border-default bg-surface-primary py-1.5 pl-3 pr-8 text-xs font-medium text-text-primary hover:border-border-strong focus:outline-none focus:ring-1 focus:ring-brand-primary cursor-pointer appearance-none"
              >
                <option value="ALL">All Accounts</option>
                {uniqueAccounts.map((acct) => (
                  <option key={acct} value={acct}>
                    {acct}
                  </option>
                ))}
              </select>
              <Filter className="absolute right-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-text-muted pointer-events-none" />
            </div>

            <div className="relative w-48 sm:w-56">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => {
                  setSearchQuery(e.target.value);
                  setCurrentPage(1);
                }}
                placeholder="Search employee # or name..."
                className="w-full rounded-xl border border-border-default bg-surface-primary py-1.5 pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary"
              />
            </div>

            <button
              type="button"
              onClick={() => refetch()}
              disabled={isRefetching}
              title="Refresh ghost records"
              className="p-1.5 rounded-xl border border-border-default bg-surface-primary text-text-secondary hover:text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
            >
              <RefreshCw className={`h-4 w-4 ${isRefetching ? "animate-spin" : ""}`} />
            </button>
          </div>
        </div>

        {/* Cases Table */}
        {isLoading ? (
          <div className="flex justify-center items-center py-20 text-xs text-text-muted">
            <Loader2 className="h-6 w-6 animate-spin mr-2.5 text-brand-primary" />
            Loading ghost employee cases...
          </div>
        ) : filteredCases.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted bg-surface-muted/20">
            <CheckCircle2 className="h-8 w-8 text-emerald-500/70 mx-auto mb-2" />
            <p className="font-semibold text-text-primary text-sm">No Ghost Cases Found</p>
            <p className="mt-1 text-text-muted max-w-sm mx-auto">
              All active biometric records in this account match active Plantilla entries, or cases have been resolved.
            </p>
          </div>
        ) : (
          <div className="rounded-2xl border border-border-default bg-surface-primary overflow-hidden shadow-2xs">
            <div className="overflow-x-auto max-h-[460px] overflow-y-auto">
              <table className="w-full text-left text-sm">
                <thead className="bg-surface-subtle border-b border-border-default sticky top-0 text-xs text-text-muted font-bold z-10">
                  <tr>
                    <th className="py-2.5 px-4">Employee</th>
                    <th className="py-2.5 px-4">Account & Store</th>
                    <th className="py-2.5 px-4">Anomaly Type</th>
                    <th className="py-2.5 px-4">Status</th>
                    <th className="py-2.5 px-4">SLA / Age</th>
                    <th className="py-2.5 px-4 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle bg-surface-primary text-xs">
                  {paginatedCases.map((c) => {
                    const breached = isBreachedSla(c.createdAt, c.status);
                    const ageHours = Math.round(getAgeHours(c.createdAt));
                    const ageDays = Math.floor(ageHours / 24);

                    return (
                      <tr key={c.id} className="hover:bg-surface-hover/60 transition-colors">
                        <td className="py-3 px-4">
                          <span className="font-mono font-bold text-text-primary block text-xs">
                            {c.employeeNo}
                          </span>
                          <span className="font-medium text-text-primary block mt-0.5">
                            {c.fullName}
                          </span>
                          {c.position && (
                            <span className="text-[11px] text-text-muted block">{c.position}</span>
                          )}
                        </td>

                        <td className="py-3 px-4">
                          <span className="font-semibold text-text-primary block">
                            {c.account || "—"}
                          </span>
                          <span className="text-text-secondary text-[11px] block mt-0.5">
                            {c.storeName || "Unassigned Store"}
                          </span>
                        </td>

                        <td className="py-3 px-4">
                          {c.ghostType === "Type B" ? (
                            <span className="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-bold bg-rose-500/15 text-rose-400 border border-rose-500/30">
                              <AlertTriangle className="h-3 w-3" /> Type B (Inactive)
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-bold bg-amber-500/15 text-amber-500 border border-amber-500/30">
                              <Users2 className="h-3 w-3" /> Type A (Unregistered)
                            </span>
                          )}
                        </td>

                        <td className="py-3 px-4">
                          <div className="space-y-1">
                            <span
                              className={`inline-block rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                                c.status === "Cleared" || c.status === "Auto Resolved" || c.status === "Resolved"
                                  ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30"
                                  : c.status === "For Encoding"
                                  ? "bg-blue-500/15 text-blue-400 border border-blue-500/30"
                                  : c.status === "Confirmed Ghost" || c.status === "For Termination"
                                  ? "bg-red-500/20 text-red-400 border border-red-500/40"
                                  : "bg-surface-subtle text-text-secondary border border-border-default"
                              }`}
                            >
                              {c.status}
                            </span>
                            {c.assignedEncoder && (
                              <span className="text-[10px] text-text-muted block">
                                Encoder: {c.assignedEncoder}
                              </span>
                            )}
                          </div>
                        </td>

                        <td className="py-3 px-4">
                          <div className="space-y-0.5">
                            {breached ? (
                              <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold bg-red-500/20 text-red-400 border border-red-500/40 animate-pulse">
                                <Clock className="h-2.5 w-2.5" /> &gt;7d Breached
                              </span>
                            ) : ageHours > 48 ? (
                              <span className="inline-flex items-center gap-1 text-[11px] text-amber-500 font-medium">
                                <Clock className="h-3 w-3" /> {ageDays}d {ageHours % 24}h old
                              </span>
                            ) : (
                              <span className="inline-flex items-center gap-1 text-[11px] text-text-muted">
                                <Clock className="h-3 w-3" /> {ageHours}h old
                              </span>
                            )}
                            <span className="text-[10px] text-text-muted block">
                              Detected: {new Date(c.createdAt).toLocaleDateString()}
                            </span>
                          </div>
                        </td>

                        <td className="py-3 px-4 text-right">
                          <button
                            type="button"
                            onClick={() => handleOpenActionModal(c)}
                            className="rounded-xl border border-border-default bg-surface-primary px-3 py-1 text-xs font-semibold text-text-primary hover:border-brand-primary hover:text-brand-primary transition cursor-pointer shadow-2xs"
                          >
                            {canMutateStatus ? "Triage / Resolve" : "Verify / Note"}
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <div className="p-3 border-t border-border-default">
              <TablePagination
                page={safePage}
                pageSize={PAGE_SIZE}
                totalCount={filteredCases.length}
                onPageChange={setCurrentPage}
              />
            </div>
          </div>
        )}
      </div>

      {/* Case Action / Ground Verification Modal */}
      {isActionModalOpen && activeCase && (
        <Modal
          isOpen={isActionModalOpen}
          onClose={() => setIsActionModalOpen(false)}
          title={
            <div className="flex items-center gap-2">
              <FileText className="h-5 w-5 text-brand-primary" />
              <span>Ghost Case Triage: {activeCase.employeeNo}</span>
            </div>
          }
          subtitle={`${activeCase.fullName} • ${activeCase.account || "No Account"} • ${activeCase.storeName || "No Store"}`}
          maxWidthClass="max-w-2xl"
          footer={
            <div className="flex items-center justify-between w-full">
              <button
                type="button"
                onClick={() => setIsActionModalOpen(false)}
                disabled={isSubmittingAction}
                className="rounded-xl border border-border-default bg-surface-primary px-4 py-2 text-xs font-semibold text-text-secondary hover:text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleExecuteAction}
                disabled={isSubmittingAction}
                className="rounded-xl bg-brand-primary text-white px-5 py-2 text-xs font-semibold shadow-xs hover:bg-brand-primary/90 transition cursor-pointer disabled:opacity-50 inline-flex items-center gap-2"
              >
                {isSubmittingAction && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                {canMutateStatus ? "Save Triage Action" : "Submit Verification Note"}
              </button>
            </div>
          }
        >
          <div className="space-y-4">
            {/* Meta Alert */}
            <div className="p-3.5 rounded-xl border border-border-subtle bg-surface-muted/40 space-y-1.5 text-xs">
              <div className="flex items-center justify-between">
                <span className="font-semibold text-text-primary">Anomaly Classification</span>
                <span
                  className={`rounded-full px-2 py-0.5 font-bold text-[10px] ${
                    activeCase.ghostType === "Type B"
                      ? "bg-rose-500/20 text-rose-400 border border-rose-500/30"
                      : "bg-amber-500/20 text-amber-500 border border-amber-500/30"
                  }`}
                >
                  {activeCase.ghostType === "Type B" ? "Type B: Inactive / Separated" : "Type A: Unregistered"}
                </span>
              </div>
              <p className="text-text-muted">
                {activeCase.ghostType === "Type B"
                  ? "High Severity: This employee is marked Inactive/Separated in Plantilla masterfile but their biometric record still clocked attendance."
                  : "Needs Verification: This employee number does not physically exist in active Plantilla. Please confirm if they are on duty or pending encoding."}
              </p>
            </div>

            {/* Existing Ground Notes History */}
            {activeCase.resolutionNotes && (
              <div className="space-y-1.5">
                <span className="text-xs font-semibold text-text-primary block">
                  Ground Verification & Ops Notes Trail
                </span>
                <div className="rounded-xl border border-border-default bg-surface-muted/30 p-3 text-xs text-text-secondary whitespace-pre-wrap max-h-36 overflow-y-auto font-mono">
                  {activeCase.resolutionNotes}
                </div>
              </div>
            )}

            {/* Field Ops Input: Ground Verification Note */}
            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-text-primary block">
                {canMutateStatus ? "Append Operational Note (Optional)" : "Add Operational Verification Note (Required for Field Ops)"}
              </label>
              <textarea
                rows={3}
                value={newVerificationNote}
                onChange={(e) => setNewVerificationNote(e.target.value)}
                placeholder="e.g. Confirmed active at branch, deployed last Monday, awaiting employee number from HR..."
                className="w-full rounded-xl border border-border-default bg-surface-primary p-3 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary"
              />
              <span className="text-[11px] text-text-muted block">
                Your note will be timestamped and permanently attributed to your name and role.
              </span>
            </div>

            {/* Admin & Encoder Action Panel */}
            {canMutateStatus ? (
              <div className="border-t border-border-subtle pt-4 space-y-3">
                <span className="text-xs font-bold text-text-primary block">
                  Administrative Status Mutation
                </span>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <label className="text-xs font-medium text-text-secondary block">
                      Change Case Status
                    </label>
                    <select
                      aria-label="Change ghost case status"
                      value={targetStatus}
                      onChange={(e) =>
                        setTargetStatus(
                          e.target.value as "Cleared" | "For Encoding" | "Confirmed Ghost" | "For Termination" | "Under Investigation"
                        )
                      }
                      className="w-full rounded-xl border border-border-default bg-surface-primary py-2 px-3 text-xs text-text-primary focus:outline-none focus:ring-1 focus:ring-brand-primary"
                    >
                      <option value="Under Investigation">Under Investigation</option>
                      <option value="For Encoding">For Encoding (Assigns 72h Deadline)</option>
                      <option value="Cleared">Cleared (False Positive / Resolved)</option>
                      <option value="Confirmed Ghost">Confirmed Ghost (Fraud / Block Payroll)</option>
                      <option value="For Termination">For Termination</option>
                    </select>
                  </div>

                  {targetStatus === "For Encoding" && (
                    <div className="space-y-1">
                      <label className="text-xs font-medium text-text-secondary block">
                        Assigned Encoder
                      </label>
                      <input
                        type="text"
                        value={assignedEncoderName}
                        onChange={(e) => setAssignedEncoderName(e.target.value)}
                        placeholder="Enter Encoder username or name..."
                        className="w-full rounded-xl border border-border-default bg-surface-primary py-2 px-3 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary"
                      />
                    </div>
                  )}
                </div>

                <div className="space-y-1">
                  <label className="text-xs font-medium text-text-secondary block">
                    Action Remarks / Audit Explanation (Mandatory for status change)
                  </label>
                  <input
                    type="text"
                    value={actionRemarks}
                    onChange={(e) => setActionRemarks(e.target.value)}
                    placeholder="Provide operational reason for this status change..."
                    className="w-full rounded-xl border border-border-default bg-surface-primary py-2 px-3 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary"
                  />
                </div>
              </div>
            ) : (
              <div className="rounded-xl bg-surface-muted/40 p-3 border border-border-subtle text-xs text-text-muted">
                ℹ️ As Field Operations (HRCO/TL/ATL), you can inspect this case and append verified ground notes. The final status resolution will be executed by the Data Team / Head Admin.
              </div>
            )}

            {actionError && (
              <div className="rounded-xl bg-danger-surface p-3 text-xs text-danger-text border border-danger-border flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}
          </div>
        </Modal>
      )}
    </Modal>
  );
}
