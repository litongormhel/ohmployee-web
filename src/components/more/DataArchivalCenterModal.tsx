"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Archive,
  Clock,
  RefreshCw,
  RotateCcw,
  Search,
  ShieldAlert,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
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
  const { data: snapshot, refetch: refetchSnapshot, isFetching: snapshotFetching } =
    useArchiveSnapshot();
  const { data: impactPreview, isLoading: impactLoading, refetch: refetchImpact } =
    useArchiveImpactPreview();
  const { data: batchHistory = [], isLoading: historyLoading, refetch: refetchHistory, isFetching: historyFetching } =
    useArchiveBatchHistory();

  const restorePlantillaMutation = useRestorePlantilla();
  const restoreVacancyMutation = useRestoreVacancy();
  const bulkArchiveMutation = useExecuteBulkArchive();
  const rollbackMutation = useRollbackArchiveBatch();

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
      refetchSnapshot();
      refetchImpact();
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
      refetchSnapshot();
      refetchImpact();
    } catch (err) {
      setRollbackError(err instanceof Error ? err.message : "Rollback batch failed.");
    }
  };

  const isRestoring =
    restorePlantillaMutation.isPending || restoreVacancyMutation.isPending;
  const isBusy =
    isRestoring || bulkArchiveMutation.isPending || rollbackMutation.isPending;

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title={
          <span className="flex items-center gap-2">
            <span>Data Archival & Recovery Center</span>
            <span className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] text-xs font-semibold px-2 py-0.5 border border-[var(--danger-border)]">
              Level 100 Super Admin
            </span>
          </span>
        }
        subtitle="Bulk archive execution, QA reset triggers, soft-deleted recycle bin, and 72-hour batch rollback controls"
        icon={Archive}
        maxWidthClass="max-w-5xl"
        disableBackdropClick={isBusy}
        isSubmitting={isBusy}
        footer={
          <div className="flex items-center justify-between w-full">
            <button
              type="button"
              onClick={() => {
                refetchSnapshot();
                refetchHistory();
                refetchImpact();
              }}
              disabled={snapshotFetching || historyFetching}
              className="flex items-center gap-1.5 text-sm text-[var(--text-muted)] hover:text-[var(--foreground)]"
            >
              <RefreshCw
                className={`w-3.5 h-3.5 ${snapshotFetching || historyFetching ? "animate-spin" : ""}`}
              />
              <span>Refresh All Data</span>
            </button>
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-sm font-medium text-[var(--foreground)] bg-[var(--card)] border border-[var(--border-subtle)] rounded-xl hover:bg-[var(--surface-muted)] transition-colors"
            >
              Close
            </button>
          </div>
        }
      >
        <div className="space-y-4">
          {/* High Risk Notice */}
          <div className="p-3 bg-[var(--danger-bg)] border border-[var(--danger-border)] text-[var(--danger)] text-sm rounded-xl flex items-center justify-between">
            <div className="flex items-center gap-2">
              <ShieldAlert className="w-4 h-4 shrink-0" />
              <span>
                Archive operations immediately hide records from operational views without hard deletes. Rollback is available for 72 active hours.
              </span>
            </div>
            {impactPreview && (
              <div className="text-xs font-mono font-medium shrink-0">
                Live Impactable: {impactPreview.total} items
              </div>
            )}
          </div>

          {/* Navigation Tabs */}
          <div className="border-b border-[var(--border-subtle)] pb-2 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div className="flex items-center gap-2 overflow-x-auto no-scrollbar scrollbar-none">
              <button
                type="button"
                onClick={() => setActiveTab("execute_archive")}
                className={`pb-2 px-3 text-sm font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                  activeTab === "execute_archive"
                    ? "border-[var(--danger)] text-[var(--danger)]"
                    : "border-transparent text-[var(--text-muted)] hover:text-[var(--foreground)]"
                }`}
              >
                <AlertTriangle className="w-4 h-4 text-[var(--danger)]" />
                <span>Execute Archive / QA Reset</span>
              </button>
              <button
                type="button"
                onClick={() => setActiveTab("batch_history")}
                className={`pb-2 px-3 text-sm font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                  activeTab === "batch_history"
                    ? "border-[var(--primary)] text-[var(--foreground)]"
                    : "border-transparent text-[var(--text-muted)] hover:text-[var(--foreground)]"
                }`}
              >
                <Clock className="w-4 h-4" />
                <span>Batch History & Rollback</span>
                <span className="px-1.5 py-0.5 rounded-full text-xs bg-[var(--surface-sunken)] text-[var(--text-muted)] font-bold">
                  {batchHistory.length}
                </span>
              </button>
              <button
                type="button"
                onClick={() => setActiveTab("plantilla")}
                className={`pb-2 px-3 text-sm font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                  activeTab === "plantilla"
                    ? "border-[var(--primary)] text-[var(--foreground)]"
                    : "border-transparent text-[var(--text-muted)] hover:text-[var(--foreground)]"
                }`}
              >
                <span>Archived Plantilla</span>
                <span className="px-1.5 py-0.5 rounded-full text-xs bg-[var(--surface-sunken)] text-[var(--text-muted)] font-bold">
                  {snapshot?.plantilla.length ?? 0}
                </span>
              </button>
              <button
                type="button"
                onClick={() => setActiveTab("vacancies")}
                className={`pb-2 px-3 text-sm font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                  activeTab === "vacancies"
                    ? "border-[var(--primary)] text-[var(--foreground)]"
                    : "border-transparent text-[var(--text-muted)] hover:text-[var(--foreground)]"
                }`}
              >
                <span>Archived Vacancies</span>
                <span className="px-1.5 py-0.5 rounded-full text-xs bg-[var(--surface-sunken)] text-[var(--text-muted)] font-bold">
                  {snapshot?.vacancies.length ?? 0}
                </span>
              </button>
              <button
                type="button"
                onClick={() => setActiveTab("audit")}
                className={`pb-2 px-3 text-sm font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                  activeTab === "audit"
                    ? "border-[var(--primary)] text-[var(--foreground)]"
                    : "border-transparent text-[var(--text-muted)] hover:text-[var(--foreground)]"
                }`}
              >
                <span>Audit Trail</span>
                <span className="px-1.5 py-0.5 rounded-full text-xs bg-[var(--surface-sunken)] text-[var(--text-muted)] font-bold">
                  {snapshot?.auditLogs.length ?? 0}
                </span>
              </button>
            </div>

            {(activeTab === "plantilla" || activeTab === "vacancies") && (
              <div className="relative w-full sm:w-64">
                <Search className="w-4 h-4 absolute left-3 top-2.5 text-[var(--text-subtle)]" />
                <input
                  type="text"
                  placeholder="Filter by name, store, vcode..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full text-sm pl-9 pr-3 py-1.5 border border-[var(--border-subtle)] rounded-lg bg-[var(--surface-sunken)] focus:bg-[var(--card)] focus:outline-hidden focus:ring-2 focus:ring-[var(--primary)]"
                />
              </div>
            )}
          </div>

          {/* TAB 1: EXECUTE ARCHIVE & QA RESET */}
          {activeTab === "execute_archive" && (
            <div className="space-y-6">
              {/* Impact summary counters */}
              <div className="p-4 rounded-xl bg-[var(--surface-muted)] border border-[var(--border-subtle)]">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-sm font-bold text-[var(--foreground)]">
                    Live Active Data Impact Preview
                  </h3>
                  <button
                    type="button"
                    onClick={() => refetchImpact()}
                    className="text-xs text-[var(--text-muted)] hover:text-[var(--foreground)] flex items-center gap-1"
                  >
                    <RefreshCw className="w-3.5 h-3.5" />
                    <span>Refresh Counters</span>
                  </button>
                </div>
                {impactLoading ? (
                  <div className="text-sm text-[var(--text-muted)] py-2">Loading live impact counts...</div>
                ) : impactPreview ? (
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
                    <div className="p-3 bg-[var(--card)] rounded-lg border border-[var(--border-subtle)]">
                      <span className="text-xs font-semibold text-[var(--text-muted)]">Plantilla</span>
                      <p className="text-base font-bold text-[var(--foreground)]">{impactPreview.plantillaCount}</p>
                    </div>
                    <div className="p-3 bg-[var(--card)] rounded-lg border border-[var(--border-subtle)]">
                      <span className="text-xs font-semibold text-[var(--text-muted)]">Vacancies</span>
                      <p className="text-base font-bold text-[var(--foreground)]">{impactPreview.vacancyCount}</p>
                    </div>
                    <div className="p-3 bg-[var(--card)] rounded-lg border border-[var(--border-subtle)]">
                      <span className="text-xs font-semibold text-[var(--text-muted)]">HR Emploc</span>
                      <p className="text-base font-bold text-[var(--foreground)]">{impactPreview.hrEmplocCount}</p>
                    </div>
                    <div className="p-3 bg-[var(--card)] rounded-lg border border-[var(--border-subtle)]">
                      <span className="text-xs font-semibold text-[var(--text-muted)]">Moses HQ Items</span>
                      <p className="text-base font-bold text-[var(--foreground)]">{impactPreview.mosesHqTotal}</p>
                    </div>
                  </div>
                ) : null}
              </div>

              {/* Action triggers grid */}
              <div className="space-y-3">
                <h3 className="text-sm font-bold text-[var(--foreground)]">
                  Bulk & Single-Module Archival Actions
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {ARCHIVE_ACTIONS.map((action) => (
                    <div
                      key={action.actionType}
                      className={`p-4 rounded-xl border flex flex-col justify-between gap-4 ${
                        action.actionType === "qa_reset"
                          ? "bg-[var(--danger-bg)] border-[var(--danger-border)]"
                          : "bg-[var(--card)] border-[var(--border-subtle)]"
                      }`}
                    >
                      <div>
                        <div className="flex items-center justify-between">
                          <h4 className="text-sm font-bold text-[var(--foreground)]">{action.title}</h4>
                          <span className="px-2 py-0.5 rounded text-xs font-bold bg-[var(--surface-sunken)] text-[var(--text-muted)] border border-[var(--border-subtle)]">
                            {action.confirmPhrase}
                          </span>
                        </div>
                        <p className="text-sm text-[var(--text-muted)] mt-1.5">{action.description}</p>
                      </div>

                      <button
                        type="button"
                        onClick={() => {
                          setActiveArchiveWizard(action);
                          setTypedConfirmation("");
                          setArchiveReason("");
                          setWizardError(null);
                        }}
                        className={`w-full py-2 px-3 rounded-lg text-sm font-bold transition-colors ${
                          action.actionType === "qa_reset"
                            ? "bg-danger-button text-white hover:bg-danger-button-hover"
                            : "bg-brand-button text-white hover:bg-brand-button-hover"
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
                  <h3 className="text-sm font-bold text-[var(--foreground)]">Archive Batch History</h3>
                  <p className="text-sm text-[var(--text-muted)]">
                    Track previous bulk archival executions. Batches in ACTIVE status can be rolled back within 72 hours.
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => refetchHistory()}
                  disabled={historyFetching}
                  className="px-3 py-1.5 rounded-lg text-sm font-semibold bg-[var(--surface-muted)] text-[var(--foreground)] hover:bg-[var(--surface-sunken)] transition-colors flex items-center gap-1.5"
                >
                  <RefreshCw className={`w-3.5 h-3.5 ${historyFetching ? "animate-spin" : ""}`} />
                  <span>Refresh</span>
                </button>
              </div>

              {historyLoading ? (
                <div className="py-12 text-center text-sm text-[var(--text-muted)]">Loading batch history...</div>
              ) : batchHistory.length === 0 ? (
                <div className="py-12 text-center text-sm text-[var(--text-muted)]">No archive batches recorded yet.</div>
              ) : (
                <div className="space-y-3">
                  {batchHistory.map((batch) => (
                    <div
                      key={batch.id}
                      className="p-4 rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] flex flex-col md:flex-row md:items-center justify-between gap-4"
                    >
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-sm font-bold text-[var(--foreground)]">
                            {batch.actionType.toUpperCase()}
                          </span>
                          <span className="px-2 py-0.5 rounded text-xs font-bold bg-[var(--surface-sunken)] text-[var(--text-muted)] border border-[var(--border-subtle)]">
                            {batch.status}
                          </span>
                          <span className="text-xs font-mono text-[var(--text-subtle)]">
                            ID: {batch.archiveBatchId}
                          </span>
                        </div>
                        <p className="text-sm text-[var(--text-muted)] italic">“{batch.reason}”</p>
                        <div className="flex flex-wrap items-center gap-3 text-xs text-[var(--text-muted)] pt-1">
                          <span>By: {batch.executedByName}</span>
                          <span>Executed: {new Date(batch.executedAt).toLocaleString()}</span>
                          <span>Deadline: {new Date(batch.rollbackDeadline).toLocaleString()}</span>
                          <span className="font-semibold text-[var(--foreground)]">
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
                          className="px-3 py-1.5 rounded-lg text-sm font-bold text-[var(--foreground)] bg-[var(--surface-muted)] hover:bg-[var(--surface-sunken)] border border-[var(--border-subtle)] transition-colors flex items-center gap-1.5 self-start md:self-center shrink-0"
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
            <div className="border border-[var(--border-subtle)] rounded-xl overflow-hidden">
              <table className="w-full text-left text-sm">
                <thead className="bg-[var(--surface-muted)] border-b border-[var(--border-subtle)] text-[var(--text-muted)] font-semibold text-xs">
                  <tr>
                    <th className="px-4 py-3">Employee</th>
                    <th className="px-4 py-3">Account & Store</th>
                    <th className="px-4 py-3">Position</th>
                    <th className="px-4 py-3">Archived By & Reason</th>
                    <th className="px-4 py-3 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border-subtle)]">
                  {plantillaList.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="py-12 text-center text-sm text-[var(--text-muted)]">
                        No archived Plantilla records found.
                      </td>
                    </tr>
                  ) : (
                    plantillaList.map((row) => (
                      <tr key={row.id} className="hover:bg-[var(--surface-muted)]/50">
                        <td className="px-4 py-3">
                          <div className="font-bold text-[var(--foreground)]">{row.employeeName}</div>
                          <div className="text-xs text-[var(--text-subtle)] font-mono">{row.employeeNo}</div>
                        </td>
                        <td className="px-4 py-3">
                          <div className="font-semibold text-[var(--foreground)]">{row.account}</div>
                          <div className="text-xs text-[var(--text-muted)]">{row.storeName}</div>
                        </td>
                        <td className="px-4 py-3 text-[var(--foreground)]">{row.position}</td>
                        <td className="px-4 py-3">
                          <div className="text-sm text-[var(--foreground)] italic">
                            {row.archiveReason ? `“${row.archiveReason}”` : "No reason logged"}
                          </div>
                          <div className="text-xs text-[var(--text-muted)]">
                            {row.archivedByName ? `By ${row.archivedByName}` : "System"}{" "}
                            {row.archivedAt ? `on ${new Date(row.archivedAt).toLocaleDateString()}` : ""}
                          </div>
                        </td>
                        <td className="px-4 py-3 text-right">
                          {canRestore ? (
                            <button
                              type="button"
                              onClick={() => handleOpenRestore("plantilla", row.id, row.employeeName)}
                              className="px-2.5 py-1 text-sm font-semibold text-[var(--foreground)] bg-[var(--surface-muted)] hover:bg-[var(--surface-sunken)] rounded-lg border border-[var(--border-subtle)] transition-colors inline-flex items-center gap-1"
                            >
                              <RotateCcw className="w-3.5 h-3.5" />
                              <span>Restore</span>
                            </button>
                          ) : (
                            <span className="text-sm text-[var(--text-subtle)]">Read-only</span>
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
            <div className="border border-[var(--border-subtle)] rounded-xl overflow-hidden">
              <table className="w-full text-left text-sm">
                <thead className="bg-[var(--surface-muted)] border-b border-[var(--border-subtle)] text-[var(--text-muted)] font-semibold text-xs">
                  <tr>
                    <th className="px-4 py-3">VCODE</th>
                    <th className="px-4 py-3">Account & Store</th>
                    <th className="px-4 py-3">Position</th>
                    <th className="px-4 py-3">Archived By & Reason</th>
                    <th className="px-4 py-3 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border-subtle)]">
                  {vacanciesList.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="py-12 text-center text-sm text-[var(--text-muted)]">
                        No archived Vacancies found.
                      </td>
                    </tr>
                  ) : (
                    vacanciesList.map((row) => (
                      <tr key={row.id} className="hover:bg-[var(--surface-muted)]/50">
                        <td className="px-4 py-3 font-mono font-bold text-[var(--foreground)]">{row.vcode}</td>
                        <td className="px-4 py-3">
                          <div className="font-semibold text-[var(--foreground)]">{row.account}</div>
                          <div className="text-xs text-[var(--text-muted)]">{row.storeName}</div>
                        </td>
                        <td className="px-4 py-3 text-[var(--foreground)]">{row.position}</td>
                        <td className="px-4 py-3">
                          <div className="text-sm text-[var(--foreground)] italic">
                            {row.archiveReason ? `“${row.archiveReason}”` : "No reason logged"}
                          </div>
                          <div className="text-xs text-[var(--text-muted)]">
                            {row.archivedByName ? `By ${row.archivedByName}` : "System"}{" "}
                            {row.archivedAt ? `on ${new Date(row.archivedAt).toLocaleDateString()}` : ""}
                          </div>
                        </td>
                        <td className="px-4 py-3 text-right">
                          {canRestore ? (
                            <button
                              type="button"
                              onClick={() => handleOpenRestore("vacancy", row.id, row.vcode)}
                              className="px-2.5 py-1 text-sm font-semibold text-[var(--foreground)] bg-[var(--surface-muted)] hover:bg-[var(--surface-sunken)] rounded-lg border border-[var(--border-subtle)] transition-colors inline-flex items-center gap-1"
                            >
                              <RotateCcw className="w-3.5 h-3.5" />
                              <span>Restore</span>
                            </button>
                          ) : (
                            <span className="text-sm text-[var(--text-subtle)]">Read-only</span>
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
            <div className="space-y-2 text-sm">
              {auditLogs.length === 0 ? (
                <div className="py-10 text-center text-sm text-[var(--text-muted)]">No archival audit entries found.</div>
              ) : (
                auditLogs.map((log) => (
                  <div
                    key={log.id}
                    className="p-3 bg-[var(--surface-muted)]/60 border border-[var(--border-subtle)] rounded-xl flex items-start justify-between gap-3"
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-[var(--foreground)] text-xs">
                          [{log.module}] {log.actionType}
                        </span>
                        <span className="text-xs font-mono text-[var(--text-muted)]">ID: {log.recordId}</span>
                      </div>
                      {log.reason && (
                        <p className="text-sm text-[var(--text-muted)] mt-1 italic">“{log.reason}”</p>
                      )}
                    </div>
                    <span className="text-xs text-[var(--text-subtle)] whitespace-nowrap">
                      {new Date(log.createdAt).toLocaleString()}
                    </span>
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      </Modal>

      {/* SUB-MODAL 1: Individual Restore Confirmation */}
      {restorePrompt && (
        <Modal
          isOpen={Boolean(restorePrompt)}
          onClose={() => setRestorePrompt(null)}
          title={`Restore Archived ${restorePrompt.type === "plantilla" ? "Plantilla" : "Vacancy"}`}
          subtitle={restorePrompt.label}
          icon={RotateCcw}
          maxWidthClass="max-w-md"
          disableBackdropClick={isRestoring}
          isSubmitting={isRestoring}
          isDirty={Boolean(reason.trim())}
        >
          {errorMessage && (
            <div className="p-3 mb-4 rounded-lg bg-[var(--danger-bg)] border border-[var(--danger-border)] text-sm text-[var(--danger)]">
              {errorMessage}
            </div>
          )}

          <form onSubmit={handleConfirmRestore} className="space-y-4">
            <div>
              <label className="block text-sm font-semibold text-[var(--foreground)] mb-1">
                Audited Reason (Required)
              </label>
              <textarea
                rows={3}
                required
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Provide reason for un-archiving this record..."
                className="w-full px-3 py-2 text-sm border border-[var(--border-subtle)] rounded-xl bg-[var(--card)] focus:outline-hidden focus:ring-2 focus:ring-[var(--primary)] text-[var(--foreground)]"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setRestorePrompt(null)}
                disabled={isRestoring}
                className="px-3 py-2 text-sm font-medium text-[var(--text-muted)] hover:bg-[var(--surface-muted)] rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isRestoring}
                className="px-4 py-2 text-sm font-bold text-white bg-[var(--primary)] hover:opacity-90 rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
              >
                {isRestoring && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                <span>Confirm Restore</span>
              </button>
            </div>
          </form>
        </Modal>
      )}

      {/* SUB-MODAL 2: Bulk Archive Execution Wizard with Phrase Confirmation */}
      {activeArchiveWizard && (
        <Modal
          isOpen={Boolean(activeArchiveWizard)}
          onClose={() => setActiveArchiveWizard(null)}
          title={
            <span className="flex items-center gap-2">
              <span>Execute {activeArchiveWizard.title}</span>
              <span className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] text-xs font-semibold px-2 py-0.5 border border-[var(--danger-border)]">
                Destructive
              </span>
            </span>
          }
          subtitle="High-risk operation • 72-hour reversible"
          icon={AlertTriangle}
          maxWidthClass="max-w-lg"
          disableBackdropClick={bulkArchiveMutation.isPending}
          isSubmitting={bulkArchiveMutation.isPending}
          isDirty={Boolean(typedConfirmation.trim() || archiveReason.trim())}
        >
          {wizardError && (
            <div className="p-3 mb-4 rounded-lg bg-[var(--danger-bg)] border border-[var(--danger-border)] text-sm text-[var(--danger)]">
              {wizardError}
            </div>
          )}

          <form onSubmit={handleExecuteArchive} className="space-y-4">
            <div>
              <label className="block text-sm font-bold text-[var(--foreground)] mb-1">
                Operational Reason (Required)
              </label>
              <textarea
                rows={2}
                required
                value={archiveReason}
                onChange={(e) => setArchiveReason(e.target.value)}
                placeholder="e.g. Scheduled QA testing cycle baseline archival"
                className="w-full px-3 py-2 text-sm border border-[var(--border-subtle)] rounded-xl bg-[var(--card)] focus:outline-hidden focus:ring-2 focus:ring-[var(--danger)] text-[var(--foreground)]"
              />
            </div>

            <div className="p-3 rounded-xl bg-[var(--danger-bg)] border border-[var(--danger-border)] space-y-2">
              <label className="block text-sm font-bold text-[var(--danger)]">
                Type confirmation phrase to proceed:
              </label>
              <p className="text-sm font-mono font-bold text-[var(--danger)] select-all">
                {activeArchiveWizard.confirmPhrase}
              </p>
              <input
                type="text"
                required
                value={typedConfirmation}
                onChange={(e) => setTypedConfirmation(e.target.value)}
                placeholder={activeArchiveWizard.confirmPhrase}
                className="w-full px-3 py-2 text-sm border border-[var(--danger-border)] rounded-xl bg-[var(--card)] font-mono focus:outline-hidden focus:ring-2 focus:ring-[var(--danger)] text-[var(--foreground)]"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setActiveArchiveWizard(null)}
                disabled={bulkArchiveMutation.isPending}
                className="px-3 py-2 text-sm font-medium text-[var(--text-muted)] hover:bg-[var(--surface-muted)] rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={bulkArchiveMutation.isPending}
                className="px-4 py-2 text-sm font-bold text-white bg-[var(--danger)] hover:opacity-90 rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
              >
                {bulkArchiveMutation.isPending && (
                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                )}
                <span>Execute Bulk Archive</span>
              </button>
            </div>
          </form>
        </Modal>
      )}

      {/* SUB-MODAL 3: Rollback Confirmation Prompt */}
      {pendingRollbackBatchId && (
        <Modal
          isOpen={Boolean(pendingRollbackBatchId)}
          onClose={() => setPendingRollbackBatchId(null)}
          title="Rollback Archive Batch"
          subtitle={`Batch ID: ${pendingRollbackBatchId}`}
          icon={RotateCcw}
          maxWidthClass="max-w-md"
          disableBackdropClick={rollbackMutation.isPending}
          isSubmitting={rollbackMutation.isPending}
          isDirty={Boolean(rollbackReason.trim())}
        >
          {rollbackError && (
            <div className="p-3 mb-4 rounded-lg bg-[var(--danger-bg)] border border-[var(--danger-border)] text-sm text-[var(--danger)]">
              {rollbackError}
            </div>
          )}

          <form onSubmit={handleRollbackBatch} className="space-y-4">
            <div>
              <label className="block text-sm font-semibold text-[var(--foreground)] mb-1">
                Rollback Reason (Required)
              </label>
              <textarea
                rows={3}
                required
                value={rollbackReason}
                onChange={(e) => setRollbackReason(e.target.value)}
                placeholder="State reason for restoring this entire batch..."
                className="w-full px-3 py-2 text-sm border border-[var(--border-subtle)] rounded-xl bg-[var(--card)] focus:outline-hidden focus:ring-2 focus:ring-[var(--primary)] text-[var(--foreground)]"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setPendingRollbackBatchId(null)}
                disabled={rollbackMutation.isPending}
                className="px-3 py-2 text-sm font-medium text-[var(--text-muted)] hover:bg-[var(--surface-muted)] rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={rollbackMutation.isPending}
                className="px-4 py-2 text-sm font-bold text-white bg-[var(--primary)] hover:opacity-90 rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
              >
                {rollbackMutation.isPending && (
                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                )}
                <span>Confirm Rollback</span>
              </button>
            </div>
          </form>
        </Modal>
      )}
    </>
  );
}
