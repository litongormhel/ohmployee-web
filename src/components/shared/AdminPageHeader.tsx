import type { ComponentType, ReactNode } from "react";
import { Badge } from "@/components/ui/badge";

export interface AdminPageHeaderProps {
  categoryTag?: string;
  moduleName?: string;
  title: ReactNode;
  subtitle?: ReactNode;
  icon?: ComponentType<{ className?: string }>;
  readOnly?: boolean;
  actionSlot?: ReactNode;
  primaryAction?: {
    label: string;
    onClick: () => void;
    disabled?: boolean;
    icon?: ComponentType<{ className?: string }>;
  };
}

export function AdminPageHeader({
  categoryTag = "ADMIN PANEL",
  moduleName,
  title,
  subtitle,
  icon: Icon,
  readOnly = false,
  actionSlot,
  primaryAction,
}: AdminPageHeaderProps) {
  const PrimaryActionIcon = primaryAction?.icon;
  const displayModuleName =
    moduleName ?? (typeof title === "string" ? title : "Dashboard");

  return (
    <header className="flex flex-wrap items-center justify-between gap-4 pb-4 border-b border-border-subtle">
      <div className="flex items-center gap-4 min-w-0">
        {/* Left Section (Module Scope) */}
        <div className="shrink-0">
          <p className="text-[10px] font-bold uppercase tracking-wider text-text-muted">
            {categoryTag}
          </p>
          <h1 className="text-xl font-bold text-text-primary tracking-tight leading-none">
            {displayModuleName}
          </h1>
        </div>

        {/* Vertical Divider */}
        <div className="h-8 w-px bg-slate-200 shrink-0" aria-hidden="true" />

        {/* Middle Section (Context & Subtitle) */}
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            {Icon && (
              <Icon
                className="h-3.5 w-3.5 text-brand-600 shrink-0"
                aria-hidden="true"
              />
            )}
            <div className="text-sm font-semibold text-text-primary leading-tight truncate">
              {title}
            </div>
            {readOnly && (
              <Badge className="border-blue-200 bg-blue-50 text-blue-700 text-[10px] py-0 px-1.5 h-4">
                Read only
              </Badge>
            )}
          </div>
          {subtitle && (
            <div className="text-xs text-text-secondary truncate leading-normal">
              {subtitle}
            </div>
          )}
        </div>
      </div>

      {/* Right Section (Actions/Counters) */}
      {(actionSlot || primaryAction) && (
        <div className="flex items-center gap-2 shrink-0">
          {actionSlot}
          {primaryAction && (
            <button
              className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary transition cursor-pointer shadow-2xs disabled:cursor-not-allowed disabled:opacity-50"
              disabled={primaryAction.disabled}
              onClick={primaryAction.onClick}
              type="button"
            >
              {PrimaryActionIcon && (
                <PrimaryActionIcon
                  className="h-3.5 w-3.5"
                  aria-hidden="true"
                />
              )}
              {primaryAction.label}
            </button>
          )}
        </div>
      )}
    </header>
  );
}
