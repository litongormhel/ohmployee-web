"use client";
import React, { useState, useMemo } from "react";
import {
  X,
  Briefcase,
  Plus,
  Trash2,
  AlertCircle,
  CheckCircle2,
  Search,
  Building2,
  Users,
  Layers,
  Sparkles,
  Loader2,
  Lock,
} from "lucide-react";
import { formatPosition } from "@/lib/utils/displayText";
import { useScopeAccounts } from "@/lib/queries/more";
import {
  useAccountPositionsDetailedQuery,
  useMasterPositionsQuery,
  useManageAccountPositionMutation,
  type DetailedAccountPosition,
} from "@/lib/queries/accountPositions";

interface AccountPositionManagerModalProps {
  isOpen: boolean;
  onClose: () => void;
  initialAccountId?: string | null;
}

export function AccountPositionManagerModal({
  isOpen,
  onClose,
  initialAccountId,
}: AccountPositionManagerModalProps) {
  // Accounts query
  const { data: accounts = [], isLoading: isLoadingAccounts } = useScopeAccounts();

  // Selected account state (supports manual override, prop fallback, or first account default)
  const [selectedAccountId, setSelectedAccountId] = useState<string>("");

  const effectiveAccountId = useMemo(() => {
    if (selectedAccountId) return selectedAccountId;
    if (initialAccountId) return initialAccountId;
    return accounts.length > 0 ? accounts[0].id : "";
  }, [selectedAccountId, initialAccountId, accounts]);

  // Active sub-tab: 'assigned' | 'add'
  const [activeTab, setActiveTab] = useState<"assigned" | "add">("assigned");

  // Filter/search in assigned roles
  const [searchQuery, setSearchQuery] = useState("");

  // Add existing position state
  const [selectedExistingPosId, setSelectedExistingPosId] = useState("");

  // Create new position state
  const [newPositionName, setNewPositionName] = useState("");

  // Inline Unlink Confirmation
  const [unlinkingPos, setUnlinkingPos] = useState<DetailedAccountPosition | null>(null);

  // Status feedback
  const [feedback, setFeedback] = useState<{ type: "success" | "error"; message: string } | null>(
    null
  );

  // Queries for the selected account
  const {
    data: assignedPositions = [],
    isLoading: isLoadingPositions,
    isRefetching: isRefetchingPositions,
  } = useAccountPositionsDetailedQuery(effectiveAccountId);

  const { data: masterPositions = [], isLoading: isLoadingMaster } = useMasterPositionsQuery();

  const manageMutation = useManageAccountPositionMutation(effectiveAccountId);

  // Filter master positions not yet assigned to the current account
  const unassignedMasterPositions = useMemo(() => {
    const assignedIds = new Set(assignedPositions.map((p) => p.positionId));
    return masterPositions.filter((p) => !assignedIds.has(p.id));
  }, [masterPositions, assignedPositions]);

  // Filter assigned positions by search query
  const filteredAssignedPositions = useMemo(() => {
    if (!searchQuery.trim()) return assignedPositions;
    const q = searchQuery.toLowerCase();
    return assignedPositions.filter(
      (p) =>
        p.positionName.toLowerCase().includes(q) ||
        (p.positionCode && p.positionCode.toLowerCase().includes(q))
    );
  }, [assignedPositions, searchQuery]);

  // Selected account object
  const currentAccount = useMemo(() => {
    return accounts.find((a) => a.id === effectiveAccountId);
  }, [accounts, effectiveAccountId]);

  // Auto-format preview for new position
  const formattedNewPositionPreview = useMemo(() => {
    if (!newPositionName.trim()) return "";
    return formatPosition(newPositionName.trim());
  }, [newPositionName]);

  // Reset local form states on account change or close
  const handleAccountChange = (newAccId: string) => {
    setSelectedAccountId(newAccId);
    setSearchQuery("");
    setSelectedExistingPosId("");
    setNewPositionName("");
    setUnlinkingPos(null);
    setFeedback(null);
  };

  // Action: Link existing position
  const handleLinkExisting = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!effectiveAccountId || !selectedExistingPosId) return;

    setFeedback(null);
    try {
      const res = await manageMutation.mutateAsync({
        action: "link",
        accountId: effectiveAccountId,
        positionId: selectedExistingPosId,
      });
      setSelectedExistingPosId("");
      setFeedback({ type: "success", message: res.message });
      setActiveTab("assigned");
    } catch (err) {
      setFeedback({
        type: "error",
        message: err instanceof Error ? err.message : "Failed to link position.",
      });
    }
  };

  // Action: Create and link new position
  const handleCreateAndLink = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!effectiveAccountId || !newPositionName.trim()) return;

    setFeedback(null);
    try {
      const res = await manageMutation.mutateAsync({
        action: "create_and_link",
        accountId: effectiveAccountId,
        positionName: newPositionName.trim(),
      });
      setNewPositionName("");
      setFeedback({ type: "success", message: res.message });
      setActiveTab("assigned");
    } catch (err) {
      setFeedback({
        type: "error",
        message: err instanceof Error ? err.message : "Failed to create position.",
      });
    }
  };

  // Action: Unlink position
  const handleConfirmUnlink = async () => {
    if (!effectiveAccountId || !unlinkingPos) return;

    setFeedback(null);
    try {
      const res = await manageMutation.mutateAsync({
        action: "unlink",
        accountId: effectiveAccountId,
        positionId: unlinkingPos.positionId,
      });
      setUnlinkingPos(null);
      setFeedback({ type: "success", message: res.message });
    } catch (err) {
      setFeedback({
        type: "error",
        message: err instanceof Error ? err.message : "Failed to unlink position.",
      });
      setUnlinkingPos(null);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs animate-in fade-in duration-150">
      <div className="relative flex flex-col w-full max-w-3xl max-h-[90vh] bg-surface-primary border border-border-default rounded-xl shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-border-subtle bg-surface-base">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-lg bg-brand-subtle text-brand-primary">
              <Briefcase className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-base font-bold text-text-primary">
                  Account Position Management
                </h2>
                <span className="px-2 py-0.5 text-3xs font-bold uppercase rounded-md bg-purple-50 text-purple-700 dark:bg-purple-950/40 dark:text-purple-300 border border-purple-200 dark:border-purple-800">
                  Data Team
                </span>
              </div>
              <p className="text-xs text-text-muted mt-0.5">
                Govern available job roles per account or register new positions into the company catalog.
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 text-text-muted hover:text-text-primary hover:bg-surface-hover rounded-lg transition"
            aria-label="Close"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Account Selector Bar */}
        <div className="px-6 py-3.5 border-b border-border-subtle bg-surface-subtle/50 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2.5 flex-1 min-w-[260px]">
            <Building2 className="w-4 h-4 text-text-muted shrink-0" />
            <span className="text-xs font-semibold text-text-secondary whitespace-nowrap">
              Select Account:
            </span>
            <select
              value={effectiveAccountId}
              onChange={(e) => handleAccountChange(e.target.value)}
              disabled={isLoadingAccounts || manageMutation.isPending}
              className="flex-1 max-w-sm h-8 px-3 text-xs font-medium rounded-lg border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:ring-2 focus:ring-brand-500 transition cursor-pointer disabled:opacity-50"
            >
              {isLoadingAccounts ? (
                <option value="">Loading accounts...</option>
              ) : accounts.length === 0 ? (
                <option value="">No accounts found</option>
              ) : (
                accounts.map((acc) => (
                  <option key={acc.id} value={acc.id}>
                    {acc.accountName}
                  </option>
                ))
              )}
            </select>
          </div>

          {currentAccount && (
            <div className="flex items-center gap-2 text-xs text-text-muted">
              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-surface-primary border border-border-default font-medium text-text-secondary">
                <Layers className="w-3.5 h-3.5 text-brand-600" />
                <span>
                  {assignedPositions.length}{" "}
                  {assignedPositions.length === 1 ? "Role Assigned" : "Roles Assigned"}
                </span>
              </span>
            </div>
          )}
        </div>

        {/* Tab Controls */}
        <div className="flex items-center gap-2 px-6 pt-3 border-b border-border-subtle bg-surface-primary">
          <button
            type="button"
            onClick={() => {
              setActiveTab("assigned");
              setFeedback(null);
            }}
            className={`flex items-center gap-2 px-4 py-2 text-xs font-semibold border-b-2 transition cursor-pointer ${
              activeTab === "assigned"
                ? "border-brand-600 text-brand-600"
                : "border-transparent text-text-muted hover:text-text-primary"
            }`}
          >
            <span>Assigned Roles</span>
            <span
              className={`px-1.5 py-0.2 rounded-full text-3xs font-bold ${
                activeTab === "assigned"
                  ? "bg-brand-subtle text-brand-primary"
                  : "bg-surface-subtle text-text-muted"
              }`}
            >
              {assignedPositions.length}
            </span>
          </button>

          <button
            type="button"
            onClick={() => {
              setActiveTab("add");
              setFeedback(null);
            }}
            className={`flex items-center gap-2 px-4 py-2 text-xs font-semibold border-b-2 transition cursor-pointer ${
              activeTab === "add"
                ? "border-brand-600 text-brand-600"
                : "border-transparent text-text-muted hover:text-text-primary"
            }`}
          >
            <Plus className="w-3.5 h-3.5" />
            <span>Add / Register Role</span>
          </button>
        </div>

        {/* Alert Feedback Banner */}
        {feedback && (
          <div
            className={`mx-6 mt-4 p-3 rounded-lg flex items-start gap-2.5 text-xs font-medium border ${
              feedback.type === "success"
                ? "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-800 dark:text-emerald-200 border-emerald-200 dark:border-emerald-800"
                : "bg-rose-50 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 border-rose-200 dark:border-rose-800"
            }`}
          >
            {feedback.type === "success" ? (
              <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" />
            ) : (
              <AlertCircle className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
            )}
            <div className="flex-1">{feedback.message}</div>
            <button
              type="button"
              onClick={() => setFeedback(null)}
              className="text-text-muted hover:text-text-primary p-0.5"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        )}

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-4 min-h-[340px]">
          {activeTab === "assigned" ? (
            /* Tab 1: Assigned Roles */
            <div className="space-y-4">
              {/* Search Bar */}
              <div className="flex items-center justify-between gap-3">
                <div className="relative flex-1 max-w-sm">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-text-muted" />
                  <input
                    type="text"
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    placeholder="Search assigned roles..."
                    className="w-full h-8 pl-8 pr-3 text-xs rounded-lg border border-border-default bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:ring-2 focus:ring-brand-500"
                  />
                </div>

                <button
                  type="button"
                  onClick={() => setActiveTab("add")}
                  className="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg bg-brand-button hover:bg-brand-button-hover text-white text-xs font-semibold shadow-2xs transition cursor-pointer"
                >
                  <Plus className="w-3.5 h-3.5" />
                  <span>Add Role</span>
                </button>
              </div>

              {/* Roles List */}
              {isLoadingPositions || isRefetchingPositions ? (
                <div className="flex flex-col items-center justify-center py-16 text-text-muted">
                  <Loader2 className="w-6 h-6 animate-spin text-brand-600 mb-2" />
                  <p className="text-xs">Loading positions for {currentAccount?.accountName}...</p>
                </div>
              ) : filteredAssignedPositions.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-16 text-center border border-dashed border-border-default rounded-xl bg-surface-subtle/40">
                  <Briefcase className="w-8 h-8 text-text-muted mb-2 opacity-50" />
                  <p className="text-xs font-semibold text-text-secondary">
                    {searchQuery ? "No matching roles found" : "No roles assigned to this account"}
                  </p>
                  <p className="text-3xs text-text-muted max-w-xs mt-1">
                    {searchQuery
                      ? "Try searching for another keyword or clear the filter."
                      : "Click 'Add / Register Role' above to assign or create roles for this account."}
                  </p>
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
                  {filteredAssignedPositions.map((pos) => {
                    const inUse = pos.activeEmployeeCount > 0 || pos.openVacancyCount > 0;
                    const isConfirmingThis = unlinkingPos?.positionId === pos.positionId;

                    return (
                      <div
                        key={pos.positionId}
                        className={`p-3 rounded-xl border transition flex flex-col justify-between gap-2.5 ${
                          isConfirmingThis
                            ? "border-rose-300 bg-rose-50/50 dark:border-rose-800 dark:bg-rose-950/20"
                            : "border-border-default bg-surface-base hover:border-border-strong"
                        }`}
                      >
                        <div className="flex items-start justify-between gap-2">
                          <div>
                            <div className="flex items-center gap-1.5">
                              <span className="text-xs font-bold text-text-primary">
                                {formatPosition(pos.positionName)}
                              </span>
                              {pos.positionCode && (
                                <span className="px-1.5 py-0.2 rounded text-3xs font-mono font-semibold bg-surface-subtle text-text-muted border border-border-default">
                                  {pos.positionCode}
                                </span>
                              )}
                            </div>
                            <div className="flex items-center gap-2 mt-1.5">
                              <span
                                className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-3xs font-semibold ${
                                  pos.activeEmployeeCount > 0
                                    ? "bg-blue-50 text-blue-700 dark:bg-blue-950/40 dark:text-blue-300 border border-blue-200 dark:border-blue-800"
                                    : "bg-surface-subtle text-text-muted border border-border-subtle"
                                }`}
                              >
                                <Users className="w-3 h-3" />
                                <span>{pos.activeEmployeeCount} active</span>
                              </span>

                              <span
                                className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-3xs font-semibold ${
                                  pos.openVacancyCount > 0
                                    ? "bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300 border border-amber-200 dark:border-amber-800"
                                    : "bg-surface-subtle text-text-muted border border-border-subtle"
                                }`}
                              >
                                <Briefcase className="w-3 h-3" />
                                <span>{pos.openVacancyCount} open vac</span>
                              </span>
                            </div>
                          </div>

                          {/* Unlink Action */}
                          {inUse ? (
                            <div
                              title={`Cannot unlink: in use by ${pos.activeEmployeeCount} employee(s) and ${pos.openVacancyCount} open vacancy(ies).`}
                              className="p-1.5 text-text-muted/40 cursor-not-allowed"
                            >
                              <Lock className="w-4 h-4" />
                            </div>
                          ) : isConfirmingThis ? (
                            <div className="flex items-center gap-1">
                              <button
                                type="button"
                                onClick={() => setUnlinkingPos(null)}
                                className="px-2 py-1 rounded-md text-3xs font-medium text-text-secondary hover:bg-surface-hover border border-border-default transition cursor-pointer"
                              >
                                Cancel
                              </button>
                              <button
                                type="button"
                                onClick={handleConfirmUnlink}
                                disabled={manageMutation.isPending}
                                className="px-2 py-1 rounded-md text-3xs font-bold text-white bg-rose-600 hover:bg-rose-700 shadow-2xs transition cursor-pointer"
                              >
                                {manageMutation.isPending ? "Unlinking..." : "Confirm"}
                              </button>
                            </div>
                          ) : (
                            <button
                              type="button"
                              onClick={() => setUnlinkingPos(pos)}
                              title="Unlink role from this account"
                              className="p-1.5 text-text-muted hover:text-rose-600 hover:bg-rose-50 dark:hover:bg-rose-950/30 rounded-lg transition cursor-pointer"
                            >
                              <Trash2 className="w-4 h-4" />
                            </button>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          ) : (
            /* Tab 2: Add / Register Role */
            <div className="space-y-6">
              {/* Option A: Link Existing Master Position */}
              <div className="p-4 rounded-xl border border-border-default bg-surface-base space-y-3">
                <div className="flex items-center gap-2">
                  <div className="p-1.5 rounded-md bg-blue-50 dark:bg-blue-950/40 text-blue-600">
                    <Layers className="w-4 h-4" />
                  </div>
                  <div>
                    <h3 className="text-xs font-bold text-text-primary">
                      Option A: Link Existing Role from Master Catalog
                    </h3>
                    <p className="text-3xs text-text-muted">
                      Select a role that already exists in the company directory and enable it for{" "}
                      <span className="font-semibold text-text-secondary">
                        {currentAccount?.accountName}
                      </span>
                      .
                    </p>
                  </div>
                </div>

                <form onSubmit={handleLinkExisting} className="flex flex-wrap items-center gap-3 pt-1">
                  <select
                    value={selectedExistingPosId}
                    onChange={(e) => setSelectedExistingPosId(e.target.value)}
                    disabled={isLoadingMaster || unassignedMasterPositions.length === 0}
                    className="flex-1 min-w-[240px] h-9 px-3 text-xs font-medium rounded-lg border border-border-default bg-surface-primary text-text-primary focus:outline-hidden focus:ring-2 focus:ring-brand-500 transition cursor-pointer"
                  >
                    <option value="">
                      {isLoadingMaster
                        ? "Loading catalog positions..."
                        : unassignedMasterPositions.length === 0
                        ? "-- All catalog positions are already linked --"
                        : "-- Select a role to link --"}
                    </option>
                    {unassignedMasterPositions.map((pos) => (
                      <option key={pos.id} value={pos.id}>
                        {formatPosition(pos.positionName)}
                      </option>
                    ))}
                  </select>

                  <button
                    type="submit"
                    disabled={!selectedExistingPosId || manageMutation.isPending}
                    className="inline-flex items-center gap-1.5 h-9 px-4 rounded-lg bg-brand-button hover:bg-brand-button-hover disabled:opacity-50 text-white text-xs font-semibold shadow-2xs transition cursor-pointer shrink-0"
                  >
                    {manageMutation.isPending && manageMutation.variables?.action === "link" ? (
                      <>
                        <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        <span>Linking...</span>
                      </>
                    ) : (
                      <>
                        <Plus className="w-3.5 h-3.5" />
                        <span>Link to {currentAccount?.accountName}</span>
                      </>
                    )}
                  </button>
                </form>
              </div>

              {/* Option B: Register Brand New Role */}
              <div className="p-4 rounded-xl border border-border-default bg-surface-base space-y-3">
                <div className="flex items-center gap-2">
                  <div className="p-1.5 rounded-md bg-purple-50 dark:bg-purple-950/40 text-purple-600">
                    <Sparkles className="w-4 h-4" />
                  </div>
                  <div>
                    <h3 className="text-xs font-bold text-text-primary">
                      Option B: Register Brand New Company Position
                    </h3>
                    <p className="text-3xs text-text-muted">
                      Add a completely new position to the company catalog and automatically link it
                      to{" "}
                      <span className="font-semibold text-text-secondary">
                        {currentAccount?.accountName}
                      </span>
                      .
                    </p>
                  </div>
                </div>

                <form onSubmit={handleCreateAndLink} className="space-y-3 pt-1">
                  <div className="flex flex-wrap items-center gap-3">
                    <input
                      type="text"
                      value={newPositionName}
                      onChange={(e) => setNewPositionName(e.target.value)}
                      placeholder="e.g. Barista, Inventory Lead, FSR Lead"
                      className="flex-1 min-w-[240px] h-9 px-3 text-xs font-medium rounded-lg border border-border-default bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:ring-2 focus:ring-brand-500 transition"
                    />

                    <button
                      type="submit"
                      disabled={
                        newPositionName.trim().length < 2 || manageMutation.isPending
                      }
                      className="inline-flex items-center gap-1.5 h-9 px-4 rounded-lg bg-purple-600 hover:bg-purple-700 disabled:opacity-50 text-white text-xs font-semibold shadow-2xs transition cursor-pointer shrink-0"
                    >
                      {manageMutation.isPending &&
                      manageMutation.variables?.action === "create_and_link" ? (
                        <>
                          <Loader2 className="w-3.5 h-3.5 animate-spin" />
                          <span>Creating...</span>
                        </>
                      ) : (
                        <>
                          <Sparkles className="w-3.5 h-3.5" />
                          <span>Create & Link</span>
                        </>
                      )}
                    </button>
                  </div>

                  {/* Dynamic Formatting Preview */}
                  {formattedNewPositionPreview && (
                    <div className="p-2.5 rounded-lg bg-surface-subtle border border-border-subtle flex items-center justify-between text-xs">
                      <div className="flex items-center gap-2">
                        <span className="text-3xs font-semibold text-text-muted">
                          Auto-formatted Preview:
                        </span>
                        <span className="px-2 py-0.5 rounded font-bold bg-brand-subtle text-brand-primary border border-brand-border">
                          {formattedNewPositionPreview}
                        </span>
                      </div>
                      <span className="text-3xs text-text-muted">
                        Proper Case • 2–3 letter uppercase rule applied
                      </span>
                    </div>
                  )}

                  <p className="text-3xs text-text-muted italic">
                    Note: Names are standardized automatically. Acronyms with 2 to 3 letters
                    (e.g., FSR, SMP, QA, HR, TL, OM) will be converted to uppercase.
                  </p>
                </form>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 py-3.5 border-t border-border-subtle bg-surface-base flex items-center justify-between">
          <span className="text-3xs text-text-muted">
            Enforced by unique index{" "}
            <code className="px-1 py-0.5 rounded bg-surface-subtle font-mono text-text-secondary">
              uq_account_positions_account_position
            </code>
          </span>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-semibold rounded-lg border border-border-default bg-surface-primary text-text-primary hover:bg-surface-hover transition cursor-pointer"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
}
