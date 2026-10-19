"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Archive,
  CheckCircle2,
  Clock,
  Layers,
  Lock,
  RefreshCw,
  RotateCcw,
  Search,
  ShieldAlert,
  X,
} from "lucide-react";
import {
  useArchiveSnapshot,
  useRestorePlantilla,
  useRestoreVacancy,
  useArchiveImpactPreview,
  useArchiveBatchHistory,
  useExecuteBulkArchive,
  useRollbackArchiveBatch,
} from "@/lib/queries/more";

export interface DataArchivalCenterModalProps {
  isOpen: boolean;
  onClose: () => void;
  canRestore: boolean;
}

type ArchivalTab = "plantilla" | "vacancies" | "audit" | "execute_archive" | "batch_history";

interface ArchiveConfig {
  title: string;
  actionType: "qa_reset" | "plantilla" | "vacancy" | "hr_emploc" | "moses_hq";
  confirmPhrase: string;
  description: string;
}

const ARCHIVE_ACTIONS: ArchiveConfig[] = [
  {
    title: "QA Reset Archive",
    actionType: "qa_reset",
    confirmPhrase: "ARCHIVE QA DATA",
    description:
      "Archives Plantilla, Vacancies, HR Emploc, Moses HQ, Slots, and Headcount Requests in a single atomic batch transaction. Use before QA test cycles.",
  },
  {
    title: "Archive Plantilla",
    actionType: "plantilla",
    confirmPhrase: "ARCHIVE PLANTILLA DATA",
    description:
      "Archives all active Plantilla records, closes open Plantilla Slots, and cascades into Moses HQ.",
  },
  {
    title: "Archive Vacancy",
    actionType: "vacancy",
    confirmPhrase: "ARCHIVE VACANCY DATA",
    description:
      "Archives all active Vacancies and related requisition items across operational groups.",
  },
  {
    title: "Archive HR Emploc",
    actionType: "hr_emploc",
    confirmPhrase: "ARCHIVE HR EMPLOC DATA",
    description:
      "Archives all active HR Emploc employee records and pending onboarding submissions.",
  },
  {
    title: "Archive Moses HQ",
    actionType: "moses_hq",
    confirmPhrase: "ARCHIVE MOSES HQ DATA",
    description:
      "Archives Workforce Pools, Pool Slots, Assignments, Requests, and related operational data.",
  },
];

export function DataArchivalCenterModal({
  isOpen,
  onClose,
  canRestore,
}: DataArchivalCenterModalProps) {
  const [activeTab, setActiveTab] = useState<ArchivalTab>("execute_archive");
  const [searchQuery, setSearchQuery] = useState("");

  // Restore prompt state (for Plantilla / Vacancy tabs)
  const [restorePrompt, setRestorePrompt] = useState<{
    type: "plantilla" | "vacancy";
    id: string;
    label: string;
  } | null>(null);
  const [reason, setReason] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Bulk Archive execution modal state
  const [activeArchiveWizard, setActiveArchiveWizard] = useState<ArchiveConfig | null>(null);
  const [typedConfirmation, setTypedConfirmation] = useState("");
  const [archiveReason, setArchiveReason] = useState("");
  const [wizardError, setWizardError] = useState<string | null>(null);

  // Rollback prompt state
  const [pendingRollbackBatchId, setPendingRollbackBatchId] = useState<string | null>(null);
  const [rollbackReason, setRollbackReason] = useState("");
  const [rollbackError, setRollbackError] = useState<string | null>(null);

  // Queries & Mutations
  const { data: snapshot, isLoading: snapshotLoading, refetch: refetchSnapshot, isFetching: snapshotFetching } =
    useArchiveSnapshot();
  const { data: impactPreview, isLoading: impactLoading, refetch: refetchImpact } =
    useArchiveImpactPreview();
  const { data: batchHistory = [], isLoading: historyLoading, refetch: refetchHistory, isFetching: historyFetching } =
    useArchiveBatchHistory();

  const restorePlantillaMutation = useRestorePlantilla();
  const restoreVacancyMutation = useRestoreVacancy();
  const bulkArchiveMutation = useExecuteBulkArchive();
  const rollbackMutation = useRollbackArchiveBatch();

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
      refetchSnapshot();
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to restore record.";
      setErrorMessage(msg);
    }
  };

  const handleExecuteArchive = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeArchiveWizard) return;

    if (typedConfirmation.trim().toUpperCase() !== activeArchiveWizard.confirmPhrase) {
      setWizardError(`Please type "${activeArchiveWizard.confirmPhrase}" exactly to confirm.`);
      return;
    }

    if (!archiveReason.trim()) {
      setWizardError("Operational justification reason is required.");
      return;
    }

    try {
      setWizardError(null);
      await bulkArchiveMutation.mutateAsync({
        actionType: activeArchiveWizard.actionType,
        reason: archiveReason.trim(),
      });
      setActiveArchiveWizard(null);
      setTypedConfirmation("");
      setArchiveReason("");
      setActiveTab("batch_history");
      refetchHistory();
    } catch (err) {
      setWizardError(err instanceof Error ? err.message : "Bulk archive failed.");
    }
  };

  const handleRollbackBatch = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pendingRollbackBatchId) return;

    if (!rollbackReason.trim()) {
      setRollbackError("Rollback justification reason is required.");
      return;
    }

    try {
      setRollbackError(null);
      await rollbackMutation.mutateAsync({
        batchId: pendingRollbackBatchId,
        reason: rollbackReason.trim(),
      });
      setPendingRollbackBatchId(null);
      setRollbackReason("");
      refetchHistory();
    } catch (err) {
      setRollbackError(err instanceof Error ? err.message : "Rollback batch failed.");
    }
  };

  const isRestoring =
    restorePlantillaMutation.isPending || restoreVacancyMutation.isPending;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="archival-center-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/70 backdrop-blur-xs animate-in fade-in duration-200"
    >
      <div className="relative w-full max-w-5xl bg-white rounded-2xl shadow-2xl border border-slate-200 overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4.5 border-b border-slate-200 bg-slate-50/80">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center shadow-xs">
              <Archive className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 id="archival-center-title" className="text-base font-bold text-slate-900 leading-tight">
                  Data Archival & Recovery Center
                </h2>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-rose-100 text-rose-800">
                  LEVEL 100 SUPER ADMIN
                </span>
              </div>
              <p className="text-xs text-slate-500">
                Bulk archive execution, QA reset triggers, soft-deleted recycle bin, and 72-hour batch rollback controls
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

        {/* High Risk Notice */}
        <div className="px-6 py-2.5 bg-rose-950 text-rose-100 text-xs flex items-center justify-between">
          <div className="flex items-center gap-2">
            <ShieldAlert className="w-4 h-4 text-rose-400 shrink-0" />
            <span>
              Archive operations immediately hide records from operational views without hard deletes. Rollback is available for 72 active hours.
            </span>
          </div>
          {impactPreview && (
            <div className="text-[11px] font-mono text-rose-300">
              Live Impactable: {impactPreview.total} items
            </div>
          )}
        </div>

        {/* Navigation Tabs */}
        <div className="px-6 py-2.5 border-b border-slate-200 bg-white flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div className="flex items-center gap-2 overflow-x-auto no-scrollbar scrollbar-none">
            <button
              type="button"
              onClick={() => setActiveTab("execute_archive")}
              className={`pb-2 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                activeTab === "execute_archive"
                  ? "border-rose-600 text-rose-900"
                  : "border-transparent text-slate-500 hover:text-slate-800"
              }`}
            >
              <AlertTriangle className="w-3.5 h-3.5 text-rose-600" />
              <span>Execute Archive / QA Reset</span>
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("batch_history")}
              className={`pb-2 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                activeTab === "batch_history"
                  ? "border-purple-600 text-purple-900"
                  : "border-transparent text-slate-500 hover:text-slate-800"
              }`}
            >
              <Clock className="w-3.5 h-3.5" />
              <span>Batch History & Rollback</span>
              <span className="px-1.5 py-0.2 rounded-full text-[10px] bg-slate-100 text-slate-700 font-bold">
                {batchHistory.length}
              </span>
            </button>
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
              <span>Audit Trail</span>
              <span className="px-1.5 py-0.2 rounded-full text-[10px] bg-slate-100 text-slate-700 font-bold">
                {snapshot?.auditLogs.length ?? 0}
              </span>
            </button>
          </div>

          {(activeTab === "plantilla" || activeTab === "vacancies") && (
            <div className="relative w-full sm:w-64">
              <Search className="w-3.5 h-3.5 absolute left-3 top-2.5 text-slate-400" />
              <input
                type="text"
                placeholder="Filter by name, store, vcode..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full text-xs pl-8 pr-3 py-1.5 border border-slate-200 rounded-lg bg-slate-50 focus:bg-white focus:outline-hidden focus:ring-2 focus:ring-purple-500"
              />
            </div>
          )}
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6">
          {/* TAB 1: EXECUTE ARCHIVE & QA RESET */}
          {activeTab === "execute_archive" && (
            <div className="space-y-6">
              {/* Impact summary counters */}
              <div className="p-4 rounded-xl bg-slate-50 border border-slate-200">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-xs font-bold uppercase tracking-wider text-slate-700">
                    Live Active Data Impact Preview
                  </h3>
                  <button
                    type="button"
                    onClick={() => refetchImpact()}
                    className="text-[11px] text-slate-500 hover:text-slate-800 flex items-center gap-1"
                  >
                    <RefreshCw className="w-3 h-3" />
                    <span>Refresh Counters</span>
                  </button>
                </div>
                {impactLoading ? (
                  <div className="text-xs text-slate-400 py-2">Loading live impact counts...</div>
                ) : impactPreview ? (
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                    <div className="p-2.5 bg-white rounded-lg border border-slate-200">
                      <span className="text-[10px] uppercase font-semibold text-slate-400">Plantilla</span>
                      <p className="text-base font-bold text-slate-900">{impactPreview.plantillaCount}</p>
                    </div>
                    <div className="p-2.5 bg-white rounded-lg border border-slate-200">
                      <span className="text-[10px] uppercase font-semibold text-slate-400">Vacancies</span>
                      <p className="text-base font-bold text-slate-900">{impactPreview.vacancyCount}</p>
                    </div>
                    <div className="p-2.5 bg-white rounded-lg border border-slate-200">
                      <span className="text-[10px] uppercase font-semibold text-slate-400">HR Emploc</span>
                      <p className="text-base font-bold text-slate-900">{impactPreview.hrEmplocCount}</p>
                    </div>
                    <div className="p-2.5 bg-white rounded-lg border border-slate-200">
                      <span className="text-[10px] uppercase font-semibold text-slate-400">Moses HQ Items</span>
                      <p className="text-base font-bold text-slate-900">{impactPreview.mosesHqTotal}</p>
                    </div>
                  </div>
                ) : null}
              </div>

              {/* Action triggers grid */}
              <div className="space-y-3">
                <h3 className="text-xs font-bold uppercase tracking-wider text-slate-700">
                  Bulk & Single-Module Archival Actions
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {ARCHIVE_ACTIONS.map((action) => (
                    <div
                      key={action.actionType}
                      className={`p-4 rounded-xl border flex flex-col justify-between gap-4 shadow-xs ${
                        action.actionType === "qa_reset"
                          ? "bg-rose-50/40 border-rose-300"
                          : "bg-white border-slate-200"
                      }`}
                    >
                      <div>
                        <div className="flex items-center justify-between">
                          <h4 className="text-sm font-bold text-slate-900">{action.title}</h4>
                          <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-rose-100 text-rose-800 border border-rose-300">
                            {action.confirmPhrase}
                          </span>
                        </div>
                        <p className="text-xs text-slate-500 mt-1.5">{action.description}</p>
                      </div>

                      <button
                        type="button"
                        onClick={() => {
                          setActiveArchiveWizard(action);
                          setTypedConfirmation("");
                          setArchiveReason("");
                          setWizardError(null);
                        }}
                        className={`w-full py-2 px-3 rounded-lg text-xs font-bold transition-colors ${
                          action.actionType === "qa_reset"
                            ? "bg-rose-600 text-white hover:bg-rose-700"
                            : "bg-slate-900 text-white hover:bg-slate-800"
                        }`}
                      >
                        Launch Archive Wizard
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: BATCH HISTORY & ROLLBACK */}
          {activeTab === "batch_history" && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-sm font-bold text-slate-900">Archive Batch History</h3>
                  <p className="text-xs text-slate-500">
                    Track previous bulk archival executions. Batches in ACTIVE status can be rolled back within 72 hours.
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => refetchHistory()}
                  disabled={historyFetching}
                  className="px-3 py-1.5 rounded-lg text-xs font-semibold bg-slate-100 text-slate-700 hover:bg-slate-200 transition-colors flex items-center gap-1.5"
                >
                  <RefreshCw className={`w-3.5 h-3.5 ${historyFetching ? "animate-spin" : ""}`} />
                  <span>Refresh</span>
                </button>
              </div>

              {historyLoading ? (
                <div className="py-12 text-center text-xs text-slate-400">Loading batch history...</div>
              ) : batchHistory.length === 0 ? (
                <div className="py-12 text-center text-xs text-slate-400">No archive batches recorded yet.</div>
              ) : (
                <div className="space-y-3">
                  {batchHistory.map((batch) => (
                    <div
                      key={batch.id}
                      className="p-4 rounded-xl border border-slate-200 bg-white flex flex-col md:flex-row md:items-center justify-between gap-4 shadow-2xs"
                    >
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-xs font-bold text-slate-900">
                            {batch.actionType.toUpperCase()}
                          </span>
                          <span
                            className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                              batch.status === "ACTIVE"
                                ? "bg-emerald-100 text-emerald-800"
                                : batch.status === "ROLLED_BACK"
                                ? "bg-blue-100 text-blue-800"
                                : "bg-slate-100 text-slate-600"
                            }`}
                          >
                            {batch.status}
                          </span>
                          <span className="text-[11px] font-mono text-slate-400">
                            ID: {batch.archiveBatchId}
                          </span>
                        </div>
                        <p className="text-xs text-slate-600 italic">“{batch.reason}”</p>
                        <div className="flex flex-wrap items-center gap-3 text-[11px] text-slate-400 pt-1">
                          <span>By: {batch.executedByName}</span>
                          <span>Executed: {new Date(batch.executedAt).toLocaleString()}</span>
                          <span>Deadline: {new Date(batch.rollbackDeadline).toLocaleString()}</span>
                          <span className="font-semibold text-slate-700">
                            Total Records: {batch.totalCount}
                          </span>
                        </div>
                      </div>

                      {batch.canRollback && (
                        <button
                          type="button"
                          onClick={() => {
                            setPendingRollbackBatchId(batch.archiveBatchId);
                            setRollbackReason("");
                            setRollbackError(null);
                          }}
                          className="px-3 py-1.5 rounded-lg text-xs font-bold text-purple-700 bg-purple-50 hover:bg-purple-100 border border-purple-200 transition-colors flex items-center gap-1.5 self-start md:self-center shrink-0"
                        >
                          <RotateCcw className="w-3.5 h-3.5" />
                          <span>Rollback Batch</span>
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* TAB 3: ARCHIVED PLANTILLA TABLE */}
          {activeTab === "plantilla" && (
            <div className="border border-slate-200 rounded-xl overflow-hidden">
              <table className="w-full text-left text-xs">
                <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider text-[10px]">
                  <tr>
                    <th className="px-4 py-3">Employee</th>
                    <th className="px-4 py-3">Account & Store</th>
                    <th className="px-4 py-3">Position</th>
                    <th className="px-4 py-3">Archived By & Reason</th>
                    <th className="px-4 py-3 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {plantillaList.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="py-12 text-center text-slate-400">
                        No archived Plantilla records found.
                      </td>
                    </tr>
                  ) : (
                    plantillaList.map((row) => (
                      <tr key={row.id} className="hover:bg-slate-50/50">
                        <td className="px-4 py-3">
                          <div className="font-bold text-slate-900">{row.employeeName}</div>
                          <div className="text-[10px] text-slate-400 font-mono">{row.employeeNo}</div>
                        </td>
                        <td className="px-4 py-3">
                          <div className="font-semibold text-slate-800">{row.account}</div>
                          <div className="text-[10px] text-slate-400">{row.storeName}</div>
                        </td>
                        <td className="px-4 py-3 text-slate-600">{row.position}</td>
                        <td className="px-4 py-3">
                          <div className="text-[11px] text-slate-700 italic">
                            {row.archiveReason ? `“${row.archiveReason}”` : "No reason logged"}
                          </div>
                          <div className="text-[10px] text-slate-400">
                            {row.archivedByName ? `By ${row.archivedByName}` : "System"}{" "}
                            {row.archivedAt ? `on ${new Date(row.archivedAt).toLocaleDateString()}` : ""}
                          </div>
                        </td>
                        <td className="px-4 py-3 text-right">
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
          )}

          {/* TAB 4: ARCHIVED VACANCIES TABLE */}
          {activeTab === "vacancies" && (
            <div className="border border-slate-200 rounded-xl overflow-hidden">
              <table className="w-full text-left text-xs">
                <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider text-[10px]">
                  <tr>
                    <th className="px-4 py-3">VCODE</th>
                    <th className="px-4 py-3">Account & Store</th>
                    <th className="px-4 py-3">Position</th>
                    <th className="px-4 py-3">Archived By & Reason</th>
                    <th className="px-4 py-3 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {vacanciesList.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="py-12 text-center text-slate-400">
                        No archived Vacancies found.
                      </td>
                    </tr>
                  ) : (
                    vacanciesList.map((row) => (
                      <tr key={row.id} className="hover:bg-slate-50/50">
                        <td className="px-4 py-3 font-mono font-bold text-slate-900">{row.vcode}</td>
                        <td className="px-4 py-3">
                          <div className="font-semibold text-slate-800">{row.account}</div>
                          <div className="text-[10px] text-slate-400">{row.storeName}</div>
                        </td>
                        <td className="px-4 py-3 text-slate-600">{row.position}</td>
                        <td className="px-4 py-3">
                          <div className="text-[11px] text-slate-700 italic">
                            {row.archiveReason ? `“${row.archiveReason}”` : "No reason logged"}
                          </div>
                          <div className="text-[10px] text-slate-400">
                            {row.archivedByName ? `By ${row.archivedByName}` : "System"}{" "}
                            {row.archivedAt ? `on ${new Date(row.archivedAt).toLocaleDateString()}` : ""}
                          </div>
                        </td>
                        <td className="px-4 py-3 text-right">
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
          )}

          {/* TAB 5: AUDIT LOGS */}
          {activeTab === "audit" && (
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
            onClick={() => {
              refetchSnapshot();
              refetchHistory();
              refetchImpact();
            }}
            disabled={snapshotFetching || historyFetching}
            className="flex items-center gap-1.5 text-xs text-slate-500 hover:text-slate-800"
          >
            <RefreshCw
              className={`w-3.5 h-3.5 ${snapshotFetching || historyFetching ? "animate-spin" : ""}`}
            />
            <span>Refresh All Data</span>
          </button>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium text-slate-700 bg-white border border-slate-300 rounded-xl hover:bg-slate-50 transition-colors"
          >
            Close
          </button>
        </div>

        {/* MODAL 1: Individual Restore Confirmation */}
        {restorePrompt && (
          <div className="fixed inset-0 z-60 flex items-center justify-center p-4 bg-slate-950/70 backdrop-blur-xs animate-in fade-in duration-150">
            <div className="w-full max-w-md bg-white rounded-2xl shadow-2xl border border-slate-200 p-6 space-y-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center">
                  <RotateCcw className="w-5 h-5" />
                </div>
                <div>
                  <h4 className="text-sm font-bold text-slate-900">
                    Restore Archived {restorePrompt.type === "plantilla" ? "Plantilla" : "Vacancy"}
                  </h4>
                  <p className="text-xs text-slate-500">{restorePrompt.label}</p>
                </div>
              </div>

              {errorMessage && (
                <div className="p-3 rounded-lg bg-rose-50 border border-rose-200 text-xs text-rose-700">
                  {errorMessage}
                </div>
              )}

              <form onSubmit={handleConfirmRestore} className="space-y-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Audited Reason (Required)
                  </label>
                  <textarea
                    rows={3}
                    required
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    placeholder="Provide reason for un-archiving this record..."
                    className="w-full px-3 py-2 text-xs border border-slate-300 rounded-xl focus:outline-hidden focus:ring-2 focus:ring-purple-500"
                  />
                </div>

                <div className="flex items-center justify-end gap-2 pt-2">
                  <button
                    type="button"
                    onClick={() => setRestorePrompt(null)}
                    disabled={isRestoring}
                    className="px-3 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={isRestoring}
                    className="px-4 py-2 text-xs font-bold text-white bg-purple-600 hover:bg-purple-700 rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
                  >
                    {isRestoring && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                    <span>Confirm Restore</span>
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* MODAL 2: Bulk Archive Execution Wizard with Phrase Confirmation */}
        {activeArchiveWizard && (
          <div className="fixed inset-0 z-60 flex items-center justify-center p-4 bg-slate-950/70 backdrop-blur-xs animate-in fade-in duration-150">
            <div className="w-full max-w-lg bg-white rounded-2xl shadow-2xl border border-rose-300 p-6 space-y-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-rose-100 text-rose-700 flex items-center justify-center">
                  <AlertTriangle className="w-5 h-5" />
                </div>
                <div>
                  <h4 className="text-sm font-bold text-slate-900">
                    Execute {activeArchiveWizard.title}
                  </h4>
                  <p className="text-xs text-rose-600 font-semibold">
                    HIGH-RISK OPERATION • 72-HOUR REVERSIBLE
                  </p>
                </div>
              </div>

              {wizardError && (
                <div className="p-3 rounded-lg bg-rose-50 border border-rose-200 text-xs text-rose-700">
                  {wizardError}
                </div>
              )}

              <form onSubmit={handleExecuteArchive} className="space-y-4">
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">
                    Operational Reason (Required)
                  </label>
                  <textarea
                    rows={2}
                    required
                    value={archiveReason}
                    onChange={(e) => setArchiveReason(e.target.value)}
                    placeholder="e.g. Scheduled QA testing cycle baseline archival"
                    className="w-full px-3 py-2 text-xs border border-slate-300 rounded-xl focus:outline-hidden focus:ring-2 focus:ring-rose-500"
                  />
                </div>

                <div className="p-3 rounded-xl bg-rose-50/60 border border-rose-200 space-y-2">
                  <label className="block text-xs font-bold text-rose-900">
                    Type confirmation phrase to proceed:
                  </label>
                  <p className="text-xs font-mono font-bold text-rose-700 select-all">
                    {activeArchiveWizard.confirmPhrase}
                  </p>
                  <input
                    type="text"
                    required
                    value={typedConfirmation}
                    onChange={(e) => setTypedConfirmation(e.target.value)}
                    placeholder={activeArchiveWizard.confirmPhrase}
                    className="w-full px-3 py-2 text-xs border border-rose-300 rounded-xl bg-white font-mono uppercase focus:outline-hidden focus:ring-2 focus:ring-rose-500"
                  />
                </div>

                <div className="flex items-center justify-end gap-2 pt-2">
                  <button
                    type="button"
                    onClick={() => setActiveArchiveWizard(null)}
                    disabled={bulkArchiveMutation.isPending}
                    className="px-3 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={bulkArchiveMutation.isPending}
                    className="px-4 py-2 text-xs font-bold text-white bg-rose-600 hover:bg-rose-700 rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
                  >
                    {bulkArchiveMutation.isPending && (
                      <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                    )}
                    <span>Execute Bulk Archive</span>
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* MODAL 3: Rollback Confirmation Prompt */}
        {pendingRollbackBatchId && (
          <div className="fixed inset-0 z-60 flex items-center justify-center p-4 bg-slate-950/70 backdrop-blur-xs animate-in fade-in duration-150">
            <div className="w-full max-w-md bg-white rounded-2xl shadow-2xl border border-purple-200 p-6 space-y-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center">
                  <RotateCcw className="w-5 h-5" />
                </div>
                <div>
                  <h4 className="text-sm font-bold text-slate-900">
                    Rollback Archive Batch
                  </h4>
                  <p className="text-xs text-slate-500 font-mono">
                    Batch ID: {pendingRollbackBatchId}
                  </p>
                </div>
              </div>

              {rollbackError && (
                <div className="p-3 rounded-lg bg-rose-50 border border-rose-200 text-xs text-rose-700">
                  {rollbackError}
                </div>
              )}

              <form onSubmit={handleRollbackBatch} className="space-y-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Rollback Reason (Required)
                  </label>
                  <textarea
                    rows={3}
                    required
                    value={rollbackReason}
                    onChange={(e) => setRollbackReason(e.target.value)}
                    placeholder="State reason for restoring this entire batch..."
                    className="w-full px-3 py-2 text-xs border border-slate-300 rounded-xl focus:outline-hidden focus:ring-2 focus:ring-purple-500"
                  />
                </div>

                <div className="flex items-center justify-end gap-2 pt-2">
                  <button
                    type="button"
                    onClick={() => setPendingRollbackBatchId(null)}
                    disabled={rollbackMutation.isPending}
                    className="px-3 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={rollbackMutation.isPending}
                    className="px-4 py-2 text-xs font-bold text-white bg-purple-600 hover:bg-purple-700 rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
                  >
                    {rollbackMutation.isPending && (
                      <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                    )}
                    <span>Confirm Rollback</span>
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
