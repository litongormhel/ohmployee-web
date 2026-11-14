"use client";

import { useState } from "react";
import { ChevronDown, ChevronRight, CheckCheck, Layers } from "lucide-react";
import type { NotificationItem } from "@/lib/queries/notifications";
import { NotificationRow } from "@/components/notifications/NotificationRow";
import { resolveNotificationPresentation } from "@/lib/notifications/severity";

export interface NotificationBurstRowProps {
  burstKey: string;
  items: NotificationItem[];
  selectedIds: Set<string>;
  onToggleSelect: (id: string) => void;
  onToggleRead: (item: NotificationItem) => void;
  onMarkBurstRead: (items: NotificationItem[]) => void;
  isToggling?: boolean;
}

export function NotificationBurstRow({
  items,
  selectedIds,
  onToggleSelect,
  onToggleRead,
  onMarkBurstRead,
  isToggling = false,
}: NotificationBurstRowProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const firstItem = items[0];
  const p = resolveNotificationPresentation(firstItem);
  const Icon = p.icon;

  const unreadCount = items.filter((n) => !n.is_read).length;
  const allSelected = items.every((n) => selectedIds.has(n.id));
  const someSelected = items.some((n) => selectedIds.has(n.id));

  const handleSelectAllInBurst = () => {
    for (const item of items) {
      if (allSelected) {
        if (selectedIds.has(item.id)) onToggleSelect(item.id);
      } else {
        if (!selectedIds.has(item.id)) onToggleSelect(item.id);
      }
    }
  };

  // Human friendly burst summary (e.g. "3 Deletion Requests Approved", "4 Vacancy Closures Pending Action")
  const burstLabel = `${items.length} ${firstItem.title.toLowerCase().includes("request") ? "Requests" : "Events"}: ${p.statusLabel}`;

  return (
    <div className="rounded-lg border border-border-default/80 bg-surface-base/80 overflow-hidden shadow-2xs">
      {/* Burst Header Summary Row */}
      <div
        onClick={() => setIsExpanded((prev) => !prev)}
        className={`flex items-center justify-between px-3 py-2.5 transition cursor-pointer select-none ${
          unreadCount > 0 ? "bg-brand-50/30 dark:bg-brand-950/20" : "hover:bg-surface-hover/80"
        }`}
      >
        <div className="flex items-center gap-2.5 min-w-0 flex-1">
          {/* Select all checkbox for burst */}
          <label className="flex items-center cursor-pointer shrink-0" onClick={(e) => e.stopPropagation()}>
            <input
              type="checkbox"
              checked={allSelected}
              ref={(el) => {
                if (el) el.indeterminate = someSelected && !allSelected;
              }}
              onChange={handleSelectAllInBurst}
              className="h-3.5 w-3.5 rounded border-border-default text-brand-600 focus:ring-brand-500/30 cursor-pointer"
              aria-label="Select all notifications in group"
            />
          </label>

          {/* Expand/Collapse Chevron */}
          <div className="text-text-muted hover:text-text-primary transition shrink-0">
            {isExpanded ? (
              <ChevronDown className="h-4 w-4" />
            ) : (
              <ChevronRight className="h-4 w-4" />
            )}
          </div>

          {/* Burst Icon Badge */}
          <div
            className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-md border ${p.containerClass}`}
          >
            <Icon className="h-3.5 w-3.5" />
          </div>

          {/* Burst Title & Count Pill */}
          <div className="flex items-center gap-2 min-w-0">
            <span
              className={`text-xs truncate ${
                unreadCount > 0
                  ? "font-bold text-text-primary"
                  : "font-medium text-text-secondary"
              }`}
            >
              {burstLabel}
            </span>

            <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold bg-surface-subtle border border-border-default text-text-secondary">
              <Layers className="h-2.5 w-2.5" />
              <span>{items.length} notifications</span>
            </span>

            {unreadCount > 0 && (
              <span className="inline-flex items-center rounded-full px-1.5 py-0.2 text-[9px] font-bold bg-brand-500 text-white">
                {unreadCount} unread
              </span>
            )}
          </div>
        </div>

        {/* Burst Actions */}
        <div className="flex items-center gap-2 shrink-0" onClick={(e) => e.stopPropagation()}>
          {unreadCount > 0 && (
            <button
              type="button"
              onClick={() => onMarkBurstRead(items)}
              disabled={isToggling}
              className="inline-flex h-7 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2 text-[11px] font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer disabled:opacity-50"
            >
              <CheckCheck className="h-3 w-3 text-emerald-600" />
              <span>Mark all read</span>
            </button>
          )}

          <span className="text-[11px] font-medium text-brand-600 hover:underline">
            {isExpanded ? "Collapse" : "Expand"}
          </span>
        </div>
      </div>

      {/* Expanded Nested Stream */}
      {isExpanded && (
        <div className="border-t border-border-subtle/80 bg-surface-base p-2 space-y-1.5 pl-6">
          {items.map((item) => (
            <NotificationRow
              key={item.id}
              notification={item}
              isSelected={selectedIds.has(item.id)}
              onToggleSelect={onToggleSelect}
              onToggleRead={onToggleRead}
              isToggling={isToggling}
            />
          ))}
        </div>
      )}
    </div>
  );
}
