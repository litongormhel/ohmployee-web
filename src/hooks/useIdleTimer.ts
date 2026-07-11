"use client";

import { useEffect, useRef, useCallback } from "react";

// ── Policy constants ──────────────────────────────────────────────────────────

/** Idle duration (ms) before the warning modal is shown. */
const WARN_MS = 25 * 60 * 1000; // 25 minutes

/** Idle duration (ms) before automatic logout fires (must be > WARN_MS). */
const LOGOUT_MS = 30 * 60 * 1000; // 30 minutes

/**
 * Browser events that constitute "user activity".
 * Background polling, API fetches, React Query refetches, and Supabase
 * realtime events are explicitly excluded — those callers must not call
 * resetTimers().
 */
const ACTIVITY_EVENTS: ReadonlyArray<keyof DocumentEventMap> = [
  "mousemove",
  "mousedown",
  "keydown",
  "touchstart",
  "scroll",
  "click",
  "pointerdown",
];

// ── Hook ──────────────────────────────────────────────────────────────────────

export type UseIdleTimerOptions = {
  /** Called at 25 minutes of inactivity — show warning modal. */
  onWarn: () => void;
  /** Called at 30 minutes of inactivity — perform logout. */
  onLogout: () => void;
};

export type UseIdleTimerReturn = {
  /** Manually reset the idle timer (e.g., when user clicks "Stay Signed In"). */
  resetTimers: () => void;
};

/**
 * Policy-locked idle timer hook.
 *
 * Attaches activity listeners on document. Fires `onWarn` at 25 min idle,
 * then `onLogout` at 30 min idle. Timers are stored in refs to avoid
 * re-render cycles and are fully cleared on unmount.
 *
 * @example
 * ```tsx
 * const { resetTimers } = useIdleTimer({
 *   onWarn: () => setWarningOpen(true),
 *   onLogout: handleIdleLogout,
 * });
 * ```
 */
export function useIdleTimer({
  onWarn,
  onLogout,
}: UseIdleTimerOptions): UseIdleTimerReturn {
  // Store callbacks in refs so the timer closures always call the latest
  // version without the timers needing to be re-registered on re-renders.
  const onWarnRef = useRef(onWarn);
  const onLogoutRef = useRef(onLogout);

  useEffect(() => {
    onWarnRef.current = onWarn;
  }, [onWarn]);

  useEffect(() => {
    onLogoutRef.current = onLogout;
  }, [onLogout]);

  // Timer IDs stored in refs (not state) to avoid triggering re-renders.
  const warnTimerId = useRef<ReturnType<typeof setTimeout> | null>(null);
  const logoutTimerId = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearTimers = useCallback(() => {
    if (warnTimerId.current !== null) {
      clearTimeout(warnTimerId.current);
      warnTimerId.current = null;
    }
    if (logoutTimerId.current !== null) {
      clearTimeout(logoutTimerId.current);
      logoutTimerId.current = null;
    }
  }, []);

  const resetTimers = useCallback(() => {
    clearTimers();

    warnTimerId.current = setTimeout(() => {
      onWarnRef.current();
    }, WARN_MS);

    logoutTimerId.current = setTimeout(() => {
      onLogoutRef.current();
    }, LOGOUT_MS);
  }, [clearTimers]);

  useEffect(() => {
    // Start timers on mount.
    resetTimers();

    // Attach activity listeners. Each user event calls resetTimers().
    // These are the ONLY paths that reset the idle clock.
    const handleActivity = () => resetTimers();

    ACTIVITY_EVENTS.forEach((event) => {
      document.addEventListener(event, handleActivity, { passive: true });
    });

    return () => {
      // Cleanup on unmount (logout, route away from authenticated shell).
      clearTimers();
      ACTIVITY_EVENTS.forEach((event) => {
        document.removeEventListener(event, handleActivity);
      });
    };
    // resetTimers is stable (useCallback with no deps that change).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { resetTimers };
}
