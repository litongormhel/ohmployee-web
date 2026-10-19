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

export interface PoolReviewQueueDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

export function PoolReviewQueueDrawer({ isOpen, onClose }: PoolReviewQueueDrawerProps) {
  const [activeTab, setActiveTab] = useState<"pending" | "resolved">("pending");
  const [selectedReviewId, setSelectedReviewId] = useState<string | null>(null);
  const [actionNotes, setActionNotes] = useState<string>("");
  const [actionType, setActionType] = useState<"reopen" | "close" | null>(null);

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
        <div className="flex border-b border-gray-200">
          <button
            type="button"
            onClick={() => setActiveTab("pending")}
            className={`pb-3 px-4 text-xs font-semibold border-b-2 transition ${
              activeTab === "pending"
                ? "border-amber-500 text-amber-600"
                : "border-transparent text-gray-500 hover:text-gray-700"
            }`}
          >
            Pending Reviews ({allReviews.filter((r) => r.status.toLowerCase() === "pending").length})
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("resolved")}
            className={`pb-3 px-4 text-xs font-semibold border-b-2 transition ${
              activeTab === "resolved"
                ? "border-blue-600 text-blue-600"
                : "border-transparent text-gray-500 hover:text-gray-700"
            }`}
          >
            Resolved ({allReviews.filter((r) => r.status.toLowerCase() !== "pending").length})
          </button>
        </div>

        {/* Action Dialog if open */}
        {selectedReviewId && actionType && (
          <div className="p-4 bg-gray-50 border border-gray-200 rounded-xl space-y-3">
            <div className="flex items-center justify-between">
              <h4 className="text-xs font-bold uppercase tracking-wider text-gray-700">
                Confirm {actionType === "reopen" ? "Reopening Slot" : "Closing Slot"}
              </h4>
              <button
                type="button"
                onClick={() => {
                  setSelectedReviewId(null);
                  setActionType(null);
                }}
                className="text-gray-400 hover:text-gray-600 text-xs"
              >
                Cancel
              </button>
            </div>
            <textarea
              rows={2}
              value={actionNotes}
              onChange={(e) => setActionNotes(e.target.value)}
              placeholder="Optional resolution remarks / rationale..."
              className="w-full text-xs rounded-lg border border-gray-300 p-2.5 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            <div className="flex justify-end gap-2">
              <button
                type="button"
                onClick={handleExecuteAction}
                disabled={isPendingAction}
                className={`px-3 py-1.5 text-xs font-semibold text-white rounded-lg transition inline-flex items-center gap-1.5 ${
                  actionType === "reopen"
                    ? "bg-emerald-600 hover:bg-emerald-700"
                    : "bg-red-600 hover:bg-red-700"
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
          <div className="divide-y divide-gray-100 border border-gray-100 rounded-xl overflow-hidden bg-white shadow-xs">
            {displayedReviews.map((rev) => (
              <div key={rev.id} className="p-4 hover:bg-gray-50/70 transition space-y-3">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-xs font-bold text-amber-700 bg-amber-50 px-2 py-0.5 rounded border border-amber-200">
                        {rev.vcode}
                      </span>
                      <span className="text-sm font-semibold text-gray-900">
                        Trigger: {rev.triggerEvent}
                      </span>
                    </div>
                    <p className="text-xs text-gray-500 mt-1">
                      Vacated by: <strong className="text-gray-700">{rev.previousEmployeeName || "—"}</strong>{" "}
                      {rev.previousPosition ? `(${rev.previousPosition})` : ""}
                    </p>
                  </div>
                  <div className="shrink-0 flex items-center gap-2">
                    {rev.reviewAgeDays != null && (
                      <span className="text-xs text-gray-400 font-mono">
                        {rev.reviewAgeDays}d in review
                      </span>
                    )}
                    <StatusBadge variant={rev.status.toLowerCase() === "pending" ? "warning" : "success"}>
                      {rev.status}
                    </StatusBadge>
                  </div>
                </div>

                {rev.reviewNotes && (
                  <p className="text-xs text-gray-600 bg-gray-50 p-2.5 rounded-lg border border-gray-100 italic">
                    &ldquo;{rev.reviewNotes}&rdquo;
                  </p>
                )}

                {rev.status.toLowerCase() === "pending" && (
                  <div className="flex items-center justify-end gap-2 pt-1 border-t border-gray-50">
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedReviewId(rev.id);
                        setActionType("reopen");
                        setActionNotes("");
                      }}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-lg hover:bg-emerald-100 transition"
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
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-red-700 bg-red-50 border border-red-200 rounded-lg hover:bg-red-100 transition"
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
