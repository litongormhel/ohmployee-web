"use client";

import React, { useMemo, useState } from "react";
import {
  Clock,
  FileSpreadsheet,
  History,
  UploadCloud,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import { useImportBatches } from "@/lib/queries/hr_emploc_import";
import { UploadTab } from "@/components/hr-emploc/import/UploadTab";
import { ReviewBatchesTab } from "@/components/hr-emploc/import/ReviewBatchesTab";
import { HistoryTab } from "@/components/hr-emploc/import/HistoryTab";
import { Modal } from "@/components/shared/Modal";

export interface HrEmplocImportModalProps {
  isOpen: boolean;
  onClose: () => void;
}

type TabType = "upload" | "review" | "history";

export function HrEmplocImportModal({ isOpen, onClose }: HrEmplocImportModalProps) {
  const [activeTab, setActiveTab] = useState<TabType>("upload");
  const currentUser = useCurrentUser();

  // Role permissions check (1:1 Mobile Parity: Super Admin & Head Admin approval / rollback)
  const role = (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
  const canAct =
    role.includes("super_admin") ||
    role.includes("head_admin") ||
    role === "sa" ||
    role === "ha";

  const { data: batches = [] } = useImportBatches();

  const pendingCount = useMemo(() => {
    return batches.filter((b) => b.status === "pending_approval").length;
  }, [batches]);

  const historyCount = useMemo(() => {
    return batches.filter((b) => b.status !== "pending_approval").length;
  }, [batches]);

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Import HR Emploc"
      subtitle="Bulk recruit onboarding pipeline with slot-first capacity reservation, ADR-001 reconciliation, and rollback safety."
      icon={FileSpreadsheet}
      maxWidthClass="max-w-5xl"
      footer={
        <div className="flex w-full items-center justify-between text-xs text-text-muted">
          <span>Full Mobile HR Emploc Parity with ADR-001 Slot Validation and Rollback Governance.</span>
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
        {/* Underlined Tab Switcher */}
        <div
          aria-label="Import wizard navigation tabs"
          className="flex items-center border-b border-border-default pb-2 gap-2"
          role="tablist"
        >
          <button
            aria-selected={activeTab === "upload"}
            className={`flex items-center gap-2 py-1.5 px-3 text-xs font-semibold rounded-lg transition cursor-pointer ${
              activeTab === "upload"
                ? "bg-brand-50 text-brand-900 border border-brand-200"
                : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
            }`}
            onClick={() => setActiveTab("upload")}
            role="tab"
            type="button"
          >
            <UploadCloud className="h-4 w-4" />
            <span>Upload & Preview</span>
          </button>

          <button
            aria-selected={activeTab === "review"}
            className={`flex items-center gap-2 py-1.5 px-3 text-xs font-semibold rounded-lg transition cursor-pointer ${
              activeTab === "review"
                ? "bg-brand-50 text-brand-900 border border-brand-200"
                : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
            }`}
            onClick={() => setActiveTab("review")}
            role="tab"
            type="button"
          >
            <Clock className="h-4 w-4" />
            <span>Review Queue</span>
            {pendingCount > 0 && (
              <span className="rounded-full bg-surface-subtle text-text-primary font-bold px-1.5 py-0.2 text-xs border border-border-default">
                {pendingCount}
              </span>
            )}
          </button>

          <button
            aria-selected={activeTab === "history"}
            className={`flex items-center gap-2 py-1.5 px-3 text-xs font-semibold rounded-lg transition cursor-pointer ${
              activeTab === "history"
                ? "bg-brand-50 text-brand-900 border border-brand-200"
                : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
            }`}
            onClick={() => setActiveTab("history")}
            role="tab"
            type="button"
          >
            <History className="h-4 w-4" />
            <span>Import History</span>
            {historyCount > 0 && (
              <span className="rounded-full bg-surface-subtle text-text-secondary font-bold px-1.5 py-0.2 text-xs border border-border-default">
                {historyCount}
              </span>
            )}
          </button>
        </div>

        {/* Tab Panels */}
        <div className="max-h-[58vh] overflow-y-auto space-y-4 pr-1">
          {activeTab === "upload" && (
            <UploadTab
              onSuccess={() => {
                setActiveTab("review");
              }}
            />
          )}

          {activeTab === "review" && (
            <ReviewBatchesTab
              canAct={canAct}
              onBatchApprovedOrRejected={() => {
                setActiveTab("history");
              }}
            />
          )}

          {activeTab === "history" && <HistoryTab canAct={canAct} />}
        </div>
      </div>
    </Modal>
  );
}
