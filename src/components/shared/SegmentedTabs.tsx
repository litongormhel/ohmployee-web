"use client";

import { useRef, useEffect, useState, useId } from "react";
import { useMotionLevel } from "@/hooks/useMotionLevel";

export interface TabItem<T extends string = string> {
  key: T;
  label: string;
  count?: number;
  badge?: React.ReactNode;
  disabled?: boolean;
}

export interface SegmentedTabsProps<T extends string = string> {
  tabs: TabItem<T>[];
  activeKey: T;
  onChange: (key: T) => void;
  className?: string;
  ariaLabel?: string;
}

export function SegmentedTabs<T extends string = string>({
  tabs,
  activeKey,
  onChange,
  className = "",
  ariaLabel = "Tabs",
}: SegmentedTabsProps<T>) {
  const motionLevel = useMotionLevel();
  const baseId = useId();
  const containerRef = useRef<HTMLDivElement>(null);
  const [indicatorStyle, setIndicatorStyle] = useState<{
    left: number;
    width: number;
  }>({ left: 0, width: 0 });

  // Update sliding pill indicator position whenever activeKey changes
  useEffect(() => {
    if (!containerRef.current) return;
    const activeBtn = containerRef.current.querySelector<HTMLButtonElement>(
      `[data-tab-key="${activeKey}"]`
    );
    if (activeBtn) {
      setIndicatorStyle({
        left: activeBtn.offsetLeft,
        width: activeBtn.offsetWidth,
      });
    }
  }, [activeKey, tabs]);

  const handleKeyDown = (e: React.KeyboardEvent, index: number) => {
    const enabledTabs = tabs.filter((t) => !t.disabled);
    const currentIndex = enabledTabs.findIndex((t) => t.key === tabs[index].key);

    let nextIndex = -1;
    if (e.key === "ArrowRight") {
      nextIndex = (currentIndex + 1) % enabledTabs.length;
    } else if (e.key === "ArrowLeft") {
      nextIndex = (currentIndex - 1 + enabledTabs.length) % enabledTabs.length;
    } else if (e.key === "Home") {
      nextIndex = 0;
    } else if (e.key === "End") {
      nextIndex = enabledTabs.length - 1;
    }

    if (nextIndex >= 0) {
      e.preventDefault();
      const targetTab = enabledTabs[nextIndex];
      onChange(targetTab.key);
      const targetBtn = containerRef.current?.querySelector<HTMLButtonElement>(
        `[data-tab-key="${targetTab.key}"]`
      );
      targetBtn?.focus();
    }
  };

  return (
    <div
      ref={containerRef}
      role="tablist"
      aria-label={ariaLabel}
      className={`relative inline-flex items-center gap-1 rounded-xl border border-border-default bg-surface-muted p-1 text-sm ${className}`}
    >
      {/* Sliding active pill indicator */}
      {indicatorStyle.width > 0 && (
        <span
          className={`absolute top-1 bottom-1 rounded-lg border border-border-subtle bg-surface-card shadow-2xs ${
            motionLevel === "full"
              ? "transition-all duration-200 ease-[cubic-bezier(0.16,1,0.3,1)]"
              : ""
          }`}
          style={{
            left: `${indicatorStyle.left}px`,
            width: `${indicatorStyle.width}px`,
          }}
          aria-hidden="true"
        />
      )}

      {tabs.map((tab, idx) => {
        const isActive = tab.key === activeKey;
        const tabId = `${baseId}-tab-${tab.key}`;

        return (
          <button
            key={tab.key}
            id={tabId}
            role="tab"
            type="button"
            data-tab-key={tab.key}
            aria-selected={isActive}
            tabIndex={isActive ? 0 : -1}
            disabled={tab.disabled}
            onClick={() => !tab.disabled && onChange(tab.key)}
            onKeyDown={(e) => handleKeyDown(e, idx)}
            className={`relative z-10 inline-flex items-center gap-2 rounded-lg px-3.5 py-1.5 text-xs font-semibold whitespace-nowrap transition-colors cursor-pointer disabled:cursor-not-allowed disabled:opacity-40 ${
              isActive
                ? "text-text-primary"
                : "text-text-secondary hover:text-text-primary"
            }`}
          >
            <span>{tab.label}</span>
            {tab.count !== undefined && (
              <span
                className={`inline-flex items-center rounded-full px-1.5 py-0.2 text-[10px] font-bold tabular-nums ${
                  isActive
                    ? "bg-surface-muted text-text-primary"
                    : "bg-surface-card text-text-muted"
                }`}
              >
                {tab.count}
              </span>
            )}
            {tab.badge}
          </button>
        );
      })}
    </div>
  );
}
