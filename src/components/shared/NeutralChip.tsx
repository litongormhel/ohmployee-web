"use client";

import { memo } from "react";

export interface NeutralChipProps {
  label: string;
  count?: number | string;
  icon?: React.ComponentType<{ className?: string }>;
  onClick?: () => void;
  className?: string;
  size?: "sm" | "md";
}

export const NeutralChip = memo(function NeutralChip({
  label,
  count,
  icon: Icon,
  onClick,
  className = "",
  size = "md",
}: NeutralChipProps) {
  const sizeClasses =
    size === "sm"
      ? "px-2 py-0.5 text-[11px]"
      : "px-2.5 py-1 text-xs";

  const Component = onClick ? "button" : "span";

  return (
    <Component
      type={onClick ? "button" : undefined}
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-full border border-border-default bg-surface-muted font-medium text-text-secondary transition-colors ${
        onClick ? "hover:border-border-strong hover:bg-surface-hover hover:text-text-primary cursor-pointer" : ""
      } ${sizeClasses} ${className}`}
    >
      {Icon && <Icon className="h-3.5 w-3.5 shrink-0 text-text-muted" />}
      <span className="truncate">{label}</span>
      {count !== undefined && (
        <span className="font-semibold text-text-primary tabular-nums">
          {count}
        </span>
      )}
    </Component>
  );
});
