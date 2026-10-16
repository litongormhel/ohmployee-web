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
  X,
} from "lucide-react";
import type { HrEmplocFilterState, HrEmplocSavedView } from "./useHrEmplocSavedViews";
import type { HrEmplocQueue } from "@/lib/queries/hr_emploc";

export interface HrEmplocSavedViewsModalProps {
  isOpen: boolean;
  onClose: () => void;
  currentFilters: HrEmplocFilterState;
  accounts: Array<{ id: string; name: string }>;
  groups: Array<{ id: string; name: string }>;
  savedViews: HrEmplocSavedView[];
  onSaveView: (name: string, filters: HrEmplocFilterState) => void;
  onUpdateView: (id: string, name: string, filters: HrEmplocFilterState) => void;
  onDeleteView: (id: string, name: string) => void;
  onApplyView: (view: HrEmplocSavedView) => void;
}

const QUEUE_LABELS: Record<HrEmplocQueue, string> = {
  pending: "Pending",
  correction: "Correction",
  review: "Review",
  ready: "Ready",
  deficiency: "Correction",
  complete: "Ready",
  deletion_pending: "Pending Deletion",
  all: "All",
};

export function HrEmplocSavedViewsModal(props: HrEmplocSavedViewsModalProps) {
  if (!props.isOpen) return null;
  return <HrEmplocSavedViewsModalContent {...props} />;
}

function HrEmplocSavedViewsModalContent({
  onClose,
  currentFilters,
  accounts,
  groups,
  savedViews,
  onSaveView,
  onUpdateView,
  onDeleteView,
  onApplyView,
}: HrEmplocSavedViewsModalProps) {
  const [newViewName, setNewViewName] = useState("");
  const [saveError, setSaveError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [activeTab, setActiveTab] = useState<"list" | "create">("list");
  const [selectedViewId, setSelectedViewId] = useState<string | null>(null);

  const accountMap = useMemo(() => new Map(accounts.map((a) => [a.id, a.name])), [accounts]);
  const groupMap = useMemo(() => new Map(groups.map((g) => [g.id, g.name])), [groups]);

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  const filteredViews = useMemo(() => {
    if (!searchQuery.trim()) return savedViews;
    const q = searchQuery.toLowerCase();
    return savedViews.filter((v) => v.name.toLowerCase().includes(q));
  }, [savedViews, searchQuery]);

  const handleSaveCurrent = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = newViewName.trim();
    if (!trimmed) {
      setSaveError("Please provide a name for this saved view.");
      return;
    }
    if (savedViews.some((v) => v.name.toLowerCase() === trimmed.toLowerCase())) {
      setSaveError("A saved view with this name already exists.");
      return;
    }

    onSaveView(trimmed, currentFilters);
    setNewViewName("");
    setSaveError(null);
    setActiveTab("list");
  };

  const describeFilters = (filters: HrEmplocFilterState) => {
    const parts: string[] = [];
    parts.push(`Queue: ${QUEUE_LABELS[filters.queue] || filters.queue}`);
    if (filters.search) parts.push(`Search: "${filters.search}"`);
    if (filters.accountId) parts.push(`Account: ${accountMap.get(filters.accountId) || "Selected"}`);
    if (filters.groupId) parts.push(`Group: ${groupMap.get(filters.groupId) || "Selected"}`);
    return parts;
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/40 backdrop-blur-xs animate-in fade-in duration-200"
        onClick={onClose}
      />

      {/* Modal Dialog */}
      <div className="relative z-10 flex flex-col w-full max-w-2xl max-h-[85vh] rounded-xl border border-border-default bg-surface shadow-2xl animate-in fade-in zoom-in-95 duration-200 overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-subtle px-6 py-4 bg-surface-muted/30">
          <div className="flex items-center gap-2.5">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-brand-50 border border-brand-200 text-brand-700">
              <FileSearch className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-text-primary">
                Saved Views & Presets
              </h2>
              <p className="text-xs text-text-muted">
                Quickly access or save filtered workspace configurations.
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary transition-colors cursor-pointer"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Tab switcher */}
        <div className="flex border-b border-border-subtle px-6 bg-surface">
          <button
            type="button"
            onClick={() => setActiveTab("list")}
            className={`py-3 px-3 text-xs font-semibold border-b-2 transition-colors cursor-pointer ${
              activeTab === "list"
                ? "border-brand-600 text-brand-700"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            All Saved Views ({savedViews.length})
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("create")}
            className={`py-3 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-1.5 cursor-pointer ${
              activeTab === "create"
                ? "border-brand-600 text-brand-700"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            <Plus className="h-3.5 w-3.5" />
            Save Current View
          </button>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6">
          {activeTab === "create" ? (
            <form onSubmit={handleSaveCurrent} className="space-y-4">
              <div>
                <label
                  htmlFor="view-name"
                  className="block text-xs font-medium text-text-secondary mb-1"
                >
                  View Preset Name
                </label>
                <input
                  id="view-name"
                  type="text"
                  placeholder="e.g., Pending High Urgency, Correction Review..."
                  value={newViewName}
                  onChange={(e) => {
                    setNewViewName(e.target.value);
                    if (saveError) setSaveError(null);
                  }}
                  autoFocus
                  className="h-10 w-full rounded-lg border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500"
                />
                {saveError && <p className="mt-1.5 text-xs text-red-600 font-medium">{saveError}</p>}
              </div>

              {/* Current Active Filters Snapshot Preview */}
              <div className="rounded-lg border border-border-subtle bg-surface-muted/40 p-3.5 space-y-2">
                <span className="text-xs font-semibold text-text-secondary block">
                  Current Filter Values Snapshot:
                </span>
                <div className="flex flex-wrap gap-1.5">
                  {describeFilters(currentFilters).map((item, idx) => (
                    <span
                      key={idx}
                      className="inline-flex items-center px-2 py-1 rounded bg-surface border border-border-subtle text-xs text-text-primary"
                    >
                      {item}
                    </span>
                  ))}
                </div>
              </div>

              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setActiveTab("list")}
                  className="h-9 px-4 text-xs font-medium rounded-lg border border-border-default bg-surface hover:bg-surface-hover text-text-secondary cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="h-9 px-4 text-xs font-semibold rounded-lg bg-brand-600 hover:bg-brand-700 text-white shadow-2xs transition-colors cursor-pointer"
                >
                  Save Preset
                </button>
              </div>
            </form>
          ) : (
            <div className="space-y-4">
              {/* Search bar inside modal */}
              {savedViews.length > 3 && (
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-text-muted" />
                  <input
                    type="text"
                    placeholder="Search saved presets..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="h-9 w-full rounded-lg border border-border-default bg-surface-muted pl-9 pr-3 text-xs text-text-primary outline-none focus:border-brand-500"
                  />
                </div>
              )}

              {filteredViews.length === 0 ? (
                <div className="text-center py-10">
                  <div className="inline-flex h-12 w-12 items-center justify-center rounded-full bg-slate-100 text-slate-400 mb-3">
                    <Bookmark className="h-6 w-6" />
                  </div>
                  <h3 className="text-sm font-semibold text-text-primary">No saved views found</h3>
                  <p className="text-xs text-text-muted mt-1 max-w-sm mx-auto">
                    {searchQuery
                      ? "No presets match your search query."
                      : "Save custom filter sets to quickly switch views without re-applying filters each time."}
                  </p>
                  {!searchQuery && (
                    <button
                      type="button"
                      onClick={() => setActiveTab("create")}
                      className="mt-4 inline-flex items-center gap-1.5 h-8 px-3 rounded-lg bg-brand-600 hover:bg-brand-700 text-white text-xs font-semibold shadow-2xs transition-colors cursor-pointer"
                    >
                      <Plus className="h-3.5 w-3.5" />
                      Save Current View
                    </button>
                  )}
                </div>
              ) : (
                <div className="space-y-2">
                  {filteredViews.map((view) => {
                    const filterParts = describeFilters(view.filters);
                    const isSelected = selectedViewId === view.id;

                    return (
                      <div
                        key={view.id}
                        onClick={() => setSelectedViewId(isSelected ? null : view.id)}
                        className={`group rounded-lg border p-3.5 transition-all cursor-pointer ${
                          isSelected
                            ? "border-brand-300 bg-brand-50/20 shadow-2xs"
                            : "border-border-subtle bg-surface hover:border-slate-300 hover:bg-surface-hover"
                        }`}
                      >
                        <div className="flex items-start justify-between gap-3">
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2">
                              <span className="font-semibold text-xs text-text-primary truncate">
                                {view.name}
                              </span>
                              <span className="rounded bg-slate-100 border border-slate-200/80 px-1.5 py-0.2 text-[10px] font-mono text-text-muted">
                                {QUEUE_LABELS[view.filters.queue] || view.filters.queue}
                              </span>
                            </div>
                            <div className="flex flex-wrap gap-1 mt-2">
                              {filterParts.map((part, pIdx) => (
                                <span
                                  key={pIdx}
                                  className="text-[11px] text-text-muted bg-surface-muted border border-border-subtle rounded px-1.5 py-0.5"
                                >
                                  {part}
                                </span>
                              ))}
                            </div>
                          </div>

                          {/* Action Buttons */}
                          <div
                            className="flex items-center gap-1.5 shrink-0"
                            onClick={(e) => e.stopPropagation()}
                          >
                            <button
                              type="button"
                              onClick={() => {
                                onApplyView(view);
                                onClose();
                              }}
                              className="h-7 px-2.5 rounded-md bg-brand-600 hover:bg-brand-700 text-white text-xs font-semibold shadow-2xs flex items-center gap-1 transition-colors cursor-pointer"
                              title="Apply this saved view"
                            >
                              <Check className="h-3 w-3" />
                              Apply
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                onUpdateView(view.id, view.name, currentFilters);
                              }}
                              className="h-7 w-7 rounded-md border border-border-default bg-surface hover:bg-surface-hover text-text-secondary hover:text-text-primary flex items-center justify-center transition-colors cursor-pointer"
                              title="Update preset with current filters"
                            >
                              <RotateCw className="h-3 w-3" />
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                if (window.confirm(`Delete saved view "${view.name}"?`)) {
                                  onDeleteView(view.id, view.name);
                                }
                              }}
                              className="h-7 w-7 rounded-md border border-red-200 bg-surface hover:bg-red-50 text-red-600 flex items-center justify-center transition-colors cursor-pointer"
                              title="Delete preset"
                            >
                              <Trash2 className="h-3 w-3" />
                            </button>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle px-6 py-3 bg-surface-muted/30">
          <div className="flex items-center gap-1.5 text-xs text-text-muted">
            <Clock className="h-3.5 w-3.5" />
            <span>Presets saved locally in browser storage</span>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="h-8 px-3 rounded-lg border border-border-default bg-surface hover:bg-surface-hover text-xs font-semibold text-text-secondary transition-colors cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
