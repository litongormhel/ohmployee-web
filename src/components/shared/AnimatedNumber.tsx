"use client";

import { useEffect, useRef } from "react";
import { useMotionLevel } from "@/hooks/useMotionLevel";

export interface AnimatedNumberProps {
  value: number;
  durationMs?: number; // default 600ms
  decimals?: number; // default 0
  prefix?: string;
  suffix?: string;
  className?: string;
}

function easeOutQuart(t: number): number {
  return 1 - Math.pow(1 - t, 4);
}

function formatNumber(val: number, decimals: number, prefix: string, suffix: string): string {
  const formatted =
    decimals > 0
      ? val.toFixed(decimals)
      : Math.round(val).toLocaleString();
  return `${prefix}${formatted}${suffix}`;
}

export function AnimatedNumber({
  value,
  durationMs = 600,
  decimals = 0,
  prefix = "",
  suffix = "",
  className = "",
}: AnimatedNumberProps) {
  const motionLevel = useMotionLevel();
  const shouldAnimate = motionLevel === "full";
  const spanRef = useRef<HTMLSpanElement>(null);
  const prevValueRef = useRef<number>(value);
  const currentValueRef = useRef<number>(value);

  useEffect(() => {
    const el = spanRef.current;
    if (!el) return;

    if (value === undefined || value === null || Number.isNaN(value)) {
      return;
    }

    if (!shouldAnimate) {
      el.textContent = formatNumber(value, decimals, prefix, suffix);
      prevValueRef.current = value;
      currentValueRef.current = value;
      return;
    }

    const startValue = currentValueRef.current;
    const endValue = value;

    if (startValue === endValue) {
      el.textContent = formatNumber(endValue, decimals, prefix, suffix);
      return;
    }

    let startTimestamp: number | null = null;
    let frameId: number;

    const step = (timestamp: number) => {
      if (!startTimestamp) startTimestamp = timestamp;
      const elapsed = timestamp - startTimestamp;
      const progress = Math.min(1, elapsed / durationMs);
      const easedProgress = easeOutQuart(progress);

      const current = startValue + (endValue - startValue) * easedProgress;
      currentValueRef.current = current;
      el.textContent = formatNumber(current, decimals, prefix, suffix);

      if (progress < 1) {
        frameId = requestAnimationFrame(step);
      } else {
        el.textContent = formatNumber(endValue, decimals, prefix, suffix);
        currentValueRef.current = endValue;
        prevValueRef.current = endValue;
      }
    };

    frameId = requestAnimationFrame(step);

    return () => {
      cancelAnimationFrame(frameId);
      prevValueRef.current = currentValueRef.current;
    };
  }, [value, durationMs, decimals, prefix, suffix, shouldAnimate]);

  return (
    <span ref={spanRef} className={`tabular-nums ${className}`}>
      {formatNumber(value, decimals, prefix, suffix)}
    </span>
  );
}
