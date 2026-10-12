"use client";

import { useState, useEffect } from "react";
import {
  Laptop,
  Smartphone,
  Globe,
  Shield,
  ShieldAlert,
  LogOut,
  RefreshCw,
  Clock,
  History,
  AlertTriangle,
  Loader2,
  CheckCircle2,
} from "lucide-react";
import {
  useActiveSessions,
  useSecurityAuditLogs,
  useRevokeSession,
  useRevokeOtherSessions,
  heartbeatSessionRpc,
  getCachedCurrentSessionId,
  setCachedCurrentSessionId,
  type ActiveUserSession,
} from "@/lib/queries/settings";

function formatRelativeTime(isoString: string, nowMs: number) {
  const diffMs = nowMs - new Date(isoString).getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHour = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHour / 24);

  if (diffSec < 60) return "Active just now";
  if (diffMin < 60) return `${diffMin}m ago`;
  if (diffHour < 24) return `${diffHour}h ago`;
  return `${diffDay}d ago`;
}

export function SecurityTab() {
  const {
    data: sessions = [],
    isLoading: isLoadingSessions,
    error: sessionsError,
    refetch: refetchSessions,
  } = useActiveSessions();

  const {
    data: auditLogs = [],
    isLoading: isLoadingLogs,
    error: logsError,
    refetch: refetchLogs,
  } = useSecurityAuditLogs();

  const revokeSessionMutation = useRevokeSession();
  const revokeOtherSessionsMutation = useRevokeOtherSessions();

  const [currentSessionId, setCurrentSessionId] = useState<string | null>(null);
  const [selectedSessionForRevoke, setSelectedSessionForRevoke] = useState<ActiveUserSession | null>(null);
  const [isRevokeOthersModalOpen, setIsRevokeOthersModalOpen] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  // Heartbeat registration & session ID resolution
  useEffect(() => {
    let isMounted = true;

    async function initSession() {
      const cached = getCachedCurrentSessionId();
      try {
        const id = await heartbeatSessionRpc({
          sessionId: cached,
          devicePlatform: "Web Browser - Desktop",
          appVersion: "1.0.0-web",
        });

        if (id && isMounted) {
          setCurrentSessionId(id);
          setCachedCurrentSessionId(id);
        }
      } catch (err: unknown) {
        if ((err as Error)?.message === "SESSION_REVOKED") {
          window.location.href = "/login";
        }
      }
    }

    initSession();

    return () => {
      isMounted = false;
    };
  }, []);

  const handleRevokeSingle = async () => {
    if (!selectedSessionForRevoke) return;
    try {
      await revokeSessionMutation.mutateAsync(selectedSessionForRevoke.id);
      setToastMessage(`Revoked session on ${selectedSessionForRevoke.devicePlatform}.`);
      setSelectedSessionForRevoke(null);
      refetchSessions();
      refetchLogs();
      setTimeout(() => setToastMessage(null), 3500);
    } catch (err) {
      console.error(err);
    }
  };

  const handleRevokeOthers = async () => {
    if (!currentSessionId) return;
    try {
      await revokeOtherSessionsMutation.mutateAsync(currentSessionId);
      setToastMessage("All other active sessions have been revoked.");
      setIsRevokeOthersModalOpen(false);
      refetchSessions();
      refetchLogs();
      setTimeout(() => setToastMessage(null), 3500);
    } catch (err) {
      console.error(err);
    }
  };

  const [currentTime, setCurrentTime] = useState(() => Date.now());

  useEffect(() => {
    const timer = setInterval(() => setCurrentTime(Date.now()), 30000);
    return () => clearInterval(timer);
  }, []);

  const getDeviceIcon = (platform: string) => {
    const lower = platform.toLowerCase();
    if (lower.includes("web") || lower.includes("browser") || lower.includes("chrome") || lower.includes("firefox")) {
      return Laptop;
    }
    if (lower.includes("android") || lower.includes("ios") || lower.includes("mobile")) {
      return Smartphone;
    }
    return Globe;
  };

  const currentDevice = sessions.find((s) => s.id === currentSessionId);
  const otherActiveSessions = sessions.filter(
    (s) => s.id !== currentSessionId && s.revokedAt === null
  );

  return (
    <div className="space-y-6">
      {/* Toast Notification */}
      {toastMessage && (
        <div className="fixed bottom-6 right-6 z-50 flex items-center gap-2 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm font-medium text-emerald-800 shadow-lg">
          <CheckCircle2 className="h-4 w-4 text-emerald-600" />
          <span>{toastMessage}</span>
        </div>
      )}

      {/* Top Controls Bar */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 className="text-base font-semibold text-text-primary">
            Active Devices & Sessions
          </h2>
          <p className="text-xs text-text-secondary">
            Manage your logged-in browsers and mobile devices. Revoke any unrecognized sessions.
          </p>
        </div>

        <div className="flex items-center gap-2.5">
          <button
            type="button"
            onClick={() => {
              refetchSessions();
              refetchLogs();
            }}
            className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover"
          >
            <RefreshCw className="h-3.5 w-3.5 text-text-muted" />
            Refresh
          </button>

          {otherActiveSessions.length > 0 && (
            <button
              type="button"
              onClick={() => setIsRevokeOthersModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-red-200 bg-red-50/70 px-3.5 py-1.5 text-xs font-semibold text-red-700 shadow-2xs hover:bg-red-100"
            >
              <LogOut className="h-3.5 w-3.5" />
              Revoke All Other Sessions ({otherActiveSessions.length})
            </button>
          )}
        </div>
      </div>

      {/* Current Device Card */}
      <div className="rounded-xl border-2 border-blue-500/30 bg-blue-50/40 p-5 shadow-xs">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3.5">
            <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-blue-600 text-white shadow-xs">
              <Laptop className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-sm font-bold text-text-primary">
                  {currentDevice?.devicePlatform ?? "Current Web Browser"}
                </h3>
                <span className="inline-flex items-center rounded-md bg-emerald-50 px-2 py-0.5 text-xs font-bold text-emerald-700 border border-emerald-200">
                  This Device
                </span>
                {currentDevice?.isSuspicious && (
                  <span className="inline-flex items-center gap-1 rounded-md bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700 border border-amber-200">
                    <AlertTriangle className="h-3 w-3" />
                    Suspicious Activity
                  </span>
                )}
              </div>
              <div className="mt-1 flex flex-wrap items-center gap-3 text-xs text-text-secondary">
                <span className="font-mono">IP: {currentDevice?.ipAddress ?? "Current Session"}</span>
                <span>•</span>
                <span>Version: {currentDevice?.appVersion ?? "1.0.0-web"}</span>
                <span>•</span>
                <span className="flex items-center gap-1 font-medium text-emerald-600">
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
                  {currentDevice ? formatRelativeTime(currentDevice.lastSeenAt, currentTime) : "Active now"}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Other Active Sessions List */}
      <div className="rounded-xl border border-border-default bg-surface-card p-6 shadow-xs space-y-4">
        <div className="flex items-center justify-between border-b border-border-default pb-3">
          <div className="flex items-center gap-2">
            <Shield className="h-4 w-4 text-blue-600" />
            <h3 className="text-sm font-semibold uppercase tracking-wider text-text-primary">
              Other Active Sessions ({otherActiveSessions.length})
            </h3>
          </div>
        </div>

        {isLoadingSessions ? (
          <div className="flex h-32 items-center justify-center text-xs text-text-secondary">
            <Loader2 className="h-4 w-4 animate-spin text-blue-600 mr-2" />
            Loading active sessions...
          </div>
        ) : sessionsError ? (
          <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-xs text-red-700">
            Failed to load active sessions: {(sessionsError as Error).message}
          </div>
        ) : otherActiveSessions.length === 0 ? (
          <div className="rounded-lg border border-border-default bg-surface-base/50 p-6 text-center text-xs text-text-muted">
            <Shield className="mx-auto h-8 w-8 text-emerald-500/70 mb-2" />
            <p className="font-medium text-text-secondary">No other active devices</p>
            <p className="mt-0.5 text-text-muted">
              You are currently logged in only on this web browser.
            </p>
          </div>
        ) : (
          <div className="divide-y divide-border-default">
            {otherActiveSessions.map((session) => {
              const DeviceIcon = getDeviceIcon(session.devicePlatform);
              return (
                <div
                  key={session.id}
                  className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 py-4 first:pt-1 last:pb-1"
                >
                  <div className="flex items-center gap-3.5">
                    <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-surface-hover text-text-secondary">
                      <DeviceIcon className="h-5 w-5" />
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <h4 className="text-sm font-semibold text-text-primary">
                          {session.devicePlatform}
                        </h4>
                        {session.isSuspicious && (
                          <span className="inline-flex items-center gap-1 rounded-md bg-amber-50 px-1.5 py-0.5 text-2xs font-medium text-amber-700 border border-amber-200">
                            <ShieldAlert className="h-3 w-3" />
                            Suspicious
                          </span>
                        )}
                      </div>
                      <div className="mt-0.5 flex flex-wrap items-center gap-2.5 text-xs text-text-muted">
                        <span className="font-mono">IP: {session.ipAddress ?? "Unknown"}</span>
                        <span>•</span>
                        <span>Logged in: {new Date(session.loginAt).toLocaleDateString()}</span>
                        <span>•</span>
                        <span>Last active: {formatRelativeTime(session.lastSeenAt, currentTime)}</span>
                      </div>
                    </div>
                  </div>

                  <button
                    type="button"
                    onClick={() => setSelectedSessionForRevoke(session)}
                    className="inline-flex items-center justify-center gap-1.5 rounded-lg border border-red-200 bg-red-50/50 px-3 py-1.5 text-xs font-semibold text-red-700 hover:bg-red-100"
                  >
                    <LogOut className="h-3.5 w-3.5" />
                    Revoke Session
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Security Audit Trail Timeline */}
      <div className="rounded-xl border border-border-default bg-surface-card p-6 shadow-xs space-y-4">
        <div className="flex items-center justify-between border-b border-border-default pb-3">
          <div className="flex items-center gap-2">
            <History className="h-4 w-4 text-purple-600" />
            <h3 className="text-sm font-semibold uppercase tracking-wider text-text-primary">
              Security Compliance & Audit Trail
            </h3>
          </div>
          <span className="text-xs text-text-muted">Recent 50 Events</span>
        </div>

        {isLoadingLogs ? (
          <div className="flex h-32 items-center justify-center text-xs text-text-secondary">
            <Loader2 className="h-4 w-4 animate-spin text-purple-600 mr-2" />
            Loading security audit timeline...
          </div>
        ) : logsError ? (
          <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-xs text-red-700">
            Failed to load security audit trail: {(logsError as Error).message}
          </div>
        ) : auditLogs.length === 0 ? (
          <div className="rounded-lg border border-border-default bg-surface-base/50 p-6 text-center text-xs text-text-muted">
            <History className="mx-auto h-8 w-8 text-text-muted mb-2" />
            <p className="font-medium text-text-secondary">No recorded security logs</p>
            <p className="mt-0.5 text-text-muted">
              Security events such as logins and revocations will appear here.
            </p>
          </div>
        ) : (
          <div className="relative pl-6 space-y-6 before:absolute before:bottom-2 before:top-2 before:left-2.5 before:w-0.5 before:bg-border-default">
            {auditLogs.map((log) => {
              const isDanger =
                log.action === "REMOTE_REVOKE" ||
                log.action === "REVOKE" ||
                log.action === "SUSPICIOUS_LOGIN";

              return (
                <div key={log.id} className="relative group">
                  {/* Timeline dot */}
                  <div
                    className={`absolute -left-6 top-1 h-2.5 w-2.5 rounded-full ring-4 ring-surface-card ${
                      isDanger
                        ? "bg-red-500"
                        : log.action === "LOGIN"
                        ? "bg-emerald-500"
                        : "bg-blue-500"
                    }`}
                  />

                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 text-xs">
                    <div className="flex items-center gap-2">
                      <span
                        className={`inline-flex items-center rounded-md px-2 py-0.5 font-bold uppercase tracking-wider text-2xs ${
                          isDanger
                            ? "bg-red-50 text-red-700 border border-red-200"
                            : log.action === "LOGIN"
                            ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                            : "bg-blue-50 text-blue-700 border border-blue-200"
                        }`}
                      >
                        {log.action}
                      </span>
                      <span className="font-semibold text-text-primary">
                        {log.devicePlatform ?? "Web Device"}
                      </span>
                      {log.ipAddress && (
                        <span className="font-mono text-text-muted">
                          (IP: {log.ipAddress})
                        </span>
                      )}
                    </div>
                    <span className="text-text-muted font-mono flex items-center gap-1">
                      <Clock className="h-3 w-3" />
                      {new Date(log.createdAt).toLocaleString()}
                    </span>
                  </div>

                  {log.details && Object.keys(log.details).length > 0 && (
                    <div className="mt-1 text-2xs text-text-secondary bg-surface-base px-2 py-1 rounded-md border border-border-default font-mono">
                      {JSON.stringify(log.details)}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Confirmation Modal: Single Session Revoke */}
      {selectedSessionForRevoke && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-xs p-4"
        >
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-card p-6 shadow-xl">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-red-50 text-red-600">
                <AlertTriangle className="h-5 w-5" />
              </div>
              <div>
                <h3 className="text-base font-bold text-text-primary">
                  Revoke Device Session?
                </h3>
                <p className="text-xs text-text-secondary">
                  Are you sure you want to log out this session?
                </p>
              </div>
            </div>

            <p className="mt-4 text-xs leading-relaxed text-text-secondary">
              This will instantly terminate the session on{" "}
              <strong>{selectedSessionForRevoke.devicePlatform}</strong> (IP:{" "}
              <code className="font-mono">{selectedSessionForRevoke.ipAddress ?? "Unknown"}</code>
              ). The user will be required to authenticate again.
            </p>

            <div className="mt-6 flex items-center justify-end gap-3">
              <button
                type="button"
                onClick={() => setSelectedSessionForRevoke(null)}
                className="rounded-lg border border-border-default px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleRevokeSingle}
                disabled={revokeSessionMutation.isPending}
                className="rounded-lg bg-red-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-red-700 disabled:opacity-50"
              >
                {revokeSessionMutation.isPending ? "Revoking..." : "Revoke Session"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Confirmation Modal: Revoke All Other Sessions */}
      {isRevokeOthersModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-xs p-4"
        >
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-card p-6 shadow-xl">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-red-50 text-red-600">
                <LogOut className="h-5 w-5" />
              </div>
              <div>
                <h3 className="text-base font-bold text-text-primary">
                  Revoke All Other Sessions?
                </h3>
                <p className="text-xs text-text-secondary">
                  Mass revocation across all connected devices.
                </p>
              </div>
            </div>

            <p className="mt-4 text-xs leading-relaxed text-text-secondary">
              This will immediately disconnect all active logins across other browsers, laptops, and mobile devices. <strong>Your current web session will remain active.</strong>
            </p>

            <div className="mt-6 flex items-center justify-end gap-3">
              <button
                type="button"
                onClick={() => setIsRevokeOthersModalOpen(false)}
                className="rounded-lg border border-border-default px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleRevokeOthers}
                disabled={revokeOtherSessionsMutation.isPending}
                className="rounded-lg bg-red-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-red-700 disabled:opacity-50"
              >
                {revokeOtherSessionsMutation.isPending ? "Logging out..." : "Revoke All Others"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
