"use client";

import { useEffect, useRef, useState } from "react";

// ── Constants ─────────────────────────────────────────────────────────────────

/** Duration of the countdown shown in the warning modal (seconds). */
const WARNING_COUNTDOWN_SECONDS = 5 * 60; // 5 minutes (matches LOGOUT_MS - WARN_MS)

// ── Component ─────────────────────────────────────────────────────────────────

export type IdleWarningModalProps = {
  /** Controls visibility. When true, shows the modal. */
  isOpen: boolean;
  /** Called when the user clicks "Stay Signed In". */
  onStaySignedIn: () => void;
  /** Called when the user clicks "Sign Out Now". */
  onSignOut: () => void;
};

/**
 * Non-dismissable idle session warning modal.
 *
 * Displayed 5 minutes before the 30-minute auto-logout policy fires.
 * The countdown shown here is decorative — the actual logout is controlled
 * by {@link useIdleTimer}. Dismissing is only possible through the two buttons.
 *
 * Must only be rendered from inside the authenticated dashboard shell.
 * Prevents stacking — the parent controls `isOpen` with a boolean flag.
 */
export function IdleWarningModal({
  isOpen,
  onStaySignedIn,
  onSignOut,
}: IdleWarningModalProps) {
  const [secondsLeft, setSecondsLeft] = useState(WARNING_COUNTDOWN_SECONDS);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const [prevOpen, setPrevOpen] = useState(isOpen);
  if (isOpen !== prevOpen) {
    setPrevOpen(isOpen);
    if (isOpen) {
      setSecondsLeft(WARNING_COUNTDOWN_SECONDS);
    }
  }

  // Reset and start the visual countdown whenever the modal opens.
  useEffect(() => {
    if (!isOpen) {
      // Clear countdown when closed.
      if (intervalRef.current !== null) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      return;
    }

    // Start fresh countdown.
    intervalRef.current = setInterval(() => {
      setSecondsLeft((prev) => Math.max(0, prev - 1));
    }, 1000);

    return () => {
      if (intervalRef.current !== null) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [isOpen]);

  if (!isOpen) return null;

  const minutes = Math.floor(secondsLeft / 60);
  const seconds = secondsLeft % 60;
  const formatted = `${minutes}:${String(seconds).padStart(2, "0")}`;

  return (
    // Fixed overlay — covers entire viewport, non-dismissable (no onClick on backdrop)
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="idle-warning-title"
      aria-describedby="idle-warning-description"
      className="fixed inset-0 z-50 flex items-center justify-center bg-[var(--surface-overlay)] backdrop-blur-xs"
    >
      <div className="mx-4 w-full max-w-sm rounded-2xl border border-[var(--border-subtle)] bg-[var(--card)] p-6 shadow-xl">
        {/* Icon */}
        <div className="flex justify-center">
          <div className="flex h-14 w-14 items-center justify-center rounded-full bg-[var(--surface-muted)]">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-7 w-7 text-[var(--primary)]"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              strokeWidth={1.8}
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M12 6v6l4 2m6-2a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z"
              />
            </svg>
          </div>
        </div>

        {/* Title */}
        <h2
          id="idle-warning-title"
          className="mt-4 text-center text-lg font-bold text-[var(--foreground)]"
        >
          Still there?
        </h2>

        {/* Description */}
        <p
          id="idle-warning-description"
          className="mt-2 text-center text-sm leading-6 text-[var(--text-muted)]"
        >
          You&apos;ve been inactive for a while. You&apos;ll be signed out
          automatically in:
        </p>

        {/* Countdown */}
        <div className="mt-4 flex justify-center">
          <div className="rounded-xl bg-[var(--surface-muted)] border border-[var(--border-subtle)] px-6 py-3">
            <span
              className="font-mono text-3xl font-extrabold tabular-nums text-[var(--foreground)]"
              aria-live="polite"
              aria-atomic="true"
            >
              {formatted}
            </span>
          </div>
        </div>

        {/* Actions */}
        <div className="mt-6 flex flex-col gap-2">
          <button
            id="idle-stay-signed-in"
            type="button"
            onClick={onStaySignedIn}
            className="w-full rounded-lg bg-[var(--primary)] px-4 py-2.5 text-sm font-semibold text-white transition-opacity hover:opacity-90 focus:outline-hidden focus-visible:ring-2 focus-visible:ring-[var(--primary)] cursor-pointer"
          >
            Stay Signed In
          </button>
          <button
            id="idle-sign-out-now"
            type="button"
            onClick={onSignOut}
            className="w-full rounded-lg px-4 py-2.5 text-sm font-medium text-[var(--text-muted)] transition-colors hover:bg-[var(--surface-muted)] hover:text-[var(--foreground)] focus:outline-hidden focus-visible:ring-2 focus-visible:ring-[var(--border-subtle)] cursor-pointer"
          >
            Sign Out Now
          </button>
        </div>
      </div>
    </div>
  );
}
