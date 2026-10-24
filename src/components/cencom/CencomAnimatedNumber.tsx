"use client";

import { useEffect, useState } from "react";
import { usePrefersReducedMotion } from "./usePrefersReducedMotion";

export interface CencomAnimatedNumberProps {
  value: number;
  durationMs?: number; // default 900ms
  decimals?: number; // default 0
  suffix?: string;
  className?: string;
}

function easeOutCubic(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

export function CencomAnimatedNumber({
  value,
  durationMs = 900,
  decimals = 0,
  suffix = "",
  className = "",
}: CencomAnimatedNumberProps) {
  const prefersReducedMotion = usePrefersReducedMotion();
  const [displayValue, setDisplayValue] = useState<number>(0);

  useEffect(() => {
    if (prefersReducedMotion) return;

    let startTimestamp: number | null = null;
    let frameId: number;
    const startValue = 0;
    const endValue = value;

    const step = (timestamp: number) => {
      if (!startTimestamp) startTimestamp = timestamp;
      const elapsed = timestamp - startTimestamp;
      const progress = Math.min(1, elapsed / durationMs);
      const easedProgress = easeOutCubic(progress);

      const current = startValue + (endValue - startValue) * easedProgress;
      setDisplayValue(current);

      if (progress < 1) {
        frameId = requestAnimationFrame(step);
      } else {
        setDisplayValue(endValue);
      }
    };

    frameId = requestAnimationFrame(step);

    return () => {
      cancelAnimationFrame(frameId);
    };
  }, [value, durationMs, prefersReducedMotion]);

  const effectiveValue = prefersReducedMotion ? value : displayValue;
  const formatted =
    decimals > 0
      ? effectiveValue.toFixed(decimals)
      : Math.round(effectiveValue).toLocaleString();

  return (
    <span className={`tabular-nums ${className}`}>
      {formatted}
      {suffix}
    </span>
  );
}
