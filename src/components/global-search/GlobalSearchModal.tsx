"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  ArrowRight,
  BriefcaseBusiness,
  CheckCheck,
  ClipboardList,
  Clock,
  CornerDownLeft,
  History,
  Loader2,
  Search,
  ShieldCheck,
  Sparkles,
  Trash2,
  X,
} from "lucide-react";
import {
  clearRecentSearches,
  getMatchedFieldLabel,
  getNavigationUrl,
  getRecentSearches,
  getTypeBadgeInfo,
  GlobalSearchResultItem,
  saveRecentSearch,
  useGlobalSearch,
} from "@/lib/queries/globalSearch";

export interface GlobalSearchModalProps {
  isOpen: boolean;
  onClose: () => void;
  onOpenOhmni?: () => void;
}

type CategoryFilter = "all" | "vacancy" | "plantilla" | "hr_emploc" | "applicant" | "store";

export function GlobalSearchModal({
  isOpen,
  onClose,
  onOpenOhmni,
}: GlobalSearchModalProps) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [debouncedQuery, setDebouncedQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState<CategoryFilter>("all");
  const [rawSelectedIndex, setRawSelectedIndex] = useState(0);
  const [recentSearches, setRecentSearches] = useState<string[]>(() => getRecentSearches());

  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  // Debounce query (250ms)
  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedQuery(query.trim());
    }, 250);
    return () => clearTimeout(handler);
  }, [query]);

  const handleClose = () => {
    setQuery("");
    setDebouncedQuery("");
    setSelectedCategory("all");
    setRawSelectedIndex(0);
    onClose();
  };

  // Focus input on open
  useEffect(() => {
    if (isOpen) {
      inputRef.current?.focus();
      inputRef.current?.select();
    }
  }, [isOpen]);

  const { data: results = [], isLoading, error } = useGlobalSearch(debouncedQuery, isOpen);

  // Filtered by Category
  const filteredResults = useMemo(() => {
    if (selectedCategory === "all") return results;
    return results.filter((item) => item.resultType.toLowerCase() === selectedCategory);
  }, [results, selectedCategory]);

  const selectedIndex = Math.min(
    rawSelectedIndex,
    Math.max(0, filteredResults.length - 1)
  );

  // Category counts
  const categoryCounts = useMemo(() => {
    const counts: Record<string, number> = {
      vacancy: 0,
      plantilla: 0,
      hr_emploc: 0,
      applicant: 0,
      store: 0,
    };
    for (const r of results) {
      const t = r.resultType.toLowerCase();
      if (counts[t] !== undefined) counts[t]++;
    }
    return counts;
  }, [results]);

  // Scroll active item into view
  useEffect(() => {
    if (listRef.current) {
      const activeEl = listRef.current.querySelector<HTMLElement>('[data-active="true"]');
      if (activeEl) {
        activeEl.scrollIntoView({ block: "nearest" });
      }
    }
  }, [selectedIndex]);

  // Handle result selection & navigation
  const handleSelectResult = (result: GlobalSearchResultItem) => {
    if (debouncedQuery.length >= 2) {
      const updated = saveRecentSearch(debouncedQuery);
      setRecentSearches(updated);
    }
    handleClose();
    const targetUrl = getNavigationUrl(result);
    router.push(targetUrl);
  };

  // Quick navigation shortcuts for initial state
  const handleQuickNavigate = (url: string) => {
    handleClose();
    router.push(url);
  };

  // Key navigation
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Escape") {
      e.preventDefault();
      handleClose();
      return;
    }

    if (e.key === "ArrowDown") {
      e.preventDefault();
      if (filteredResults.length > 0) {
        setRawSelectedIndex((prev) => (prev + 1) % filteredResults.length);
      }
      return;
    }

    if (e.key === "ArrowUp") {
      e.preventDefault();
      if (filteredResults.length > 0) {
        setRawSelectedIndex((prev) => (prev - 1 + filteredResults.length) % filteredResults.length);
      }
      return;
    }

    if (e.key === "Enter") {
      e.preventDefault();
      if (filteredResults.length > 0 && filteredResults[selectedIndex]) {
        handleSelectResult(filteredResults[selectedIndex]);
      } else if (debouncedQuery.trim() && onOpenOhmni) {
        handleClose();
        onOpenOhmni();
      }
    }
  };

  const handleApplyRecent = (term: string) => {
    setQuery(term);
    setDebouncedQuery(term);
    inputRef.current?.focus();
  };

  const handleClearHistory = (e: React.MouseEvent) => {
    e.stopPropagation();
    clearRecentSearches();
    setRecentSearches([]);
  };

  if (!isOpen) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Global search command palette"
      className="fixed inset-0 z-50 flex items-start justify-center pt-16 sm:pt-24 px-4 bg-black/60 backdrop-blur-xs animate-in fade-in-0 duration-150"
      onClick={handleClose}
    >
      <div
        className="w-full max-w-2xl overflow-hidden rounded-2xl border border-[var(--line-strong)] bg-[var(--card)] text-[var(--text)] shadow-2xl transition-all"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={handleKeyDown}
      >
        {/* Search Bar Input */}
        <div className="relative flex items-center border-b border-[var(--line)] px-4 py-3 bg-[var(--soft)]/30">
          <Search size={18} className="shrink-0 text-[var(--muted)] mr-3" />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search vacancies, personnel, VCODE, accounts, applicants…"
            className="w-full bg-transparent text-sm sm:text-base text-[var(--text)] placeholder:text-[var(--muted)] outline-hidden"
          />
          {isLoading && (
            <Loader2 size={16} className="animate-spin text-brand-500 shrink-0 mx-2" />
          )}
          {query && !isLoading && (
            <button
              type="button"
              onClick={() => {
                setQuery("");
                setDebouncedQuery("");
                inputRef.current?.focus();
              }}
              className="p-1 rounded-md text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)] transition mr-1.5 cursor-pointer"
            >
              <X size={15} />
            </button>
          )}
          <kbd className="hidden sm:inline-flex items-center gap-0.5 rounded border border-[var(--line)] bg-[var(--soft)] px-1.5 py-0.5 text-[10px] font-mono font-medium text-[var(--muted)]">
            ESC
          </kbd>
        </div>

        {/* Category Filter Pills (When search query exists) */}
        {debouncedQuery.length >= 2 && results.length > 0 && (
          <div className="flex items-center gap-1.5 px-4 py-2 border-b border-[var(--line)] bg-[var(--card)] overflow-x-auto no-scrollbar text-xs">
            <button
              type="button"
              onClick={() => setSelectedCategory("all")}
              className={`px-2.5 py-1 rounded-md font-medium transition cursor-pointer ${
                selectedCategory === "all"
                  ? "bg-brand-500 text-white font-semibold"
                  : "text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)]"
              }`}
            >
              All ({results.length})
            </button>
            <button
              type="button"
              onClick={() => setSelectedCategory("vacancy")}
              className={`px-2.5 py-1 rounded-md font-medium transition cursor-pointer ${
                selectedCategory === "vacancy"
                  ? "bg-brand-500 text-white font-semibold"
                  : "text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)]"
              }`}
            >
              Vacancies ({categoryCounts.vacancy || 0})
            </button>
            <button
              type="button"
              onClick={() => setSelectedCategory("plantilla")}
              className={`px-2.5 py-1 rounded-md font-medium transition cursor-pointer ${
                selectedCategory === "plantilla"
                  ? "bg-brand-500 text-white font-semibold"
                  : "text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)]"
              }`}
            >
              Plantilla ({categoryCounts.plantilla || 0})
            </button>
            <button
              type="button"
              onClick={() => setSelectedCategory("hr_emploc")}
              className={`px-2.5 py-1 rounded-md font-medium transition cursor-pointer ${
                selectedCategory === "hr_emploc"
                  ? "bg-brand-500 text-white font-semibold"
                  : "text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)]"
              }`}
            >
              HR Emploc ({categoryCounts.hr_emploc || 0})
            </button>
            <button
              type="button"
              onClick={() => setSelectedCategory("applicant")}
              className={`px-2.5 py-1 rounded-md font-medium transition cursor-pointer ${
                selectedCategory === "applicant"
                  ? "bg-brand-500 text-white font-semibold"
                  : "text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)]"
              }`}
            >
              Applicants ({categoryCounts.applicant || 0})
            </button>
            <button
              type="button"
              onClick={() => setSelectedCategory("store")}
              className={`px-2.5 py-1 rounded-md font-medium transition cursor-pointer ${
                selectedCategory === "store"
                  ? "bg-brand-500 text-white font-semibold"
                  : "text-[var(--muted)] hover:text-[var(--text)] hover:bg-[var(--soft)]"
              }`}
            >
              Stores ({categoryCounts.store || 0})
            </button>
          </div>
        )}

        {/* Modal Body & Results Container */}
        <div ref={listRef} className="max-h-[60vh] overflow-y-auto p-2">
          {/* Initial State: Recent Searches & Shortcuts */}
          {debouncedQuery.length < 2 && (
            <div className="p-3 space-y-4">
              {/* Recent Searches */}
              {recentSearches.length > 0 && (
                <div className="space-y-2">
                  <div className="flex items-center justify-between text-xs font-semibold text-[var(--muted)] px-1">
                    <span className="flex items-center gap-1.5 uppercase tracking-wider text-[11px]">
                      <History size={12} />
                      Recent Searches
                    </span>
                    <button
                      type="button"
                      onClick={handleClearHistory}
                      className="text-[11px] text-[var(--muted)] hover:text-rose-500 transition cursor-pointer flex items-center gap-1"
                    >
                      <Trash2 size={11} />
                      Clear
                    </button>
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {recentSearches.map((term) => (
                      <button
                        key={term}
                        type="button"
                        onClick={() => handleApplyRecent(term)}
                        className="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-lg border border-[var(--line)] bg-[var(--soft)] hover:bg-[var(--card)] hover:border-brand-500 text-[var(--text)] transition cursor-pointer"
                      >
                        <Clock size={11} className="text-[var(--muted)]" />
                        <span>{term}</span>
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {/* Module Shortcuts */}
              <div className="space-y-1 pt-1">
                <span className="text-[11px] font-semibold text-[var(--muted)] uppercase tracking-wider px-1 block mb-1">
                  Quick Navigation
                </span>
                <button
                  type="button"
                  onClick={() => handleQuickNavigate("/vacancy")}
                  className="w-full flex items-center justify-between p-2 rounded-lg hover:bg-[var(--soft)] transition text-left cursor-pointer group"
                >
                  <span className="flex items-center gap-2.5 text-xs text-[var(--text)] font-medium">
                    <BriefcaseBusiness size={14} className="text-amber-500" />
                    <span>Vacancy Management</span>
                  </span>
                  <span className="text-[11px] text-[var(--muted)] group-hover:text-[var(--text)]">Jump to /vacancy →</span>
                </button>
                <button
                  type="button"
                  onClick={() => handleQuickNavigate("/plantilla")}
                  className="w-full flex items-center justify-between p-2 rounded-lg hover:bg-[var(--soft)] transition text-left cursor-pointer group"
                >
                  <span className="flex items-center gap-2.5 text-xs text-[var(--text)] font-medium">
                    <ShieldCheck size={14} className="text-blue-500" />
                    <span>Plantilla Personnel Roster</span>
                  </span>
                  <span className="text-[11px] text-[var(--muted)] group-hover:text-[var(--text)]">Jump to /plantilla →</span>
                </button>
                <button
                  type="button"
                  onClick={() => handleQuickNavigate("/approvals")}
                  className="w-full flex items-center justify-between p-2 rounded-lg hover:bg-[var(--soft)] transition text-left cursor-pointer group"
                >
                  <span className="flex items-center gap-2.5 text-xs text-[var(--text)] font-medium">
                    <CheckCheck size={14} className="text-purple-500" />
                    <span>Approvals Center</span>
                  </span>
                  <span className="text-[11px] text-[var(--muted)] group-hover:text-[var(--text)]">Jump to /approvals →</span>
                </button>
                <button
                  type="button"
                  onClick={() => handleQuickNavigate("/my-requests")}
                  className="w-full flex items-center justify-between p-2 rounded-lg hover:bg-[var(--soft)] transition text-left cursor-pointer group"
                >
                  <span className="flex items-center gap-2.5 text-xs text-[var(--text)] font-medium">
                    <ClipboardList size={14} className="text-emerald-500" />
                    <span>My Requests Feed</span>
                  </span>
                  <span className="text-[11px] text-[var(--muted)] group-hover:text-[var(--text)]">Jump to /my-requests →</span>
                </button>
              </div>

              {/* OHMni Co-Pilot Bridge */}
              {onOpenOhmni && (
                <div className="pt-2 border-t border-[var(--line)]">
                  <button
                    type="button"
                    onClick={() => {
                      handleClose();
                      onOpenOhmni();
                    }}
                    className="w-full flex items-center justify-between p-2.5 rounded-xl border border-amber-500/20 bg-amber-500/5 hover:bg-amber-500/10 transition text-left cursor-pointer group"
                  >
                    <span className="flex items-center gap-2 text-xs font-semibold text-amber-700 dark:text-amber-400">
                      <Sparkles size={14} className="text-amber-500" />
                      <span>Ask OHMni AI Co-Pilot</span>
                    </span>
                    <span className="text-[11px] text-amber-600 dark:text-amber-400 font-mono">⌘J / Open Assistant →</span>
                  </button>
                </div>
              )}
            </div>
          )}

          {/* Results List */}
          {debouncedQuery.length >= 2 && filteredResults.length > 0 && (
            <div className="space-y-1">
              {filteredResults.map((item, idx) => {
                const isSelected = idx === selectedIndex;
                const badgeInfo = getTypeBadgeInfo(item.resultType);
                const matchedText = getMatchedFieldLabel(item.matchedField);

                return (
                  <div
                    key={`${item.resultType}-${item.recordId}-${idx}`}
                    data-active={isSelected}
                    onClick={() => handleSelectResult(item)}
                    onMouseEnter={() => setRawSelectedIndex(idx)}
                    className={`flex items-center justify-between p-3 rounded-xl transition cursor-pointer border ${
                      isSelected
                        ? "bg-brand-500/10 border-brand-500/40 shadow-xs"
                        : "border-transparent hover:bg-[var(--soft)]/70"
                    }`}
                  >
                    {/* Left: Result Details */}
                    <div className="space-y-1 min-w-0 pr-3">
                      <div className="flex items-center gap-2">
                        <span
                          className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold border ${badgeInfo.badgeClass}`}
                        >
                          {badgeInfo.label}
                        </span>
                        <h4 className="text-sm font-semibold text-[var(--text)] truncate">
                          {item.primaryLabel}
                        </h4>
                        {item.status && (
                          <span className="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-[var(--soft)] text-[var(--muted)] border border-[var(--line)]">
                            {item.status}
                          </span>
                        )}
                      </div>

                      <p className="text-xs text-[var(--muted)] truncate">
                        {item.secondaryLabel}
                      </p>

                      <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[10px] text-[var(--muted)]">
                        <span className="font-mono text-brand-600 dark:text-brand-400">
                          {matchedText}
                        </span>
                        {item.accountName && (
                          <>
                            <span>·</span>
                            <span>{item.accountName}</span>
                          </>
                        )}
                        {item.groupName && (
                          <>
                            <span>·</span>
                            <span>{item.groupName}</span>
                          </>
                        )}
                      </div>
                    </div>

                    {/* Right: Enter key indicator */}
                    <div className="shrink-0 flex items-center gap-1 text-[var(--muted)]">
                      {isSelected ? (
                        <span className="inline-flex items-center gap-1 text-[11px] font-medium text-brand-600 dark:text-brand-400">
                          <span>Open</span>
                          <CornerDownLeft size={12} />
                        </span>
                      ) : (
                        <ArrowRight size={14} className="opacity-40" />
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {/* No Results Empty State */}
          {debouncedQuery.length >= 2 && !isLoading && filteredResults.length === 0 && (
            <div className="p-8 text-center space-y-3">
              <Search size={28} className="mx-auto text-[var(--muted)] opacity-50" />
              <div>
                <p className="text-sm font-semibold text-[var(--text)]">
                  No records found for &ldquo;{debouncedQuery}&rdquo;
                </p>
                <p className="text-xs text-[var(--muted)] mt-1 max-w-sm mx-auto">
                  Try searching by VCODE (e.g. V-0012), employee name, employee number, position title, or store branch.
                </p>
              </div>

              {onOpenOhmni && (
                <button
                  type="button"
                  onClick={() => {
                    handleClose();
                    onOpenOhmni();
                  }}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-amber-500/30 bg-amber-500/10 text-xs font-medium text-amber-700 dark:text-amber-400 hover:bg-amber-500/20 transition cursor-pointer"
                >
                  <Sparkles size={13} className="text-amber-500" />
                  <span>Ask OHMni AI about &ldquo;{debouncedQuery}&rdquo;</span>
                </button>
              )}
            </div>
          )}

          {/* Error State */}
          {debouncedQuery.length >= 2 && error && (
            <div className="p-6 text-center text-xs text-rose-600 dark:text-rose-400 space-y-1">
              <p className="font-semibold">Search unavailable</p>
              <p className="text-[11px] opacity-80">
                {error instanceof Error ? error.message : "Failed to query global index."}
              </p>
            </div>
          )}
        </div>

        {/* Footer info bar */}
        <div className="flex items-center justify-between px-4 py-2 border-t border-[var(--line)] bg-[var(--soft)]/50 text-[11px] text-[var(--muted)]">
          <div className="flex items-center gap-3">
            <span className="flex items-center gap-1">
              <kbd className="px-1 py-0.5 rounded border border-[var(--line)] bg-[var(--card)] font-mono text-[9px]">↑</kbd>
              <kbd className="px-1 py-0.5 rounded border border-[var(--line)] bg-[var(--card)] font-mono text-[9px]">↓</kbd>
              <span>Navigate</span>
            </span>
            <span className="flex items-center gap-1">
              <kbd className="px-1 py-0.5 rounded border border-[var(--line)] bg-[var(--card)] font-mono text-[9px]">↵</kbd>
              <span>Select</span>
            </span>
          </div>
          <span className="text-[10px] font-mono">
            Powered by search_global_index
          </span>
        </div>
      </div>
    </div>
  );
}
