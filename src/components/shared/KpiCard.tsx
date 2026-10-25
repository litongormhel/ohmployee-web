"use client";

import { memo, type ReactNode } from "react";
import { AnimatedNumber } from "./AnimatedNumber";

export interface KpiCardProps {
  title: string;
  value: number;
  decimals?: number;
  prefix?: string;
  suffix?: string;
  subtitle?: string;
  badge?: ReactNode;
  footer?: ReactNode;
  icon?: React.ComponentType<{ className?: string }>;
  className?: string;
}

export const KpiCard = memo(function KpiCard({
  title,
  value,
  decimals = 0,
  prefix = "",
  suffix = "",
  subtitle,
  badge,
  footer,
  icon: Icon,
  className = "",
}: KpiCardProps) {
  return (
    <div
      className={`flex flex-col justify-between rounded-xl border border-border-default bg-surface-card p-5 shadow-2xs transition-colors ${className}`}
    >
      <div>
        <div className="flex items-center justify-between gap-2">
          <span className="text-xs font-medium text-text-secondary truncate">
            {title}
          </span>
          <div className="flex items-center gap-1.5 shrink-0">
            {badge}
            {Icon && <Icon className="h-4 w-4 text-text-muted" />}
          </div>
        </div>

        <div className="mt-2 flex items-baseline gap-1">
          <span className="text-3xl font-semibold tracking-tight text-text-primary sm:text-4xl">
            <AnimatedNumber
              value={value}
              decimals={decimals}
              prefix={prefix}
              suffix={suffix}
            />
          </span>
        </div>

        {subtitle && (
          <p className="mt-1 text-xs text-text-muted truncate">{subtitle}</p>
        )}
      </div>

      {footer && <div className="mt-4 pt-3 border-t border-border-subtle">{footer}</div>}
    </div>
  );
});
