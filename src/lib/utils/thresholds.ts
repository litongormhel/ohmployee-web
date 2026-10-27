/**
 * Authoritative Percentage Thresholds Helper
 * Centralizes the two core business scales across OHMployee Web.
 *
 * SCALES:
 * 1. "mfr" (Manpower Fulfillment Rate / CENCOM):
 *    - Good (Healthy): >= 100%
 *    - Warn (At risk): 95.0% to 99.99%
 *    - Bad (Critical): < 95.0%
 *
 * 2. "fill_rate" (Store / Position Fill Rate / Dashboard & Plantilla):
 *    - Good: > 70%
 *    - Warn: 40% to 70%
 *    - Bad: < 40%
 *
 * Note: 41.5% MFR evaluates to "bad" (Critical), while 48.8% Fill Rate evaluates
 * to "warn" (Warning). They serve distinct operational purposes.
 */

export type PercentageScaleName = "mfr" | "fill_rate";

export type PercentageStatus = "good" | "warn" | "bad";

export interface PercentageEvaluation {
  status: PercentageStatus;
  scale: PercentageScaleName;
  percent: number;
  label: string;
  classes: {
    text: string;
    bg: string;
    border: string;
    track: string;
    bar: string;
    dot: string;
  };
}

export function evaluatePercentage(
  scale: PercentageScaleName,
  percent: number
): PercentageEvaluation {
  let status: PercentageStatus = "bad";
  let label = "Critical";

  if (scale === "mfr") {
    if (percent >= 100) {
      status = "good";
      label = "Healthy";
    } else if (percent >= 95) {
      status = "warn";
      label = "At risk";
    } else {
      status = "bad";
      label = "Critical";
    }
  } else if (scale === "fill_rate") {
    if (percent > 70) {
      status = "good";
      label = "Optimal";
    } else if (percent >= 40) {
      status = "warn";
      label = "Watch";
    } else {
      status = "bad";
      label = "Low";
    }
  }

  // Pure token-based semantic color mapping with high contrast bars and recessed tracks
  const classes = {
    good: {
      text: "text-pct-good-text",
      bg: "bg-pct-good-bg",
      border: "border-pct-good-border",
      track: "bg-surface-muted",
      bar: "bg-pct-good-bar",
      dot: "bg-pct-good-bar",
    },
    warn: {
      text: "text-pct-warn-text",
      bg: "bg-pct-warn-bg",
      border: "border-pct-warn-border",
      track: "bg-surface-muted",
      bar: "bg-pct-warn-bar",
      dot: "bg-pct-warn-bar",
    },
    bad: {
      text: "text-pct-bad-text",
      bg: "bg-pct-bad-bg",
      border: "border-pct-bad-border",
      track: "bg-surface-muted",
      bar: "bg-pct-bad-bar",
      dot: "bg-pct-bad-bar",
    },
  }[status];

  return {
    status,
    scale,
    percent,
    label,
    classes,
  };
}
