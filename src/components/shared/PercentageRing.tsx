"use client";

import { memo, useEffect, useState } from "react";
import { useMotionLevel } from "@/hooks/useMotionLevel";
import { evaluatePercentage, type PercentageScaleName } from "@/lib/utils/thresholds";

export interface PercentageRingProps {
  percent: number; // 0 to 100
  scale?: PercentageScaleName;
  size?: number; // default 140
  strokeWidth?: number; // default 12
  showLabel?: boolean;
  className?: string;
}

function easeOutQuart(t: number): number {
  return 1 - Math.pow(1 - t, 4);
}

export const PercentageRing = memo(function PercentageRing({
  percent,
  scale = "mfr",
  size = 140,
  strokeWidth = 12,
  showLabel = true,
  className = "",
}: PercentageRingProps) {
  const motionLevel = useMotionLevel();
  const shouldAnimate = motionLevel === "full";

  const evaluation = evaluatePercentage(scale, percent);

  const [animatedProgress, setAnimatedProgress] = useState<number>(
    shouldAnimate ? 0 : percent
  );

  useEffect(() => {
    if (!shouldAnimate) {
      setAnimatedProgress(percent);
      return;
    }

    let startTimestamp: number | null = null;
    let frameId: number;
    const startValue = 0;
    const endValue = percent;
    const duration = 800; // within budget

    const step = (timestamp: number) => {
      if (!startTimestamp) startTimestamp = timestamp;
      const elapsed = timestamp - startTimestamp;
      const progress = Math.min(1, elapsed / duration);
      const eased = easeOutQuart(progress);

      setAnimatedProgress(startValue + (endValue - startValue) * eased);

      if (progress < 1) {
        frameId = requestAnimationFrame(step);
      } else {
        setAnimatedProgress(endValue);
      }
    };

    frameId = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frameId);
  }, [percent, shouldAnimate]);

  const effectiveProgress = shouldAnimate ? animatedProgress : percent;

  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const sweepFraction = Math.min(1, Math.max(0, effectiveProgress / 100));
  const strokeDashoffset = circumference * (1 - sweepFraction);

  const strokeColor =
    evaluation.status === "good"
      ? "var(--pct-good-text)"
      : evaluation.status === "warn"
      ? "var(--pct-warn-text)"
      : "var(--pct-bad-text)";

  const trackColor =
    evaluation.status === "good"
      ? "var(--pct-good-bg)"
      : evaluation.status === "warn"
      ? "var(--pct-warn-bg)"
      : "var(--pct-bad-bg)";

  return (
    <div
      className={`relative inline-flex items-center justify-center ${className}`}
      style={{ width: size, height: size }}
      role="progressbar"
      aria-valuenow={Math.round(percent)}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <svg
        width={size}
        height={size}
        className="-rotate-90 transform"
        aria-hidden="true"
      >
        {/* Track circle */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke={trackColor}
          strokeWidth={strokeWidth}
          fill="transparent"
          strokeLinecap="round"
        />
        {/* Value sweep circle */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke={strokeColor}
          strokeWidth={strokeWidth}
          fill="transparent"
          strokeDasharray={circumference}
          strokeDashoffset={strokeDashoffset}
          strokeLinecap="round"
          className={shouldAnimate ? "transition-all duration-75" : ""}
        />
      </svg>
      {showLabel && (
        <div className="absolute flex flex-col items-center justify-center text-center">
          <span className="text-2xl font-bold tracking-tight text-text-primary tabular-nums">
            {percent.toFixed(1)}%
          </span>
          <span className={`text-[11px] font-semibold ${evaluation.classes.text}`}>
            {evaluation.label}
          </span>
        </div>
      )}
    </div>
  );
});
