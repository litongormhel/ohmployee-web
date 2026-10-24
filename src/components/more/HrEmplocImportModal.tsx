"use client";

import React, { useMemo, useState } from "react";
import {
  Clock,
  FileSpreadsheet,
  History,
  UploadCloud,
  X,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import { useImportBatches } from "@/lib/queries/hr_emploc_import";
import { UploadTab } from "@/components/hr-emploc/import/UploadTab";
import { ReviewBatchesTab } from "@/components/hr-emploc/import/ReviewBatchesTab";
import { HistoryTab } from "@/components/hr-emploc/import/HistoryTab";

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

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 sm:p-6 overflow-y-auto">
      <div className="relative flex w-full max-w-5xl max-h-[92vh] flex-col rounded-2xl border border-border-subtle bg-surface shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-150">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-subtle px-6 py-4 bg-surface-subtle">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-purple-50 text-purple-700 border border-purple-200">
              <FileSpreadsheet className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-base font-bold text-text-primary">Import HR Emploc</h2>
                <span className="rounded-md bg-purple-100 text-purple-800 px-2 py-0.5 text-3xs font-bold uppercase tracking-wider">
                  RECONCILIATION
                </span>
              </div>
              <p className="text-xs text-text-secondary">
                Bulk recruit onboarding pipeline with slot-first capacity reservation, ADR-001 reconciliation, and rollback safety.
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-text-muted hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
            aria-label="Close modal"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Purple-accented Underlined Tab Switcher */}
        <div
          aria-label="Import wizard navigation tabs"
          className="flex items-center border-b border-border-subtle px-6 bg-surface"
          role="tablist"
        >
          <button
            aria-selected={activeTab === "upload"}
            className={`flex items-center gap-2 py-3 px-4 text-xs font-semibold border-b-2 transition cursor-pointer ${
              activeTab === "upload"
                ? "border-purple-600 text-purple-700"
                : "border-transparent text-text-secondary hover:text-text-primary"
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
            className={`flex items-center gap-2 py-3 px-4 text-xs font-semibold border-b-2 transition cursor-pointer ${
              activeTab === "review"
                ? "border-purple-600 text-purple-700"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
            onClick={() => setActiveTab("review")}
            role="tab"
            type="button"
          >
            <Clock className="h-4 w-4" />
            <span>Review Queue</span>
            {pendingCount > 0 && (
              <span className="rounded-full bg-purple-100 text-purple-700 font-bold px-1.5 py-0.5 text-3xs">
                {pendingCount}
              </span>
            )}
          </button>

          <button
            aria-selected={activeTab === "history"}
            className={`flex items-center gap-2 py-3 px-4 text-xs font-semibold border-b-2 transition cursor-pointer ${
              activeTab === "history"
                ? "border-purple-600 text-purple-700"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
            onClick={() => setActiveTab("history")}
            role="tab"
            type="button"
          >
            <History className="h-4 w-4" />
            <span>Import History</span>
            {historyCount > 0 && (
              <span className="rounded-full bg-slate-100 text-slate-700 font-bold px-1.5 py-0.5 text-3xs border border-slate-200">
                {historyCount}
              </span>
            )}
          </button>
        </div>

        {/* Tab Panels */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
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

        {/* Parity Footer Bar */}
        <div className="flex items-center justify-between border-t border-border-subtle px-6 py-3 bg-surface-subtle">
          <p className="text-2xs text-text-muted">
            Full Mobile HR Emploc Parity with ADR-001 Slot Validation and Rollback Governance.
          </p>
          <button
            onClick={onClose}
            className="px-4 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer"
            type="button"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
