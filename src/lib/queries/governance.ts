import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ============================================================================
// Types: QA Center
// ============================================================================

export interface QaScenarioStep {
  step: number;
  role: string;
  action: string;
  status: "passed" | "failed";
  details: string;
}

export interface QaScenarioRunResult {
  success: boolean;
  run_id: string;
  scenario_code: string;
  sandbox_rolled_back: boolean;
  steps: QaScenarioStep[];
  finding_counts: {
    critical?: number;
    high?: number;
    medium?: number;
    low?: number;
    total?: number;
  };
  executed_at: string;
  // Ergonomic camelCase aliases for React UI components
  runId?: string;
  scenarioCode?: string;
  sandboxRolledBack?: boolean;
  findingCounts?: {
    critical?: number;
    high?: number;
    medium?: number;
    low?: number;
    total?: number;
  };
  executedAt?: string;
}

export interface QaRunSummary {
  id: string;
  agentName: string;
  status: string;
  targetModule: string;
  findingCount: number;
  criticalCount: number;
  highCount: number;
  mediumCount: number;
  lowCount: number;
  startedAt: string | null;
  completedAt: string | null;
  summary?: string | null;
  executionType?: string;
  rolledBack?: boolean;
  stepsCount?: number;
}

export interface QaFinding {
  id: string;
  findingCode: string;
  findingType?: string;
  category: string;
  severity: "critical" | "high" | "medium" | "low";
  moduleName: string;
  status: string;
  title: string;
  details: string | null;
  recommendation?: string | null;
  referenceTable?: string | null;
  referenceRecordId?: string | null;
  runId?: string | null;
  createdAt: string | null;
}

export interface QaSchedule {
  id: string;
  scheduleName: string;
  cronExpression: string;
  frequency?: string;
  runTime?: string | null;
  targetModule: string;
  suiteName?: string;
  isActive: boolean;
  isEnabled?: boolean;
  lastRunAt: string | null;
  nextRunAt: string | null;
}

export interface QaQueueItem {
  id: string;
  scheduleId: string | null;
  status: string;
  queueStatus?: string;
  suiteName?: string;
  runId?: string | null;
  priority: number;
  retryCount?: number;
  maxRetries?: number;
  queuedAt: string | null;
  startedAt: string | null;
  errorMessage: string | null;
}

export interface QaDailyReport {
  id: string;
  reportDate: string;
  environment: string;
  healthScore: number | null;
  totalRuns: number;
  passedRuns: number;
  failedRuns: number;
  criticalFindings: number;
  criticalCount?: number;
  executiveSummary: string | null;
  createdAt: string | null;
  generatedAt?: string | null;
}

export interface QaNotification {
  id: string;
  title: string;
  message: string;
  severity: string;
  createdAt: string;
}

export interface QaHealthMetric {
  id: string;
  metricName: string;
  metricValue: number;
  metricUnit: string;
  metricDate: string;
}

export interface QaUnstableModule {
  moduleName: string;
  findingCount: number;
  failureRate: number;
}

export interface QaFlakyTest {
  testCode: string;
  moduleName: string;
  occurrenceCount: number;
  lastFailedAt: string | null;
}

export interface QaCenterSnapshot {
  runs: QaRunSummary[];
  findings: QaFinding[];
  schedules: QaSchedule[];
  queueItems: QaQueueItem[];
  reports: QaDailyReport[];
  notifications: QaNotification[];
  healthMetrics: QaHealthMetric[];
  unstableModules: QaUnstableModule[];
  flakyTests: QaFlakyTest[];
}

// ============================================================================
// Types: Permission Matrix & Role Permissions
// ============================================================================

export interface RoleEntry {
  id: string;
  name: string;
  level: number;
}

export interface EffectivePermissionRow {
  roleName: string;
  roleLevel: number;
  moduleKey: string;
  resourceKey: string;
  actionKey: string;
  scopeMode: string;
  enforcementTier: string;
  baseAllowed: boolean;
  overrideAllowed: boolean | null;
  isAllowed: boolean;
  sourceType: string;
  hasOverride: boolean;
  isSensitive: boolean;
  isSystemLocked: boolean;
  description: string | null;
  sortOrder: number;
  overrideReason: string | null;
}

export interface PendingPermissionChange {
  roleName: string;
  moduleKey: string;
  resourceKey: string;
  actionKey: string;
  targetAllowed: boolean;
}

export interface RolePermissionMatrixItem {
  roleName: string;
  roleLevel: number;
  moduleKey: string;
  resourceKey: string;
  actionKey: string;
  scopeMode: string;
  enforcementType: string;
  isAllowed: boolean;
  sourceType: string;
  isSensitive: boolean;
  isSystemLocked: boolean;
  description: string | null;
  sortOrder: number;
}

// ============================================================================
// Types: Permission Drift
// ============================================================================

export interface PermissionDriftEvidence {
  evidenceType: string;
  evidenceKey: string;
  evidenceValue: string;
  filePath: string | null;
  lineNote: string | null;
}

export interface PermissionDriftFinding {
  findingId: string;
  findingCode: string;
  driftCategory: string;
  severity: "critical" | "high" | "medium" | "low" | string;
  status: "open" | "resolved" | "accepted_risk" | string;
  moduleKey: string;
  resourceKey: string;
  actionKey: string;
  roleName: string | null;
  expectedEnforcement: string;
  observedEnforcement: string;
  findingSummary: string;
  recommendation: string;
  evidence: PermissionDriftEvidence[];
  acceptedRiskReason: string | null;
  createdAt: string;
  resolvedAt: string | null;
}

export interface PermissionDriftSummary {
  totalFindings: number;
  openFindings: number;
  criticalCount: number;
  highCount: number;
  mediumCount: number;
  lowCount: number;
  resolvedCount: number;
  acceptedRiskCount: number;
}

// ============================================================================
// Types: Security Events
// ============================================================================

export interface SecurityEventItem {
  id: string;
  eventType: string;
  severity: "critical" | "high" | "medium" | "low" | string;
  actorId: string | null;
  actorName?: string | null;
  actorRole?: string | null;
  targetId: string | null;
  action: string;
  details: Record<string, unknown> | null;
  happenedAt: string;
}

export interface SecurityEventsSummary {
  totalEvents: number;
  criticalHighCount: number;
  suspiciousLogins: number;
  terminatedSessions: number;
}

// ============================================================================
// Types: Audit Logs
// ============================================================================

export interface SystemAuditLogItem {
  id: string;
  actorId: string | null;
  actorName: string | null;
  actorRole: string | null;
  module: string;
  action: string;
  recordId: string | null;
  oldData: Record<string, unknown> | null;
  newData: Record<string, unknown> | null;
  timestamp: string;
}

// ============================================================================
// Queries & Mutations: QA Center
// ============================================================================

export async function fetchQaCenterSnapshot(): Promise<QaCenterSnapshot> {
  const supabase = createClient();

  const [
    runsRes,
    findingsRes,
    schedulesRes,
    queueRes,
    reportsRes,
    notifsRes,
    metricsRes,
    unstableRes,
    flakyRes,
  ] = await Promise.allSettled([
    supabase
      .from("v_qa_detection_run_summary")
      .select("*")
      .order("started_at", { ascending: false })
      .limit(25),
    supabase
      .from("v_qa_open_findings")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(50),
    supabase
      .from("v_qa_schedules")
      .select("*")
      .order("schedule_name", { ascending: true })
      .limit(20),
    supabase
      .from("v_qa_run_queue")
      .select("*")
      .order("queued_at", { ascending: false })
      .limit(30),
    supabase
      .from("v_qa_daily_reports")
      .select("*")
      .order("report_date", { ascending: false })
      .limit(20),
    supabase
      .from("v_qa_notifications")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(30),
    supabase
      .from("v_qa_health_metrics")
      .select("*")
      .order("metric_date", { ascending: false })
      .limit(20),
    supabase
      .from("v_qa_unstable_modules")
      .select("*")
      .order("finding_count", { ascending: false })
      .limit(10),
    supabase
      .from("v_qa_flaky_tests")
      .select("*")
      .order("occurrence_count", { ascending: false })
      .limit(25),
  ]);

  const runs: QaRunSummary[] =
    runsRes.status === "fulfilled" && runsRes.value.data
      ? runsRes.value.data.map((r: Record<string, unknown>) => ({
          id: String(r.id ?? ""),
          agentName: String(r.agent_name ?? "QA Core Agent"),
          status: String(r.status ?? "unknown"),
          targetModule: String(r.target_module ?? "all"),
          findingCount: Number(r.finding_count ?? 0),
          criticalCount: Number(r.critical_count ?? 0),
          highCount: Number(r.high_count ?? 0),
          mediumCount: Number(r.medium_count ?? 0),
          lowCount: Number(r.low_count ?? 0),
          startedAt: r.started_at ? String(r.started_at) : null,
          completedAt: r.completed_at ? String(r.completed_at) : null,
          summary: r.summary ? String(r.summary) : null,
          executionType: r.execution_type ? String(r.execution_type) : undefined,
        }))
      : [];

  const findings: QaFinding[] =
    findingsRes.status === "fulfilled" && findingsRes.value.data
      ? findingsRes.value.data.map((f: Record<string, unknown>) => {
          const findingType = String(f.finding_type ?? f.finding_code ?? f.code ?? "QA_FINDING");
          return {
            id: String(f.id ?? ""),
            findingCode: findingType,
            findingType,
            category: String(f.category ?? f.finding_type ?? "General"),
            severity: (f.severity as "critical" | "high" | "medium" | "low") ?? "medium",
            moduleName: String(f.module_name ?? f.module ?? "System"),
            status: String(f.status ?? "open"),
            title: String(f.title ?? f.finding_summary ?? "Detected Anomaly"),
            details: f.details || f.error_message ? String(f.details ?? f.error_message) : null,
            recommendation: f.recommendation ? String(f.recommendation) : null,
            referenceTable: f.reference_table ? String(f.reference_table) : null,
            referenceRecordId: f.reference_record_id ? String(f.reference_record_id) : null,
            runId: f.run_id ? String(f.run_id) : null,
            createdAt: f.created_at ? String(f.created_at) : null,
          };
        })
      : [];

  const schedules: QaSchedule[] =
    schedulesRes.status === "fulfilled" && schedulesRes.value.data
      ? schedulesRes.value.data.map((s: Record<string, unknown>) => {
          const frequency = s.frequency ? String(s.frequency) : "";
          const runTime = s.run_time ? String(s.run_time) : "";
          const cronExpression = String(
            s.cron_expression ?? (runTime ? `${frequency} at ${runTime}` : frequency || "@daily")
          );
          const suiteName = String(s.suite_name ?? s.target_module ?? "all");
          const isEnabled = Boolean(s.is_enabled ?? s.is_active ?? true);
          return {
            id: String(s.id ?? ""),
            scheduleName: String(s.schedule_name ?? "Scheduled Run"),
            cronExpression,
            frequency: frequency || undefined,
            runTime: runTime || null,
            targetModule: suiteName,
            suiteName,
            isActive: isEnabled,
            isEnabled,
            lastRunAt: s.last_run_at ? String(s.last_run_at) : null,
            nextRunAt: s.next_run_at ? String(s.next_run_at) : null,
          };
        })
      : [];

  const queueItems: QaQueueItem[] =
    queueRes.status === "fulfilled" && queueRes.value.data
      ? queueRes.value.data.map((q: Record<string, unknown>) => {
          const queueStatus = String(q.queue_status ?? q.status ?? "queued");
          return {
            id: String(q.id ?? ""),
            scheduleId: q.schedule_id ? String(q.schedule_id) : null,
            status: queueStatus,
            queueStatus,
            suiteName: q.suite_name ? String(q.suite_name) : undefined,
            runId: q.run_id ? String(q.run_id) : null,
            priority: Number(q.priority ?? 0),
            retryCount: q.retry_count != null ? Number(q.retry_count) : undefined,
            maxRetries: q.max_retries != null ? Number(q.max_retries) : undefined,
            queuedAt: q.queued_at ? String(q.queued_at) : null,
            startedAt: q.started_at ? String(q.started_at) : null,
            errorMessage: q.error_message ? String(q.error_message) : null,
          };
        })
      : [];

  const reports: QaDailyReport[] =
    reportsRes.status === "fulfilled" && reportsRes.value.data
      ? reportsRes.value.data.map((dr: Record<string, unknown>) => {
          const createdAt = (dr.generated_at ?? dr.created_at) ? String(dr.generated_at ?? dr.created_at) : null;
          const criticalCount = Number(dr.critical_count ?? dr.critical_findings ?? 0);
          const executiveSummary = dr.executive_summary
            ? String(dr.executive_summary)
            : dr.health_status
            ? `Status: ${dr.health_status}${dr.most_unstable_workflow ? ` • Unstable: ${dr.most_unstable_workflow}` : ""}`
            : null;
          return {
            id: String(dr.id ?? ""),
            reportDate: String(dr.report_date ?? ""),
            environment: String(dr.environment ?? "staging"),
            healthScore: dr.health_score != null ? Number(dr.health_score) : null,
            totalRuns: Number(dr.total_runs ?? 0),
            passedRuns: Number(dr.passed_runs ?? 0),
            failedRuns: Number(dr.failed_runs ?? 0),
            criticalFindings: criticalCount,
            criticalCount,
            executiveSummary,
            createdAt,
            generatedAt: createdAt,
          };
        })
      : [];

  const notifications: QaNotification[] =
    notifsRes.status === "fulfilled" && notifsRes.value.data
      ? notifsRes.value.data.map((n: Record<string, unknown>) => ({
          id: String(n.id ?? ""),
          title: String(n.title ?? "QA Notice"),
          message: String(n.message ?? ""),
          severity: String(n.severity ?? "info"),
          createdAt: String(n.created_at ?? new Date().toISOString()),
        }))
      : [];

  const healthMetrics: QaHealthMetric[] =
    metricsRes.status === "fulfilled" && metricsRes.value.data
      ? metricsRes.value.data.map((m: Record<string, unknown>) => ({
          id: String(m.id ?? ""),
          metricName: String(m.metric_name ?? ""),
          metricValue: Number(m.metric_value ?? 0),
          metricUnit: String(m.metric_unit ?? "%"),
          metricDate: String(m.metric_date ?? ""),
        }))
      : [];

  const unstableModules: QaUnstableModule[] =
    unstableRes.status === "fulfilled" && unstableRes.value.data
      ? unstableRes.value.data.map((u: Record<string, unknown>) => ({
          moduleName: String(u.module_name ?? ""),
          findingCount: Number(u.finding_count ?? 0),
          failureRate: Number(u.failure_rate ?? 0),
        }))
      : [];

  const flakyTests: QaFlakyTest[] =
    flakyRes.status === "fulfilled" && flakyRes.value.data
      ? flakyRes.value.data.map((fl: Record<string, unknown>) => ({
          testCode: String(fl.test_code ?? ""),
          moduleName: String(fl.module_name ?? ""),
          occurrenceCount: Number(fl.occurrence_count ?? 0),
          lastFailedAt: fl.last_failed_at ? String(fl.last_failed_at) : null,
        }))
      : [];

  return {
    runs,
    findings,
    schedules,
    queueItems,
    reports,
    notifications,
    healthMetrics,
    unstableModules,
    flakyTests,
  };
}

export function useQaCenterSnapshot() {
  return useQuery({
    queryKey: ["qa-center-snapshot"],
    queryFn: fetchQaCenterSnapshot,
    staleTime: 15_000,
  });
}

export async function runQaCoreDetectionSuiteRpc() {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("qa_run_core_detection_suite");
  if (error) throw error;
  return data;
}

export function useRunQaCoreDetectionSuite() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: runQaCoreDetectionSuiteRpc,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["qa-center-snapshot"] });
    },
  });
}

export async function runQaScenarioRpc(scenarioCode: string): Promise<QaScenarioRunResult> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("qa_run_scenario", {
    p_scenario_code: scenarioCode.trim(),
  });
  if (error) throw error;

  const raw = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;

  // Defend against null, undefined, primitive, or array items inside steps array
  const rawSteps = Array.isArray(raw.steps)
    ? raw.steps.filter(
        (s): s is Record<string, unknown> => s !== null && typeof s === "object" && !Array.isArray(s)
      )
    : [];

  const steps: QaScenarioStep[] = rawSteps.map((s: Record<string, unknown>, idx: number) => {
    const rawStepNum = Number(s?.step);
    const step = Number.isFinite(rawStepNum) && rawStepNum > 0 ? Math.floor(rawStepNum) : idx + 1;
    const rawStatus = typeof s?.status === "string" ? s.status.trim().toLowerCase() : "";
    const status: "passed" | "failed" = rawStatus === "failed" ? "failed" : "passed";

    return {
      step,
      role: String(s?.role ?? "System"),
      action: String(s?.action ?? "unknown_action"),
      status,
      details: String(s?.details ?? ""),
    };
  });

  // Defend against non-object or malformed finding_counts
  const rawCounts = (raw.finding_counts &&
  typeof raw.finding_counts === "object" &&
  !Array.isArray(raw.finding_counts)
    ? raw.finding_counts
    : {}) as Record<string, unknown>;

  const toSafeCount = (val: unknown): number => {
    const num = Number(val);
    return Number.isFinite(num) && num >= 0 ? Math.floor(num) : 0;
  };

  const critical = toSafeCount(rawCounts.critical);
  const high = toSafeCount(rawCounts.high);
  const medium = toSafeCount(rawCounts.medium);
  const low = toSafeCount(rawCounts.low);
  const rawTotal = toSafeCount(rawCounts.total);
  const total = rawTotal > 0 ? rawTotal : critical + high + medium + low;

  const findingCounts = {
    critical,
    high,
    medium,
    low,
    total,
  };

  const success = Boolean(raw.success);
  const runId = String(raw.run_id ?? "");
  const scenarioCodeResolved = String(raw.scenario_code ?? scenarioCode);
  const sandboxRolledBack = Boolean(raw.sandbox_rolled_back);
  const executedAt = String(raw.executed_at ?? new Date().toISOString());

  return {
    success,
    run_id: runId,
    scenario_code: scenarioCodeResolved,
    sandbox_rolled_back: sandboxRolledBack,
    steps,
    finding_counts: findingCounts,
    executed_at: executedAt,
    // Convenience aliases
    runId,
    scenarioCode: scenarioCodeResolved,
    sandboxRolledBack,
    findingCounts,
    executedAt,
  };
}

export function useRunQaScenario() {
  const queryClient = useQueryClient();
  return useMutation<QaScenarioRunResult, Error, string>({
    mutationFn: runQaScenarioRpc,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["qa-center-snapshot"] });
    },
  });
}

export const useRunQaScenarioMutation = useRunQaScenario;

export async function generateDailyQaReportRpc(environment = "staging") {
  const supabase = createClient();
  const today = new Date().toISOString().substring(0, 10);
  const { data, error } = await supabase.rpc("generate_daily_qa_report", {
    p_report_date: today,
    p_environment: environment,
  });
  if (error) throw error;
  return data;
}

export function useGenerateDailyQaReport() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (environment: string = "staging") => generateDailyQaReportRpc(environment),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["qa-center-snapshot"] });
    },
  });
}


// ============================================================================
// Queries & Mutations: Permission Matrix & Roles
// ============================================================================

export async function fetchGovernanceRoles(): Promise<RoleEntry[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("roles")
    .select("id, role_name, role_level")
    .order("role_level", { ascending: false });

  if (error || !data) return [];
  return data.map((r: Record<string, unknown>) => ({
    id: String(r.id),
    name: String(r.role_name ?? "Unknown Role"),
    level: Number(r.role_level ?? 0),
  }));
}

export function useGovernanceRoles() {
  return useQuery({
    queryKey: ["governance-roles"],
    queryFn: fetchGovernanceRoles,
    staleTime: 60_000,
  });
}

export async function fetchEffectivePermissionMatrix(roleName: string): Promise<EffectivePermissionRow[]> {
  if (!roleName) return [];
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_effective_permission_matrix", {
    p_role_name: roleName,
  });

  if (error || !data) {
    if (error) console.error("Error fetching effective permission matrix:", error);
    return [];
  }

  return (data as Record<string, unknown>[]).map((m) => ({
    roleName: String(m.role_name ?? roleName),
    roleLevel: Number(m.role_level ?? 0),
    moduleKey: String(m.module_key ?? ""),
    resourceKey: String(m.resource_key ?? ""),
    actionKey: String(m.action_key ?? ""),
    scopeMode: String(m.scope_mode ?? "global"),
    enforcementTier: String(m.enforcement_tier ?? "standard"),
    baseAllowed: Boolean(m.base_allowed ?? false),
    overrideAllowed: m.override_allowed != null ? Boolean(m.override_allowed) : null,
    isAllowed: Boolean(m.is_allowed ?? false),
    sourceType: String(m.source_type ?? "base"),
    hasOverride: Boolean(m.has_override ?? false),
    isSensitive: Boolean(m.is_sensitive ?? false),
    isSystemLocked: Boolean(m.is_system_locked ?? false),
    description: m.description ? String(m.description) : null,
    sortOrder: Number(m.sort_order ?? 0),
    overrideReason: m.override_reason ? String(m.override_reason) : null,
  }));
}

export function useEffectivePermissionMatrix(roleName: string | null) {
  return useQuery({
    queryKey: ["effective-permission-matrix", roleName],
    queryFn: () => (roleName ? fetchEffectivePermissionMatrix(roleName) : Promise.resolve([])),
    enabled: Boolean(roleName),
    staleTime: 30_000,
  });
}

export async function applyPermissionOverridesRpc(params: {
  changes: {
    role_name: string;
    module_key: string;
    resource_key: string;
    action_key: string;
    is_allowed: boolean;
  }[];
  reason?: string;
}) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("apply_permission_overrides", {
    p_changes: params.changes,
    p_reason: params.reason || "Audited override via Web Governance Center",
  });
  if (error) throw error;
  return data;
}

export function useApplyPermissionOverrides() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: applyPermissionOverridesRpc,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["effective-permission-matrix"] });
      queryClient.invalidateQueries({ queryKey: ["role-permission-matrix"] });
    },
  });
}

// ============================================================================
// Queries: Role Permissions (Read-Only Matrix)
// ============================================================================

export async function fetchRolePermissionMatrix(roleId: string): Promise<RolePermissionMatrixItem[]> {
  if (!roleId) return [];
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_permission_matrix", {
    p_role_id: roleId,
  });

  if (error || !data) {
    if (error) console.error("Error fetching role permission matrix:", error);
    return [];
  }

  return (data as Record<string, unknown>[]).map((m) => ({
    roleName: String(m.role_name ?? ""),
    roleLevel: Number(m.role_level ?? 0),
    moduleKey: String(m.module_key ?? ""),
    resourceKey: String(m.resource_key ?? ""),
    actionKey: String(m.action_key ?? ""),
    scopeMode: String(m.scope_mode ?? "global"),
    enforcementType: String(m.enforcement_type ?? "standard"),
    isAllowed: Boolean(m.is_allowed ?? false),
    sourceType: String(m.source_type ?? "base"),
    isSensitive: Boolean(m.is_sensitive ?? false),
    isSystemLocked: Boolean(m.is_system_locked ?? false),
    description: m.description ? String(m.description) : null,
    sortOrder: Number(m.sort_order ?? 0),
  }));
}

export function useRolePermissionMatrix(roleId: string | null) {
  return useQuery({
    queryKey: ["role-permission-matrix", roleId],
    queryFn: () => (roleId ? fetchRolePermissionMatrix(roleId) : Promise.resolve([])),
    enabled: Boolean(roleId),
    staleTime: 30_000,
  });
}

// ============================================================================
// Queries: Permission Drift
// ============================================================================

export async function fetchPermissionDriftSummary(): Promise<PermissionDriftSummary> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_permission_drift_summary");
  if (error || !data) {
    return {
      totalFindings: 0,
      openFindings: 0,
      criticalCount: 0,
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      resolvedCount: 0,
      acceptedRiskCount: 0,
    };
  }

  const row = Array.isArray(data) ? (data[0] as Record<string, unknown>) : (data as Record<string, unknown>);
  return {
    totalFindings: Number(row?.total_findings ?? row?.total ?? 0),
    openFindings: Number(row?.open_findings ?? row?.open ?? 0),
    criticalCount: Number(row?.critical_count ?? row?.critical ?? 0),
    highCount: Number(row?.high_count ?? row?.high ?? 0),
    mediumCount: Number(row?.medium_count ?? row?.medium ?? 0),
    lowCount: Number(row?.low_count ?? row?.low ?? 0),
    resolvedCount: Number(row?.resolved_count ?? row?.resolved ?? 0),
    acceptedRiskCount: Number(row?.accepted_risk_count ?? row?.accepted_risk ?? 0),
  };
}

export function usePermissionDriftSummary() {
  return useQuery({
    queryKey: ["permission-drift-summary"],
    queryFn: fetchPermissionDriftSummary,
    staleTime: 30_000,
  });
}

export async function fetchPermissionDriftFindings(params?: {
  status?: string;
  severity?: string;
  moduleKey?: string;
}): Promise<PermissionDriftFinding[]> {
  const supabase = createClient();
  const rpcParams: Record<string, string> = {};
  if (params?.status && params.status !== "all") {
    rpcParams.p_status = params.status;
  }
  if (params?.severity && params.severity !== "all") {
    rpcParams.p_severity = params.severity;
  }
  if (params?.moduleKey && params.moduleKey !== "all") {
    rpcParams.p_module_key = params.moduleKey;
  }

  const { data, error } = await supabase.rpc("fn_get_permission_drift_findings", rpcParams);
  if (error || !data) return [];

  return (data as Record<string, unknown>[]).map((m) => {
    const rawEvidence = m.evidence;
    const parsedEvidence: PermissionDriftEvidence[] = Array.isArray(rawEvidence)
      ? rawEvidence.map((e: Record<string, unknown>) => ({
          evidenceType: String(e.evidence_type ?? ""),
          evidenceKey: String(e.evidence_key ?? ""),
          evidenceValue: String(e.evidence_value ?? ""),
          filePath: e.file_path ? String(e.file_path) : null,
          lineNote: e.line_note ? String(e.line_note) : null,
        }))
      : [];

    return {
      findingId: String(m.finding_id ?? m.id ?? ""),
      findingCode: String(m.finding_code ?? ""),
      driftCategory: String(m.drift_category ?? "Enforcement Gap"),
      severity: String(m.severity ?? "medium"),
      status: String(m.status ?? "open"),
      moduleKey: String(m.module_key ?? ""),
      resourceKey: String(m.resource_key ?? ""),
      actionKey: String(m.action_key ?? ""),
      roleName: m.role_name ? String(m.role_name) : null,
      expectedEnforcement: String(m.expected_enforcement ?? "Required"),
      observedEnforcement: String(m.observed_enforcement ?? "Missing or Relaxed"),
      findingSummary: String(m.finding_summary ?? ""),
      recommendation: String(m.recommendation ?? ""),
      evidence: parsedEvidence,
      acceptedRiskReason: m.accepted_risk_reason ? String(m.accepted_risk_reason) : null,
      createdAt: String(m.created_at ?? new Date().toISOString()),
      resolvedAt: m.resolved_at ? String(m.resolved_at) : null,
    };
  });
}

export function usePermissionDriftFindings(params?: {
  status?: string;
  severity?: string;
  moduleKey?: string;
}) {
  return useQuery({
    queryKey: ["permission-drift-findings", params?.status, params?.severity, params?.moduleKey],
    queryFn: () => fetchPermissionDriftFindings(params),
    staleTime: 30_000,
  });
}

// ============================================================================
// Queries: Security Events Stream
// ============================================================================

export async function fetchSecurityEvents(params?: {
  severity?: string;
  limit?: number;
  dateRangeDays?: number;
}): Promise<SecurityEventItem[]> {
  const supabase = createClient();
  let query = supabase
    .from("security_events")
    .select("id, event_type, severity, actor_id, target_id, action, details, happened_at");

  if (params?.severity && params.severity !== "all") {
    query = query.eq("severity", params.severity);
  }

  if (params?.dateRangeDays && params.dateRangeDays > 0) {
    const cutoff = new Date(Date.now() - params.dateRangeDays * 24 * 60 * 60 * 1000).toISOString();
    query = query.gte("happened_at", cutoff);
  }

  const { data, error } = await query
    .order("happened_at", { ascending: false })
    .limit(params?.limit ?? 50);

  if (error || !data) return [];

  // Fetch unique actor profiles for display names
  const actorIds = Array.from(new Set(data.map((d: Record<string, unknown>) => d.actor_id).filter(Boolean)));
  const profilesMap: Record<string, { fullName: string; roleName: string }> = {};

  if (actorIds.length > 0) {
    const { data: profiles } = await supabase
      .from("users_profile")
      .select("id, auth_user_id, full_name, roles:role_id(role_name)")
      .or(`id.in.(${actorIds.join(",")}),auth_user_id.in.(${actorIds.join(",")})`);

    if (profiles) {
      for (const p of profiles as Record<string, unknown>[]) {
        const roleObj = p.roles as Record<string, unknown> | null;
        const info = {
          fullName: String(p.full_name ?? "User"),
          roleName: String(roleObj?.role_name ?? "Unknown"),
        };
        if (p.id) profilesMap[String(p.id)] = info;
        if (p.auth_user_id) profilesMap[String(p.auth_user_id)] = info;
      }
    }
  }

  return (data as Record<string, unknown>[]).map((d) => {
    const actorId = d.actor_id ? String(d.actor_id) : null;
    const actorProfile = actorId ? profilesMap[actorId] : null;

    return {
      id: String(d.id),
      eventType: String(d.event_type ?? "security_notice"),
      severity: String(d.severity ?? "low"),
      actorId,
      actorName: actorProfile?.fullName ?? null,
      actorRole: actorProfile?.roleName ?? null,
      targetId: d.target_id ? String(d.target_id) : null,
      action: String(d.action ?? "Security Action"),
      details: d.details && typeof d.details === "object" ? (d.details as Record<string, unknown>) : null,
      happenedAt: String(d.happened_at ?? new Date().toISOString()),
    };
  });
}

export function useSecurityEvents(params?: {
  severity?: string;
  limit?: number;
  dateRangeDays?: number;
}) {
  return useQuery({
    queryKey: ["security-events", params?.severity, params?.limit, params?.dateRangeDays],
    queryFn: () => fetchSecurityEvents(params),
    staleTime: 15_000,
  });
}

// ============================================================================
// Queries: System Audit Logs
// ============================================================================

export async function fetchSystemAuditLogs(params?: {
  module?: string;
  action?: string;
  search?: string;
  startDate?: string;
  endDate?: string;
  datePreset?: "today" | "7d" | "30d" | "all";
  limit?: number;
}): Promise<SystemAuditLogItem[]> {
  const supabase = createClient();
  let query = supabase.from("audit_logs").select("*");

  if (params?.module && params.module !== "all") {
    query = query.eq("module", params.module);
  }
  if (params?.action && params.action !== "all") {
    query = query.eq("action", params.action);
  }

  let effectiveStartDate = params?.startDate;
  if (!effectiveStartDate && params?.datePreset && params.datePreset !== "all") {
    const now = Date.now();
    if (params.datePreset === "today") {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      effectiveStartDate = today.toISOString();
    } else if (params.datePreset === "7d") {
      effectiveStartDate = new Date(now - 7 * 24 * 60 * 60 * 1000).toISOString();
    } else if (params.datePreset === "30d") {
      effectiveStartDate = new Date(now - 30 * 24 * 60 * 60 * 1000).toISOString();
    }
  }

  if (effectiveStartDate) {
    query = query.gte("timestamp", effectiveStartDate);
  }
  if (params?.endDate) {
    query = query.lte("timestamp", params.endDate);
  }

  const { data, error } = await query
    .order("timestamp", { ascending: false })
    .limit(params?.limit ?? 100);

  if (error || !data) return [];

  // Enrich with actor profiles
  const actorIds = Array.from(new Set(data.map((d: Record<string, unknown>) => d.actor_id).filter(Boolean)));
  const profilesMap: Record<string, { fullName: string; roleName: string }> = {};

  if (actorIds.length > 0) {
    const { data: profiles } = await supabase
      .from("users_profile")
      .select("id, auth_user_id, full_name, roles:role_id(role_name)")
      .or(`id.in.(${actorIds.join(",")}),auth_user_id.in.(${actorIds.join(",")})`);

    if (profiles) {
      for (const p of profiles as Record<string, unknown>[]) {
        const roleObj = p.roles as Record<string, unknown> | null;
        const info = {
          fullName: String(p.full_name ?? "User"),
          roleName: String(roleObj?.role_name ?? "Role"),
        };
        if (p.id) profilesMap[String(p.id)] = info;
        if (p.auth_user_id) profilesMap[String(p.auth_user_id)] = info;
      }
    }
  }

  let logs: SystemAuditLogItem[] = (data as Record<string, unknown>[]).map((d) => {
    const actorId = d.actor_id ? String(d.actor_id) : null;
    const actorProfile = actorId ? profilesMap[actorId] : null;

    return {
      id: String(d.id),
      actorId,
      actorName: actorProfile?.fullName ?? (d.actor_name ? String(d.actor_name) : null),
      actorRole: actorProfile?.roleName ?? (d.actor_role ? String(d.actor_role) : null),
      module: String(d.module ?? "General"),
      action: String(d.action ?? "ACTION"),
      recordId: d.record_id ? String(d.record_id) : null,
      oldData: d.old_data && typeof d.old_data === "object" ? (d.old_data as Record<string, unknown>) : null,
      newData: d.new_data && typeof d.new_data === "object" ? (d.new_data as Record<string, unknown>) : null,
      timestamp: String(d.timestamp ?? new Date().toISOString()),
    };
  });

  if (params?.search?.trim()) {
    const term = params.search.trim().toLowerCase();
    logs = logs.filter(
      (l) =>
        (l.actorName ?? "").toLowerCase().includes(term) ||
        (l.module ?? "").toLowerCase().includes(term) ||
        (l.action ?? "").toLowerCase().includes(term) ||
        (l.recordId ?? "").toLowerCase().includes(term)
    );
  }

  return logs;
}

export function useSystemAuditLogs(params?: {
  module?: string;
  action?: string;
  search?: string;
  startDate?: string;
  endDate?: string;
  datePreset?: "today" | "7d" | "30d" | "all";
  limit?: number;
}) {
  return useQuery({
    queryKey: [
      "system-audit-logs",
      params?.module,
      params?.action,
      params?.search,
      params?.startDate,
      params?.endDate,
      params?.datePreset,
      params?.limit,
    ],
    queryFn: () => fetchSystemAuditLogs(params),
    staleTime: 15_000,
  });
}

