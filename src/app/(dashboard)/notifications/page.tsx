"use client";

import { Suspense, useState, useTransition } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  AlertTriangle,
  Bell,
  CheckCheck,
  CheckCircle,
  Inbox,
  Mail,
  RefreshCw,
} from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import {
  useNotifications,
  useNotificationsRealtime,
  useNotificationCounts,
  useUnreadNotificationsCount,
  useMarkAllAsRead,
  useToggleNotificationRead,
  type NotificationItem,
  type NotificationTabFilter,
} from "@/lib/queries/notifications";
import {
  NotificationCard,
  NotificationEmptyState,
} from "@/components/notifications/NotificationCard";

interface TabConfig {
  key: NotificationTabFilter;
  label: string;
  count: number;
  icon: typeof Inbox;
}

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

  // Queries
  const {
    data: notifications = [],
    isLoading,
    isRefetching,
    refetch: refetchList,
    error,
  } = useNotifications({ tab: activeTab, limit: 150 });

  const {
    data: counts = { all: 0, unread: 0, requests: 0, alerts: 0, system: 0 },
    refetch: refetchCounts,
  } = useNotificationCounts();

  const {
    data: unreadCount = 0,
    refetch: refetchUnread,
  } = useUnreadNotificationsCount();

  // Mutations
  const markAllMutation = useMarkAllAsRead();
  const toggleMutation = useToggleNotificationRead();

  const handleTabChange = (tab: NotificationTabFilter) => {
    setActiveTab(tab);
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

  const handleToggleRead = (item: NotificationItem) => {
    toggleMutation.mutate({
      id: item.id,
      isRead: !item.is_read,
    });
  };

  const tabs: TabConfig[] = [
    {
      key: "all",
      label: "All",
      count: counts.all,
      icon: Inbox,
    },
    {
      key: "unread",
      label: "Unread",
      count: counts.unread,
      icon: Mail,
    },
    {
      key: "requests",
      label: "Requests & Approvals",
      count: counts.requests,
      icon: CheckCircle,
    },
    {
      key: "alerts",
      label: "SLA & Alerts",
      count: counts.alerts,
      icon: AlertTriangle,
    },
    {
      key: "system",
      label: "System",
      count: counts.system,
      icon: Bell,
    },
  ];

  return (
    <div className="space-y-6">
      {/* Top Header */}
      <AdminPageHeader
        categoryTag="ADMIN PANEL"
        moduleName="Notifications"
        title="Alerts & Activity Center"
        subtitle="Operational alerts, approval actions, and system notices"
        icon={Bell}
        actionSlot={
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => markAllMutation.mutate()}
              disabled={unreadCount === 0 || markAllMutation.isPending}
              className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:border-border-strong hover:bg-surface-hover hover:text-text-primary transition cursor-pointer shadow-2xs disabled:cursor-not-allowed disabled:opacity-50"
            >
              <CheckCheck className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
              <span>{markAllMutation.isPending ? "Marking..." : "Mark All as Read"}</span>
            </button>

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

      {/* Main Content Card */}
      <div className="space-y-4 rounded-xl border border-border-default bg-surface-base p-4 shadow-xs">
        {/* Horizontal Standard Tabs */}
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
                      ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                      : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  <Icon
                    className={`h-4 w-4 shrink-0 transition-colors ${
                      isActive
                        ? "text-brand-700"
                        : "text-text-muted group-hover:text-text-secondary"
                    }`}
                    aria-hidden="true"
                  />
                  <span>{tab.label}</span>
                  <span
                    className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                      isActive
                        ? "bg-brand-500 text-white"
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

        {/* Notifications Stream Area */}
        <div className="space-y-3 pt-1">
          {isLoading ? (
            <div className="space-y-3">
              {[1, 2, 3, 4].map((i) => (
                <div
                  key={i}
                  className="flex items-start gap-3.5 rounded-xl border border-border-default/70 bg-surface-base p-4 animate-pulse"
                >
                  <div className="h-9 w-9 rounded-full bg-surface-muted shrink-0" />
                  <div className="flex-1 space-y-2">
                    <div className="flex justify-between items-center">
                      <div className="h-4 w-1/3 rounded bg-surface-muted" />
                      <div className="h-3 w-16 rounded bg-surface-muted" />
                    </div>
                    <div className="h-3 w-3/4 rounded bg-surface-muted" />
                  </div>
                </div>
              ))}
            </div>
          ) : error ? (
            <div className="rounded-xl border border-danger-border bg-danger-subtle/50 p-6 text-center text-danger-text">
              <p className="text-xs font-medium">Failed to load notifications stream.</p>
              <button
                type="button"
                onClick={handleRefresh}
                className="mt-2 inline-flex items-center gap-1 text-xs font-bold underline hover:no-underline"
              >
                Try refreshing
              </button>
            </div>
          ) : notifications.length === 0 ? (
            <NotificationEmptyState tab={activeTab} />
          ) : (
            notifications.map((item) => (
              <NotificationCard
                key={item.id}
                notification={item}
                onToggleRead={handleToggleRead}
                isToggling={toggleMutation.isPending}
              />
            ))
          )}
        </div>
      </div>
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
