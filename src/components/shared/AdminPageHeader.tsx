import type { ComponentType, ReactNode } from "react";
import { Badge } from "@/components/ui/badge";

export interface AdminPageHeaderProps {
  title: string;
  subtitle?: string;
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
  title,
  subtitle,
  icon: Icon,
  readOnly = false,
  actionSlot,
  primaryAction,
}: AdminPageHeaderProps) {
  const PrimaryActionIcon = primaryAction?.icon;

  return (
    <section className="flex flex-wrap items-start justify-between gap-4 border-b border-border-default pb-5">
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          {Icon && <Icon className="h-6 w-6 text-brand-600" aria-hidden="true" />}
          <h1 className="text-2xl font-semibold tracking-normal text-text-primary">{title}</h1>
          {readOnly && (
            <Badge className="border-blue-200 bg-blue-50 text-blue-700">
              Read only
            </Badge>
          )}
        </div>
        {subtitle && (
          <p className="mt-1.5 max-w-5xl text-base leading-6 text-text-secondary">
            {subtitle}
          </p>
        )}
      </div>
      <div className="flex items-center gap-2">
        {actionSlot}
        {primaryAction && (
          <button
            className="inline-flex h-10 items-center gap-2 rounded-md border border-border-default bg-surface-base px-4 text-sm font-medium text-text-secondary shadow-sm transition-colors hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-50"
            disabled={primaryAction.disabled}
            onClick={primaryAction.onClick}
            type="button"
          >
            {PrimaryActionIcon && <PrimaryActionIcon className="h-4 w-4" aria-hidden="true" />}
            {primaryAction.label}
          </button>
        )}
      </div>
    </section>
  );
}
