"use client";

import { useEffect, useMemo, useState } from "react";
import {
  Bookmark,
  Check,
  Clock,
  FileSearch,
  Plus,
  RotateCw,
  Search,
  Trash2,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import type { VacancyFilterState, VacancySavedView } from "./useVacancySavedViews";
import type { VacancyStatus } from "./VacancyTable";

export interface SavedViewsModalProps {
  isOpen: boolean;
  onClose: () => void;
  currentFilters: VacancyFilterState;
  accounts: Array<{ id: string; name: string }>;
  groups: Array<{ id: string; name: string }>;
  savedViews: VacancySavedView[];
  onSaveView: (name: string, filters: VacancyFilterState) => void;
  onUpdateView: (id: string, name: string, filters: VacancyFilterState) => void;
  onDeleteView: (id: string, name: string) => void;
  onApplyView: (view: VacancySavedView) => void;
}

const TAB_LABELS: Record<VacancyStatus, string> = {
  open: "Open",
  pipeline: "Pipeline",
  hired: "Hired",
  closure: "Closure",
  failed_backout: "Failed / Backout",
  with_applicant: "Pipeline",
  rejected: "Failed / Backout",
  backout: "Failed / Backout",
};

const AGING_LABELS: Record<string, string> = {
  advance: "Advance",
  "1_15": "1-15 days",
  "16_30": "16-30 days",
  "31_60": "31-60 days",
  "61_120": "61-120 days",
  gt121: "121+ days",
};

export function SavedViewsModal(props: SavedViewsModalProps) {
  if (!props.isOpen) return null;
  return <SavedViewsModalContent {...props} />;
}

function SavedViewsModalContent({
  isOpen = true,
  onClose,
  currentFilters,
  accounts,
  groups,
  savedViews,
  onSaveView,
  onUpdateView,
  onDeleteView,
  onApplyView,
}: SavedViewsModalProps) {
  const suggestedName = useMemo(() => {
    const parts: string[] = [];
    const tabName = TAB_LABELS[currentFilters.status] || currentFilters.status;
    parts.push(tabName);
    if (currentFilters.accountId) {
      const acc = accounts.find((a) => a.id === currentFilters.accountId);
      if (acc) parts.push(acc.name);
    }
    if (currentFilters.urgency) {
      parts.push(`${currentFilters.urgency} Urgency`);
    }
    if (currentFilters.agingBucket) {
      parts.push(AGING_LABELS[currentFilters.agingBucket] || currentFilters.agingBucket);
    }
    return parts.join(" · ");
  }, [currentFilters, accounts]);

  const [newViewName, setNewViewName] = useState(suggestedName);
  const [activeTab, setActiveTab] = useState<"list" | "save">("list");
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") {
        onClose();
      }
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newViewName.trim()) return;
    onSaveView(newViewName.trim(), currentFilters);
    setNewViewName("");
    setActiveTab("list");
  };

  const currentAccountName = accounts.find((a) => a.id === currentFilters.accountId)?.name;
  const currentGroupName = groups.find((g) => g.id === currentFilters.groupId)?.name;

  const getAccountName = (id: string) => accounts.find((a) => a.id === id)?.name || id;
  const getGroupName = (id: string) => groups.find((g) => g.id === id)?.name || id;

  const hasActiveFilters = Boolean(
    currentFilters.search.trim() ||
      currentFilters.accountId ||
      currentFilters.groupId ||
      currentFilters.agingBucket ||
      currentFilters.urgency ||
      currentFilters.vacantFrom ||
      currentFilters.vacantTo,
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Saved Views & Presets"
      subtitle="Save active filters as reusable views or quickly switch between saved presets."
      icon={FileSearch}
      maxWidthClass="max-w-2xl"
    >
      <div className="space-y-4 text-xs">

        {/* Tab navigation within modal */}
        <div className="flex border-b border-border-subtle px-6 pt-3 bg-surface">
          <button
            type="button"
            onClick={() => setActiveTab("list")}
            className={`pb-2.5 px-3 text-xs font-semibold border-b-2 transition-colors cursor-pointer ${
              activeTab === "list"
                ? "border-brand-600 text-brand-700"
                : "border-transparent text-text-muted hover:text-text-primary"
            }`}
          >
            Saved Presets ({savedViews.length})
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("save")}
            className={`pb-2.5 px-3 text-xs font-semibold border-b-2 transition-colors cursor-pointer flex items-center gap-1.5 ${
              activeTab === "save"
                ? "border-brand-600 text-brand-700"
                : "border-transparent text-text-muted hover:text-text-primary"
            }`}
          >
            <Plus className="h-3.5 w-3.5" />
            <span>Save Current View</span>
          </button>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-5">
          {activeTab === "save" ? (
            /* Save current view form */
            <form onSubmit={handleSave} className="space-y-4">
              <div className="rounded-lg border border-border-subtle bg-surface-muted/50 p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-semibold text-text-secondary">
                    Active Criteria Snapshot
                  </span>
                  <span className="rounded-full bg-surface-muted border border-border-default px-2 py-0.5 text-[10px] font-bold text-text-secondary">
                    Tab: {TAB_LABELS[currentFilters.status] || currentFilters.status}
                  </span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs">
                  <div className="rounded border border-border-subtle bg-surface-card p-2">
                    <span className="text-text-muted block text-[10px]">Search Query</span>
                    <span className="font-medium text-text-primary">
                      {currentFilters.search.trim() ? `"${currentFilters.search.trim()}"` : "None"}
                    </span>
                  </div>

                  <div className="rounded border border-border-subtle bg-surface-card p-2">
                    <span className="text-text-muted block text-[10px]">Account Filter</span>
                    <span className="font-medium text-text-primary">
                      {currentAccountName || "All Accounts"}
                    </span>
                  </div>

                  <div className="rounded border border-border-subtle bg-surface-card p-2">
                    <span className="text-text-muted block text-[10px]">Group Filter</span>
                    <span className="font-medium text-text-primary">
                      {currentGroupName || "All Groups"}
                    </span>
                  </div>

                  <div className="rounded border border-border-subtle bg-surface-card p-2">
                    <span className="text-text-muted block text-[10px]">Aging Bucket</span>
                    <span className="font-medium text-text-primary">
                      {AGING_LABELS[currentFilters.agingBucket] || currentFilters.agingBucket || "All Aging"}
                    </span>
                  </div>

                  <div className="rounded border border-border-subtle bg-surface-card p-2">
                    <span className="text-text-muted block text-[10px]">Urgency</span>
                    <span className="font-medium text-text-primary">
                      {currentFilters.urgency || "All Urgency"}
                    </span>
                  </div>

                  <div className="rounded border border-border-subtle bg-surface-card p-2">
                    <span className="text-text-muted block text-[10px]">Vacant Date Range</span>
                    <span className="font-medium text-text-primary font-mono text-[11px]">
                      {currentFilters.vacantFrom || currentFilters.vacantTo
                        ? `${currentFilters.vacantFrom || "Start"} → ${currentFilters.vacantTo || "End"}`
                        : "Any Date"}
                    </span>
                  </div>
                </div>

                {!hasActiveFilters && (
                  <p className="text-[11px] text-text-secondary bg-surface-muted border border-border-default rounded p-2">
                    Note: No custom search or secondary filters are currently applied. Saving this preset will capture the default view for the {TAB_LABELS[currentFilters.status] || currentFilters.status} tab.
                  </p>
                )}
              </div>

              <div className="space-y-1.5">
                <label
                  htmlFor="saved-view-name"
                  className="block text-xs font-semibold text-text-primary"
                >
                  Preset Name <span className="text-text-muted">*</span>
                </label>
                <input
                  id="saved-view-name"
                  type="text"
                  required
                  placeholder="e.g. Q4 Priority Pipeline - SM Manila"
                  value={newViewName}
                  onChange={(e) => setNewViewName(e.target.value)}
                  className="h-9 w-full rounded-md border border-border-default bg-surface-base px-3 text-xs text-text-primary outline-none focus:border-brand-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-subtle">
                <button
                  type="button"
                  onClick={() => setActiveTab("list")}
                  className="h-8 px-3 rounded-md text-xs font-medium text-text-muted hover:text-text-primary hover:bg-surface-hover transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={!newViewName.trim()}
                  className="h-8 px-4 rounded-md text-xs font-semibold bg-brand-600 text-white hover:bg-brand-700 disabled:opacity-50 transition cursor-pointer shadow-xs flex items-center gap-1.5"
                >
                  <Bookmark className="h-3.5 w-3.5" />
                  <span>Save View Preset</span>
                </button>
              </div>
            </form>
          ) : (
            /* List of existing saved views */
            <div className="space-y-3">
              {savedViews.length === 0 ? (
                <div className="rounded-lg border border-dashed border-border-default p-8 text-center space-y-3 bg-surface-muted">
                  <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-surface-muted text-text-muted">
                    <Bookmark className="h-5 w-5" />
                  </div>
                  <div>
                    <h3 className="text-sm font-semibold text-text-primary">
                      No saved views yet
                    </h3>
                    <p className="text-xs text-text-muted max-w-sm mx-auto mt-1">
                      Configure your search keywords, account, group, aging, and urgency filters, then save them as a reusable preset for fast one-click access.
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setActiveTab("save")}
                    className="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand-700 transition cursor-pointer shadow-xs"
                  >
                    <Plus className="h-3.5 w-3.5" />
                    <span>Save Current View</span>
                  </button>
                </div>
              ) : (
                savedViews.map((view) => {
                  const viewTabLabel = TAB_LABELS[view.filters.status] || view.filters.status;

                  return (
                    <div
                      key={view.id}
                      className="rounded-lg border border-border-subtle bg-surface p-4 transition hover:border-brand-300 hover:shadow-xs flex flex-col sm:flex-row sm:items-center justify-between gap-3"
                    >
                      <div className="space-y-1.5 flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="font-semibold text-sm text-text-primary">
                            {view.name}
                          </span>
                          <span
                            className="rounded-full px-2 py-0.5 text-[10px] font-medium border border-border-default bg-surface-muted text-text-secondary"
                          >
                            {viewTabLabel} Tab
                          </span>
                        </div>

                        {/* Filter summary badges */}
                        <div className="flex flex-wrap items-center gap-1.5 text-[11px] text-text-muted">
                          {view.filters.search && (
                            <span className="inline-flex items-center gap-1 rounded bg-surface-muted border border-border-subtle px-1.5 py-0.5 font-medium text-text-secondary">
                              <Search className="h-2.5 w-2.5" />
                              &quot;{view.filters.search}&quot;
                            </span>
                          )}

                          {view.filters.accountId && (
                            <span className="inline-flex items-center gap-1 rounded bg-surface-muted border border-border-subtle px-1.5 py-0.5 font-medium text-text-secondary">
                              Acc: {getAccountName(view.filters.accountId)}
                            </span>
                          )}

                          {view.filters.groupId && (
                            <span className="inline-flex items-center gap-1 rounded bg-surface-muted border border-border-subtle px-1.5 py-0.5 font-medium text-text-secondary">
                              Grp: {getGroupName(view.filters.groupId)}
                            </span>
                          )}

                          {view.filters.agingBucket && (
                            <span className="inline-flex items-center gap-1 rounded bg-surface-muted border border-border-subtle px-1.5 py-0.5 font-medium text-text-secondary">
                              Aging: {AGING_LABELS[view.filters.agingBucket] || view.filters.agingBucket}
                            </span>
                          )}

                          {view.filters.urgency && (
                            <span className="inline-flex items-center gap-1 rounded bg-surface-muted border border-border-subtle px-1.5 py-0.5 font-medium text-text-secondary">
                              Urgency: {view.filters.urgency}
                            </span>
                          )}

                          {(view.filters.vacantFrom || view.filters.vacantTo) && (
                            <span className="inline-flex items-center gap-1 rounded bg-surface-muted border border-border-subtle px-1.5 py-0.5 font-mono text-[10px] text-text-secondary">
                              {view.filters.vacantFrom || "*"} → {view.filters.vacantTo || "*"}
                            </span>
                          )}

                          {!view.filters.search &&
                            !view.filters.accountId &&
                            !view.filters.groupId &&
                            !view.filters.agingBucket &&
                            !view.filters.urgency &&
                            !view.filters.vacantFrom &&
                            !view.filters.vacantTo && (
                              <span className="text-[10px] text-text-muted italic">
                                Default tab queue (no additional filters)
                              </span>
                            )}
                        </div>

                        <div className="flex items-center gap-1 text-[10px] text-text-muted">
                          <Clock className="h-3 w-3" />
                          <span>
                            Updated {new Date(view.updatedAt).toLocaleDateString()}
                          </span>
                        </div>
                      </div>

                      {/* View Action buttons */}
                      <div className="flex items-center gap-1.5 shrink-0 self-end sm:self-center">
                        <button
                          type="button"
                          onClick={() => onApplyView(view)}
                          className="inline-flex items-center gap-1 rounded-md bg-brand-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand-700 transition cursor-pointer shadow-xs"
                          title={`Apply view preset "${view.name}"`}
                        >
                          <Check className="h-3.5 w-3.5" />
                          <span>Apply</span>
                        </button>

                        <button
                          type="button"
                          onClick={() => onUpdateView(view.id, view.name, currentFilters)}
                          className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface px-2.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
                          title="Overwrite preset with currently active filters"
                        >
                          <RotateCw className="h-3.5 w-3.5" />
                          <span className="hidden md:inline">Update</span>
                        </button>

                        {confirmDeleteId === view.id ? (
                          <div className="flex items-center gap-1">
                            <button
                              type="button"
                              onClick={() => {
                                onDeleteView(view.id, view.name);
                                setConfirmDeleteId(null);
                              }}
                              className="rounded-md border border-border-default bg-surface-muted px-2 py-1 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer"
                            >
                              Confirm
                            </button>
                            <button
                              type="button"
                              onClick={() => setConfirmDeleteId(null)}
                              className="rounded-md border border-border-default px-1.5 py-1 text-xs text-text-muted hover:bg-surface-hover transition cursor-pointer"
                            >
                              ✕
                            </button>
                          </div>
                        ) : (
                          <button
                            type="button"
                            onClick={() => setConfirmDeleteId(view.id)}
                            className="inline-flex items-center justify-center rounded-md border border-border-default bg-surface p-1.5 text-text-muted hover:text-text-primary hover:bg-surface-hover transition cursor-pointer"
                            title="Delete this preset"
                            aria-label={`Delete preset ${view.name}`}
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle pt-3 text-xs text-text-muted">
          <span>
            {savedViews.length} {savedViews.length === 1 ? "preset" : "presets"} stored locally
          </span>
          <button
            type="button"
            onClick={onClose}
            className="h-8 px-3 rounded-md border border-border-default bg-surface-base text-xs font-medium text-text-secondary hover:bg-surface-hover transition cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </Modal>
  );
}
