"use client";

import { Suspense, useMemo, useState, useTransition } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  AlertCircle,
  AlertTriangle,
  Bell,
  CheckCheck,
  CheckCircle,
  Clock,
  Filter,
  Inbox,
  Mail,
  RefreshCw,
  Search,
  Sparkles,
  X,
} from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import {
  useNotifications,
  useNotificationsRealtime,
  useNotificationCounts,
  useUnreadNotificationsCount,
  useToggleNotificationRead,
  useMarkNotificationsReadBatch,
  type NotificationItem,
  type NotificationTabFilter,
} from "@/lib/queries/notifications";
import { NotificationRow } from "@/components/notifications/NotificationRow";
import { NotificationBurstRow } from "@/components/notifications/NotificationBurstRow";
import { NotificationBulkBar } from "@/components/notifications/NotificationBulkBar";
import { NotificationUndoToast } from "@/components/notifications/NotificationUndoToast";
import { NotificationEmptyState } from "@/components/notifications/NotificationCard";
import {
  resolveNotificationPresentation,
  resolveNotificationModule,
  extractEntityCode,
  type NotificationModule,
} from "@/lib/notifications/severity";

// ============================================================================
// Types & Helper Config
// ============================================================================

interface TabConfig {
  key: NotificationTabFilter;
  label: string;
  count: number;
  icon: typeof Inbox;
}

interface DateGroup {
  key: "today" | "yesterday" | "this_week" | "earlier";
  label: string;
  items: (
    | { type: "single"; item: NotificationItem }
    | { type: "burst"; key: string; items: NotificationItem[] }
  )[];
}

const MODULE_OPTIONS: { id: NotificationModule | "all"; label: string }[] = [
  { id: "all", label: "All Modules" },
  { id: "vacancy", label: "Vacancy" },
  { id: "plantilla", label: "Plantilla" },
  { id: "hr_emploc", label: "HR Emploc" },
  { id: "approvals", label: "Approvals" },
  { id: "cencom", label: "CENCOM" },
  { id: "system", label: "System" },
];

function getDateBucket(dateString: string): "today" | "yesterday" | "this_week" | "earlier" {
  const date = new Date(dateString);
  if (isNaN(date.getTime())) return "earlier";

  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterdayStart = new Date(todayStart.getTime() - 24 * 60 * 60 * 1000);
  const weekStart = new Date(todayStart.getTime() - 6 * 24 * 60 * 1000 * 60 * 60);

  if (date >= todayStart) return "today";
  if (date >= yesterdayStart) return "yesterday";
  if (date >= weekStart) return "this_week";
  return "earlier";
}

// ============================================================================
// Main Notifications Page Content
// ============================================================================

function NotificationsPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();

  // Realtime Supabase Channel Subscription
  useNotificationsRealtime();

  // Active Tab state synced with URL search parameter
  const rawTab = (searchParams.get("tab") || "all") as NotificationTabFilter;
  const initialTab: NotificationTabFilter = [
    "all",
    "unread",
    "requests",
    "alerts",
    "system",
  ].includes(rawTab)
    ? rawTab
    : "all";

  const [activeTab, setActiveTab] = useState<NotificationTabFilter>(initialTab);
  const [selectedModules, setSelectedModules] = useState<Set<NotificationModule>>(new Set());
  const [searchQuery, setSearchQuery] = useState("");
  const [needsActionOnly, setNeedsActionOnly] = useState(false);

  // Bulk Selection State
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Undo Toast State
  const [undoToast, setUndoToast] = useState<{
    visible: boolean;
    message: string;
    affectedIds: string[];
    previousReadStates: Record<string, boolean>;
  }>({
    visible: false,
    message: "",
    affectedIds: [],
    previousReadStates: {},
  });

  // Mark-all Confirmation Modal State
  const [confirmMarkAllOpen, setConfirmMarkAllOpen] = useState(false);

  // Pagination display limit
  const [displayLimit, setDisplayLimit] = useState(50);

  // Queries
  const {
    data: allNotifications = [],
    isLoading,
    isRefetching,
    refetch: refetchList,
    error,
  } = useNotifications({ tab: activeTab, limit: 300 });

  const {
    data: counts = { all: 0, unread: 0, requests: 0, alerts: 0, system: 0 },
    refetch: refetchCounts,
  } = useNotificationCounts();

  const {
    data: unreadCount = 0,
    refetch: refetchUnread,
  } = useUnreadNotificationsCount();

  // Mutations
  const toggleMutation = useToggleNotificationRead();
  const batchMutation = useMarkNotificationsReadBatch();

  // Navigation / Tab sync
  const handleTabChange = (tab: NotificationTabFilter) => {
    setActiveTab(tab);
    setSelectedIds(new Set());
    startTransition(() => {
      const params = new URLSearchParams(searchParams.toString());
      if (tab === "all") {
        params.delete("tab");
      } else {
        params.set("tab", tab);
      }
      const query = params.toString();
      router.replace(query ? `/notifications?${query}` : "/notifications");
    });
  };

  const handleRefresh = async () => {
    await Promise.all([refetchList(), refetchCounts(), refetchUnread()]);
  };

  // Module filter toggle
  const handleToggleModule = (mod: NotificationModule | "all") => {
    if (mod === "all") {
      setSelectedModules(new Set());
      return;
    }
    setSelectedModules((prev) => {
      const next = new Set(prev);
      if (next.has(mod)) next.delete(mod);
      else next.add(mod);
      return next;
    });
  };

  // Toggle single item read
  const handleToggleRead = (item: NotificationItem) => {
    toggleMutation.mutate({
      id: item.id,
      isRead: !item.is_read,
    });
  };

  // Toggle selection
  const handleToggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  // Filtered Notifications Stream
  const filteredNotifications = useMemo(() => {
    return allNotifications.filter((item) => {
      // 1. Module filter
      if (selectedModules.size > 0) {
        const itemMod = resolveNotificationModule(item);
        if (!selectedModules.has(itemMod)) return false;
      }

      // 2. Needs action filter
      if (needsActionOnly) {
        const p = resolveNotificationPresentation(item);
        if (!p.isAttentionRequired) return false;
      }

      // 3. Search query filter
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase().trim();
        const code = (extractEntityCode(item) || "").toLowerCase();
        const title = (item.title || "").toLowerCase();
        const msg = (item.message || "").toLowerCase();
        const actor = ((item.data?.actor_name as string) || "").toLowerCase();
        if (
          !title.includes(q) &&
          !msg.includes(q) &&
          !code.includes(q) &&
          !actor.includes(q)
        ) {
          return false;
        }
      }

      return true;
    });
  }, [allNotifications, selectedModules, needsActionOnly, searchQuery]);

  // Summary Metrics Computation
  const summaryMetrics = useMemo(() => {
    let unread = 0;
    let needsAction = 0;
    let today = 0;

    for (const item of allNotifications) {
      if (!item.is_read) unread++;
      const p = resolveNotificationPresentation(item);
      if (p.isAttentionRequired) needsAction++;
      if (getDateBucket(item.created_at) === "today") today++;
    }

    return { unread, needsAction, today };
  }, [allNotifications]);

  // Date Grouping with Consecutive Burst Collapsing
  const dateGroups: DateGroup[] = useMemo(() => {
    const buckets: Record<DateGroup["key"], NotificationItem[]> = {
      today: [],
      yesterday: [],
      this_week: [],
      earlier: [],
    };

    // Slice to pagination limit
    const pagedItems = filteredNotifications.slice(0, displayLimit);

    for (const item of pagedItems) {
      const bucket = getDateBucket(item.created_at);
      buckets[bucket].push(item);
    }

    const groupConfigs: { key: DateGroup["key"]; label: string }[] = [
      { key: "today", label: "Today" },
      { key: "yesterday", label: "Yesterday" },
      { key: "this_week", label: "This Week" },
      { key: "earlier", label: "Earlier" },
    ];

    return groupConfigs
      .map(({ key, label }) => {
        const rawItems = buckets[key];
        const processedItems: DateGroup["items"] = [];

        let currentBurst: NotificationItem[] = [];

        const flushBurst = () => {
          if (currentBurst.length === 1) {
            processedItems.push({ type: "single", item: currentBurst[0] });
          } else if (currentBurst.length > 1) {
            const burstKey = `${currentBurst[0].notification_type}-${currentBurst[0].event_type}-${currentBurst[0].title}`;
            processedItems.push({ type: "burst", key: burstKey, items: [...currentBurst] });
          }
          currentBurst = [];
        };

        for (const item of rawItems) {
          if (currentBurst.length === 0) {
            currentBurst.push(item);
          } else {
            const prev = currentBurst[currentBurst.length - 1];
            // Collapse burst if consecutive items share same notification_type, event_type, and identical title pattern
            const isSameType =
              prev.notification_type === item.notification_type &&
              prev.event_type === item.event_type &&
              (prev.title === item.title || prev.reference_type === item.reference_type);

            if (isSameType) {
              currentBurst.push(item);
            } else {
              flushBurst();
              currentBurst.push(item);
            }
          }
        }
        flushBurst();

        return { key, label, items: processedItems };
      })
      .filter((g) => g.items.length > 0);
  }, [filteredNotifications, displayLimit]);

  // Bulk Actions
  const handleBulkMarkRead = (isRead: boolean) => {
    const ids = Array.from(selectedIds);
    if (!ids.length) return;

    // Record previous states for undo
    const previousStates: Record<string, boolean> = {};
    for (const id of ids) {
      const found = allNotifications.find((n) => n.id === id);
      if (found) previousStates[id] = found.is_read;
    }

    batchMutation.mutate(
      { ids, isRead },
      {
        onSuccess: () => {
          setSelectedIds(new Set());
          setUndoToast({
            visible: true,
            message: `Marked ${ids.length} notifications as ${isRead ? "read" : "unread"}.`,
            affectedIds: ids,
            previousReadStates: previousStates,
          });
        },
      }
    );
  };

  // Burst Mark Read
  const handleMarkBurstRead = (items: NotificationItem[]) => {
    const ids = items.map((i) => i.id);
    const previousStates: Record<string, boolean> = {};
    for (const item of items) {
      previousStates[item.id] = item.is_read;
    }

    batchMutation.mutate(
      { ids, isRead: true },
      {
        onSuccess: () => {
          setUndoToast({
            visible: true,
            message: `Marked group of ${ids.length} notifications as read.`,
            affectedIds: ids,
            previousReadStates: previousStates,
          });
        },
      }
    );
  };

  // Scope-Aware Mark All Read Execution
  const handleExecuteScopedMarkAll = () => {
    const unreadFiltered = filteredNotifications.filter((n) => !n.is_read);
    const ids = unreadFiltered.map((n) => n.id);
    setConfirmMarkAllOpen(false);

    if (!ids.length) return;

    const previousStates: Record<string, boolean> = {};
    for (const n of unreadFiltered) {
      previousStates[n.id] = false;
    }

    batchMutation.mutate(
      { ids, isRead: true },
      {
        onSuccess: () => {
          setUndoToast({
            visible: true,
            message: `Marked all ${ids.length} filtered notifications as read.`,
            affectedIds: ids,
            previousReadStates: previousStates,
          });
        },
      }
    );
  };

  // Undo Handler
  const handleUndo = () => {
    const { affectedIds, previousReadStates } = undoToast;
    if (!affectedIds.length) return;

    // Revert each id to its previous state
    const toUnread = affectedIds.filter((id) => previousReadStates[id] === false);
    const toRead = affectedIds.filter((id) => previousReadStates[id] === true);

    if (toUnread.length > 0) {
      batchMutation.mutate({ ids: toUnread, isRead: false });
    }
    if (toRead.length > 0) {
      batchMutation.mutate({ ids: toRead, isRead: true });
    }

    setUndoToast({
      visible: false,
      message: "",
      affectedIds: [],
      previousReadStates: {},
    });
  };

  // Reset all filters
  const handleResetFilters = () => {
    setSelectedModules(new Set());
    setSearchQuery("");
    setNeedsActionOnly(false);
  };

  const hasActiveFilters =
    selectedModules.size > 0 || needsActionOnly || Boolean(searchQuery.trim());

  const unreadFilteredCount = useMemo(
    () => filteredNotifications.filter((n) => !n.is_read).length,
    [filteredNotifications]
  );

  const tabs: TabConfig[] = [
    { key: "all", label: "All", count: counts.all, icon: Inbox },
    { key: "unread", label: "Unread", count: counts.unread, icon: Mail },
    { key: "requests", label: "Requests & Approvals", count: counts.requests, icon: CheckCircle },
    { key: "alerts", label: "SLA & Alerts", count: counts.alerts, icon: AlertTriangle },
    { key: "system", label: "System", count: counts.system, icon: Bell },
  ];

  return (
    <div className="space-y-5">
      {/* Top Header */}
      <AdminPageHeader
        categoryTag="Admin panel"
        moduleName="Notifications"
        title="Alerts & Activity Center"
        subtitle="Operational alerts, approval actions, and system notices"
        icon={Bell}
        actionSlot={
          <div className="flex items-center gap-2">
            {/* Scope-Aware Mark All as Read */}
            <button
              type="button"
              onClick={() => setConfirmMarkAllOpen(true)}
              disabled={unreadFilteredCount === 0 || batchMutation.isPending}
              className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:border-border-strong hover:bg-surface-hover hover:text-text-primary transition cursor-pointer shadow-2xs disabled:cursor-not-allowed disabled:opacity-50"
            >
              <CheckCheck className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
              <span>
                {batchMutation.isPending
                  ? "Marking..."
                  : hasActiveFilters
                  ? `Mark Filtered Read (${unreadFilteredCount})`
                  : "Mark All as Read"}
              </span>
            </button>

            {/* Refresh */}
            <button
              type="button"
              onClick={handleRefresh}
              disabled={isRefetching || isLoading}
              title="Refresh notifications"
              className="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-border-default bg-surface-base text-text-secondary hover:border-border-strong hover:bg-surface-hover hover:text-text-primary transition cursor-pointer shadow-2xs disabled:cursor-not-allowed disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isRefetching || isLoading ? "animate-spin text-brand-600" : ""
                }`}
                aria-hidden="true"
              />
            </button>
          </div>
        }
      />

      {/* Header Summary Strip (Unread · Needs Action · Today) */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div className="flex items-center justify-between p-3 rounded-xl border border-border-default bg-surface-base shadow-2xs">
          <div className="flex items-center gap-2.5">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-brand-50 text-brand-600 dark:bg-brand-950/40 dark:text-brand-400">
              <Mail className="h-4 w-4" />
            </div>
            <div>
              <p className="text-[11px] font-medium text-text-muted">Unread Alerts</p>
              <p className="text-sm font-bold text-text-primary tabular-nums">
                {summaryMetrics.unread} of {counts.all}
              </p>
            </div>
          </div>
          <span className="text-[10px] font-semibold text-text-muted">
            {unreadCount > 0 ? "Requires review" : "Caught up"}
          </span>
        </div>

        <div className="flex items-center justify-between p-3 rounded-xl border border-border-default bg-surface-base shadow-2xs">
          <div className="flex items-center gap-2.5">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-amber-50 text-amber-600 dark:bg-amber-950/40 dark:text-amber-400">
              <Clock className="h-4 w-4" />
            </div>
            <div>
              <p className="text-[11px] font-medium text-text-muted">Needs Action</p>
              <p className="text-sm font-bold text-text-primary tabular-nums">
                {summaryMetrics.needsAction}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => setNeedsActionOnly((prev) => !prev)}
            className={`text-[10px] font-semibold px-2 py-0.5 rounded transition ${
              needsActionOnly
                ? "bg-amber-600 text-white"
                : "bg-surface-subtle text-text-secondary hover:bg-surface-hover"
            }`}
          >
            {needsActionOnly ? "Filter active" : "Filter items"}
          </button>
        </div>

        <div className="flex items-center justify-between p-3 rounded-xl border border-border-default bg-surface-base shadow-2xs">
          <div className="flex items-center gap-2.5">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-50 text-emerald-600 dark:bg-emerald-950/40 dark:text-emerald-400">
              <Sparkles className="h-4 w-4" />
            </div>
            <div>
              <p className="text-[11px] font-medium text-text-muted">Today&apos;s Activity</p>
              <p className="text-sm font-bold text-text-primary tabular-nums">
                {summaryMetrics.today}
              </p>
            </div>
          </div>
          <span className="text-[10px] font-semibold text-text-muted">Past 24 hours</span>
        </div>
      </div>

      {/* Main Filter & Stream Container */}
      <div className="space-y-4 rounded-xl border border-border-default bg-surface-base p-4 shadow-xs">
        {/* Horizontal Category Tabs */}
        <div className="flex items-center justify-between border-b border-border-subtle pb-3">
          <nav
            aria-label="Notification Categories"
            role="tablist"
            className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none"
          >
            {tabs.map((tab) => {
              const Icon = tab.icon;
              const isActive = activeTab === tab.key;

              return (
                <button
                  key={tab.key}
                  type="button"
                  role="tab"
                  aria-selected={isActive}
                  onClick={() => handleTabChange(tab.key)}
                  className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                    isActive
                      ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                      : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  <Icon
                    className={`h-4 w-4 shrink-0 transition-colors ${
                      isActive
                        ? "text-tab-active-text"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                    aria-hidden="true"
                  />
                  <span>{tab.label}</span>
                  <span
                    className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-sans tabular-nums text-xs font-semibold shadow-2xs transition-colors ${
                      isActive
                        ? "bg-brand-button text-white"
                        : tab.key === "unread" && tab.count > 0
                        ? "border border-border-default bg-surface-subtle text-text-primary"
                        : "border border-border-default bg-surface-subtle text-text-secondary"
                    }`}
                  >
                    {tab.count}
                  </span>
                </button>
              );
            })}
          </nav>
        </div>

        {/* Secondary Filter Bar: Module Chips + Search Input + Needs Action Switch */}
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-3 pt-1">
          {/* Module Multi-select Chips */}
          <div className="flex items-center gap-1.5 overflow-x-auto no-scrollbar py-0.5">
            <span className="text-[11px] font-semibold text-text-muted flex items-center gap-1 mr-1">
              <Filter className="h-3 w-3" />
              <span>Module:</span>
            </span>
            {MODULE_OPTIONS.map((opt) => {
              const isSelected =
                opt.id === "all"
                  ? selectedModules.size === 0
                  : selectedModules.has(opt.id);

              return (
                <button
                  key={opt.id}
                  type="button"
                  onClick={() => handleToggleModule(opt.id)}
                  className={`inline-flex items-center rounded-md px-2.5 py-1 text-[11px] font-medium transition cursor-pointer whitespace-nowrap ${
                    isSelected
                      ? "bg-brand-600 text-white font-semibold shadow-2xs"
                      : "bg-surface-subtle text-text-secondary border border-border-default hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  {opt.label}
                </button>
              );
            })}
          </div>

          {/* Search Box + Needs Action Toggle */}
          <div className="flex items-center gap-2.5 shrink-0">
            {/* Search Input */}
            <div className="relative w-full md:w-56">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search title, code, actor..."
                className="w-full h-8 pl-8 pr-7 text-xs rounded-lg border border-border-default bg-surface-base text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-500"
              />
              {searchQuery && (
                <button
                  type="button"
                  onClick={() => setSearchQuery("")}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-primary"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </div>

            {/* Needs Action Toggle */}
            <label className="flex items-center gap-1.5 text-xs font-semibold text-text-secondary cursor-pointer whitespace-nowrap select-none">
              <input
                type="checkbox"
                checked={needsActionOnly}
                onChange={(e) => setNeedsActionOnly(e.target.checked)}
                className="h-3.5 w-3.5 rounded border-border-default text-brand-600 focus:ring-brand-500/30 cursor-pointer"
              />
              <span>Needs action only</span>
            </label>
          </div>
        </div>

        {/* Date Grouped Notifications Stream */}
        <div className="space-y-5 pt-2">
          {isLoading ? (
            /* Skeleton Loading State */
            <div className="space-y-2.5">
              {[1, 2, 3, 4, 5, 6].map((i) => (
                <div
                  key={i}
                  className="flex items-center gap-3 rounded-lg border border-border-default/70 bg-surface-base p-3 animate-pulse"
                >
                  <div className="h-3.5 w-3.5 rounded bg-surface-muted shrink-0" />
                  <div className="h-7 w-7 rounded-md bg-surface-muted shrink-0" />
                  <div className="flex-1 space-y-1.5">
                    <div className="flex justify-between items-center">
                      <div className="h-3.5 w-1/4 rounded bg-surface-muted" />
                      <div className="h-3 w-16 rounded bg-surface-muted" />
                    </div>
                    <div className="h-3 w-2/3 rounded bg-surface-muted" />
                  </div>
                </div>
              ))}
            </div>
          ) : error ? (
            /* Error State */
            <div className="rounded-xl border border-danger-border bg-danger-subtle/50 p-6 text-center text-danger-text">
              <AlertCircle className="h-8 w-8 mx-auto text-rose-600 mb-2" />
              <p className="text-xs font-bold">Failed to load notifications stream.</p>
              <p className="text-[11px] text-text-muted mt-1">
                Unable to synchronize with the notifications service.
              </p>
              <button
                type="button"
                onClick={handleRefresh}
                className="mt-3 inline-flex items-center gap-1 text-xs font-bold underline hover:no-underline cursor-pointer"
              >
                Try refreshing
              </button>
            </div>
          ) : dateGroups.length === 0 ? (
            /* Empty State */
            <NotificationEmptyState
              tab={activeTab}
              hasActiveFilters={hasActiveFilters}
              onResetFilters={handleResetFilters}
            />
          ) : (
            /* Grouped Stream */
            dateGroups.map((group) => (
              <div key={group.key} className="space-y-2">
                {/* Sticky Group Header */}
                <div className="sticky top-0 z-10 flex items-center gap-2 bg-surface-base/95 py-1 backdrop-blur-xs border-b border-border-subtle">
                  <span className="text-[11px] font-bold tracking-wider uppercase text-text-muted font-mono">
                    {group.label}
                  </span>
                  <div className="flex-1 h-px bg-border-subtle" />
                </div>

                {/* Items in Date Bucket */}
                <div className="space-y-1.5">
                  {group.items.map((entry) => {
                    if (entry.type === "burst") {
                      return (
                        <NotificationBurstRow
                          key={entry.key}
                          burstKey={entry.key}
                          items={entry.items}
                          selectedIds={selectedIds}
                          onToggleSelect={handleToggleSelect}
                          onToggleRead={handleToggleRead}
                          onMarkBurstRead={handleMarkBurstRead}
                          isToggling={toggleMutation.isPending || batchMutation.isPending}
                        />
                      );
                    }

                    return (
                      <NotificationRow
                        key={entry.item.id}
                        notification={entry.item}
                        isSelected={selectedIds.has(entry.item.id)}
                        onToggleSelect={handleToggleSelect}
                        onToggleRead={handleToggleRead}
                        isToggling={toggleMutation.isPending}
                      />
                    );
                  })}
                </div>
              </div>
            ))
          )}

          {/* Load More Pagination Trigger */}
          {filteredNotifications.length > displayLimit && (
            <div className="pt-2 text-center">
              <button
                type="button"
                onClick={() => setDisplayLimit((prev) => prev + 50)}
                className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-primary hover:bg-surface-hover hover:border-border-strong transition cursor-pointer shadow-2xs"
              >
                <span>
                  Load more notifications ({filteredNotifications.length - displayLimit} remaining)
                </span>
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Floating Sticky Bulk Actions Bar */}
      <NotificationBulkBar
        selectedCount={selectedIds.size}
        onMarkRead={() => handleBulkMarkRead(true)}
        onMarkUnread={() => handleBulkMarkRead(false)}
        onClear={() => setSelectedIds(new Set())}
        isPending={batchMutation.isPending}
      />

      {/* Floating Undo Toast */}
      {undoToast.visible && (
        <NotificationUndoToast
          message={undoToast.message}
          onUndo={handleUndo}
          onDismiss={() =>
            setUndoToast({
              visible: false,
              message: "",
              affectedIds: [],
              previousReadStates: {},
            })
          }
        />
      )}

      {/* Scoped Mark All Confirmation Dialog */}
      {confirmMarkAllOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-2xs animate-fade-in"
        >
          <div className="w-full max-w-sm rounded-xl border border-border-default bg-surface-base p-5 shadow-xl space-y-3">
            <h3 className="text-sm font-bold text-text-primary">
              Confirm Mark as Read
            </h3>
            <p className="text-xs text-text-secondary leading-relaxed">
              Are you sure you want to mark all{" "}
              <strong className="text-text-primary">{unreadFilteredCount}</strong>{" "}
              {hasActiveFilters ? "filtered" : "unread"} notifications as read?
            </p>
            <div className="flex justify-end gap-2 pt-2 border-t border-border-subtle">
              <button
                type="button"
                onClick={() => setConfirmMarkAllOpen(false)}
                className="rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleExecuteScopedMarkAll}
                className="rounded-lg bg-brand-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand-700 transition cursor-pointer shadow-2xs"
              >
                Mark as read
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function NotificationsPage() {
  return (
    <Suspense
      fallback={
        <div className="space-y-6">
          <div className="h-14 border-b border-border-subtle bg-surface-base animate-pulse" />
          <div className="h-64 rounded-xl border border-border-default bg-surface-base animate-pulse" />
        </div>
      }
    >
      <NotificationsPageContent />
    </Suspense>
  );
}
