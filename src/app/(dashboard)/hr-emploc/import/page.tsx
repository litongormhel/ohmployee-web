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
        className="flex flex-wrap items-center gap-2 border-b border-gray-200 pb-3"
        role="tablist"
      >
        <button
          aria-selected={activeTab === "upload"}
          className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-xs font-semibold transition ${
            activeTab === "upload"
              ? "bg-slate-900 text-white shadow-xs"
              : "border border-gray-200 bg-white text-gray-600 hover:border-gray-300 hover:bg-gray-50 hover:text-gray-900"
          }`}
          onClick={() => setActiveTab("upload")}
          role="tab"
          type="button"
        >
          <UploadCloud className="h-3.5 w-3.5" />
          <span>Upload & Preview</span>
        </button>

        <button
          aria-selected={activeTab === "review"}
          className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-xs font-semibold transition ${
            activeTab === "review"
              ? "bg-slate-900 text-white shadow-xs"
              : "border border-gray-200 bg-white text-gray-600 hover:border-gray-300 hover:bg-gray-50 hover:text-gray-900"
          }`}
          onClick={() => setActiveTab("review")}
          role="tab"
          type="button"
        >
          <Clock className="h-3.5 w-3.5" />
          <span>Review Batches</span>
          <span
            className={`inline-flex items-center justify-center rounded-full px-2 py-0.5 text-[10px] font-bold ${
              activeTab === "review"
                ? "bg-white/20 text-white"
                : "border border-gray-200/80 bg-gray-100 text-gray-600"
            }`}
          >
            {pendingCount}
          </span>
        </button>

        <button
          aria-selected={activeTab === "history"}
          className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-xs font-semibold transition ${
            activeTab === "history"
              ? "bg-slate-900 text-white shadow-xs"
              : "border border-gray-200 bg-white text-gray-600 hover:border-gray-300 hover:bg-gray-50 hover:text-gray-900"
          }`}
          onClick={() => setActiveTab("history")}
          role="tab"
          type="button"
        >
          <History className="h-3.5 w-3.5" />
          <span>History & Rollback</span>
          <span
            className={`inline-flex items-center justify-center rounded-full px-2 py-0.5 text-[10px] font-bold ${
              activeTab === "history"
                ? "bg-white/20 text-white"
                : "border border-gray-200/80 bg-gray-100 text-gray-600"
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
