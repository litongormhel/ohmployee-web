import type { PostgrestError } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";

// ---------------------------------------------------------------------------
// Primitive types
// ---------------------------------------------------------------------------

export type PlantillaPlantillaType = "Budgeted" | "AH" | string;

export type PlantillaStatus =
  | "Active"
  | "Pending Transfer"
  | "Pending Separation"
  | "Suspended"
  | "Inactive"
  | string;

export type PlantillaStaffingSlaStatus =
  | "Under-staffed"
  | "Fully-staffed"
  | "Over-staffed"
  | string;

export type PlantillaStaffingRiskStatus =
  | "Low"
  | "Medium"
  | "High"
  | "Critical"
  | string;

// ---------------------------------------------------------------------------
// Row capabilities
// ---------------------------------------------------------------------------

export type PlantillaRowCapabilities = {
  canViewDetail: boolean;
  canRequestDeactivation: boolean;
  canReviewDeactivation: boolean;
  canRequestDeletion: boolean;
  canReviewDeletion: boolean;
  canTransferEmployee: boolean;
  raw: Record<string, boolean>;
};

export type PlantillaStoreRowCapabilities = {
  canViewDetail: boolean;
  canRequestAh: boolean;
  raw: Record<string, boolean>;
};

// ---------------------------------------------------------------------------
// JSONB sub-types
// ---------------------------------------------------------------------------

export type PlantillaCoveredStore = {
  stableKey: string;
  storeId: string;
  storeName: string;
  allocationPercent: number | null;
  isPrimary: boolean;
};

export type PlantillaGovernmentIds = {
  sss: string | null;
  philhealth: string | null;
  pagibig: string | null;
  tin: string | null;
};

export type PlantillaClearanceChecklistItem = {
  stableKey: string;
  key: string;
  label: string;
  completed: boolean;
};

export type PlantillaClearanceDocument = {
  stableKey: string;
  documentId: string;
  fileName: string;
  fileUrl: string | null;
  uploadedAt: string | null;
  uploadedBy: string | null;
};

export type PlantillaMovementRequest = {
  movementId: string;
  movementType: string;
  targetStoreName: string | null;
  requestedAt: string | null;
  requestedBy: string | null;
  status: string;
};

export type PlantillaAuditTimelineItem = {
  stableKey: string;
  eventId: string;
  eventLabel: string;
  eventDescription: string | null;
  createdAt: string | null;
  profileName: string | null;
};

// ---------------------------------------------------------------------------
// Masked fields (pre-masked by backend for restricted roles)
// ---------------------------------------------------------------------------

export type PlantillaMaskedFields = {
  baseRateMasked: string | null;
  contactNumber: string | null;
  emailAddress: string | null;
  residentialAddress: string | null;
  governmentIds: PlantillaGovernmentIds;
};

// ---------------------------------------------------------------------------
// Staffing risk (derived presentation type from store staffing row)
// ---------------------------------------------------------------------------

export type PlantillaStaffingRisk = {
  staffingRisk: PlantillaStaffingRiskStatus | null;
  slaBadge: string | null;
  vacancySlaBreached: boolean;
  vacancyCount: number;
};

// ---------------------------------------------------------------------------
// Deactivation overlay (derived presentation hints from plantilla_status)
// ---------------------------------------------------------------------------

export type PlantillaDeactivationOverlay = {
  isDimmed: boolean;
  isPendingSeparation: boolean;
  showSeparationBanner: boolean;
  showDeactivatedBanner: boolean;
};

// ---------------------------------------------------------------------------
// Transfer overlay (derived presentation hints from active_movement_req)
// ---------------------------------------------------------------------------

export type PlantillaTransferOverlay = {
  hasActiveTransfer: boolean;
  transferType: string | null;
  targetStoreName: string | null;
  slaBreached: boolean;
  requestedAt: string | null;
};

// ---------------------------------------------------------------------------
// List and detail row types
// ---------------------------------------------------------------------------

export type PlantillaEmployeeListItem = {
  id: string;
  employeeNo: string;
  firstName: string | null;
  lastName: string | null;
  positionTitle: string | null;
  accountName: string | null;
  primaryStoreName: string | null;
  assignmentType: string | null;
  coveredStoresCount: number;
  plantillaType: PlantillaPlantillaType | null;
  plantillaStatus: PlantillaStatus | null;
  dateDeployed: string | null;
  tenureDays: number;
  baseRateMasked: string | null;
  slaBreached: boolean;
  rowCapabilities: PlantillaRowCapabilities;
  totalCount: number;
};

export type PlantillaStoreStaffingRow = {
  storeId: string;
  storeCode: string | null;
  storeName: string | null;
  accountName: string | null;
  region: string | null;
  requiredHeadcount: number;
  // MFR breakdown fields (OHM2026_1132 backend contract)
  onboardCount: number;       // Actual: confirmed onboarded headcount
  hrPipelineCount: number;    // HR Pipeline: in-progress hiring/deploying
  openHeadcount: number;      // Vacancy: open unfilled slots
  // fill_rate from backend only — do NOT recompute on the web layer.
  // Formula: Actual / (Actual + HR Pipeline + Vacancy)
  fillRate: number | null;
  // Legacy aliases kept for backward compat with deriveStaffingRisk
  activeHeadcount: number;    // alias → onboardCount
  vacancyCount: number;       // alias → openHeadcount
  pipelineCount: number;      // alias → hrPipelineCount
  staffingGap: number;
  staffingRisk: PlantillaStaffingRiskStatus | null;
  slaBadge: string | null;
  vacancySlaBreached: boolean;
  rowCapabilities: PlantillaStoreRowCapabilities;
  totalCount: number;
};

export type PlantillaSummary = {
  totalActiveRoster: number;
  totalBudgetedSlots: number;
  totalAdditionalSlots: number;
  understaffedStores: number;
  slaBreachesCount: number;
};

export type PlantillaDetailItem = {
  id: string;
  employeeNo: string;
  firstName: string | null;
  lastName: string | null;
  positionTitle: string | null;
  accountName: string | null;
  primaryStoreName: string | null;
  assignmentType: string | null;
  coveredStores: PlantillaCoveredStore[];
  plantillaType: PlantillaPlantillaType | null;
  plantillaStatus: PlantillaStatus | null;
  dateDeployed: string | null;
  tenureDescription: string | null;
  maskedFields: PlantillaMaskedFields;
  clearanceStatus: string | null;
  clearanceChecklist: PlantillaClearanceChecklistItem[];
  clearanceDocuments: PlantillaClearanceDocument[];
  slaElapsedHours: number;
  slaBreached: boolean;
  activeMovementRequest: PlantillaMovementRequest | null;
  auditTimeline: PlantillaAuditTimelineItem[];
  rowCapabilities: PlantillaRowCapabilities;
};

// ---------------------------------------------------------------------------
// Query params
// ---------------------------------------------------------------------------

export type PlantillaEmployeeListParams = {
  accountId?: string;
  groupId?: string;
  storeId?: string;
  deployment?: string;
  activeState?: string;
  status?: string;
  search?: string;
  page: number;
  pageSize: number;
  sortBy?: string;
  sortDir?: "asc" | "desc";
};

export type PlantillaStoreStaffingListParams = {
  accountId?: string;
  groupId?: string;
  riskFilter?: string;
  search?: string;
  page: number;
  pageSize: number;
  sortBy?: string;
  sortDir?: "asc" | "desc";
};

export type PlantillaSummaryParams = {
  search?: string;
  accountId?: string;
  groupId?: string;
};

// ---------------------------------------------------------------------------
// Error class
// ---------------------------------------------------------------------------

export type PlantillaDataErrorKind = "access_denied" | "retryable";

export class PlantillaDataError extends Error {
  kind: PlantillaDataErrorKind;

  constructor(kind: PlantillaDataErrorKind, message: string) {
    super(message);
    this.name = "PlantillaDataError";
    this.kind = kind;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

type PlantillaRpcRow = Record<string, unknown>;

const DEFAULT_PAGE_SIZE = 25;
const MAX_PAGE_SIZE = 100;
const DEFAULT_EMPLOYEE_SORT_BY = "employee_name";
const DEFAULT_STORE_STAFFING_SORT_BY = "store_name";

const EMPLOYEE_SORT_FIELDS = new Set([
  "employee_name",
  "employee_no",
  "account_name",
  "primary_store_name",
  "position_title",
  "plantilla_type",
  "plantilla_status",
  "date_deployed",
  "created_at",
]);

const STORE_STAFFING_SORT_FIELDS = new Set([
  "store_name",
  "store_code",
  "account_name",
  "region",
  "required_headcount",
  "active_headcount",
  "vacancy_count",
  "pipeline_count",
  "staffing_gap",
  "staffing_risk",
  "sla_badge",
]);

function asObject(value: unknown): Record<string, unknown> {
  return value && !Array.isArray(value) && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function asBadgeText(value: unknown): string | null {
  if (typeof value === "string" && value.trim().length > 0) {
    return value;
  }

  const obj = asObject(value);
  return (
    asString(obj.text) ??
    asString(obj.label) ??
    asString(obj.status) ??
    asString(obj.value)
  );
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asBoolean(value: unknown): boolean {
  return value === true;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asCount(value: unknown): number {
  return Math.max(0, Math.trunc(asNumber(value) ?? 0));
}

function asInteger(value: unknown): number {
  return Math.trunc(asNumber(value) ?? 0);
}

function splitEmployeeName(value: unknown): Pick<
  PlantillaEmployeeListItem,
  "firstName" | "lastName"
> {
  const name = asString(value);
  if (!name) {
    return { firstName: null, lastName: null };
  }

  const [last, ...rest] = name.split(",");
  if (rest.length > 0) {
    return {
      firstName: asString(rest.join(",").trim()),
      lastName: asString(last.trim()),
    };
  }

  return { firstName: name, lastName: null };
}

function getErrorKind(error: PostgrestError): PlantillaDataErrorKind {
  const combined = `${error.code ?? ""} ${error.message ?? ""} ${error.details ?? ""}`
    .toLowerCase()
    .trim();

  if (
    combined.includes("permission denied") ||
    combined.includes("not authorized") ||
    combined.includes("unauthorized") ||
    combined.includes("forbidden") ||
    combined.includes("rls") ||
    error.code === "42501"
  ) {
    return "access_denied";
  }

  return "retryable";
}

function throwPlantillaError(error: PostgrestError): never {
  throw new PlantillaDataError(getErrorKind(error), error.message);
}

// ---------------------------------------------------------------------------
// Normalizers
// ---------------------------------------------------------------------------

function normalizeEmployeeCapabilities(value: unknown): PlantillaRowCapabilities {
  const raw = Object.fromEntries(
    Object.entries(asObject(value))
      .filter(([, item]) => typeof item === "boolean")
      .map(([key, item]) => [key, item === true]),
  );

  return {
    canViewDetail: raw.can_view_detail === true,
    canRequestDeactivation: raw.can_request_deactivation === true,
    canReviewDeactivation: raw.can_review_deactivation === true,
    canRequestDeletion: raw.can_request_deletion === true,
    canReviewDeletion: raw.can_review_deletion === true,
    canTransferEmployee: raw.can_transfer_employee === true,
    raw,
  };
}

function normalizeStoreCapabilities(value: unknown): PlantillaStoreRowCapabilities {
  const raw = Object.fromEntries(
    Object.entries(asObject(value))
      .filter(([, item]) => typeof item === "boolean")
      .map(([key, item]) => [key, item === true]),
  );

  return {
    canViewDetail: raw.can_view_detail === true,
    canRequestAh: raw.can_request_ah === true,
    raw,
  };
}

function normalizeGovernmentIds(value: unknown): PlantillaGovernmentIds {
  const obj = asObject(value);
  return {
    sss: asString(obj.sss),
    philhealth: asString(obj.philhealth),
    pagibig: asString(obj.pagibig),
    tin: asString(obj.tin),
  };
}

function normalizeCoveredStore(item: unknown, index: number): PlantillaCoveredStore {
  const obj = asObject(item);
  const storeId = asString(obj.store_id ?? obj.storeId) ?? "";
  const storeName = asString(obj.store_name ?? obj.storeName) ?? "Unknown Store";
  return {
    stableKey: [
      "covered-store",
      storeId || "missing-id",
      storeName,
      asNumber(obj.allocation_percent ?? obj.allocationPercent) ?? "na",
      index,
    ].join(":"),
    storeId,
    storeName,
    allocationPercent: asNumber(obj.allocation_percent ?? obj.allocationPercent),
    isPrimary: asBoolean(obj.is_primary ?? obj.isPrimary),
  };
}

function normalizeClearanceChecklistItem(
  item: unknown,
  index: number,
): PlantillaClearanceChecklistItem {
  const obj = asObject(item);
  const key = asString(obj.key) ?? "";
  const label = asString(obj.label) ?? "Checklist Item";
  return {
    stableKey: ["clearance-item", key || "missing-key", label, index].join(":"),
    key,
    label,
    completed: asBoolean(obj.completed),
  };
}

function normalizeClearanceDocument(item: unknown, index: number): PlantillaClearanceDocument {
  const obj = asObject(item);
  const documentId = asString(obj.document_id ?? obj.documentId) ?? "";
  const fileName = asString(obj.file_name ?? obj.fileName) ?? "unnamed_file";
  return {
    stableKey: ["clearance-doc", documentId || "missing-id", fileName, index].join(":"),
    documentId,
    fileName,
    fileUrl: asString(obj.file_url ?? obj.fileUrl),
    uploadedAt: asString(obj.uploaded_at ?? obj.uploadedAt),
    uploadedBy: asString(obj.uploaded_by ?? obj.uploadedBy),
  };
}

function normalizeMovementRequest(value: unknown): PlantillaMovementRequest | null {
  if (!value) return null;
  const obj = asObject(value);
  const movementId = asString(obj.movement_id ?? obj.movementId);
  if (!movementId) return null;

  return {
    movementId,
    movementType: asString(obj.movement_type ?? obj.movementType) ?? "Transfer",
    targetStoreName: asString(obj.target_store_name ?? obj.targetStoreName),
    requestedAt: asString(obj.requested_at ?? obj.requestedAt),
    requestedBy: asString(obj.requested_by ?? obj.requestedBy),
    status: asString(obj.status) ?? "Pending",
  };
}

function normalizeAuditTimelineItem(item: unknown, index: number): PlantillaAuditTimelineItem {
  const obj = asObject(item);
  const eventId = asString(obj.event_id ?? obj.eventId) ?? "";
  const eventLabel = asString(obj.event_label ?? obj.eventLabel) ?? "Event";
  const createdAt = asString(obj.created_at ?? obj.createdAt);
  return {
    stableKey: [
      "audit-event",
      eventId || "missing-id",
      eventLabel,
      createdAt ?? "missing-date",
      index,
    ].join(":"),
    eventId,
    eventLabel,
    eventDescription: asString(obj.event_description ?? obj.eventDescription),
    createdAt,
    profileName: asString(obj.profile_name ?? obj.profileName),
  };
}

function normalizeEmployeeListRow(row: PlantillaRpcRow): PlantillaEmployeeListItem | null {
  const id = asString(row.id ?? row.plantilla_id ?? row.plantillaId);
  if (!id) return null;

  const employeeName = splitEmployeeName(row.employee_name ?? row.employeeName);

  return {
    id,
    employeeNo: asString(row.employee_no) ?? "Uncoded",
    firstName: asString(row.first_name) ?? employeeName.firstName,
    lastName: asString(row.last_name) ?? employeeName.lastName,
    positionTitle: asString(row.position_title),
    accountName: asString(row.account_name),
    primaryStoreName: asString(row.primary_store_name ?? row.store_name),
    assignmentType: asString(row.assignment_type ?? row.deployment_type),
    coveredStoresCount: asCount(row.covered_stores_count ?? row.roving_store_count),
    plantillaType: asString(row.plantilla_type),
    plantillaStatus: asString(row.plantilla_status ?? row.status),
    dateDeployed: asString(row.date_deployed ?? row.date_hired),
    tenureDays: asCount(row.tenure_days),
    baseRateMasked: asString(row.base_rate_masked),
    slaBreached: asBoolean(row.sla_breached),
    rowCapabilities: normalizeEmployeeCapabilities(row.row_capabilities),
    totalCount: asCount(row.total_count),
  };
}

function normalizeStoreStaffingRow(row: PlantillaRpcRow): PlantillaStoreStaffingRow | null {
  const storeId =
    asString(row.store_id) ??
    asString(row.store_code) ??
    asString(row.store_name) ??
    "unknown-store";

  // OHM2026_1132: new field names from backend; fall back to legacy names for older deploys
  const onboardCount = asCount(row.onboard_count ?? row.active_headcount ?? row.active_budgeted_count);
  const hrPipelineCount = asCount(row.hr_pipeline_count ?? row.pipeline_count);
  const openHeadcount = asCount(row.open_headcount ?? row.vacancy_count ?? row.vacancies_count);
  const requiredHeadcount = asCount(row.required_headcount ?? row.budgeted_target);

  return {
    storeId,
    storeCode: asString(row.store_code),
    storeName: asString(row.store_name),
    accountName: asString(row.account_name),
    region: asString(row.region),
    requiredHeadcount,
    // MFR breakdown — canonical new fields
    onboardCount,
    hrPipelineCount,
    openHeadcount,
    // fill_rate is backend-computed; do NOT derive on the web layer.
    // Formula: onboardCount / (onboardCount + hrPipelineCount + openHeadcount)
    fillRate: asNumber(row.fill_rate),
    // Legacy aliases so deriveStaffingRisk and existing renders keep working
    activeHeadcount: onboardCount,
    vacancyCount: openHeadcount,
    pipelineCount: hrPipelineCount,
    staffingGap: asInteger(row.staffing_gap),
    staffingRisk: asString(row.staffing_risk ?? row.staffing_sla_status),
    slaBadge: asBadgeText(row.sla_badge ?? row.staffing_sla_status),
    vacancySlaBreached: asBoolean(row.vacancy_sla_breached),
    rowCapabilities: normalizeStoreCapabilities(row.row_capabilities),
    totalCount: asCount(row.total_count),
  };
}

function normalizeDetailRow(row: PlantillaRpcRow): PlantillaDetailItem | null {
  const id =
    asString(row.id) ??
    asString(row.employee_id) ??
    asString(row.plantilla_id) ??
    asString(row.plantillaId);
  if (!id) return null;

  const coveredStores = asArray(row.covered_stores).map(normalizeCoveredStore);
  const clearanceChecklist = asArray(row.clearance_checklist).map(
    normalizeClearanceChecklistItem,
  );
  const clearanceDocuments = asArray(row.clearance_documents).map(
    normalizeClearanceDocument,
  );
  const auditTimeline = asArray(row.audit_timeline).map(normalizeAuditTimelineItem);

  const activeMovementRequest = normalizeMovementRequest(row.active_movement_req);

  const maskedFields: PlantillaMaskedFields = {
    baseRateMasked: asString(row.base_rate_masked),
    contactNumber: asString(row.contact_number),
    emailAddress: asString(row.email_address),
    residentialAddress: asString(row.residential_address),
    governmentIds: normalizeGovernmentIds(row.government_ids),
  };

  return {
    id,
    employeeNo: asString(row.employee_no) ?? "Uncoded",
    firstName: asString(row.first_name),
    lastName: asString(row.last_name),
    positionTitle: asString(row.position_title),
    accountName: asString(row.account_name),
    primaryStoreName: asString(row.primary_store_name),
    assignmentType: asString(row.assignment_type),
    coveredStores,
    plantillaType: asString(row.plantilla_type),
    plantillaStatus: asString(row.plantilla_status),
    dateDeployed: asString(row.date_deployed),
    tenureDescription: asString(row.tenure_description),
    maskedFields,
    clearanceStatus: asString(row.clearance_status),
    clearanceChecklist,
    clearanceDocuments,
    slaElapsedHours: asCount(row.sla_elapsed_hours),
    slaBreached: asBoolean(row.sla_breached),
    activeMovementRequest,
    auditTimeline,
    rowCapabilities: normalizeEmployeeCapabilities(row.row_capabilities),
  };
}

function normalizeSummary(data: unknown): PlantillaSummary {
  const row = Array.isArray(data) ? asObject(data[0]) : asObject(data);

  return {
    totalActiveRoster: asCount(row.total_active_roster),
    totalBudgetedSlots: asCount(row.total_budgeted_slots),
    totalAdditionalSlots: asCount(row.total_additional_slots),
    understaffedStores: asCount(row.understaffed_stores),
    slaBreachesCount: asCount(row.sla_breaches_count),
  };
}

// ---------------------------------------------------------------------------
// Presentation-layer derivation helpers
// ---------------------------------------------------------------------------

export function deriveDeactivationOverlay(
  status: PlantillaStatus | null | undefined,
): PlantillaDeactivationOverlay {
  const s = (status ?? "").toLowerCase();
  const isPendingSeparation = s === "pending_separation" || s === "pending separation";
  const isDimmed =
    s === "inactive" || s === "terminated" || s === "suspended" || isPendingSeparation;

  return {
    isDimmed,
    isPendingSeparation,
    showSeparationBanner: isPendingSeparation,
    showDeactivatedBanner: s === "inactive" || s === "terminated",
  };
}

export function deriveTransferOverlay(
  movement: PlantillaMovementRequest | null | undefined,
  slaBreached: boolean,
): PlantillaTransferOverlay {
  if (!movement) {
    return {
      hasActiveTransfer: false,
      transferType: null,
      targetStoreName: null,
      slaBreached: false,
      requestedAt: null,
    };
  }

  return {
    hasActiveTransfer: true,
    transferType: movement.movementType,
    targetStoreName: movement.targetStoreName,
    slaBreached,
    requestedAt: movement.requestedAt,
  };
}

export function deriveStaffingRisk(row: PlantillaStoreStaffingRow): PlantillaStaffingRisk {
  return {
    staffingRisk: row.staffingRisk,
    slaBadge: row.slaBadge,
    vacancySlaBreached: row.vacancySlaBreached,
    vacancyCount: row.vacancyCount,
  };
}

// ---------------------------------------------------------------------------
// Pagination helpers
// ---------------------------------------------------------------------------

function clampPage(page: number, pageSize: number) {
  const p = Math.max(1, Math.trunc(page));
  const ps = Math.min(MAX_PAGE_SIZE, Math.max(1, Math.trunc(pageSize)));
  return { page: p, pageSize: ps, offset: (p - 1) * ps };
}

function getEmployeeTotalCount(rows: PlantillaEmployeeListItem[]): number {
  const totalCount = rows[0]?.totalCount ?? 0;
  return totalCount > 0 ? totalCount : rows.length;
}

function getStoreTotalCount(rows: PlantillaStoreStaffingRow[]): number {
  const totalCount = rows[0]?.totalCount ?? 0;
  return totalCount > 0 ? totalCount : rows.length;
}

function getAllowedSortField(
  sortBy: string | undefined,
  allowedFields: Set<string>,
  fallback: string,
): string {
  return sortBy && allowedFields.has(sortBy) ? sortBy : fallback;
}

// ---------------------------------------------------------------------------
// Public RPC wrappers
// ---------------------------------------------------------------------------

export async function getPlantillaSummary(
  params: PlantillaSummaryParams = {},
): Promise<PlantillaSummary> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_plantilla_summary", {
    p_search: params.search?.trim() || null,
    p_account_id: params.accountId ?? null,
    p_group_id: params.groupId ?? null,
  });

  if (error) {
    throwPlantillaError(error);
  }

  return normalizeSummary(data);
}

export async function listWebPlantillaEmployees(params: PlantillaEmployeeListParams) {
  const supabase = createClient();
  const { page, pageSize, offset } = clampPage(
    params.page,
    params.pageSize ?? DEFAULT_PAGE_SIZE,
  );

  const { data, error } = await supabase.rpc("list_web_plantilla_employees", {
    p_search: params.search?.trim() || null,
    p_account_id: params.accountId ?? null,
    p_group_id: params.groupId ?? null,
    p_store_id: params.storeId ?? null,
    p_employment_status: params.status ?? null,
    p_deployment: params.deployment ?? null,
    p_active_state: params.activeState ?? null,
    p_limit: pageSize,
    p_offset: offset,
    p_sort_by: getAllowedSortField(
      params.sortBy,
      EMPLOYEE_SORT_FIELDS,
      DEFAULT_EMPLOYEE_SORT_BY,
    ),
    p_sort_dir: params.sortDir ?? "asc",
  });

  if (error) {
    throwPlantillaError(error);
  }

  const rows = (Array.isArray(data) ? data : [])
    .map((row) => normalizeEmployeeListRow(asObject(row)))
    .filter((row): row is PlantillaEmployeeListItem => row !== null);

  return {
    data: rows,
    totalCount: getEmployeeTotalCount(rows),
    page,
    pageSize,
  };
}

export async function listWebPlantillaStoreStaffing(params: PlantillaStoreStaffingListParams) {
  const supabase = createClient();
  const { page, pageSize, offset } = clampPage(
    params.page,
    params.pageSize ?? DEFAULT_PAGE_SIZE,
  );

  const { data, error } = await supabase.rpc("list_web_plantilla_store_staffing", {
    p_search: params.search?.trim() || null,
    p_account_id: params.accountId ?? null,
    p_group_id: params.groupId ?? null,
    p_risk_filter: params.riskFilter ?? null,
    p_limit: pageSize,
    p_offset: offset,
    p_sort_by: getAllowedSortField(
      params.sortBy,
      STORE_STAFFING_SORT_FIELDS,
      DEFAULT_STORE_STAFFING_SORT_BY,
    ),
    p_sort_dir: params.sortDir ?? "asc",
  });

  if (error) {
    throwPlantillaError(error);
  }

  const rows = (Array.isArray(data) ? data : [])
    .map((row) => normalizeStoreStaffingRow(asObject(row)))
    .filter((row): row is PlantillaStoreStaffingRow => row !== null);

  return {
    data: rows,
    totalCount: getStoreTotalCount(rows),
    page,
    pageSize,
  };
}

export async function getWebPlantillaDetail(plantillaId: string): Promise<PlantillaDetailItem> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_plantilla_detail", {
    p_employee_id: plantillaId,
  });

  if (error) {
    throwPlantillaError(error);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new PlantillaDataError("retryable", "No Plantilla detail record found");
  }

  const normalized = normalizeDetailRow(asObject(row));
  if (!normalized) {
    throw new PlantillaDataError("retryable", "Failed to normalize Plantilla detail record");
  }

  return normalized;
}
