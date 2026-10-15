"use client";

import React, { useMemo, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Clock, History, UploadCloud } from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import { useImportBatches } from "@/lib/queries/hr_emploc_import";
import { UploadTab } from "@/components/hr-emploc/import/UploadTab";
import { ReviewBatchesTab } from "@/components/hr-emploc/import/ReviewBatchesTab";
import { HistoryTab } from "@/components/hr-emploc/import/HistoryTab";

type WizardTab = "upload" | "review" | "history";

export default function HrEmplocImportPage() {
  const [activeTab, setActiveTab] = useState<WizardTab>("upload");
  const currentUser = useCurrentUser();

  // Role permissions check
  const role = (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
  const canAct = role.includes("super_admin") || role.includes("head_admin") || role === "sa" || role === "ha";

  const { data: batches = [] } = useImportBatches();

  const pendingCount = useMemo(() => {
    return batches.filter((b) => b.status === "pending_approval").length;
  }, [batches]);

  const historyCount = useMemo(() => {
    return batches.filter((b) => b.status !== "pending_approval").length;
  }, [batches]);

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-5 text-gray-900 pb-12">
      {/* Top Navigation & Header */}
      <div className="flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <Link
            className="inline-flex items-center gap-1.5 text-xs font-semibold text-gray-600 hover:text-gray-900 transition"
            href="/hr-emploc"
          >
            <ArrowLeft className="h-3.5 w-3.5" />
            <span>Back to HR Emploc</span>
          </Link>
        </div>

        <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold tracking-tight text-gray-900">
              HR Emploc Bulk XLSX Import & Reconciliation Wizard
            </h1>
            <p className="text-xs text-gray-500">
              Bulk recruit onboarding pipeline with slot-first capacity reservation, ADR-001 reconciliation, and rollback safety.
            </p>
          </div>
        </div>
      </div>

      {/* 3-Tab Wizard Navigation */}
      <div
        aria-label="Import wizard navigation tabs"
        className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none border-b border-border-subtle pb-3"
        role="tablist"
      >
        <button
          aria-selected={activeTab === "upload"}
          className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
            activeTab === "upload"
              ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
              : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
          }`}
          onClick={() => setActiveTab("upload")}
          role="tab"
          type="button"
        >
          <UploadCloud
            className={`w-4 h-4 shrink-0 transition-colors ${
              activeTab === "upload"
                ? "text-brand-700"
                : "text-text-muted group-hover:text-text-secondary"
            }`}
          />
          <span>Upload & Preview</span>
        </button>

        <button
          aria-selected={activeTab === "review"}
          className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
            activeTab === "review"
              ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
              : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
          }`}
          onClick={() => setActiveTab("review")}
          role="tab"
          type="button"
        >
          <Clock
            className={`w-4 h-4 shrink-0 transition-colors ${
              activeTab === "review"
                ? "text-brand-700"
                : "text-text-muted group-hover:text-text-secondary"
            }`}
          />
          <span>Review Batches</span>
          <span
            className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
              activeTab === "review"
                ? "bg-brand-600 text-white"
                : "bg-slate-100 text-slate-600 border border-slate-200/80"
            }`}
          >
            {pendingCount}
          </span>
        </button>

        <button
          aria-selected={activeTab === "history"}
          className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
            activeTab === "history"
              ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
              : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
          }`}
          onClick={() => setActiveTab("history")}
          role="tab"
          type="button"
        >
          <History
            className={`w-4 h-4 shrink-0 transition-colors ${
              activeTab === "history"
                ? "text-brand-700"
                : "text-text-muted group-hover:text-text-secondary"
            }`}
          />
          <span>History & Rollback</span>
          <span
            className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
              activeTab === "history"
                ? "bg-brand-600 text-white"
                : "bg-slate-100 text-slate-600 border border-slate-200/80"
            }`}
          >
            {historyCount}
          </span>
        </button>
      </div>

      {/* Tab Panels */}
      <div className="flex-1">
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
  );
}
