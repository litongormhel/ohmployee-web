"use client";

import { Clock, History, User } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { usePoolRequestHistory } from "@/lib/queries/workforcePool";
import type { BaseModalProps } from "@/types/modal";

export type PoolRequestHistoryDrawerProps = BaseModalProps;

export function PoolRequestHistoryDrawer({ isOpen, onClose }: PoolRequestHistoryDrawerProps) {
  const historyQuery = usePoolRequestHistory();
  const requests = historyQuery.data ?? [];

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      maxWidthClass="max-w-2xl"
      title="Pool Headcount Request History"
      subtitle="Audit trail of workforce pool requirement requests, endorsements, and slot approvals"
      footer={
        <button
          type="button"
          onClick={onClose}
          className="rounded-lg border border-border-default bg-surface px-4 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition-colors cursor-pointer"
        >
          Close
        </button>
      }
    >
      <div className="space-y-6">
        <div className="flex items-center justify-between text-xs text-text-secondary border-b border-border-subtle pb-2">
          <span>
            Total: <strong className="text-text-primary">{requests.length}</strong> request logs
          </span>
          <span className="flex items-center gap-1.5 text-text-primary font-medium">
            <History className="h-3.5 w-3.5 text-text-muted" /> Immutable Audit Trail
          </span>
        </div>

        {historyQuery.isLoading ? (
          <DataState state="loading" message="Loading pool request history..." />
        ) : requests.length === 0 ? (
          <DataState
            state="empty"
            title="No request history found"
            message="No workforce pool requests have been logged yet."
          />
        ) : (
          <div className="divide-y divide-border-subtle border border-border-subtle rounded-xl overflow-hidden bg-surface shadow-xs">
            {requests.map((req) => (
              <div key={req.id} className="p-4 hover:bg-surface-hover transition space-y-2.5">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-bold text-text-primary">
                        {req.poolTypeName || "Workforce Pool"}
                      </span>
                      <span className="text-xs text-text-muted font-mono">
                        {req.headcountNeeded} slot{req.headcountNeeded > 1 ? "s" : ""}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 text-xs text-text-secondary mt-1">
                      <span>Account: {req.requestingAccount || req.operationalAccountName || "—"}</span>
                      {req.positionName && <span>&bull; {req.positionName}</span>}
                    </div>
                  </div>
                  <div className="shrink-0 flex items-center gap-2">
                    <StatusBadge
                      variant={
                        req.status.toLowerCase() === "approved"
                          ? "success"
                          : req.status.toLowerCase() === "rejected"
                          ? "danger"
                          : "warning"
                      }
                    >
                      {req.status}
                    </StatusBadge>
                  </div>
                </div>

                {req.vcodes.length > 0 && (
                  <div className="flex flex-wrap gap-1.5 pt-1">
                    {req.vcodes.map((vcode) => (
                      <span
                        key={vcode}
                        className="font-mono text-xs font-semibold px-2 py-0.5 rounded bg-surface-muted text-text-primary border border-border-default"
                      >
                        {vcode}
                      </span>
                    ))}
                  </div>
                )}

                <div className="flex items-center justify-between text-xs text-text-muted pt-1 border-t border-border-subtle">
                  <span className="flex items-center gap-1">
                    <User className="h-3.5 w-3.5" />
                    By: {req.createdBy || "System"}
                  </span>
                  {req.createdAt && (
                    <span className="flex items-center gap-1 font-mono">
                      <Clock className="h-3.5 w-3.5" />
                      {new Date(req.createdAt).toLocaleDateString("en-PH", {
                        dateStyle: "medium",
                      })}
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </Modal>
  );
}
