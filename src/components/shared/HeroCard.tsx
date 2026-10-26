"use client";

import { memo, type ReactNode } from "react";
import { PercentageRing } from "./PercentageRing";
import { AnimatedNumber } from "./AnimatedNumber";
import { evaluatePercentage, type PercentageScaleName } from "@/lib/utils/thresholds";

export interface HeroCardProps {
  title: string;
  subtitle?: string;
  percent: number;
  scale?: PercentageScaleName;
  actual?: number;
  actualLabel?: string;
  required?: number;
  requiredLabel?: string;
  badge?: ReactNode;
  footerCaption?: string;
  className?: string;
}

export const HeroCard = memo(function HeroCard({
  title,
  subtitle,
  percent,
  scale = "mfr",
  actual,
  actualLabel = "Actual",
  required,
  requiredLabel = "Required",
  badge,
  footerCaption,
  className = "",
}: HeroCardProps) {
  const evaluation = evaluatePercentage(scale, percent);

  return (
    <div
      className={`flex flex-col justify-between rounded-2xl border border-hero-border bg-hero-surface p-6 shadow-xs transition-colors duration-200 ${className}`}
    >
      {/* Top Header */}
      <div className="flex items-center justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold leading-snug text-hero-text">
            {title}
          </h2>
          {subtitle && (
            <p className="mt-0.5 text-xs text-hero-muted">{subtitle}</p>
          )}
        </div>
        <div>
          {badge ?? (
            <span
              className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-semibold ${evaluation.classes.border} ${evaluation.classes.bg} ${evaluation.classes.text}`}
            >
              <span
                className={`h-1.5 w-1.5 rounded-full ${evaluation.classes.dot}`}
              />
              {evaluation.label}
            </span>
          )}
        </div>
      </div>

      {/* Main Metric Visualization */}
      <div className="my-5 flex flex-col items-center justify-center gap-4 sm:flex-row sm:justify-around">
        <PercentageRing percent={percent} scale={scale} size={150} strokeWidth={13} />

        {(actual !== undefined || required !== undefined) && (
          <div className="flex flex-col gap-3 text-left">
            {actual !== undefined && (
              <div>
                <span className="text-xs font-medium text-hero-muted">
                  {actualLabel}
                </span>
                <p className="text-2xl font-bold tracking-tight text-hero-text tabular-nums">
                  <AnimatedNumber value={actual} />
                </p>
              </div>
            )}
            {required !== undefined && (
              <div>
                <span className="text-xs font-medium text-hero-muted">
                  {requiredLabel}
                </span>
                <p className="text-2xl font-bold tracking-tight text-hero-text tabular-nums">
                  <AnimatedNumber value={required} />
                </p>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Bottom Footer Caption */}
      {footerCaption && (
        <div className="border-t border-hero-border/60 pt-3 text-xs text-hero-muted">
          {footerCaption}
        </div>
      )}
    </div>
  );
});
