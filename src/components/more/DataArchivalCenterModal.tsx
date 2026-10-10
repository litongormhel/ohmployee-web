"use client";

import { useState } from "react";
import {
  Archive,
  RefreshCw,
  RotateCcw,
  Search,
  X,
} from "lucide-react";
import {
  useArchiveSnapshot,
  useRestorePlantilla,
  useRestoreVacancy,
} from "@/lib/queries/more";

export interface DataArchivalCenterModalProps {
  isOpen: boolean;
  onClose: () => void;
  canRestore: boolean;
}

export function DataArchivalCenterModal({
  isOpen,
  onClose,
  canRestore,
}: DataArchivalCenterModalProps) {
  const [activeTab, setActiveTab] = useState<"plantilla" | "vacancies" | "audit">("plantilla");
  const [searchQuery, setSearchQuery] = useState("");
  const [restorePrompt, setRestorePrompt] = useState<{
    type: "plantilla" | "vacancy";
    id: string;
    label: string;
  } | null>(null);
  const [reason, setReason] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const { data: snapshot, isLoading, refetch, isFetching } = useArchiveSnapshot();
  const restorePlantillaMutation = useRestorePlantilla();
  const restoreVacancyMutation = useRestoreVacancy();

  if (!isOpen) return null;

  const plantillaList = (snapshot?.plantilla ?? []).filter((p) => {
    if (!searchQuery) return true;
    const q = searchQuery.toLowerCase();
    return (
      p.employeeName.toLowerCase().includes(q) ||
      p.employeeNo.toLowerCase().includes(q) ||
      p.storeName.toLowerCase().includes(q) ||
      p.account.toLowerCase().includes(q)
    );
  });

  const vacanciesList = (snapshot?.vacancies ?? []).filter((v) => {
    if (!searchQuery) return true;
    const q = searchQuery.toLowerCase();
    return (
      pMatches(v.vcode, q) ||
      pMatches(v.storeName, q) ||
      pMatches(v.account, q) ||
      pMatches(v.position, q)
    );
  });

  function pMatches(field: string | null | undefined, q: string) {
    return (field || "").toLowerCase().includes(q);
  }

  const auditLogs = snapshot?.auditLogs ?? [];

  const handleOpenRestore = (type: "plantilla" | "vacancy", id: string, label: string) => {
    setRestorePrompt({ type, id, label });
    setReason("");
    setErrorMessage(null);
  };

  const handleConfirmRestore = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!restorePrompt) return;
    if (!reason.trim()) {
      setErrorMessage("Please enter an audited reason for restoring this record.");
      return;
    }

    try {
      setErrorMessage(null);
      if (restorePrompt.type === "plantilla") {
        await restorePlantillaMutation.mutateAsync({
          plantillaId: restorePrompt.id,
          reason,
        });
      } else {
        await restoreVacancyMutation.mutateAsync({
          vacancyId: restorePrompt.id,
          reason,
        });
      }
      setRestorePrompt(null);
      setReason("");
      refetch();
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to restore record.";
      setErrorMessage(msg);
    }
  };

  const isRestoring =
    restorePlantillaMutation.isPending || restoreVacancyMutation.isPending;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="archival-center-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/60 backdrop-blur-xs animate-in fade-in duration-200"
    >
      <div className="relative w-full max-w-4xl bg-white rounded-2xl shadow-2xl border border-slate-200 overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4.5 border-b border-slate-200 bg-slate-50/80">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center">
              <Archive className="w-5 h-5" />
            </div>
            <div>
              <h2 id="archival-center-title" className="text-base font-bold text-slate-900 leading-tight">
                Data Archival & Recovery Center
              </h2>
              <p className="text-xs text-slate-500">
                Recycle bin inspection and rollback controls for archived Plantilla and Vacancies
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-200/60 transition-colors"
            aria-label="Close modal"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Search & Tabs */}
        <div className="px-6 py-3 border-b border-slate-200 bg-white flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => setActiveTab("plantilla")}
              className={`pb-2 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                activeTab === "plantilla"
                  ? "border-purple-600 text-purple-900"
                  : "border-transparent text-slate-500 hover:text-slate-800"
              }`}
            >
              <span>Archived Plantilla</span>
              <span className="px-1.5 py-0.2 rounded-full text-[10px] bg-purple-100 text-purple-800 font-bold">
                {snapshot?.plantilla.length ?? 0}
              </span>
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("vacancies")}
              className={`pb-2 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                activeTab === "vacancies"
                  ? "border-purple-600 text-purple-900"
                  : "border-transparent text-slate-500 hover:text-slate-800"
              }`}
            >
              <span>Archived Vacancies</span>
              <span className="px-1.5 py-0.2 rounded-full text-[10px] bg-slate-100 text-slate-700 font-bold">
                {snapshot?.vacancies.length ?? 0}
              </span>
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("audit")}
              className={`pb-2 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                activeTab === "audit"
                  ? "border-purple-600 text-purple-900"
                  : "border-transparent text-slate-500 hover:text-slate-800"
              }`}
            >
              <span>Archival Logs</span>
              <span className="px-1.5 py-0.2 rounded-full text-[10px] bg-slate-100 text-slate-700 font-bold">
                {snapshot?.auditLogs.length ?? 0}
              </span>
            </button>
          </div>

          <div className="relative w-full sm:w-64">
            <Search className="w-3.5 h-3.5 absolute left-3 top-2.5 text-slate-400" />
            <input
              type="text"
              placeholder="Filter by name, store, vcode..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full text-xs pl-8 pr-3 py-1.5 border border-slate-200 rounded-lg bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500"
            />
          </div>
        </div>

        {/* Content Body */}
        <div className="p-6 overflow-y-auto flex-1 space-y-4">
          {/* Restore Confirmation Dialog Overlay */}
          {restorePrompt && (
            <form
              onSubmit={handleConfirmRestore}
              className="p-4 bg-purple-50 border border-purple-200 rounded-xl space-y-3 text-xs"
            >
              <div className="flex items-center justify-between">
                <span className="font-bold text-slate-900 flex items-center gap-1.5">
                  <RotateCcw className="w-4 h-4 text-purple-600" />
                  Restore {restorePrompt.type === "plantilla" ? "Plantilla Employee" : "Vacancy Requisition"}:{" "}
                  <span className="text-purple-900">{restorePrompt.label}</span>
                </span>
                <button
                  type="button"
                  onClick={() => setRestorePrompt(null)}
                  className="text-slate-400 hover:text-slate-600 text-xs"
                >
                  Cancel
                </button>
              </div>

              <div>
                <label className="block font-medium text-slate-700 mb-1">
                  Reason for Restoration <span className="text-rose-500">*</span>
                </label>
                <textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g., Record inadvertently soft-deleted during seasonal cleanup; employee is active..."
                  rows={2}
                  className="w-full text-xs px-3 py-2 border border-slate-300 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-purple-500"
                  autoFocus
                />
              </div>

              {errorMessage && (
                <p className="text-xs text-rose-600 font-medium">{errorMessage}</p>
              )}

              <div className="flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setRestorePrompt(null)}
                  className="px-3 py-1.5 text-xs text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isRestoring}
                  className="px-3.5 py-1.5 text-xs font-semibold text-white bg-purple-600 hover:bg-purple-700 rounded-lg shadow-xs flex items-center gap-1.5"
                >
                  {isRestoring && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                  <span>Confirm Restore</span>
                </button>
              </div>
            </form>
          )}

          {activeTab === "plantilla" ? (
            /* Plantilla Table */
            <div className="border border-slate-200 rounded-xl overflow-hidden text-xs">
              <table className="w-full text-left divide-y divide-slate-200">
                <thead className="bg-slate-50 text-slate-600 font-semibold">
                  <tr>
                    <th className="px-4 py-3">Employee</th>
                    <th className="px-4 py-3">Position & Store</th>
                    <th className="px-4 py-3">Account</th>
                    <th className="px-4 py-3">Archived By / Date</th>
                    <th className="px-4 py-3 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 bg-white text-slate-700">
                  {isLoading ? (
                    <tr>
                      <td colSpan={5} className="px-4 py-10 text-center text-slate-400">
                        Loading archived records...
                      </td>
                    </tr>
                  ) : plantillaList.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="px-4 py-10 text-center text-slate-400">
                        No archived plantilla records found.
                      </td>
                    </tr>
                  ) : (
                    plantillaList.map((row) => (
                      <tr key={row.id} className="hover:bg-slate-50/70 transition-colors">
                        <td className="px-4 py-2.5">
                          <div className="font-semibold text-slate-900">{row.employeeName}</div>
                          <div className="text-[11px] text-slate-400 font-mono">{row.employeeNo}</div>
                        </td>
                        <td className="px-4 py-2.5">
                          <div className="font-medium text-slate-800">{row.position}</div>
                          <div className="text-[11px] text-slate-500">{row.storeName}</div>
                        </td>
                        <td className="px-4 py-2.5">
                          <span className="px-2 py-0.5 rounded-md bg-slate-100 text-slate-700 font-medium text-[11px]">
                            {row.account}
                          </span>
                        </td>
                        <td className="px-4 py-2.5">
                          <div className="text-slate-800">{row.archivedByName || "System"}</div>
                          <div className="text-[11px] text-slate-400">
                            {row.archivedAt ? new Date(row.archivedAt).toLocaleDateString() : "—"}
                          </div>
                        </td>
                        <td className="px-4 py-2.5 text-right">
                          {canRestore ? (
                            <button
                              type="button"
                              onClick={() => handleOpenRestore("plantilla", row.id, row.employeeName)}
                              className="px-2.5 py-1 text-[11px] font-semibold text-purple-700 bg-purple-50 hover:bg-purple-100 rounded-lg border border-purple-200 transition-colors inline-flex items-center gap-1"
                            >
                              <RotateCcw className="w-3 h-3" />
                              <span>Restore</span>
                            </button>
                          ) : (
                            <span className="text-[11px] text-slate-400">Read-only</span>
                          )}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          ) : activeTab === "vacancies" ? (
            /* Vacancies Table */
            <div className="border border-slate-200 rounded-xl overflow-hidden text-xs">
              <table className="w-full text-left divide-y divide-slate-200">
                <thead className="bg-slate-50 text-slate-600 font-semibold">
                  <tr>
                    <th className="px-4 py-3">VCODE</th>
                    <th className="px-4 py-3">Position</th>
                    <th className="px-4 py-3">Store & Account</th>
                    <th className="px-4 py-3">Archived By / Date</th>
                    <th className="px-4 py-3 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 bg-white text-slate-700">
                  {isLoading ? (
                    <tr>
                      <td colSpan={5} className="px-4 py-10 text-center text-slate-400">
                        Loading archived vacancies...
                      </td>
                    </tr>
                  ) : vacanciesList.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="px-4 py-10 text-center text-slate-400">
                        No archived vacancies found.
                      </td>
                    </tr>
                  ) : (
                    vacanciesList.map((row) => (
                      <tr key={row.id} className="hover:bg-slate-50/70 transition-colors">
                        <td className="px-4 py-2.5 font-mono font-bold text-slate-900">
                          {row.vcode}
                        </td>
                        <td className="px-4 py-2.5 font-medium text-slate-800">
                          {row.position}
                        </td>
                        <td className="px-4 py-2.5">
                          <div className="font-medium text-slate-800">{row.storeName}</div>
                          <div className="text-[11px] text-slate-500">{row.account}</div>
                        </td>
                        <td className="px-4 py-2.5">
                          <div className="text-slate-800">{row.archivedByName || "System"}</div>
                          <div className="text-[11px] text-slate-400">
                            {row.archivedAt ? new Date(row.archivedAt).toLocaleDateString() : "—"}
                          </div>
                        </td>
                        <td className="px-4 py-2.5 text-right">
                          {canRestore ? (
                            <button
                              type="button"
                              onClick={() => handleOpenRestore("vacancy", row.id, row.vcode)}
                              className="px-2.5 py-1 text-[11px] font-semibold text-purple-700 bg-purple-50 hover:bg-purple-100 rounded-lg border border-purple-200 transition-colors inline-flex items-center gap-1"
                            >
                              <RotateCcw className="w-3 h-3" />
                              <span>Restore</span>
                            </button>
                          ) : (
                            <span className="text-[11px] text-slate-400">Read-only</span>
                          )}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          ) : (
            /* Audit Logs View */
            <div className="space-y-2 text-xs">
              {auditLogs.length === 0 ? (
                <div className="py-10 text-center text-slate-400">No archival audit entries found.</div>
              ) : (
                auditLogs.map((log) => (
                  <div
                    key={log.id}
                    className="p-3 bg-slate-50/60 border border-slate-200 rounded-xl flex items-start justify-between gap-3"
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-slate-900 uppercase tracking-wider text-[11px]">
                          [{log.module}] {log.actionType}
                        </span>
                        <span className="text-[11px] font-mono text-slate-500">ID: {log.recordId}</span>
                      </div>
                      {log.reason && (
                        <p className="text-[11px] text-slate-600 mt-1 italic">“{log.reason}”</p>
                      )}
                    </div>
                    <span className="text-[11px] text-slate-400 whitespace-nowrap">
                      {new Date(log.createdAt).toLocaleString()}
                    </span>
                  </div>
                ))
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-4 border-t border-slate-200 bg-slate-50/50">
          <button
            type="button"
            onClick={() => refetch()}
            disabled={isFetching}
            className="flex items-center gap-1.5 text-xs text-slate-500 hover:text-slate-800"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isFetching ? "animate-spin" : ""}`} />
            <span>Refresh</span>
          </button>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium text-slate-700 bg-white border border-slate-300 rounded-xl hover:bg-slate-50 transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
