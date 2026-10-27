"use client";

import { memo } from "react";
import { useMotionLevel } from "@/hooks/useMotionLevel";
import { evaluatePercentage, type PercentageScaleName } from "@/lib/utils/thresholds";

export interface PercentageBarProps {
  percent: number; // 0 to 100
  scale?: PercentageScaleName;
  heightClass?: string; // default "h-2"
  showLabel?: boolean;
  className?: string;
}

export const PercentageBar = memo(function PercentageBar({
  percent,
  scale = "fill_rate",
  heightClass = "h-2",
  showLabel = false,
  className = "",
}: PercentageBarProps) {
  const motionLevel = useMotionLevel();
  const evaluation = evaluatePercentage(scale, percent);
  const clamped = Math.min(100, Math.max(0, percent));

  const barColor =
    evaluation.status === "good"
      ? "bg-pct-good-bar"
      : evaluation.status === "warn"
      ? "bg-pct-warn-bar"
      : "bg-pct-bad-bar";

  const trackColor = "bg-surface-muted border border-border-subtle/50";

  return (
    <div className={`w-full ${className}`}>
      {showLabel && (
        <div className="mb-1 flex items-center justify-between text-xs">
          <span className="font-medium text-text-secondary">{evaluation.label}</span>
          <span className="font-semibold text-text-primary tabular-nums">
            {percent.toFixed(1)}%
          </span>
        </div>
      )}
      <div
        className={`w-full overflow-hidden rounded-full ${trackColor} ${heightClass}`}
        role="progressbar"
        aria-valuenow={Math.round(clamped)}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        <div
          className={`h-full rounded-full ${barColor} ${
            motionLevel === "full" ? "transition-all duration-700 ease-out" : ""
          }`}
          style={{ width: `${clamped}%` }}
        />
      </div>
    </div>
  );
});
