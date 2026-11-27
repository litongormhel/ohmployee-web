"use client";
import React, { useState, useMemo, useRef, useEffect } from "react";
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
  Loader2,
  Lock,
  ChevronDown,
} from "lucide-react";
import { formatPosition } from "@/lib/utils/displayText";
import { useScopeAccounts } from "@/lib/queries/more";
import {
  useAccountPositionsDetailedQuery,
  useMasterPositionsQuery,
  useManageAccountPositionMutation,
  type DetailedAccountPosition,
  type MasterPositionItem,
} from "@/lib/queries/accountPositions";

interface AccountPositionManagerModalProps {
  isOpen: boolean;
  onClose: () => void;
  initialAccountId?: string | null;
  initialAccountName?: string | null;
}

export function AccountPositionManagerModal({
  isOpen,
  onClose,
  initialAccountId,
  initialAccountName,
}: AccountPositionManagerModalProps) {
  const isFixedAccount = Boolean(initialAccountId);

  // Accounts query (used for name lookup and fallback when no account is preselected)
  const { data: accounts = [], isLoading: isLoadingAccounts } = useScopeAccounts();

  // Selected account state for global mode (e.g. from /more)
  const [selectedAccountId, setSelectedAccountId] = useState<string>("");

  const effectiveAccountId = useMemo(() => {
    if (initialAccountId) return initialAccountId;
    if (selectedAccountId) return selectedAccountId;
    return accounts.length > 0 ? accounts[0].id : "";
  }, [initialAccountId, selectedAccountId, accounts]);

  // Selected account object
  const currentAccount = useMemo(() => {
    return accounts.find((a) => a.id === effectiveAccountId);
  }, [accounts, effectiveAccountId]);

  const accountDisplayName = useMemo(() => {
    if (initialAccountName && isFixedAccount) return initialAccountName;
    return currentAccount?.accountName || "Account";
  }, [initialAccountName, isFixedAccount, currentAccount]);

  // Input & dropdown states
  const [positionInput, setPositionInput] = useState("");
  const [selectedCatalogPosition, setSelectedCatalogPosition] = useState<MasterPositionItem | null>(null);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [unlinkingPos, setUnlinkingPos] = useState<DetailedAccountPosition | null>(null);
  const [feedback, setFeedback] = useState<{ type: "success" | "error"; message: string } | null>(null);

  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Queries for the selected account
  const {
    data: assignedPositions = [],
    isLoading: isLoadingPositions,
    isRefetching: isRefetchingPositions,
  } = useAccountPositionsDetailedQuery(effectiveAccountId);

  const { data: masterPositions = [] } = useMasterPositionsQuery();

  const manageMutation = useManageAccountPositionMutation(effectiveAccountId);

  // Filter master positions not yet assigned to the current account
  const unassignedMasterPositions = useMemo(() => {
    const assignedIds = new Set(assignedPositions.map((p) => p.positionId));
    const assignedNames = new Set(assignedPositions.map((p) => p.positionName.trim().toLowerCase()));
    return masterPositions.filter(
      (p) => !assignedIds.has(p.id) && !assignedNames.has(p.positionName.trim().toLowerCase())
    );
  }, [masterPositions, assignedPositions]);

  // Filter unassigned master positions by the input query
  const matchingCatalogPositions = useMemo(() => {
    const q = positionInput.trim().toLowerCase();
    if (!q) return unassignedMasterPositions.slice(0, 8);
    return unassignedMasterPositions
      .filter((p) => p.positionName.toLowerCase().includes(q))
      .slice(0, 8);
  }, [unassignedMasterPositions, positionInput]);

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

  // Dynamic formatting preview
  const formattedPreview = useMemo(() => {
    if (!positionInput.trim()) return "";
    return formatPosition(positionInput.trim());
  }, [positionInput]);

  // Close dropdown on click outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsDropdownOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const resetForm = () => {
    setPositionInput("");
    setSelectedCatalogPosition(null);
    setIsDropdownOpen(false);
    setSearchQuery("");
    setUnlinkingPos(null);
    setFeedback(null);
  };

  const handleClose = () => {
    resetForm();
    onClose();
  };

  // Handle Account Change in global mode
  const handleAccountChange = (newAccId: string) => {
    setSelectedAccountId(newAccId);
    resetForm();
  };

  // Add Position Action (Unified simple add)
  const handleAddPosition = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = positionInput.trim();
    if (!effectiveAccountId || trimmed.length < 2) return;

    // Check if already assigned
    const alreadyAssigned = assignedPositions.some(
      (p) => p.positionName.trim().toLowerCase() === trimmed.toLowerCase()
    );
    if (alreadyAssigned) {
      setFeedback({
        type: "error",
        message: `Position "${formatPosition(trimmed)}" is already added to this account.`,
      });
      return;
    }

    setFeedback(null);
    setIsDropdownOpen(false);

    try {
      const matchedPos =
        selectedCatalogPosition ||
        unassignedMasterPositions.find(
          (p) => p.positionName.trim().toLowerCase() === trimmed.toLowerCase()
        );

      let res;
      if (matchedPos) {
        res = await manageMutation.mutateAsync({
          action: "link",
          accountId: effectiveAccountId,
          positionId: matchedPos.id,
        });
      } else {
        res = await manageMutation.mutateAsync({
          action: "create_and_link",
          accountId: effectiveAccountId,
          positionName: trimmed,
        });
      }

      setPositionInput("");
      setSelectedCatalogPosition(null);
      setFeedback({
        type: "success",
        message: res.message || `Position "${formatPosition(trimmed)}" added to ${accountDisplayName}.`,
      });
    } catch (err) {
      setFeedback({
        type: "error",
        message: err instanceof Error ? err.message : "Failed to add position.",
      });
    }
  };

  // Remove Position Action
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
      setFeedback({
        type: "success",
        message: res.message || "Position removed from account.",
      });
    } catch (err) {
      setFeedback({
        type: "error",
        message: err instanceof Error ? err.message : "Failed to remove position.",
      });
      setUnlinkingPos(null);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs animate-in fade-in duration-150">
      <div className="relative flex flex-col w-full max-w-2xl max-h-[90vh] bg-surface-primary border border-border-default rounded-xl shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-border-subtle bg-surface-base">
          <div className="flex items-center gap-3 min-w-0">
            <div className="p-2.5 rounded-lg bg-brand-subtle text-brand-primary shrink-0">
              <Briefcase className="w-5 h-5 text-brand-600" />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <h2 className="text-base font-bold text-text-primary">
                  Manage Positions
                </h2>
                {isFixedAccount && (
                  <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-md bg-brand-subtle text-brand-primary text-xs font-semibold border border-brand-border">
                    <Building2 className="w-3.5 h-3.5" />
                    <span>{accountDisplayName}</span>
                  </span>
                )}
                <span className="px-2 py-0.5 text-3xs font-bold uppercase rounded-md bg-purple-50 text-purple-700 dark:bg-purple-950/40 dark:text-purple-300 border border-purple-200 dark:border-purple-800">
                  Data Team
                </span>
              </div>
              <p className="text-xs text-text-muted mt-0.5 truncate">
                Configure job positions available for {accountDisplayName}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="p-1.5 text-text-muted hover:text-text-primary hover:bg-surface-hover rounded-lg transition shrink-0 cursor-pointer"
            aria-label="Close"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Global Account Selector Bar: ONLY rendered when not locked to a specific account */}
        {!isFixedAccount && (
          <div className="px-6 py-3 border-b border-border-subtle bg-surface-subtle/40 flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-2.5 flex-1 min-w-[240px]">
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

            <div className="flex items-center gap-1.5 text-xs text-text-muted">
              <span className="px-2 py-0.5 rounded-md bg-surface-primary border border-border-default font-medium text-text-secondary text-3xs">
                {assignedPositions.length} {assignedPositions.length === 1 ? "Position" : "Positions"}
              </span>
            </div>
          </div>
        )}

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
              className="text-text-muted hover:text-text-primary p-0.5 cursor-pointer"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        )}

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-5">
          {/* Section 1: Simple Add Position Input */}
          <div
            ref={containerRef}
            className="p-4 rounded-xl border border-border-default bg-surface-subtle/40 space-y-2.5"
          >
            <div className="flex items-center justify-between">
              <label
                htmlFor="position-add-input"
                className="text-xs font-bold text-text-primary flex items-center gap-1.5"
              >
                <span>Add Position</span>
              </label>
              {formattedPreview && formattedPreview.toLowerCase() !== positionInput.trim().toLowerCase() && (
                <span className="text-3xs text-text-muted">
                  Auto-formatted: <strong className="text-brand-600">{formattedPreview}</strong>
                </span>
              )}
            </div>

            <form onSubmit={handleAddPosition} className="space-y-2">
              <div className="relative flex items-center gap-2">
                <div className="relative flex-1">
                  <input
                    id="position-add-input"
                    ref={inputRef}
                    type="text"
                    value={positionInput}
                    onChange={(e) => {
                      setPositionInput(e.target.value);
                      setSelectedCatalogPosition(null);
                      setIsDropdownOpen(true);
                    }}
                    onFocus={() => setIsDropdownOpen(true)}
                    placeholder="Type or select position (e.g. Barista, Cashier, FSR)..."
                    className="w-full h-9 pl-3 pr-8 text-xs font-medium rounded-lg border border-border-default bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:ring-2 focus:ring-brand-500 transition"
                  />
                  <button
                    type="button"
                    onClick={() => setIsDropdownOpen((prev) => !prev)}
                    className="absolute right-2 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-primary p-1 cursor-pointer"
                    title="Toggle catalog suggestions"
                    tabIndex={-1}
                  >
                    <ChevronDown className="w-3.5 h-3.5" />
                  </button>

                  {/* Autocomplete / Catalog Suggestions Dropdown */}
                  {isDropdownOpen && (
                    <div className="absolute left-0 right-0 top-full mt-1 max-h-48 overflow-y-auto rounded-lg border border-border-default bg-surface-primary shadow-lg z-20 py-1">
                      <div className="px-3 py-1 text-3xs font-semibold text-text-muted uppercase tracking-wider bg-surface-subtle border-b border-border-subtle">
                        {matchingCatalogPositions.length > 0
                          ? "Suggested Catalog Positions"
                          : "No matching catalog positions"}
                      </div>
                      {matchingCatalogPositions.map((pos) => (
                        <button
                          key={pos.id}
                          type="button"
                          onClick={() => {
                            setPositionInput(pos.positionName);
                            setSelectedCatalogPosition(pos);
                            setIsDropdownOpen(false);
                          }}
                          className="w-full px-3 py-2 text-left text-xs hover:bg-surface-hover flex items-center justify-between text-text-primary transition cursor-pointer"
                        >
                          <span className="font-medium">{formatPosition(pos.positionName)}</span>
                          {pos.positionCode && (
                            <span className="text-3xs font-mono text-text-muted bg-surface-subtle px-1.5 py-0.2 rounded border border-border-subtle">
                              {pos.positionCode}
                            </span>
                          )}
                        </button>
                      ))}
                      {positionInput.trim().length >= 2 &&
                        !matchingCatalogPositions.some(
                          (p) => p.positionName.trim().toLowerCase() === positionInput.trim().toLowerCase()
                        ) && (
                          <div className="px-3 py-1.5 text-3xs text-brand-600 bg-brand-subtle/40 border-t border-border-subtle flex items-center gap-1">
                            <Plus className="w-3 h-3" />
                            <span>Will create new catalog position &quot;{formattedPreview}&quot;</span>
                          </div>
                        )}
                    </div>
                  )}
                </div>

                <button
                  type="submit"
                  disabled={positionInput.trim().length < 2 || manageMutation.isPending}
                  className="inline-flex items-center gap-1.5 h-9 px-4 rounded-lg bg-brand-button hover:bg-brand-button-hover disabled:opacity-50 text-white text-xs font-semibold shadow-2xs transition cursor-pointer shrink-0"
                >
                  {manageMutation.isPending ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>Adding...</span>
                    </>
                  ) : (
                    <>
                      <Plus className="w-3.5 h-3.5" />
                      <span>Add Position</span>
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>

          {/* Section 2: Current Positions List */}
          <div className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <h3 className="text-xs font-bold text-text-primary">
                  Assigned Positions
                </h3>
                <span className="px-2 py-0.5 rounded-full text-3xs font-bold bg-surface-subtle text-text-secondary border border-border-default">
                  {assignedPositions.length}
                </span>
              </div>

              {assignedPositions.length > 0 && (
                <div className="relative w-full sm:w-56">
                  <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-text-muted" />
                  <input
                    type="text"
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    placeholder="Search assigned roles..."
                    className="w-full h-8 pl-8 pr-3 text-xs rounded-lg border border-border-default bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:ring-1 focus:ring-brand-500"
                  />
                </div>
              )}
            </div>

            {/* Content states */}
            {isLoadingPositions || isRefetchingPositions ? (
              <div className="flex flex-col items-center justify-center py-12 text-text-muted">
                <Loader2 className="w-6 h-6 animate-spin text-brand-600 mb-2" />
                <p className="text-xs">Loading positions for {accountDisplayName}...</p>
              </div>
            ) : filteredAssignedPositions.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-center border border-dashed border-border-default rounded-xl bg-surface-subtle/30 px-4">
                <Briefcase className="w-8 h-8 text-text-muted mb-2 opacity-50" />
                <p className="text-xs font-semibold text-text-secondary">
                  {searchQuery ? "No matching positions found" : "No positions assigned yet"}
                </p>
                <p className="text-3xs text-text-muted max-w-sm mt-1">
                  {searchQuery
                    ? "Try adjusting your search keyword."
                    : `Type or select a position in the input above and click "Add Position" to enable roles for ${accountDisplayName}.`}
                </p>
              </div>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                {filteredAssignedPositions.map((pos) => {
                  const inUse = pos.activeEmployeeCount > 0 || pos.openVacancyCount > 0;
                  const isConfirmingThis = unlinkingPos?.positionId === pos.positionId;

                  return (
                    <div
                      key={pos.positionId}
                      className={`p-3 rounded-xl border transition flex items-center justify-between gap-2.5 ${
                        isConfirmingThis
                          ? "border-rose-300 bg-rose-50/50 dark:border-rose-800 dark:bg-rose-950/20"
                          : "border-border-default bg-surface-base hover:border-border-strong"
                      }`}
                    >
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="text-xs font-bold text-text-primary truncate">
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
                            className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-3xs font-medium ${
                              pos.activeEmployeeCount > 0
                                ? "bg-blue-50 text-blue-700 dark:bg-blue-950/40 dark:text-blue-300 border border-blue-200 dark:border-blue-800 font-semibold"
                                : "bg-surface-subtle text-text-muted"
                            }`}
                          >
                            <Users className="w-3 h-3" />
                            <span>{pos.activeEmployeeCount} active</span>
                          </span>

                          <span
                            className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-3xs font-medium ${
                              pos.openVacancyCount > 0
                                ? "bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300 border border-amber-200 dark:border-amber-800 font-semibold"
                                : "bg-surface-subtle text-text-muted"
                            }`}
                          >
                            <Briefcase className="w-3 h-3" />
                            <span>{pos.openVacancyCount} open vac</span>
                          </span>
                        </div>
                      </div>

                      {/* Remove / Lock Action */}
                      <div className="shrink-0">
                        {inUse ? (
                          <div
                            title={`Locked: In use by ${pos.activeEmployeeCount} employee(s) and ${pos.openVacancyCount} open vacancy(ies).`}
                            className="p-1.5 text-text-muted/40 cursor-not-allowed"
                          >
                            <Lock className="w-4 h-4" />
                          </div>
                        ) : isConfirmingThis ? (
                          <div className="flex items-center gap-1">
                            <button
                              type="button"
                              onClick={() => setUnlinkingPos(null)}
                              className="px-2 py-1 rounded text-3xs font-medium text-text-secondary hover:bg-surface-hover border border-border-default transition cursor-pointer"
                            >
                              Cancel
                            </button>
                            <button
                              type="button"
                              onClick={handleConfirmUnlink}
                              disabled={manageMutation.isPending}
                              className="px-2 py-1 rounded text-3xs font-bold text-white bg-rose-600 hover:bg-rose-700 transition cursor-pointer"
                            >
                              {manageMutation.isPending ? "..." : "Remove"}
                            </button>
                          </div>
                        ) : (
                          <button
                            type="button"
                            onClick={() => setUnlinkingPos(pos)}
                            title="Remove position from this account"
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
        </div>

        {/* Footer */}
        <div className="px-6 py-3.5 border-t border-border-subtle bg-surface-base flex items-center justify-between">
          <span className="text-3xs text-text-muted flex items-center gap-1.5">
            <Lock className="w-3 h-3 text-text-muted/70" />
            <span>Positions with active staff or open vacancies cannot be removed.</span>
          </span>
          <button
            type="button"
            onClick={handleClose}
            className="px-4 py-1.5 text-xs font-semibold rounded-lg border border-border-default bg-surface-primary text-text-primary hover:bg-surface-hover transition cursor-pointer"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
}
