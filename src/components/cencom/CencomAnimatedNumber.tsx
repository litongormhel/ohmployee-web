"use client";

import { AnimatedNumber } from "@/components/shared/AnimatedNumber";

export interface CencomAnimatedNumberProps {
  value: number;
  durationMs?: number; // default 900ms
  decimals?: number; // default 0
  suffix?: string;
  className?: string;
}

export function CencomAnimatedNumber({
  value,
  durationMs = 900,
  decimals = 0,
  suffix = "",
  className = "",
}: CencomAnimatedNumberProps) {
  return (
    <AnimatedNumber
      value={value}
      durationMs={durationMs}
      decimals={decimals}
      suffix={suffix}
      className={className}
    />
  );
}
