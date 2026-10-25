"use client";

import { memo } from "react";
import { ShieldCheck } from "lucide-react";
import { HeroCard } from "@/components/shared/HeroCard";

export interface CencomOverviewHeroCardProps {
  mfrPercent: number; // e.g. 74.2
  healthStatus?: "healthy" | "at_risk" | "critical";
  isNormalized?: boolean;
  actual: number;
  required: number;
  isLoading?: boolean;
}

export const CencomOverviewHeroCard = memo(function CencomOverviewHeroCard({
  mfrPercent,
  healthStatus = "critical",
  isNormalized = false,
  actual,
  required,
  isLoading = false,
}: CencomOverviewHeroCardProps) {
  const chipLabel = isNormalized
    ? "Coherent"
    : healthStatus === "healthy"
    ? "Healthy"
    : healthStatus === "at_risk"
    ? "At risk"
    : "Critical";

  const chipClass = isNormalized
    ? "border-status-info-border bg-status-info-bg text-status-info-text"
    : healthStatus === "healthy"
    ? "border-status-success-border bg-status-success-bg text-status-success-text"
    : healthStatus === "at_risk"
    ? "border-status-warning-border bg-status-warning-bg text-status-warning-text"
    : "border-status-danger-border bg-status-danger-bg text-status-danger-text";

  const customBadge = (
    <div
      className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold ${chipClass}`}
    >
      {isNormalized && <ShieldCheck className="h-3 w-3" />}
      <span>{chipLabel}</span>
    </div>
  );

  return (
    <HeroCard
      title="Overall MFR"
      subtitle="Manpower fulfillment rate"
      percent={isLoading ? 0 : mfrPercent}
      scale="mfr"
      actual={actual}
      actualLabel="Filled"
      required={required}
      requiredLabel="Required"
      badge={customBadge}
      footerCaption="Fulfillment vs required · Target 80%"
      className="lg:row-span-2"
    />
  );
});
