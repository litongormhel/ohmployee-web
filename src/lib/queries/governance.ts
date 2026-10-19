import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ============================================================================
// Types: QA Center
// ============================================================================

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
}

export interface QaFinding {
  id: string;
  findingCode: string;
  category: string;
  severity: "critical" | "high" | "medium" | "low";
  moduleName: string;
  status: string;
  title: string;
  details: string | null;
  createdAt: string | null;
}

export interface QaSchedule {
  id: string;
  scheduleName: string;
  cronExpression: string;
  targetModule: string;
  isActive: boolean;
  lastRunAt: string | null;
  nextRunAt: string | null;
}

export interface QaQueueItem {
  id: string;
  scheduleId: string | null;
  status: string;
  priority: number;
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
  executiveSummary: string | null;
  createdAt: string | null;
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
        }))
      : [];

  const findings: QaFinding[] =
    findingsRes.status === "fulfilled" && findingsRes.value.data
      ? findingsRes.value.data.map((f: Record<string, unknown>) => ({
          id: String(f.id ?? ""),
          findingCode: String(f.finding_code ?? f.code ?? "QA_FINDING"),
          category: String(f.category ?? "General"),
          severity: (f.severity as "critical" | "high" | "medium" | "low") ?? "medium",
          moduleName: String(f.module_name ?? f.module ?? "System"),
          status: String(f.status ?? "open"),
          title: String(f.title ?? f.finding_summary ?? "Detected Anomaly"),
          details: f.details || f.error_message ? String(f.details ?? f.error_message) : null,
          createdAt: f.created_at ? String(f.created_at) : null,
        }))
      : [];

  const schedules: QaSchedule[] =
    schedulesRes.status === "fulfilled" && schedulesRes.value.data
      ? schedulesRes.value.data.map((s: Record<string, unknown>) => ({
          id: String(s.id ?? ""),
          scheduleName: String(s.schedule_name ?? "Scheduled Run"),
          cronExpression: String(s.cron_expression ?? "@daily"),
          targetModule: String(s.target_module ?? "all"),
          isActive: Boolean(s.is_active ?? true),
          lastRunAt: s.last_run_at ? String(s.last_run_at) : null,
          nextRunAt: s.next_run_at ? String(s.next_run_at) : null,
        }))
      : [];

  const queueItems: QaQueueItem[] =
    queueRes.status === "fulfilled" && queueRes.value.data
      ? queueRes.value.data.map((q: Record<string, unknown>) => ({
          id: String(q.id ?? ""),
          scheduleId: q.schedule_id ? String(q.schedule_id) : null,
          status: String(q.status ?? "queued"),
          priority: Number(q.priority ?? 0),
          queuedAt: q.queued_at ? String(q.queued_at) : null,
          startedAt: q.started_at ? String(q.started_at) : null,
          errorMessage: q.error_message ? String(q.error_message) : null,
        }))
      : [];

  const reports: QaDailyReport[] =
    reportsRes.status === "fulfilled" && reportsRes.value.data
      ? reportsRes.value.data.map((dr: Record<string, unknown>) => ({
          id: String(dr.id ?? ""),
          reportDate: String(dr.report_date ?? ""),
          environment: String(dr.environment ?? "production"),
          healthScore: dr.health_score != null ? Number(dr.health_score) : null,
          totalRuns: Number(dr.total_runs ?? 0),
          passedRuns: Number(dr.passed_runs ?? 0),
          failedRuns: Number(dr.failed_runs ?? 0),
          criticalFindings: Number(dr.critical_findings ?? 0),
          executiveSummary: dr.executive_summary ? String(dr.executive_summary) : null,
          createdAt: dr.created_at ? String(dr.created_at) : null,
        }))
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

export async function runQaScenarioRpc(scenarioCode: string) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("qa_run_scenario", {
    p_scenario_code: scenarioCode.trim(),
  });
  if (error) throw error;
  return data;
}

export function useRunQaScenario() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: runQaScenarioRpc,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["qa-center-snapshot"] });
    },
  });
}

export async function generateDailyQaReportRpc(environment = "production") {
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
    mutationFn: (environment?: string) => generateDailyQaReportRpc(environment),
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

