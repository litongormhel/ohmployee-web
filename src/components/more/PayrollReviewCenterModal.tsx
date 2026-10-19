"use client";

import React, { useMemo, useState } from "react";
import {
  AlertCircle,
  CheckCircle2,
  ChevronRight,
  FileText,
  Loader2,
  MessageSquare,
  RefreshCw,
  X,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import {
  closePayrollReviewItem,
  closePayrollReviewSession,
  fetchPayrollReviewItems,
  PayrollReviewDetailItem,
  PayrollReviewSessionItem,
  submitOpsPayrollReviewComment,
  usePayrollReviewSessions,
} from "@/lib/queries/dataControl";

export interface PayrollReviewCenterModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function PayrollReviewCenterModal({
  isOpen,
  onClose,
}: PayrollReviewCenterModalProps) {
  const currentUser = useCurrentUser();

  // Status Filter: "All" | "Open" | "Closed"
  const [statusFilter, setStatusFilter] = useState<string>("All");

  // Selected Session Drilldown
  const [selectedSession, setSelectedSession] = useState<PayrollReviewSessionItem | null>(null);
  const [sessionItems, setSessionItems] = useState<PayrollReviewDetailItem[]>([]);
  const [isLoadingItems, setIsLoadingItems] = useState(false);
  const [itemStatusFilter, setItemStatusFilter] = useState<string>("All");

  // Comment & Resolution Drawer
  const [activeItem, setActiveItem] = useState<PayrollReviewDetailItem | null>(null);
  const [opsResponse, setOpsResponse] = useState<string>("Confirmed Correct");
  const [opsComment, setOpsComment] = useState<string>("");
  const [isSubmittingComment, setIsSubmittingComment] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const {
    data: sessions = [],
    refetch: refetchSessions,
    isLoading: isLoadingSessions,
  } = usePayrollReviewSessions(statusFilter === "All" ? undefined : statusFilter);

  const canManage = useMemo(() => {
    const role = (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
    return (
      role.includes("super_admin") ||
      role.includes("head_admin") ||
      role === "sa" ||
      role === "ha"
    );
  }, [currentUser]);

  if (!isOpen) return null;

  const handleOpenSession = async (session: PayrollReviewSessionItem) => {
    setSelectedSession(session);
    setIsLoadingItems(true);
    setActionError(null);
    try {
      const items = await fetchPayrollReviewItems(
        session.id,
        itemStatusFilter === "All" ? undefined : itemStatusFilter
      );
      setSessionItems(items);
    } catch (err) {
      setActionError(
        err instanceof Error ? err.message : "Failed to load session items."
      );
    } finally {
      setIsLoadingItems(false);
    }
  };

  const handleRefreshSessionItems = async (filter = itemStatusFilter) => {
    if (!selectedSession) return;
    setIsLoadingItems(true);
    try {
      const items = await fetchPayrollReviewItems(
        selectedSession.id,
        filter === "All" ? undefined : filter
      );
      setSessionItems(items);
    } catch (err) {
      setActionError(
        err instanceof Error ? err.message : "Failed to load session items."
      );
    } finally {
      setIsLoadingItems(false);
    }
  };

  const handleSubmitComment = async () => {
    if (!activeItem) return;
    setIsSubmittingComment(true);
    setActionError(null);

    try {
      await submitOpsPayrollReviewComment({
        itemId: activeItem.id,
        opsResponse,
        comment: opsComment.trim() || undefined,
      });

      setActiveItem(null);
      setOpsComment("");
      handleRefreshSessionItems();
      refetchSessions();
    } catch (err) {
      setActionError(
        err instanceof Error ? err.message : "Failed to submit comment."
      );
    } finally {
      setIsSubmittingComment(false);
    }
  };

  const handleCloseItem = async (itemId: string) => {
    setIsLoadingItems(true);
    try {
      await closePayrollReviewItem(itemId);
      handleRefreshSessionItems();
      refetchSessions();
    } catch (err) {
      setActionError(
        err instanceof Error ? err.message : "Failed to close item."
      );
    } finally {
      setIsLoadingItems(false);
    }
  };

  const handleCloseSession = async (sessionId: string) => {
    if (!confirm("Are you sure you want to close this payroll review session?"))
      return;
    setIsLoadingItems(true);
    try {
      await closePayrollReviewSession(sessionId);
      setSelectedSession(null);
      refetchSessions();
    } catch (err) {
      setActionError(
        err instanceof Error ? err.message : "Failed to close session."
      );
    } finally {
      setIsLoadingItems(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 sm:p-6 overflow-y-auto">
      <div className="relative flex w-full max-w-5xl max-h-[92vh] flex-col rounded-2xl border border-border-subtle bg-surface shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-150">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-subtle px-6 py-4 bg-surface-subtle">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-purple-50 text-purple-700 border border-purple-200">
              <FileText className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-base font-bold text-text-primary">
                  Payroll Review Center
                </h2>
                <span className="rounded-md bg-purple-100 text-purple-800 px-2 py-0.5 text-3xs font-bold uppercase tracking-wider">
                  OPS WORKBENCH
                </span>
              </div>
              <p className="text-xs text-text-secondary">
                Audit, track, and resolve payroll reconciliation discrepancies with Operations remarks.
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-text-muted hover:bg-surface-hover hover:text-text-primary transition"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {actionError && (
            <div className="rounded-xl border border-rose-200 bg-rose-50/80 p-3.5 flex items-start gap-3">
              <AlertCircle className="h-5 w-5 text-rose-600 shrink-0 mt-0.5" />
              <p className="text-xs font-medium text-rose-800">{actionError}</p>
            </div>
          )}

          {/* Master View: Sessions List */}
          {!selectedSession && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  {(["All", "Open", "Closed"] as const).map((filter) => (
                    <button
                      key={filter}
                      onClick={() => setStatusFilter(filter)}
                      className={`h-8 px-3 rounded-lg text-xs font-semibold transition cursor-pointer ${
                        statusFilter === filter
                          ? "bg-purple-100 text-purple-900 border border-purple-200"
                          : "text-text-secondary hover:bg-surface-hover"
                      }`}
                    >
                      {filter}
                    </button>
                  ))}
                </div>
                <button
                  onClick={() => refetchSessions()}
                  className="inline-flex items-center gap-1.5 text-xs text-text-muted hover:text-text-primary transition"
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                  Refresh
                </button>
              </div>

              {isLoadingSessions ? (
                <div className="flex justify-center p-8 text-xs text-text-muted">
                  <Loader2 className="h-5 w-5 animate-spin mr-2" /> Loading review sessions...
                </div>
              ) : sessions.length === 0 ? (
                <div className="rounded-xl border border-dashed border-border-subtle p-10 text-center text-xs text-text-muted">
                  No payroll review sessions found.
                </div>
              ) : (
                <div className="space-y-3">
                  {sessions.map((session) => (
                    <div
                      key={session.id}
                      onClick={() => handleOpenSession(session)}
                      className="group rounded-xl border border-border-subtle hover:border-purple-300 bg-surface hover:bg-purple-50/10 p-4 transition cursor-pointer flex flex-col md:flex-row items-start md:items-center justify-between gap-4"
                    >
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-xs text-text-primary">
                            {session.payrollFileName}
                          </span>
                          <span
                            className={`rounded-md px-2 py-0.5 text-3xs font-bold uppercase ${
                              session.status.toLowerCase() === "open"
                                ? "bg-emerald-100 text-emerald-800"
                                : "bg-slate-100 text-slate-800"
                            }`}
                          >
                            {session.status}
                          </span>
                        </div>
                        <div className="text-2xs text-text-muted flex flex-wrap gap-x-3 gap-y-1">
                          <span>Created by: {session.createdByName || "Admin"}</span>
                          <span>Items: {session.totalItems}</span>
                          <span>Pending: {session.pendingCount}</span>
                          <span>Commented: {session.commentedCount}</span>
                          <span>Confirmed: {session.confirmedCount}</span>
                          <span>Date: {new Date(session.createdAt).toLocaleDateString()}</span>
                        </div>
                        {session.notes && (
                          <p className="text-2xs italic text-text-secondary mt-1">
                            &quot;{session.notes}&quot;
                          </p>
                        )}
                      </div>

                      <div className="flex items-center gap-2 text-purple-700 font-semibold text-xs group-hover:translate-x-1 transition">
                        <span>Inspect Items</span>
                        <ChevronRight className="h-4 w-4" />
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Detail View: Session Items Drilldown */}
          {selectedSession && (
            <div className="space-y-4">
              {/* Back / Title bar */}
              <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 bg-surface-subtle border border-border-subtle rounded-xl p-3">
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => setSelectedSession(null)}
                    className="text-xs font-semibold text-purple-700 hover:underline"
                  >
                    ← Back to Sessions
                  </button>
                  <span className="text-text-muted">/</span>
                  <span className="text-xs font-bold text-text-primary">
                    {selectedSession.payrollFileName}
                  </span>
                  <span className="rounded-md bg-purple-100 text-purple-800 text-3xs font-bold px-2 py-0.5">
                    {selectedSession.status}
                  </span>
                </div>

                <div className="flex items-center gap-2">
                  {canManage && selectedSession.status.toLowerCase() === "open" && (
                    <button
                      onClick={() => handleCloseSession(selectedSession.id)}
                      className="h-8 px-3 rounded-lg border border-rose-200 bg-rose-50 hover:bg-rose-100 text-rose-700 text-xs font-semibold transition"
                    >
                      Close Review Session
                    </button>
                  )}
                  <button
                    onClick={() => handleRefreshSessionItems()}
                    className="h-8 px-2.5 rounded-lg border border-border-subtle bg-surface text-text-secondary hover:text-text-primary transition"
                  >
                    <RefreshCw className="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>

              {/* Status Filter for Items */}
              <div className="flex items-center gap-1 overflow-x-auto border-b border-border-subtle pb-2 no-scrollbar">
                {[
                  "All",
                  "Pending Ops Review",
                  "Ops Commented",
                  "Needs Fixing",
                  "Confirmed Correct",
                  "Not My Scope",
                  "Closed",
                ].map((s) => (
                  <button
                    key={s}
                    onClick={() => {
                      setItemStatusFilter(s);
                      handleRefreshSessionItems(s);
                    }}
                    className={`py-1 px-3 rounded-lg text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                      itemStatusFilter === s
                        ? "bg-purple-100 text-purple-900 border border-purple-200"
                        : "text-text-secondary hover:bg-surface-hover hover:text-text-primary"
                    }`}
                  >
                    {s}
                  </button>
                ))}
              </div>

              {/* Items Table */}
              <div className="rounded-xl border border-border-subtle overflow-hidden max-h-72 overflow-y-auto">
                {isLoadingItems ? (
                  <div className="flex justify-center p-8 text-xs text-text-muted">
                    <Loader2 className="h-5 w-5 animate-spin mr-2" /> Loading discrepancy items...
                  </div>
                ) : sessionItems.length === 0 ? (
                  <div className="p-8 text-center text-xs text-text-muted">
                    No discrepancy items match the selected filter.
                  </div>
                ) : (
                  <table className="w-full text-left text-xs">
                    <thead className="bg-surface-subtle border-b border-border-subtle sticky top-0 text-2xs uppercase text-text-muted font-bold">
                      <tr>
                        <th className="py-2 px-3">Emp No</th>
                        <th className="py-2 px-3">Type</th>
                        <th className="py-2 px-3">Status</th>
                        <th className="py-2 px-3">Payroll Name</th>
                        <th className="py-2 px-3">Plantilla Name</th>
                        <th className="py-2 px-3">Ops Response</th>
                        <th className="py-2 px-3">Actions</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle">
                      {sessionItems.map((item) => (
                        <tr key={item.id} className="hover:bg-surface-hover/50">
                          <td className="py-2 px-3 font-mono font-semibold text-purple-700">
                            {item.employeeNumber}
                          </td>
                          <td className="py-2 px-3 text-2xs text-text-secondary font-medium">
                            {item.findingType}
                          </td>
                          <td className="py-2 px-3">
                            <span className="rounded-md bg-slate-100 text-slate-800 text-3xs font-bold px-1.5 py-0.5">
                              {item.status}
                            </span>
                          </td>
                          <td className="py-2 px-3 text-text-primary">{item.payrollFullName || "—"}</td>
                          <td className="py-2 px-3 text-text-primary">{item.plantillaFullName || "—"}</td>
                          <td className="py-2 px-3 text-text-secondary">
                            {item.opsResponse ? (
                              <div className="space-y-0.5">
                                <span className="font-semibold">{item.opsResponse}</span>
                                {item.opsComment && (
                                  <p className="text-3xs italic text-text-muted">&quot;{item.opsComment}&quot;</p>
                                )}
                              </div>
                            ) : (
                              "—"
                            )}
                          </td>
                          <td className="py-2 px-3">
                            <div className="flex items-center gap-1.5">
                              {item.status !== "Closed" && (
                                <>
                                  <button
                                    onClick={() => {
                                      setActiveItem(item);
                                      setOpsResponse(item.opsResponse || "Confirmed Correct");
                                      setOpsComment(item.opsComment || "");
                                    }}
                                    className="p-1 rounded-md hover:bg-purple-100 text-purple-700 transition"
                                    title="Add Response / Comment"
                                  >
                                    <MessageSquare className="h-3.5 w-3.5" />
                                  </button>
                                  {canManage && (
                                    <button
                                      onClick={() => handleCloseItem(item.id)}
                                      className="p-1 rounded-md hover:bg-emerald-100 text-emerald-700 transition"
                                      title="Close Item"
                                    >
                                      <CheckCircle2 className="h-3.5 w-3.5" />
                                    </button>
                                  )}
                                </>
                              )}
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>

              {/* Ops Response Modal / Drawer */}
              {activeItem && (
                <div className="rounded-xl border border-purple-200 bg-purple-50/50 p-4 space-y-3">
                  <div className="flex items-center justify-between">
                    <h4 className="text-xs font-bold text-text-primary">
                      Ops Feedback for Employee #{activeItem.employeeNumber} ({activeItem.payrollFullName || activeItem.plantillaFullName})
                    </h4>
                    <button
                      onClick={() => setActiveItem(null)}
                      className="text-text-muted hover:text-text-primary"
                    >
                      <X className="h-4 w-4" />
                    </button>
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div>
                      <label className="block text-2xs font-bold text-text-secondary uppercase mb-1">
                        Ops Resolution Status
                      </label>
                      <select
                        value={opsResponse}
                        onChange={(e) => setOpsResponse(e.target.value)}
                        className="w-full h-8 rounded-lg border border-border-subtle bg-surface px-2.5 text-xs text-text-primary focus:outline-hidden"
                      >
                        <option value="Confirmed Correct">Confirmed Correct (Expected variance)</option>
                        <option value="Needs Fixing">Needs Fixing (HR action required)</option>
                        <option value="Not My Scope">Not My Scope (Reassign account)</option>
                      </select>
                    </div>

                    <div>
                      <label className="block text-2xs font-bold text-text-secondary uppercase mb-1">
                        Audited Remarks
                      </label>
                      <input
                        type="text"
                        placeholder="Explain reason, payroll cutoff timing, or HR action..."
                        value={opsComment}
                        onChange={(e) => setOpsComment(e.target.value)}
                        className="w-full h-8 rounded-lg border border-border-subtle bg-surface px-2.5 text-xs text-text-primary focus:outline-hidden"
                      />
                    </div>
                  </div>

                  <div className="flex justify-end gap-2 pt-1">
                    <button
                      onClick={() => setActiveItem(null)}
                      className="px-3 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-medium text-text-secondary"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleSubmitComment}
                      disabled={isSubmittingComment}
                      className="px-4 py-1.5 rounded-lg bg-purple-600 hover:bg-purple-700 text-white text-xs font-semibold flex items-center gap-1.5 disabled:opacity-50"
                    >
                      {isSubmittingComment ? (
                        <>
                          <Loader2 className="h-3.5 w-3.5 animate-spin" />
                          Saving...
                        </>
                      ) : (
                        "Save Ops Response"
                      )}
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle px-6 py-3 bg-surface-subtle">
          <p className="text-2xs text-text-muted">
            Full Mobile Payroll Review Center Parity: Cross-check review sessions, Ops audit feedback, and variance resolution.
          </p>
          <button
            onClick={onClose}
            className="px-4 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-semibold text-text-primary hover:bg-surface-hover transition"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
