"use client";

import { Suspense, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  FileBarChart,
  FileBarChart2,
  FileSpreadsheet,
  Layers,
  ShieldAlert,
  Users,
} from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { ReportsCatalogTab } from "@/components/reports/ReportsCatalogTab";
import { FloatingStaffTab } from "@/components/reports/FloatingStaffTab";
import { TeamPerformanceTab } from "@/components/reports/TeamPerformanceTab";
import { DataIntegrityTab } from "@/components/reports/DataIntegrityTab";
import { CustomReportTab } from "@/components/reports/CustomReportTab";

type ReportTab =
  | "catalog"
  | "floating"
  | "team_performance"
  | "data_integrity"
  | "custom";

function ReportsPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const tabParam = searchParams.get("tab");
  const reportParam = searchParams.get("report");

  // Backward-compatible query redirects for legacy qa and drift tabs
  useEffect(() => {
    if (tabParam === "qa_center" || tabParam === "qa") {
      router.replace("/more?open=qa_center");
    } else if (tabParam === "permission_drift" || tabParam === "drift") {
      router.replace("/more?open=permission_drift");
    }
  }, [tabParam, router]);

  const activeTab: ReportTab =
    tabParam === "floating" ||
    tabParam === "team_performance" ||
    tabParam === "data_integrity" ||
    tabParam === "custom"
      ? tabParam
      : "catalog";

  const handleTabChange = (newTab: string) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("tab", newTab);
    params.delete("report");
    router.push(`/reports?${params.toString()}`);
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <AdminPageHeader
        categoryTag="OPERATIONAL SUITE"
        moduleName="REPORTS & ANALYTICS"
        title="Operational Reports Hub"
        subtitle="Consolidated workforce intelligence covering Attrition, Floating, Team Performance, Data Integrity, and Custom Query Builder."
        icon={FileBarChart}
      />

      {/* High-Density Multi-Tab Bar */}
      <div className="flex items-center gap-1.5 overflow-x-auto no-scrollbar border-b border-border-subtle pb-2">
        <button
          onClick={() => handleTabChange("catalog")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "catalog"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <FileBarChart2 className="w-3.5 h-3.5" />
          Overview & Quick Reports
        </button>

        <button
          onClick={() => handleTabChange("floating")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "floating"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <Users className="w-3.5 h-3.5" />
          Floating Staff
        </button>

        <button
          onClick={() => handleTabChange("team_performance")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "team_performance"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <Layers className="w-3.5 h-3.5" />
          Team Performance
        </button>

        <button
          onClick={() => handleTabChange("data_integrity")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "data_integrity"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <ShieldAlert className="w-3.5 h-3.5" />
          Data Integrity
        </button>

        <button
          onClick={() => handleTabChange("custom")}
          className={`flex items-center gap-2 px-3.5 py-2 text-xs font-semibold rounded-lg transition whitespace-nowrap cursor-pointer ${
            activeTab === "custom"
              ? "bg-brand-50 text-brand-900 border border-brand-200 shadow-2xs"
              : "text-text-secondary hover:text-text-primary hover:bg-surface-hover border border-transparent"
          }`}
        >
          <FileSpreadsheet className="w-3.5 h-3.5" />
          Custom Report Builder
        </button>
      </div>

      {/* Tab Panels */}
      <div>
        {activeTab === "catalog" && (
          <ReportsCatalogTab
            initialReportId={reportParam}
            onSwitchTab={handleTabChange}
          />
        )}
        {activeTab === "floating" && <FloatingStaffTab />}
        {activeTab === "team_performance" && <TeamPerformanceTab />}
        {activeTab === "data_integrity" && <DataIntegrityTab />}
        {activeTab === "custom" && <CustomReportTab />}
      </div>
    </div>
  );
}

export default function ReportsPage() {
  return (
    <Suspense fallback={<div className="h-64 animate-pulse bg-surface-base rounded-xl" />}>
      <ReportsPageContent />
    </Suspense>
  );
}
