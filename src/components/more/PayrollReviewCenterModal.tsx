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
import { Modal } from "@/components/shared/Modal";

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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Payroll Review Center"
      subtitle="Audit, track, and resolve payroll reconciliation discrepancies with Operations remarks."
      icon={FileText}
      maxWidthClass="max-w-5xl"
      footer={
        <div className="flex w-full items-center justify-between text-xs text-text-muted">
          <span>Full Mobile Payroll Review Center Parity: Cross-check review sessions, Ops audit feedback, and variance resolution.</span>
          <button
            onClick={onClose}
            className="rounded-xl border border-border-default bg-surface-primary px-4 py-2 text-xs font-semibold text-text-primary transition hover:bg-surface-hover cursor-pointer"
            type="button"
          >
            Close
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        {actionError && (
          <div className="rounded-xl border border-danger-border bg-danger-surface p-3.5 flex items-start gap-3">
            <AlertCircle className="h-5 w-5 text-danger-text shrink-0 mt-0.5" />
            <p className="text-xs font-medium text-danger-text">{actionError}</p>
          </div>
        )}

        {/* Master View: Sessions List */}
        {!selectedSession && (
          <div className="space-y-4">
            <div className="flex items-center justify-between border-b border-border-default pb-3">
              <div className="flex items-center gap-2">
                {(["All", "Open", "Closed"] as const).map((filter) => (
                  <button
                    key={filter}
                    onClick={() => setStatusFilter(filter)}
                    className={`h-8 px-3 rounded-lg text-xs font-semibold transition cursor-pointer ${
                      statusFilter === filter
                        ? "bg-brand-50 text-brand-900 border border-brand-200"
                        : "text-text-secondary hover:bg-surface-hover hover:text-text-primary"
                    }`}
                  >
                    {filter}
                  </button>
                ))}
              </div>
              <button
                onClick={() => refetchSessions()}
                className="inline-flex items-center gap-1.5 text-xs text-text-muted hover:text-text-primary transition cursor-pointer"
              >
                <RefreshCw className="h-3.5 w-3.5" />
                <span>Refresh</span>
              </button>
            </div>

            {isLoadingSessions ? (
              <div className="flex justify-center p-8 text-xs text-text-muted">
                <Loader2 className="h-5 w-5 animate-spin mr-2 text-brand-primary" /> Loading review sessions...
              </div>
            ) : sessions.length === 0 ? (
              <div className="rounded-2xl border border-dashed border-border-default p-10 text-center text-xs text-text-muted">
                No payroll review sessions found.
              </div>
            ) : (
              <div className="space-y-3 max-h-[55vh] overflow-y-auto pr-1">
                {sessions.map((session) => (
                  <div
                    key={session.id}
                    onClick={() => handleOpenSession(session)}
                    className="group rounded-2xl border border-border-default hover:border-brand-primary bg-surface-primary hover:bg-surface-hover p-4 transition cursor-pointer flex flex-col md:flex-row items-start md:items-center justify-between gap-4 shadow-2xs"
                  >
                    <div className="space-y-1">
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-sm text-text-primary">
                          {session.payrollFileName}
                        </span>
                        <span className="rounded-full px-2 py-0.5 text-xs font-semibold uppercase bg-surface-subtle text-text-secondary border border-border-default">
                          {session.status}
                        </span>
                      </div>
                      <div className="text-xs text-text-muted flex flex-wrap gap-x-3 gap-y-1">
                        <span>Created by: {session.createdByName || "Admin"}</span>
                        <span>Items: {session.totalItems}</span>
                        <span>Pending: {session.pendingCount}</span>
                        <span>Commented: {session.commentedCount}</span>
                        <span>Confirmed: {session.confirmedCount}</span>
                        <span>Date: {new Date(session.createdAt).toLocaleDateString()}</span>
                      </div>
                      {session.notes && (
                        <p className="text-xs italic text-text-secondary mt-1">
                          &quot;{session.notes}&quot;
                        </p>
                      )}
                    </div>

                    <div className="flex items-center gap-2 text-brand-primary font-semibold text-xs group-hover:translate-x-1 transition">
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
            <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 bg-surface-subtle border border-border-default rounded-xl p-3">
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setSelectedSession(null)}
                  className="text-xs font-semibold text-brand-primary hover:underline cursor-pointer"
                >
                  ← Back to Sessions
                </button>
                <span className="text-text-muted">/</span>
                <span className="text-sm font-bold text-text-primary">
                  {selectedSession.payrollFileName}
                </span>
                <span className="rounded-full bg-surface-primary text-text-secondary border border-border-default text-xs font-semibold px-2 py-0.5">
                  {selectedSession.status}
                </span>
              </div>

              <div className="flex items-center gap-2">
                {canManage && selectedSession.status.toLowerCase() === "open" && (
                  <button
                    onClick={() => handleCloseSession(selectedSession.id)}
                    className="h-8 px-3 rounded-xl border border-danger-border bg-danger-surface hover:bg-danger-border/30 text-danger-text text-xs font-semibold transition cursor-pointer"
                  >
                    Close Review Session
                  </button>
                )}
                <button
                  onClick={() => handleRefreshSessionItems()}
                  className="h-8 px-2.5 rounded-xl border border-border-default bg-surface-primary text-text-secondary hover:text-text-primary hover:bg-surface-hover transition cursor-pointer"
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                </button>
              </div>
            </div>

            {/* Status Filter for Items */}
            <div className="flex items-center gap-1.5 overflow-x-auto border-b border-border-default pb-2 no-scrollbar">
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
                  className={`py-1.5 px-3 rounded-lg text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                    itemStatusFilter === s
                      ? "bg-brand-50 text-brand-900 border border-brand-200"
                      : "text-text-secondary hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  {s}
                </button>
              ))}
            </div>

            {/* Items Table */}
            <div className="rounded-xl border border-border-default overflow-hidden max-h-72 overflow-y-auto">
              {isLoadingItems ? (
                <div className="flex justify-center p-8 text-xs text-text-muted">
                  <Loader2 className="h-5 w-5 animate-spin mr-2 text-brand-primary" /> Loading discrepancy items...
                </div>
              ) : sessionItems.length === 0 ? (
                <div className="p-8 text-center text-xs text-text-muted">
                  No discrepancy items match the selected filter.
                </div>
              ) : (
                <table className="w-full text-left text-sm">
                  <thead className="bg-surface-subtle border-b border-border-default sticky top-0 text-xs uppercase text-text-muted font-bold">
                    <tr>
                      <th className="py-2.5 px-3.5">Emp No</th>
                      <th className="py-2.5 px-3.5">Type</th>
                      <th className="py-2.5 px-3.5">Status</th>
                      <th className="py-2.5 px-3.5">Payroll Name</th>
                      <th className="py-2.5 px-3.5">Plantilla Name</th>
                      <th className="py-2.5 px-3.5">Ops Response</th>
                      <th className="py-2.5 px-3.5">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border-subtle bg-surface-primary">
                    {sessionItems.map((item) => (
                      <tr key={item.id} className="hover:bg-surface-hover/50">
                        <td className="py-2.5 px-3.5 font-mono font-semibold text-text-primary">
                          {item.employeeNumber}
                        </td>
                        <td className="py-2.5 px-3.5 text-xs text-text-secondary font-medium">
                          {item.findingType}
                        </td>
                        <td className="py-2.5 px-3.5">
                          <span className="rounded-full bg-surface-subtle text-text-secondary border border-border-default text-xs font-semibold px-2 py-0.5">
                            {item.status}
                          </span>
                        </td>
                        <td className="py-2.5 px-3.5 text-text-primary">{item.payrollFullName || "—"}</td>
                        <td className="py-2.5 px-3.5 text-text-primary">{item.plantillaFullName || "—"}</td>
                        <td className="py-2.5 px-3.5 text-xs text-text-secondary">
                          {item.opsResponse ? (
                            <div className="space-y-0.5">
                              <span className="font-semibold text-text-primary">{item.opsResponse}</span>
                              {item.opsComment && (
                                <p className="text-xs italic text-text-muted">&quot;{item.opsComment}&quot;</p>
                              )}
                            </div>
                          ) : (
                            "—"
                          )}
                        </td>
                        <td className="py-2.5 px-3.5">
                          <div className="flex items-center gap-1.5">
                            {item.status !== "Closed" && (
                              <>
                                <button
                                  onClick={() => {
                                    setActiveItem(item);
                                    setOpsResponse(item.opsResponse || "Confirmed Correct");
                                    setOpsComment(item.opsComment || "");
                                  }}
                                  className="p-1.5 rounded-lg border border-border-default hover:bg-surface-hover text-text-primary transition cursor-pointer"
                                  title="Add Response / Comment"
                                >
                                  <MessageSquare className="h-3.5 w-3.5" />
                                </button>
                                {canManage && (
                                  <button
                                    onClick={() => handleCloseItem(item.id)}
                                    className="p-1.5 rounded-lg border border-border-default hover:bg-surface-hover text-text-primary transition cursor-pointer"
                                    title="Close Item"
                                  >
                                    <CheckCircle2 className="h-3.5 w-3.5 text-brand-primary" />
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
              <div className="rounded-2xl border border-border-default bg-surface-subtle p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <h4 className="text-xs font-bold text-text-primary">
                    Ops Feedback for Employee #{activeItem.employeeNumber} ({activeItem.payrollFullName || activeItem.plantillaFullName})
                  </h4>
                  <button
                    onClick={() => setActiveItem(null)}
                    className="text-text-muted hover:text-text-primary cursor-pointer"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-bold text-text-secondary uppercase mb-1">
                      Ops Resolution Status
                    </label>
                    <select
                      value={opsResponse}
                      onChange={(e) => setOpsResponse(e.target.value)}
                      className="w-full h-9 rounded-xl border border-border-default bg-surface-primary px-2.5 text-xs text-text-primary focus:outline-hidden focus:border-brand-primary"
                    >
                      <option value="Confirmed Correct">Confirmed Correct (Expected variance)</option>
                      <option value="Needs Fixing">Needs Fixing (HR action required)</option>
                      <option value="Not My Scope">Not My Scope (Reassign account)</option>
                    </select>
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-text-secondary uppercase mb-1">
                      Audited Remarks
                    </label>
                    <input
                      type="text"
                      placeholder="Explain reason, payroll cutoff timing, or HR action..."
                      value={opsComment}
                      onChange={(e) => setOpsComment(e.target.value)}
                      className="w-full h-9 rounded-xl border border-border-default bg-surface-primary px-2.5 text-xs text-text-primary focus:outline-hidden focus:border-brand-primary"
                    />
                  </div>
                </div>

                <div className="flex justify-end gap-2 pt-1 border-t border-border-default">
                  <button
                    onClick={() => setActiveItem(null)}
                    className="px-3.5 py-2 rounded-xl border border-border-default bg-surface-primary text-xs font-medium text-text-secondary hover:bg-surface-hover cursor-pointer"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleSubmitComment}
                    disabled={isSubmittingComment}
                    className="px-4 py-2 rounded-xl bg-brand-primary hover:bg-brand-primary-hover text-surface-primary text-xs font-semibold flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
                  >
                    {isSubmittingComment ? (
                      <>
                        <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        <span>Saving...</span>
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
    </Modal>
  );
}
