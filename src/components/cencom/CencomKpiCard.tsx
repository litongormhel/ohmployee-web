"use client";

import { memo } from "react";
import { KpiCard } from "@/components/shared/KpiCard";
import { NeutralChip } from "@/components/shared/NeutralChip";
import { PercentageBar } from "@/components/shared/PercentageBar";

export interface CencomKpiCardProps {
  label: string; // sentence case, e.g. "Total required"
  value: number | undefined;
  subtitle?: string; // e.g. "Plantilla slot capacity"
  badge?: string; // e.g. "Authorized"
  progressRatio?: {
    current: number;
    total: number;
    ratePercent: number;
  };
  isLoading?: boolean;
}

export const CencomKpiCard = memo(function CencomKpiCard({
  label,
  value,
  subtitle,
  badge,
  progressRatio,
  isLoading = false,
}: CencomKpiCardProps) {
  const footerContent = progressRatio ? (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between text-xs font-medium text-text-muted">
        <span>Network coverage ({progressRatio.current} / {progressRatio.total})</span>
        <span className="tabular-nums font-semibold text-text-secondary">
          {progressRatio.ratePercent.toFixed(1)}%
        </span>
      </div>
      <PercentageBar
        percent={progressRatio.ratePercent}
        showLabel={false}
        heightClass="h-1.5"
      />
    </div>
  ) : undefined;

  return (
    <KpiCard
      title={label}
      value={isLoading ? 0 : (value ?? progressRatio?.current ?? 0)}
      subtitle={subtitle}
      badge={badge ? <NeutralChip label={badge} /> : undefined}
      footer={footerContent}
    />
  );
});
