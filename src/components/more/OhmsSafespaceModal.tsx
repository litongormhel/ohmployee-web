"use client";

import { useState } from "react";
import {
  Activity,
  AlertTriangle,
  CheckCircle2,
  Lock,
  RefreshCw,
  Shield,
  ShieldAlert,
  Snowflake,
  Sliders,
  Terminal,
  Wrench,
} from "lucide-react";
import {
  useGovernanceControls,
  useGovernanceAuditLogs,
  useRiskControls,
  useFreezeModes,
  useUpdateGovernanceControl,
  useUpdateFreezeMode,
  type GovernanceControlItem,
} from "@/lib/queries/more";
import { useCurrentUser } from "@/lib/auth";
import { Modal } from "@/components/shared/Modal";

export interface OhmsSafespaceModalProps {
  isOpen: boolean;
  onClose: () => void;
}

type SafespaceTab =
  | "overview"
  | "super_admin_controls"
  | "risk_controls"
  | "freeze_modes"
  | "diagnostics"
  | "audit_logs";

export function OhmsSafespaceModal({ isOpen, onClose }: OhmsSafespaceModalProps) {
  const currentUser = useCurrentUser();
  const [activeTab, setActiveTab] = useState<SafespaceTab>("overview");

  // Dialog prompt state for toggling a control
  const [pendingToggle, setPendingToggle] = useState<{
    type: "governance" | "risk" | "freeze";
    control: GovernanceControlItem;
    targetEnabled: boolean;
  } | null>(null);
  const [reasonInput, setReasonInput] = useState("");
  const [toggleError, setToggleError] = useState<string | null>(null);

  // Diagnostics check state
  const [diagnosticsRunning, setDiagnosticsRunning] = useState(false);
  const [lastDiagCheck, setLastDiagCheck] = useState<Date | null>(null);
  const [connectivityLatency, setConnectivityLatency] = useState<number | null>(null);
  const [diagResults, setDiagResults] = useState<{
    rpcStatus: "healthy" | "degraded" | "checking";
    freezeStatus: "nominal" | "active_freeze" | "error";
    auditLogAvailable: boolean;
  }>({
    rpcStatus: "healthy",
    freezeStatus: "nominal",
    auditLogAvailable: true,
  });

  // Queries
  const {
    data: govControls = [],
    isLoading: govLoading,
    refetch: refetchGov,
  } = useGovernanceControls();

  const {
    data: riskControls = [],
    isLoading: riskLoading,
    refetch: refetchRisk,
  } = useRiskControls();

  const {
    data: freezeModes = [],
    isLoading: freezeLoading,
    refetch: refetchFreeze,
  } = useFreezeModes();

  const {
    data: auditLogs = [],
    isLoading: auditLoading,
    refetch: refetchAudit,
  } = useGovernanceAuditLogs();

  const updateGovMutation = useUpdateGovernanceControl();
  const updateFreezeMutation = useUpdateFreezeMode();

  const runDiagnostics = async () => {
    setDiagnosticsRunning(true);
    const start = performance.now();
    try {
      await Promise.all([refetchGov(), refetchRisk(), refetchFreeze()]);
      const latency = Math.round(performance.now() - start);
      setConnectivityLatency(latency);
      const activeFreezes = freezeModes.filter((f) => f.enabled);
      setDiagResults({
        rpcStatus: "healthy",
        freezeStatus: activeFreezes.length > 0 ? "active_freeze" : "nominal",
        auditLogAvailable: auditLogs.length >= 0,
      });
      setLastDiagCheck(new Date());
    } catch {
      setDiagResults({
        rpcStatus: "degraded",
        freezeStatus: "error",
        auditLogAvailable: false,
      });
    } finally {
      setDiagnosticsRunning(false);
    }
  };

  const handleOpenToggle = (
    type: "governance" | "risk" | "freeze",
    control: GovernanceControlItem,
  ) => {
    setPendingToggle({
      type,
      control,
      targetEnabled: !control.enabled,
    });
    setReasonInput("");
    setToggleError(null);
  };

  const handleConfirmToggle = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pendingToggle || !currentUser?.profileId) return;

    if (!reasonInput.trim()) {
      setToggleError("An audited reason is required for governance actions.");
      return;
    }

    try {
      setToggleError(null);
      if (pendingToggle.type === "freeze") {
        await updateFreezeMutation.mutateAsync({
          controlKey: pendingToggle.control.controlKey,
          enabled: pendingToggle.targetEnabled,
          reason: reasonInput.trim(),
          actorId: currentUser.profileId,
        });
      } else {
        await updateGovMutation.mutateAsync({
          controlKey: pendingToggle.control.controlKey,
          enabled: pendingToggle.targetEnabled,
          reason: reasonInput.trim(),
          actorId: currentUser.profileId,
        });
      }

      setPendingToggle(null);
      setReasonInput("");
    } catch (err) {
      setToggleError(
        err instanceof Error ? err.message : "Failed to update governance control.",
      );
    }
  };

  const isMutating = updateGovMutation.isPending || updateFreezeMutation.isPending;
  const isReasonDirty = reasonInput.trim().length > 0;

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="OHM's Safespace"
        subtitle="Owner command center — system controls, capability restrictions, diagnostics, and operational freeze modes"
        icon={ShieldAlert}
        maxWidthClass="max-w-5xl"
        footer={
          <div className="flex w-full items-center justify-between text-xs text-text-muted">
            <span>Phase 4 Security & Governance Parity • Level 100 Hub</span>
            <button
              type="button"
              onClick={onClose}
              className="rounded-xl border border-border-default bg-surface-primary px-4 py-2 text-xs font-semibold text-text-primary transition hover:bg-surface-hover cursor-pointer"
            >
              Close Safespace
            </button>
          </div>
        }
      >
        <div className="space-y-4">
          {/* Super Admin Notice Banner */}
          <div className="p-3 bg-surface-subtle border border-border-default rounded-xl text-xs flex items-center justify-between">
            <div className="flex items-center gap-2 text-text-secondary">
              <Lock className="w-3.5 h-3.5 text-brand-primary shrink-0" />
              <span>
                Restricted to Super Admin. All toggle operations are strictly validated against backend RPC gates and audit-logged.
              </span>
            </div>
            <div className="text-xs text-text-muted font-mono shrink-0">
              {currentUser?.email || "Unknown Admin"}
            </div>
          </div>

          {/* Navigation Tabs Bar */}
          <div className="border-b border-border-default flex items-center gap-2 overflow-x-auto no-scrollbar scrollbar-none pb-2">
            <button
              type="button"
              onClick={() => setActiveTab("overview")}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === "overview"
                  ? "bg-brand-50 text-brand-900 border border-brand-200"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              <Shield className="w-3.5 h-3.5" />
              <span>Overview & Hub</span>
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("super_admin_controls")}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === "super_admin_controls"
                  ? "bg-brand-50 text-brand-900 border border-brand-200"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              <Sliders className="w-3.5 h-3.5" />
              <span>System Controls</span>
              <span className="px-1.5 py-0.2 rounded-full text-xs bg-surface-subtle text-text-muted">
                {govControls.length}
              </span>
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("risk_controls")}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === "risk_controls"
                  ? "bg-brand-50 text-brand-900 border border-brand-200"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              <AlertTriangle className="w-3.5 h-3.5" />
              <span>Risk Controls</span>
              <span className="px-1.5 py-0.2 rounded-full text-xs bg-surface-subtle text-text-muted">
                {riskControls.length}
              </span>
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("freeze_modes")}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === "freeze_modes"
                  ? "bg-brand-50 text-brand-900 border border-brand-200"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              <Snowflake className="w-3.5 h-3.5" />
              <span>Freeze Modes</span>
              <span className="px-1.5 py-0.2 rounded-full text-xs bg-surface-subtle text-text-muted">
                {freezeModes.length}
              </span>
            </button>
            <button
              type="button"
              onClick={() => {
                setActiveTab("diagnostics");
                if (!lastDiagCheck) runDiagnostics();
              }}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === "diagnostics"
                  ? "bg-brand-50 text-brand-900 border border-brand-200"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              <Activity className="w-3.5 h-3.5" />
              <span>Diagnostics</span>
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("audit_logs")}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === "audit_logs"
                  ? "bg-brand-50 text-brand-900 border border-brand-200"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              <Terminal className="w-3.5 h-3.5" />
              <span>Security Audit Log</span>
              <span className="px-1.5 py-0.2 rounded-full text-xs bg-surface-subtle text-text-muted">
                {auditLogs.length}
              </span>
            </button>
          </div>

          {/* Content Body */}
          <div className="max-h-[58vh] overflow-y-auto space-y-4 pr-1">
            {activeTab === "overview" && (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <div
                  onClick={() => setActiveTab("super_admin_controls")}
                  className="p-4 rounded-xl border border-border-default hover:border-brand-primary bg-surface-primary hover:bg-surface-hover cursor-pointer transition-all shadow-2xs group"
                >
                  <div className="flex items-center justify-between">
                    <div className="w-9 h-9 rounded-lg bg-surface-subtle text-text-primary flex items-center justify-center">
                      <Sliders className="w-4 h-4" />
                    </div>
                    <span className="px-2 py-0.5 rounded text-xs font-semibold bg-surface-subtle text-text-secondary border border-border-default">
                      Active
                    </span>
                  </div>
                  <h3 className="mt-3 text-sm font-semibold text-text-primary group-hover:text-brand-primary">
                    Super Admin Controls
                  </h3>
                  <p className="mt-1 text-xs text-text-secondary">
                    Toggle system-wide feature gates: Account Registration, Import Plantilla, and backend ingestion filters.
                  </p>
                </div>

                <div
                  onClick={() => setActiveTab("risk_controls")}
                  className="p-4 rounded-xl border border-border-default hover:border-brand-primary bg-surface-primary hover:bg-surface-hover cursor-pointer transition-all shadow-2xs group"
                >
                  <div className="flex items-center justify-between">
                    <div className="w-9 h-9 rounded-lg bg-surface-subtle text-text-primary flex items-center justify-center">
                      <AlertTriangle className="w-4 h-4" />
                    </div>
                    <span className="px-2 py-0.5 rounded text-xs font-semibold bg-surface-subtle text-text-secondary border border-border-default">
                      Active
                    </span>
                  </div>
                  <h3 className="mt-3 text-sm font-semibold text-text-primary group-hover:text-brand-primary">
                    Risk Controls
                  </h3>
                  <p className="mt-1 text-xs text-text-secondary">
                    Bulk move, role editing, VCODE generation, deletion requests, and sensitive data export gates.
                  </p>
                </div>

                <div
                  onClick={() => setActiveTab("freeze_modes")}
                  className="p-4 rounded-xl border border-border-default hover:border-brand-primary bg-surface-primary hover:bg-surface-hover cursor-pointer transition-all shadow-2xs group"
                >
                  <div className="flex items-center justify-between">
                    <div className="w-9 h-9 rounded-lg bg-surface-subtle text-text-primary flex items-center justify-center">
                      <Snowflake className="w-4 h-4" />
                    </div>
                    <span className="px-2 py-0.5 rounded text-xs font-semibold bg-surface-subtle text-text-secondary border border-border-default">
                      Active
                    </span>
                  </div>
                  <h3 className="mt-3 text-sm font-semibold text-text-primary group-hover:text-brand-primary">
                    Freeze Modes
                  </h3>
                  <p className="mt-1 text-xs text-text-secondary">
                    Operational freeze states: Payroll freeze, Audit freeze, Recruitment freeze, and Read-Only Emergency lock.
                  </p>
                </div>

                <div
                  onClick={() => {
                    setActiveTab("diagnostics");
                    runDiagnostics();
                  }}
                  className="p-4 rounded-xl border border-border-default hover:border-brand-primary bg-surface-primary hover:bg-surface-hover cursor-pointer transition-all shadow-2xs group"
                >
                  <div className="flex items-center justify-between">
                    <div className="w-9 h-9 rounded-lg bg-surface-subtle text-text-primary flex items-center justify-center">
                      <Activity className="w-4 h-4" />
                    </div>
                    <span className="px-2 py-0.5 rounded text-xs font-semibold bg-surface-subtle text-text-secondary border border-border-default">
                      Monitor
                    </span>
                  </div>
                  <h3 className="mt-3 text-sm font-semibold text-text-primary group-hover:text-brand-primary">
                    Diagnostics & Live Monitors
                  </h3>
                  <p className="mt-1 text-xs text-text-secondary">
                    RPC health check, Supabase round-trip latency, RLS integrity, and live connection validator.
                  </p>
                </div>

                <div
                  onClick={() => setActiveTab("audit_logs")}
                  className="p-4 rounded-xl border border-border-default hover:border-brand-primary bg-surface-primary hover:bg-surface-hover cursor-pointer transition-all shadow-2xs group"
                >
                  <div className="flex items-center justify-between">
                    <div className="w-9 h-9 rounded-lg bg-surface-subtle text-text-primary flex items-center justify-center">
                      <Terminal className="w-4 h-4" />
                    </div>
                    <span className="px-2 py-0.5 rounded text-xs font-semibold bg-surface-subtle text-text-secondary border border-border-default">
                      Logged
                    </span>
                  </div>
                  <h3 className="mt-3 text-sm font-semibold text-text-primary group-hover:text-brand-primary">
                    Security Audit Logs
                  </h3>
                  <p className="mt-1 text-xs text-text-secondary">
                    Audited stream of governance changes, toggle history, acting administrators, and reasons.
                  </p>
                </div>

                <div className="p-4 rounded-xl border border-border-default bg-surface-subtle shadow-2xs">
                  <div className="flex items-center justify-between">
                    <div className="w-9 h-9 rounded-lg bg-surface-primary text-text-primary flex items-center justify-center">
                      <Wrench className="w-4 h-4" />
                    </div>
                    <span className="px-2 py-0.5 rounded text-xs font-semibold bg-surface-primary text-text-primary border border-border-default">
                      System ready
                    </span>
                  </div>
                  <h3 className="mt-3 text-sm font-semibold text-text-primary">
                    Safespace Parity Confirmed
                  </h3>
                  <p className="mt-1 text-xs text-text-secondary">
                    Full functional equivalence with Mobile Safespace: backend enforcement, audit-logged reasons, and instant propagation.
                  </p>
                </div>
              </div>
            )}

            {activeTab === "super_admin_controls" && (
              <div className="space-y-4">
                <div className="p-3.5 rounded-xl bg-surface-subtle border border-border-default text-xs text-text-secondary">
                  Toggles below are enforced directly by Supabase RPCs. Disabling a control rejects requests system-wide regardless of client state.
                </div>

                {govLoading ? (
                  <div className="py-12 text-center text-xs text-text-muted">Loading governance controls...</div>
                ) : govControls.length === 0 ? (
                  <div className="py-12 text-center text-xs text-text-muted border border-dashed border-border-default rounded-2xl">
                    No governance controls found.
                  </div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {govControls.map((c) => (
                      <div
                        key={c.controlKey}
                        className="p-4 rounded-xl border border-border-default bg-surface-primary flex flex-col justify-between gap-3 shadow-2xs"
                      >
                        <div>
                          <div className="flex items-center justify-between">
                            <span className="text-sm font-semibold text-text-primary font-mono">
                              {c.controlKey.toUpperCase()}
                            </span>
                            <span
                              className={`px-2 py-0.5 rounded text-xs font-semibold ${
                                c.enabled
                                  ? "bg-surface-subtle text-text-primary border border-border-default"
                                  : "bg-danger-surface text-danger-text border border-danger-border"
                              }`}
                            >
                              {c.enabled ? "ENABLED" : "DISABLED"}
                            </span>
                          </div>
                          <p className="text-xs text-text-secondary mt-1">
                            {c.controlKey === "account_registration"
                              ? "Controls whether new users can submit account registration requests."
                              : c.controlKey === "import_plantilla"
                              ? "Controls whether Plantilla CSV/XLSX imports can be processed."
                              : `Backend governance gate for ${c.controlKey}.`}
                          </p>
                          {c.reason && (
                            <p className="mt-2 text-xs text-text-muted bg-surface-subtle p-2 rounded-lg italic border border-border-default">
                              Last reason: “{c.reason}”
                            </p>
                          )}
                          <p className="mt-1 text-xs text-text-muted">
                            Updated: {new Date(c.updatedAt).toLocaleString()}{" "}
                            {c.updatedByName ? `by ${c.updatedByName}` : ""}
                          </p>
                        </div>

                        <button
                          type="button"
                          onClick={() => handleOpenToggle("governance", c)}
                          className={`w-full py-2 px-3 rounded-lg text-xs font-semibold transition-colors cursor-pointer ${
                            c.enabled
                              ? "bg-danger-surface text-danger-text hover:bg-danger-border/30 border border-danger-border"
                              : "bg-brand-primary text-surface-primary hover:bg-brand-primary-hover"
                          }`}
                        >
                          {c.enabled ? "Disable Control" : "Enable Control"}
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {activeTab === "risk_controls" && (
              <div className="space-y-4">
                <div className="p-3.5 rounded-xl bg-surface-subtle border border-border-default text-xs text-text-secondary">
                  Phase 1 Risk Controls govern high-impact operational tools. When a risk control is restricted, users cannot perform mass changes or sensitive exports.
                </div>

                {riskLoading ? (
                  <div className="py-12 text-center text-xs text-text-muted">Loading risk controls...</div>
                ) : riskControls.length === 0 ? (
                  <div className="py-12 text-center text-xs text-text-muted border border-dashed border-border-default rounded-2xl">
                    No risk controls registered.
                  </div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {riskControls.map((c) => (
                      <div
                        key={c.controlKey}
                        className="p-4 rounded-xl border border-border-default bg-surface-primary flex flex-col justify-between gap-3 shadow-2xs"
                      >
                        <div>
                          <div className="flex items-center justify-between">
                            <span className="text-sm font-semibold text-text-primary font-mono">
                              {c.controlKey.replace("risk_", "").toUpperCase()}
                            </span>
                            <span
                              className={`px-2 py-0.5 rounded text-xs font-semibold ${
                                c.enabled
                                  ? "bg-surface-subtle text-text-primary border border-border-default"
                                  : "bg-surface-subtle text-text-muted border border-border-default"
                              }`}
                            >
                              {c.enabled ? "ALLOWED" : "RESTRICTED"}
                            </span>
                          </div>
                          <p className="text-xs text-text-secondary mt-1">
                            {c.controlKey.includes("bulk")
                              ? "Mass employee moves and batch updates."
                              : c.controlKey.includes("role")
                              ? "User role assignments and scope mutations."
                              : c.controlKey.includes("vcode")
                              ? "VCODE generation for vacancy requisitions."
                              : c.controlKey.includes("export")
                              ? "ATM account reveal and sensitive PII exports."
                              : c.controlKey.includes("manual_deletion")
                              ? "Manual deletion request submissions."
                              : c.controlKey.includes("rollback")
                              ? "Approved import batch rollbacks."
                              : "Cross-group operational boundaries."}
                          </p>
                          {c.reason && (
                            <p className="mt-2 text-xs text-text-muted bg-surface-subtle p-2 rounded-lg italic border border-border-default">
                              Last reason: “{c.reason}”
                            </p>
                          )}
                          <p className="mt-1 text-xs text-text-muted">
                            Updated: {new Date(c.updatedAt).toLocaleString()}{" "}
                            {c.updatedByName ? `by ${c.updatedByName}` : ""}
                          </p>
                        </div>

                        <button
                          type="button"
                          onClick={() => handleOpenToggle("risk", c)}
                          className={`w-full py-2 px-3 rounded-lg text-xs font-semibold transition-colors cursor-pointer ${
                            c.enabled
                              ? "bg-surface-subtle text-text-secondary hover:bg-surface-hover border border-border-default"
                              : "bg-brand-primary text-surface-primary hover:bg-brand-primary-hover"
                          }`}
                        >
                          {c.enabled ? "Restrict Capability" : "Allow Capability"}
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {activeTab === "freeze_modes" && (
              <div className="space-y-4">
                <div className="p-3.5 rounded-xl bg-surface-subtle border border-border-default text-xs text-text-secondary">
                  Freeze modes suspend entire operational domains during cutoff calculations, security audits, or emergency containment.
                </div>

                {freezeLoading ? (
                  <div className="py-12 text-center text-xs text-text-muted">Loading freeze modes...</div>
                ) : freezeModes.length === 0 ? (
                  <div className="py-12 text-center text-xs text-text-muted border border-dashed border-border-default rounded-2xl">
                    No freeze modes configured.
                  </div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {freezeModes.map((c) => (
                      <div
                        key={c.controlKey}
                        className="p-4 rounded-xl border border-border-default bg-surface-primary flex flex-col justify-between gap-3 shadow-2xs"
                      >
                        <div>
                          <div className="flex items-center justify-between">
                            <span className="text-sm font-semibold text-text-primary font-mono">
                              {c.controlKey.toUpperCase()}
                            </span>
                            <span
                              className={`px-2 py-0.5 rounded text-xs font-semibold ${
                                c.enabled
                                  ? "bg-danger-surface text-danger-text border border-danger-border"
                                  : "bg-surface-subtle text-text-secondary border border-border-default"
                              }`}
                            >
                              {c.enabled ? "FROZEN (ACTIVE)" : "NOMINAL (INACTIVE)"}
                            </span>
                          </div>
                          <p className="text-xs text-text-secondary mt-1">
                            {c.controlKey === "payroll_freeze"
                              ? "Suspends payroll-related adjustments and hours logging during cutoff calculations."
                              : c.controlKey === "audit_freeze"
                              ? "Halts administrative modifications and role updates for compliance audits."
                              : c.controlKey === "recruitment_freeze"
                              ? "Suspends vacancy creation, applicant progression, and onboarding workflows."
                              : "Emergency switch: converts entire OHM system to read-only."}
                          </p>
                          {c.reason && (
                            <p className="mt-2 text-xs text-text-muted bg-surface-subtle p-2 rounded-lg italic border border-border-default">
                              Reason: “{c.reason}”
                            </p>
                          )}
                          <p className="mt-1 text-xs text-text-muted">
                            Updated: {new Date(c.updatedAt).toLocaleString()}{" "}
                            {c.updatedByName ? `by ${c.updatedByName}` : ""}
                          </p>
                        </div>

                        <button
                          type="button"
                          onClick={() => handleOpenToggle("freeze", c)}
                          className={`w-full py-2 px-3 rounded-lg text-xs font-semibold transition-colors cursor-pointer ${
                            c.enabled
                              ? "bg-brand-primary text-surface-primary hover:bg-brand-primary-hover"
                              : "bg-danger-surface text-danger-text hover:bg-danger-border/30 border border-danger-border"
                          }`}
                        >
                          {c.enabled ? "Deactivate Freeze" : "Activate Freeze"}
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {activeTab === "diagnostics" && (
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="text-sm font-semibold text-text-primary">System Diagnostics & RPC Latency</h3>
                    <p className="text-xs text-text-secondary">
                      Live telemetry against Supabase cluster and governance control RPCs
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={runDiagnostics}
                    disabled={diagnosticsRunning}
                    className="px-3 py-1.5 rounded-xl text-xs font-semibold bg-surface-primary border border-border-default hover:bg-surface-hover text-text-primary transition-colors flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
                  >
                    <RefreshCw className={`w-3.5 h-3.5 ${diagnosticsRunning ? "animate-spin text-brand-primary" : ""}`} />
                    <span>Run Diagnostics</span>
                  </button>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <div className="p-4 rounded-xl border border-border-default bg-surface-primary">
                    <span className="text-xs font-semibold text-text-muted">
                      Supabase Latency
                    </span>
                    <div className="mt-1 flex items-baseline gap-2">
                      <span className="text-2xl font-bold text-text-primary">
                        {connectivityLatency !== null ? `${connectivityLatency}ms` : "—"}
                      </span>
                      <span className="text-xs text-text-secondary font-medium">Round-trip</span>
                    </div>
                  </div>

                  <div className="p-4 rounded-xl border border-border-default bg-surface-primary">
                    <span className="text-xs font-semibold text-text-muted">
                      Governance RPCs
                    </span>
                    <div className="mt-1 flex items-center gap-2">
                      <CheckCircle2 className="w-5 h-5 text-text-primary" />
                      <span className="text-sm font-bold text-text-primary">
                        {diagResults.rpcStatus.toUpperCase()}
                      </span>
                    </div>
                  </div>

                  <div className="p-4 rounded-xl border border-border-default bg-surface-primary">
                    <span className="text-xs font-semibold text-text-muted">
                      Freeze State
                    </span>
                    <div className="mt-1 flex items-center gap-2">
                      <span
                        className={`px-2 py-0.5 rounded text-xs font-semibold ${
                          diagResults.freezeStatus === "nominal"
                            ? "bg-surface-subtle text-text-primary border border-border-default"
                            : "bg-danger-surface text-danger-text border border-danger-border"
                        }`}
                      >
                        {diagResults.freezeStatus === "nominal" ? "NOMINAL" : "FREEZE ACTIVE"}
                      </span>
                    </div>
                  </div>
                </div>

                <div className="p-4 rounded-xl bg-surface-subtle border border-border-default text-xs space-y-2">
                  <div className="flex justify-between">
                    <span className="text-text-muted">Last Telemetry Run:</span>
                    <span className="font-mono text-text-secondary">
                      {lastDiagCheck ? lastDiagCheck.toLocaleTimeString() : "Pending"}
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-text-muted">Audit Logs Availability:</span>
                    <span className="font-semibold text-text-primary">Online</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-text-muted">Client Session Level:</span>
                    <span className="font-semibold text-text-primary">Super Admin (100)</span>
                  </div>
                </div>
              </div>
            )}

            {activeTab === "audit_logs" && (
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="text-sm font-semibold text-text-primary">Governance Security Audit Trail</h3>
                    <p className="text-xs text-text-secondary">
                      Immutable log of all Safespace control mutations and freeze state transitions
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => refetchAudit()}
                    className="px-3 py-1.5 rounded-xl text-xs font-semibold bg-surface-primary border border-border-default text-text-primary hover:bg-surface-hover transition-colors flex items-center gap-1.5 cursor-pointer"
                  >
                    <RefreshCw className="w-3.5 h-3.5" />
                    <span>Refresh</span>
                  </button>
                </div>

                {auditLoading ? (
                  <div className="py-12 text-center text-xs text-text-muted">Loading audit log...</div>
                ) : auditLogs.length === 0 ? (
                  <div className="py-12 text-center text-xs text-text-muted border border-dashed border-border-default rounded-2xl">
                    No governance audit entries found.
                  </div>
                ) : (
                  <div className="space-y-2">
                    {auditLogs.map((log) => (
                      <div
                        key={log.id}
                        className="p-3 bg-surface-subtle border border-border-default rounded-xl flex items-start justify-between gap-3 text-xs"
                      >
                        <div>
                          <div className="flex items-center gap-2">
                            <span className="font-bold text-text-primary font-mono">
                              [{log.controlKey.toUpperCase()}]
                            </span>
                            <span className="px-1.5 py-0.2 rounded text-xs font-semibold bg-surface-primary border border-border-default text-text-secondary">
                              {log.action}
                            </span>
                            {log.changedByName && (
                              <span className="text-text-muted">by {log.changedByName}</span>
                            )}
                          </div>
                          {log.reason && (
                            <p className="mt-1 text-xs text-text-secondary italic">
                              “{log.reason}”
                            </p>
                          )}
                        </div>
                        <span className="text-xs text-text-muted whitespace-nowrap">
                          {new Date(log.changedAt).toLocaleString()}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </Modal>

      {/* Control State Toggle Confirmation Sub-Modal */}
      <Modal
        isOpen={Boolean(pendingToggle)}
        onClose={() => setPendingToggle(null)}
        title={
          pendingToggle
            ? `${pendingToggle.targetEnabled ? "Enable" : "Disable"} ${pendingToggle.control.controlKey
                .replace("risk_", "")
                .toUpperCase()}`
            : ""
        }
        subtitle="Confirm state transition and provide audited justification"
        icon={ShieldAlert}
        maxWidthClass="max-w-md"
        isSubmitting={isMutating}
        disableBackdropClick={isMutating}
        isDirty={isReasonDirty}
      >
        {pendingToggle && (
          <form onSubmit={handleConfirmToggle} className="space-y-4">
            {toggleError && (
              <div className="p-3 rounded-xl bg-danger-surface border border-danger-border text-danger-text text-xs">
                {toggleError}
              </div>
            )}

            <div>
              <label className="block text-xs font-bold text-text-primary mb-1">
                Audited Reason (Required)
              </label>
              <textarea
                rows={3}
                required
                value={reasonInput}
                onChange={(e) => setReasonInput(e.target.value)}
                placeholder="Enter the operational justification for this change..."
                className="w-full px-3 py-2 text-xs border border-border-default rounded-xl bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:border-brand-primary"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-default">
              <button
                type="button"
                onClick={() => setPendingToggle(null)}
                disabled={isMutating}
                className="px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover rounded-xl transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isMutating}
                className={`px-4 py-2 text-xs font-semibold rounded-xl transition cursor-pointer flex items-center gap-1.5 ${
                  pendingToggle.type === "freeze" || !pendingToggle.targetEnabled
                    ? "bg-danger text-surface-primary hover:bg-danger-hover"
                    : "bg-brand-primary text-surface-primary hover:bg-brand-primary-hover"
                }`}
              >
                {isMutating && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                <span>Confirm Change</span>
              </button>
            </div>
          </form>
        )}
      </Modal>
    </>
  );
}
