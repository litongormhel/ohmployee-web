"use client";

import { memo } from "react";
import { useMotionLevel } from "@/hooks/useMotionLevel";

export interface SkeletonProps {
  className?: string;
  count?: number;
}

export const Skeleton = memo(function Skeleton({
  className = "h-4 w-full",
  count = 1,
}: SkeletonProps) {
  const motionLevel = useMotionLevel();
  const pulseClass = motionLevel === "full" ? "animate-pulse" : "";

  if (count === 1) {
    return (
      <div
        className={`rounded-md bg-surface-muted border border-border-subtle/50 ${pulseClass} ${className}`}
        aria-hidden="true"
      />
    );
  }

  return (
    <div className="space-y-2 w-full" aria-hidden="true">
      {Array.from({ length: count }).map((_, idx) => (
        <div
          key={idx}
          className={`rounded-md bg-surface-muted border border-border-subtle/50 ${pulseClass} ${className}`}
        />
      ))}
    </div>
  );
});
