"use client";

import { useSyncExternalStore } from "react";
import { useUserSettings } from "@/lib/queries/settings";

export type MotionLevel = "full" | "lite" | "off";

function subscribeReducedMotion(callback: () => void): () => void {
  if (typeof window === "undefined") return () => {};
  const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  mediaQuery.addEventListener("change", callback);
  return () => mediaQuery.removeEventListener("change", callback);
}

function getSystemReducedMotion(): boolean {
  if (typeof window === "undefined") return false;
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function isWeakDevice(): boolean {
  if (typeof window === "undefined") return false;
  const nav = window.navigator as Navigator & { deviceMemory?: number };
  if (typeof nav.hardwareConcurrency === "number" && nav.hardwareConcurrency <= 4) {
    return true;
  }
  if (typeof nav.deviceMemory === "number" && nav.deviceMemory <= 4) {
    return true;
  }
  return false;
}

/**
 * Authoritative Motion Level Hook.
 * Determines whether the user should receive "full", "lite", or "off" motion.
 *
 * Rules:
 * - "off": prefers-reduced-motion is active OR user manually set reduceMotionEnabled in Settings.
 * - "lite": weak device (concurrency <= 4 or RAM <= 4GB). Lite = opacity fades <= 150ms only.
 * - "full": capable device, standard motion enabled.
 */
export function useMotionLevel(): MotionLevel {
  const systemReduced = useSyncExternalStore(
    subscribeReducedMotion,
    getSystemReducedMotion,
    () => false
  );

  const { data: userSettings } = useUserSettings();
  const userReduced = userSettings?.reduceMotionEnabled ?? false;

  if (systemReduced || userReduced) {
    return "off";
  }

  if (isWeakDevice()) {
    return "lite";
  }

  return "full";
}
