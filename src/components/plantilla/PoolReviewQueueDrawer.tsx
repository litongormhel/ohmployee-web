"use client";

import { useState } from "react";
import { Loader2, RefreshCw, XCircle } from "lucide-react";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import {
  useSlotReviewQueue,
  useReopenPoolSlotReview,
  useClosePoolSlotReview,
} from "@/lib/queries/workforcePool";
import { useCurrentUser } from "@/lib/auth";
import { hasFullAccess, isEncoder } from "@/lib/rbac";

export interface PoolReviewQueueDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

export function PoolReviewQueueDrawer({ isOpen, onClose }: PoolReviewQueueDrawerProps) {
  const [activeTab, setActiveTab] = useState<"pending" | "resolved">("pending");
  const [selectedReviewId, setSelectedReviewId] = useState<string | null>(null);
  const [actionNotes, setActionNotes] = useState<string>("");
  const [actionType, setActionType] = useState<"reopen" | "close" | null>(null);

  const currentUser = useCurrentUser();
  const canReviewSlots = Boolean(
    currentUser && (hasFullAccess(currentUser) || isEncoder(currentUser))
  );

  const reviewsQuery = useSlotReviewQueue();
  const reopenMutation = useReopenPoolSlotReview();
  const closeMutation = useClosePoolSlotReview();

  const allReviews = reviewsQuery.data ?? [];
  const displayedReviews = allReviews.filter((r) =>
    activeTab === "pending"
      ? r.status.toLowerCase() === "pending"
      : r.status.toLowerCase() !== "pending"
  );

  const handleExecuteAction = () => {
    if (!selectedReviewId || !actionType) return;
    const mutation = actionType === "reopen" ? reopenMutation : closeMutation;

    mutation.mutate(
      { reviewId: selectedReviewId, notes: actionNotes.trim() || undefined },
      {
        onSuccess: () => {
          setSelectedReviewId(null);
          setActionType(null);
          setActionNotes("");
          reviewsQuery.refetch();
        },
      }
    );
  };

  const isPendingAction = reopenMutation.isPending || closeMutation.isPending;

  return (
    <DetailDrawer
      isOpen={isOpen}
      onClose={onClose}
      title="Workforce Slot Review Queue"
      subtitle="Decide whether vacated pool slots are reopened for replenishment or closed"
    >
      <div className="p-6 space-y-6">
        {/* Tab Switcher */}
        <div className="flex border-b border-border-default">
          <button
            type="button"
            onClick={() => setActiveTab("pending")}
            className={`pb-3 px-4 text-xs font-semibold border-b-2 transition cursor-pointer ${
              activeTab === "pending"
                ? "border-brand-primary text-brand-primary"
                : "border-transparent text-text-muted hover:text-text-primary"
            }`}
          >
            Pending Reviews ({allReviews.filter((r) => r.status.toLowerCase() === "pending").length})
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("resolved")}
            className={`pb-3 px-4 text-xs font-semibold border-b-2 transition cursor-pointer ${
              activeTab === "resolved"
                ? "border-brand-primary text-brand-primary"
                : "border-transparent text-text-muted hover:text-text-primary"
            }`}
          >
            Resolved ({allReviews.filter((r) => r.status.toLowerCase() !== "pending").length})
          </button>
        </div>

        {/* Action Dialog if open */}
        {canReviewSlots && selectedReviewId && actionType && (
          <div className="p-4 bg-surface-muted border border-border-default rounded-xl space-y-3">
            <div className="flex items-center justify-between">
              <h4 className="text-xs font-bold text-text-primary">
                Confirm {actionType === "reopen" ? "Reopening Slot" : "Closing Slot"}
              </h4>
              <button
                type="button"
                onClick={() => {
                  setSelectedReviewId(null);
                  setActionType(null);
                }}
                className="text-text-muted hover:text-text-primary text-xs cursor-pointer"
              >
                Cancel
              </button>
            </div>
            <textarea
              rows={2}
              value={actionNotes}
              onChange={(e) => setActionNotes(e.target.value)}
              placeholder="Optional resolution remarks / rationale..."
              className="w-full text-xs rounded-lg border border-border-default p-2.5 bg-surface text-text-primary focus:outline-none focus:ring-2 focus:ring-brand-primary"
            />
            <div className="flex justify-end gap-2">
              <button
                type="button"
                onClick={handleExecuteAction}
                disabled={isPendingAction}
                className={`px-3 py-1.5 text-xs font-semibold text-white rounded-lg transition inline-flex items-center gap-1.5 cursor-pointer disabled:opacity-50 ${
                  actionType === "reopen"
                    ? "bg-brand-500 hover:bg-brand-600"
                    : "bg-danger-text hover:opacity-90"
                }`}
              >
                {isPendingAction && <Loader2 className="h-3 w-3 animate-spin" />}
                Confirm {actionType === "reopen" ? "Reopen Slot" : "Close Slot"}
              </button>
            </div>
          </div>
        )}

        {/* List */}
        {reviewsQuery.isLoading ? (
          <DataState state="loading" message="Loading slot review queue..." />
        ) : displayedReviews.length === 0 ? (
          <DataState
            state="empty"
            title={activeTab === "pending" ? "No pending reviews" : "No resolved reviews"}
            message="No slot reviews found matching the current tab."
          />
        ) : (
          <div className="divide-y divide-border-subtle border border-border-subtle rounded-xl overflow-hidden bg-surface shadow-xs">
            {displayedReviews.map((rev) => (
              <div key={rev.id} className="p-4 hover:bg-surface-hover transition space-y-3">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-xs font-bold text-text-primary bg-surface-muted px-2 py-0.5 rounded border border-border-default">
                        {rev.vcode}
                      </span>
                      <span className="text-sm font-semibold text-text-primary">
                        Trigger: {rev.triggerEvent}
                      </span>
                    </div>
                    <p className="text-xs text-text-secondary mt-1">
                      Vacated by: <strong className="text-text-primary">{rev.previousEmployeeName || "—"}</strong>{" "}
                      {rev.previousPosition ? `(${rev.previousPosition})` : ""}
                    </p>
                  </div>
                  <div className="shrink-0 flex items-center gap-2">
                    {rev.reviewAgeDays != null && (
                      <span className="text-xs text-text-muted font-mono">
                        {rev.reviewAgeDays}d in review
                      </span>
                    )}
                    <StatusBadge variant={rev.status.toLowerCase() === "pending" ? "warning" : "success"}>
                      {rev.status}
                    </StatusBadge>
                  </div>
                </div>

                {rev.reviewNotes && (
                  <p className="text-xs text-text-secondary bg-surface-muted p-2.5 rounded-lg border border-border-subtle italic">
                    &ldquo;{rev.reviewNotes}&rdquo;
                  </p>
                )}

                {canReviewSlots && rev.status.toLowerCase() === "pending" && (
                  <div className="flex items-center justify-end gap-2 pt-1 border-t border-border-subtle">
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedReviewId(rev.id);
                        setActionType("reopen");
                        setActionNotes("");
                      }}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-text-primary bg-surface border border-border-default rounded-lg hover:bg-surface-hover transition cursor-pointer"
                    >
                      <RefreshCw className="h-3.5 w-3.5" /> Reopen for Replenishment
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedReviewId(rev.id);
                        setActionType("close");
                        setActionNotes("");
                      }}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-danger-text bg-danger-bg border border-danger-border rounded-lg hover:opacity-90 transition cursor-pointer"
                    >
                      <XCircle className="h-3.5 w-3.5" /> Close Slot
                    </button>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </DetailDrawer>
  );
}
