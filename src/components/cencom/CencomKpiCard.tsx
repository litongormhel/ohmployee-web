"use client";

import { memo, useEffect, useState } from "react";
import { CencomAnimatedNumber } from "./CencomAnimatedNumber";
import { usePrefersReducedMotion } from "./usePrefersReducedMotion";

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

function easeOutCubic(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

export const CencomKpiCard = memo(function CencomKpiCard({
  label,
  value,
  subtitle,
  badge,
  progressRatio,
  isLoading = false,
}: CencomKpiCardProps) {
  const prefersReducedMotion = usePrefersReducedMotion();

  // Animated progress bar (1100ms) if progressRatio is provided
  const targetRate = progressRatio?.ratePercent ?? 0;
  const [animatedRate, setAnimatedRate] = useState<number>(0);

  useEffect(() => {
    if (!progressRatio) return;
    if (prefersReducedMotion) return;

    let startTimestamp: number | null = null;
    let frameId: number;
    const startValue = 0;
    const endValue = targetRate;
    const duration = 1100;

    const step = (timestamp: number) => {
      if (!startTimestamp) startTimestamp = timestamp;
      const elapsed = timestamp - startTimestamp;
      const progress = Math.min(1, elapsed / duration);
      const eased = easeOutCubic(progress);

      setAnimatedRate(startValue + (endValue - startValue) * eased);

      if (progress < 1) {
        frameId = requestAnimationFrame(step);
      } else {
        setAnimatedRate(endValue);
      }
    };

    frameId = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frameId);
  }, [progressRatio, targetRate, prefersReducedMotion]);

  const effectiveRate = prefersReducedMotion ? targetRate : animatedRate;

  return (
    <div className="flex flex-col justify-between rounded-xl border border-border-default bg-surface-base p-5 shadow-xs transition-colors">
      {/* Top Header Row */}
      <div className="flex items-center justify-between gap-2">
        <h4 className="text-xs font-semibold text-text-secondary">
          {label}
        </h4>
        {badge ? (
          <span className="inline-flex items-center rounded-full border border-border-default bg-surface-muted px-2 py-0.5 text-[11px] font-medium text-text-secondary">
            {badge}
          </span>
        ) : null}
      </div>

      {/* Main KPI Number Display */}
      <div className="my-2.5">
        <div className="text-[44px] font-semibold leading-none tracking-[-0.04em] text-text-primary tabular-nums">
          {isLoading ? (
            "--"
          ) : progressRatio ? (
            <span className="text-[32px] sm:text-[38px] lg:text-[40px]">
              <CencomAnimatedNumber value={progressRatio.current} />
              <span className="text-xl font-normal text-text-muted"> / </span>
              <CencomAnimatedNumber value={progressRatio.total} />
            </span>
          ) : value !== undefined ? (
            <CencomAnimatedNumber value={value} />
          ) : (
            "--"
          )}
        </div>

        {/* Optional Progress Bar for Deployed Stores */}
        {progressRatio && (
          <div className="mt-3 space-y-1">
            <div className="flex items-center justify-between text-xs font-medium text-text-muted">
              <span>Network coverage</span>
              <span className="tabular-nums font-semibold text-text-secondary">
                {effectiveRate.toFixed(1)}%
              </span>
            </div>
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-surface-muted">
              <div
                className="h-full bg-brand-500 transition-[width] duration-75"
                style={{
                  width: `${Math.min(100, Math.max(0, effectiveRate))}%`,
                }}
              />
            </div>
          </div>
        )}
      </div>

      {/* Footer Subtitle */}
      {subtitle && (
        <p className="mt-1 text-xs text-text-muted">
          {subtitle}
        </p>
      )}
    </div>
  );
});
