"use client";

import { useState } from "react";
import { Download, FileSpreadsheet, Loader2, Store, Users, X } from "lucide-react";
import { useAttritionDetails } from "@/lib/queries/reports";
import { exportMultiSheetXlsx, exportToCsv } from "@/lib/utils/reports_export";

interface AttritionDrilldownModalProps {
  accountId: string;
  accountName: string;
  startDate?: string | null;
  endDate?: string | null;
  onClose: () => void;
}

export function AttritionDrilldownModal({
  accountId,
  accountName,
  startDate,
  endDate,
  onClose,
}: AttritionDrilldownModalProps) {
  const [activeTab, setActiveTab] = useState<"employees" | "stores">("employees");
  const [searchQuery, setSearchQuery] = useState("");

  const { data, isLoading, error } = useAttritionDetails(
    accountId,
    startDate,
    endDate
  );

  const employees = data?.employees ?? [];
  const stores = data?.stores ?? [];

  const filteredEmployees = employees.filter(
    (e) =>
      e.employeeName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (e.employeeNo && e.employeeNo.toLowerCase().includes(searchQuery.toLowerCase())) ||
      e.storeName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      e.position.toLowerCase().includes(searchQuery.toLowerCase()) ||
      e.reason.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const filteredStores = stores.filter(
    (s) =>
      s.storeName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      s.location.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleExportXlsx = () => {
    exportMultiSheetXlsx(
      [
        {
          name: "Separated Employees",
          data: employees.map((e) => ({
            "Employee Name": e.employeeName,
            "Employee No": e.employeeNo || "—",
            "Store Branch": e.storeName,
            Position: e.position,
            "Separation Date": e.separationDate ? e.separationDate.substring(0, 10) : "—",
            Reason: e.reason,
            Status: e.separationStatus || "Separated",
          })),
        },
        {
          name: "Affected Stores",
          data: stores.map((s) => ({
            "Store Name": s.storeName,
            Location: s.location,
            "Separated Headcount": s.separatedCount,
          })),
        },
      ],
      `Attrition_Drilldown_${accountName.replace(/\s+/g, "_")}`
    );
  };

  const handleExportCsv = () => {
    if (activeTab === "employees") {
      exportToCsv(
        employees.map((e) => ({
          "Employee Name": e.employeeName,
          "Employee No": e.employeeNo || "—",
          "Store Branch": e.storeName,
          Position: e.position,
          "Separation Date": e.separationDate ? e.separationDate.substring(0, 10) : "—",
          Reason: e.reason,
          Status: e.separationStatus || "Separated",
        })),
        `Attrition_Employees_${accountName.replace(/\s+/g, "_")}`
      );
    } else {
      exportToCsv(
        stores.map((s) => ({
          "Store Name": s.storeName,
          Location: s.location,
          "Separated Headcount": s.separatedCount,
        })),
        `Attrition_Stores_${accountName.replace(/\s+/g, "_")}`
      );
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 backdrop-blur-xs p-4 animate-in fade-in duration-150">
      <div className="relative flex flex-col w-full max-w-4xl max-h-[90vh] bg-surface-base rounded-xl border border-border-default shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-border-subtle bg-surface-muted/40">
          <div>
            <div className="flex items-center gap-2">
              <span className="text-[10px] font-bold uppercase tracking-wider text-brand-600 bg-brand-50 px-2 py-0.5 rounded border border-brand-200">
                Attrition Audit Drilldown
              </span>
              {startDate && endDate && (
                <span className="text-xs text-text-muted">
                  {startDate} to {endDate}
                </span>
              )}
            </div>
            <h2 className="text-lg font-bold text-text-primary mt-1">
              {accountName} — Movement & Separation Details
            </h2>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-text-muted hover:text-text-primary hover:bg-surface-hover transition cursor-pointer"
            aria-label="Close modal"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Toolbar */}
        <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-3 border-b border-border-subtle bg-surface-base">
          <div className="flex items-center gap-2">
            <button
              onClick={() => setActiveTab("employees")}
              className={`flex items-center gap-2 px-3 py-1.5 text-xs font-semibold rounded-lg transition cursor-pointer ${
                activeTab === "employees"
                  ? "bg-brand-50 text-brand-700 border border-brand-200 shadow-2xs"
                  : "text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <Users className="w-3.5 h-3.5" />
              Separated Staff ({employees.length})
            </button>
            <button
              onClick={() => setActiveTab("stores")}
              className={`flex items-center gap-2 px-3 py-1.5 text-xs font-semibold rounded-lg transition cursor-pointer ${
                activeTab === "stores"
                  ? "bg-brand-50 text-brand-700 border border-brand-200 shadow-2xs"
                  : "text-text-secondary hover:bg-surface-hover"
              }`}
            >
              <Store className="w-3.5 h-3.5" />
              Affected Stores ({stores.length})
            </button>
          </div>

          <div className="flex items-center gap-2 ml-auto">
            <input
              type="text"
              placeholder={`Search ${activeTab}...`}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="h-8 px-3 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500 w-48 sm:w-64"
            />
            <button
              onClick={handleExportXlsx}
              disabled={isLoading || !employees.length}
              className="flex items-center gap-1.5 h-8 px-2.5 text-xs font-medium text-emerald-700 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 rounded-md transition cursor-pointer disabled:opacity-50"
              title="Export complete workbook to XLSX"
            >
              <FileSpreadsheet className="w-3.5 h-3.5" />
              XLSX
            </button>
            <button
              onClick={handleExportCsv}
              disabled={isLoading || !employees.length}
              className="flex items-center gap-1.5 h-8 px-2.5 text-xs font-medium text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer disabled:opacity-50"
              title="Export active view to CSV"
            >
              <Download className="w-3.5 h-3.5" />
              CSV
            </button>
          </div>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6">
          {isLoading ? (
            <div className="flex flex-col items-center justify-center py-20 text-text-muted">
              <Loader2 className="w-8 h-8 animate-spin text-brand-600 mb-2" />
              <p className="text-xs font-medium">Loading attrition separation records...</p>
            </div>
          ) : error ? (
            <div className="p-4 rounded-lg bg-rose-50 border border-rose-200 text-rose-800 text-sm">
              Failed to load attrition details. {String(error)}
            </div>
          ) : activeTab === "employees" ? (
            filteredEmployees.length === 0 ? (
              <div className="text-center py-16 text-text-muted text-xs">
                No separated employee records match your search criteria.
              </div>
            ) : (
              <div className="overflow-x-auto border border-border-subtle rounded-lg">
                <table className="w-full text-left text-xs">
                  <thead className="bg-surface-muted border-b border-border-subtle text-text-secondary uppercase text-[10px] tracking-wider font-semibold">
                    <tr>
                      <th className="py-2.5 px-3">Employee</th>
                      <th className="py-2.5 px-3">Position</th>
                      <th className="py-2.5 px-3">Store Branch</th>
                      <th className="py-2.5 px-3">Separation Date</th>
                      <th className="py-2.5 px-3">Reason / Details</th>
                      <th className="py-2.5 px-3 text-right">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border-subtle font-medium">
                    {filteredEmployees.map((emp) => (
                      <tr key={emp.id || `${emp.employeeName}-${emp.storeName}`} className="hover:bg-surface-hover/50 transition">
                        <td className="py-2.5 px-3">
                          <div className="font-semibold text-text-primary">{emp.employeeName}</div>
                          {emp.employeeNo && (
                            <div className="text-[10px] text-text-muted font-mono">#{emp.employeeNo}</div>
                          )}
                        </td>
                        <td className="py-2.5 px-3 text-text-secondary">{emp.position}</td>
                        <td className="py-2.5 px-3 text-text-secondary">{emp.storeName}</td>
                        <td className="py-2.5 px-3 text-text-secondary font-mono text-[11px]">
                          {emp.separationDate ? emp.separationDate.substring(0, 10) : "—"}
                        </td>
                        <td className="py-2.5 px-3 text-text-secondary max-w-xs truncate" title={emp.reason}>
                          {emp.reason}
                        </td>
                        <td className="py-2.5 px-3 text-right">
                          <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-semibold bg-rose-50 text-rose-700 border border-rose-200">
                            {emp.separationStatus || "Separated"}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )
          ) : filteredStores.length === 0 ? (
            <div className="text-center py-16 text-text-muted text-xs">
              No affected stores match your search criteria.
            </div>
          ) : (
            <div className="overflow-x-auto border border-border-subtle rounded-lg">
              <table className="w-full text-left text-xs">
                <thead className="bg-surface-muted border-b border-border-subtle text-text-secondary uppercase text-[10px] tracking-wider font-semibold">
                  <tr>
                    <th className="py-2.5 px-3">Store Branch</th>
                    <th className="py-2.5 px-3">Location / Area</th>
                    <th className="py-2.5 px-3 text-right">Separated Headcount</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle font-medium">
                  {filteredStores.map((store) => (
                    <tr key={store.storeName} className="hover:bg-surface-hover/50 transition">
                      <td className="py-2.5 px-3 font-semibold text-text-primary flex items-center gap-2">
                        <Store className="w-3.5 h-3.5 text-text-muted shrink-0" />
                        {store.storeName}
                      </td>
                      <td className="py-2.5 px-3 text-text-secondary">{store.location}</td>
                      <td className="py-2.5 px-3 text-right">
                        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold bg-slate-100 text-slate-800 border border-slate-200">
                          {store.separatedCount}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-3 border-t border-border-subtle bg-surface-muted/30 text-xs text-text-muted">
          <span>
            Total: {employees.length} separated personnel across {stores.length} store locations
          </span>
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-xs font-semibold text-text-primary bg-surface-base hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer shadow-2xs"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
