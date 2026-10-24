"use client";

import { memo, useEffect, useState } from "react";
import { ShieldCheck } from "lucide-react";
import { usePrefersReducedMotion } from "./usePrefersReducedMotion";

export interface CencomOverviewHeroCardProps {
  mfrPercent: number; // e.g. 74.2
  healthStatus?: "healthy" | "at_risk" | "critical";
  isNormalized?: boolean;
  actual: number;
  required: number;
  isLoading?: boolean;
}

function easeOutCubic(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

export const CencomOverviewHeroCard = memo(function CencomOverviewHeroCard({
  mfrPercent,
  healthStatus = "critical",
  isNormalized = false,
  actual,
  required,
  isLoading = false,
}: CencomOverviewHeroCardProps) {
  const prefersReducedMotion = usePrefersReducedMotion();

  // 1. Animated sweep for ring gauge (1300ms)
  const [animatedProgress, setAnimatedProgress] = useState<number>(0);

  useEffect(() => {
    if (prefersReducedMotion) return;

    let startTimestamp: number | null = null;
    let frameId: number;
    const startValue = 0;
    const endValue = mfrPercent;
    const duration = 1300;

    const step = (timestamp: number) => {
      if (!startTimestamp) startTimestamp = timestamp;
      const elapsed = timestamp - startTimestamp;
      const progress = Math.min(1, elapsed / duration);
      const eased = easeOutCubic(progress);

      setAnimatedProgress(startValue + (endValue - startValue) * eased);

      if (progress < 1) {
        frameId = requestAnimationFrame(step);
      } else {
        setAnimatedProgress(endValue);
      }
    };

    frameId = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frameId);
  }, [mfrPercent, prefersReducedMotion]);

  const effectiveProgress = prefersReducedMotion ? mfrPercent : animatedProgress;

  // 2. SVG Ring Gauge Geometry
  const size = 180;
  const strokeWidth = 14;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  // Sweep fraction capped between 0 and 1
  const sweepFraction = Math.min(1, Math.max(0, effectiveProgress / 100));
  const strokeDashoffset = circumference * (1 - sweepFraction);

  // Status chip label and tokens
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

  return (
    <div className="flex flex-col justify-between rounded-2xl border border-hero-border bg-hero-surface p-6 shadow-xs transition-colors duration-[250ms] lg:row-span-2">
      {/* Header with Title and Chip */}
      <div className="flex items-center justify-between gap-3">
        <div>
          <h3 className="text-base font-semibold leading-snug text-hero-text">
            Overall MFR
          </h3>
          <p className="mt-0.5 text-xs text-hero-muted">
            Manpower fulfillment rate
          </p>
        </div>
        <div
          className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold ${chipClass}`}
        >
          {isNormalized && <ShieldCheck className="h-3 w-3" />}
          <span>{chipLabel}</span>
        </div>
      </div>

      {/* Hero Circular Gauge Section */}
      <div className="my-6 flex flex-col items-center justify-center">
        <div
          className="relative flex items-center justify-center"
          style={{ width: size, height: size, contain: "paint" }}
        >
          <svg
            width={size}
            height={size}
            viewBox={`0 0 ${size} ${size}`}
            className="-rotate-90 transform"
          >
            {/* Background Track */}
            <circle
              cx={size / 2}
              cy={size / 2}
              r={radius}
              fill="none"
              stroke="currentColor"
              strokeWidth={strokeWidth}
              className="text-hero-track"
            />
            {/* Animated Active Arc */}
            <circle
              cx={size / 2}
              cy={size / 2}
              r={radius}
              fill="none"
              stroke="currentColor"
              strokeWidth={strokeWidth}
              strokeLinecap="round"
              strokeDasharray={circumference}
              strokeDashoffset={strokeDashoffset}
              className="text-hero-accent transition-[stroke-dashoffset] duration-75"
            />
          </svg>

          {/* Centered Number Display (52px w600 tabular) */}
          <div className="absolute inset-0 flex flex-col items-center justify-center text-center">
            <span className="text-[52px] font-semibold leading-none tracking-[-0.04em] text-hero-text tabular-nums">
              {isLoading ? (
                "--"
              ) : (
                <>
                  {effectiveProgress.toFixed(1)}
                  <span className="text-2xl font-medium text-hero-muted">%</span>
                </>
              )}
            </span>
            <span className="mt-1 text-xs font-medium text-hero-muted tabular-nums">
              {actual} of {required} filled
            </span>
          </div>
        </div>
      </div>

      {/* Footer Meta */}
      <div className="border-t border-hero-border/60 pt-3 text-center">
        <p className="text-xs font-medium text-hero-muted">
          Fulfillment vs required · Target 80%
        </p>
      </div>
    </div>
  );
});
