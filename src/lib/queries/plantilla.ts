import type { PostgrestError } from "@supabase/supabase-js";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ---------------------------------------------------------------------------
// Primitive types
// ---------------------------------------------------------------------------

export type PlantillaSlotStatus =
  | "open"
  | "pipeline"
  | "hr_processing"
  | "occupied"
  | "closed"
  | string;

export interface PlantillaSlotOccupant {
  id: string;
  employeeNo: string | null;
  employeeName: string | null;
  position: string | null;
  deploymentType: string | null;
  status: string | null;
}

export interface PlantillaSlotCandidate {
  id: string;
  name: string | null;
  status: string | null;
  contactNumber?: string | null;
  email?: string | null;
}

export interface PlantillaSlotItem {
  id: string;
  storeId: string | null;
  storeName: string | null;
  storeCode: string | null;
  accountId: string | null;
  accountName: string | null;
  groupId: string | null;
  groupName: string | null;
  position: string;
  employmentType: string;
  isRoving: boolean;
  slotStatus: PlantillaSlotStatus;
  slotOrdinal: number;
  legacyVcode: string | null;
  sourceHcRequestId: string | null;
  currentOccupantPlantillaId: string | null;
  occupant: PlantillaSlotOccupant | null;
  candidate: PlantillaSlotCandidate | null;
  requiredHeadcountQuota?: number | null;
  createdAt: string;
  updatedAt: string;
  closedAt: string | null;
  closureReasonCode: string | null;
}

export interface PlantillaSlotHistoryEvent {
  id: string;
  slotId: string;
  accountId: string | null;
  actionType: string;
  oldValue: string | null;
  newValue: string | null;
  reasonCode: string | null;
  performedBy: string | null;
  performerName: string | null;
  remarks: string | null;
  createdAt: string;
}

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
  canSeparate?: boolean;
  canUpdateStatus?: boolean;
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
  required: number;
  actual: number;
  hrProcess: number;
  vacant: number;
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
  accountId?: string | null;
  storeId?: string | null;
  province?: string | null;
  islandGroup?: string | null;
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

function parseAndFormatName(
  firstName: string | null,
  lastName: string | null,
  middleName: string | null,
  fullName: string | null
): { firstName: string | null; lastName: string | null } {
  if (firstName && lastName) {
    const fName = middleName ? `${firstName} ${middleName}` : firstName;
    return {
      firstName: fName,
      lastName: lastName,
    };
  }

  const name = fullName ? fullName.trim() : "";
  if (!name) {
    return { firstName: null, lastName: null };
  }

  if (name.toLowerCase().includes("vacant")) {
    return { firstName: name, lastName: null };
  }

  const commaIndex = name.indexOf(",");
  if (commaIndex !== -1) {
    const lastPart = name.substring(0, commaIndex).trim();
    const firstPart = name.substring(commaIndex + 1).trim();
    return {
      firstName: firstPart || null,
      lastName: lastPart || null,
    };
  }

  const parts = name.split(/\s+/);
  if (parts.length >= 2) {
    const lastPart = parts[parts.length - 1];
    const firstParts = parts.slice(0, parts.length - 1);
    return {
      firstName: firstParts.join(" "),
      lastName: lastPart,
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
    canSeparate: raw.can_separate === true || raw.can_resign === true || raw.can_endo === true,
    canUpdateStatus: raw.can_update_status === true || raw.can_separate === true,
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

  const nameObj = parseAndFormatName(
    asString(row.first_name),
    asString(row.last_name),
    asString(row.middle_name),
    asString(row.employee_name ?? row.employeeName)
  );

  return {
    id,
    employeeNo: asString(row.employee_no) ?? "Uncoded",
    firstName: nameObj.firstName,
    lastName: nameObj.lastName,
    positionTitle: asString(row.position_title),
    accountName: asString(row.account_name),
    primaryStoreName: asString(row.primary_store_name ?? row.store_name),
    assignmentType: asString(row.derived_employment_type ?? row.assignment_type ?? row.deployment_type) ?? (asCount(row.covered_stores_count ?? row.roving_store_count) > 1 ? "Roving" : "Stationary"),
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

  const nameObj = parseAndFormatName(
    asString(row.first_name),
    asString(row.last_name),
    asString(row.middle_name),
    asString(row.employee_name ?? row.employeeName ?? row.employeeNameSnapshot ?? row.employee_name_snapshot)
  );

  return {
    id,
    employeeNo: asString(row.employee_no) ?? "Uncoded",
    firstName: nameObj.firstName,
    lastName: nameObj.lastName,
    positionTitle: asString(row.position_title),
    accountName: asString(row.account_name),
    primaryStoreName: asString(row.primary_store_name),
    assignmentType: asString(row.derived_employment_type ?? row.assignment_type ?? row.deployment_type) ?? (coveredStores.length > 1 ? "Roving" : "Stationary"),
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
    accountId: asString(row.account_id ?? row.accountId),
    storeId: asString(row.store_id ?? row.storeId),
    province: asString(row.province ?? row.area_province ?? row.area),
    islandGroup: asString(row.island_group ?? row.islandGroup),
    rowCapabilities: normalizeEmployeeCapabilities(row.row_capabilities),
  };
}

function normalizeSummary(data: unknown): PlantillaSummary {
  const row = Array.isArray(data) ? asObject(data[0]) : asObject(data);

  const actual = asCount(row.active_employees);
  const hrProcess = asCount(row.onboarding_pipeline_count);
  const vacant = asCount(row.open_headcount_count);
  const required = actual + hrProcess + vacant;

  return {
    required,
    actual,
    hrProcess,
    vacant,
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

export async function fetchUnassignedHrcoCount(accountId: string): Promise<number> {
  if (!accountId) return 0;
  const supabase = createClient();
  try {
    const { data, error } = await supabase.rpc("get_plantilla_unassigned_hrco_count", {
      p_account_id: accountId,
    });
    if (!error && typeof data === "number") {
      return data;
    }
  } catch {
    // Fallback
  }
  return 0;
}

export async function fetchNeedsHrcoEmployees(
  accountId: string,
  search?: string
): Promise<PlantillaEmployeeListItem[]> {
  if (!accountId) return [];
  const supabase = createClient();
  try {
    const { data, error } = await supabase.rpc("get_plantilla_needs_hrco_employees", {
      p_account_id: accountId,
    });
    if (!error && Array.isArray(data)) {
      const rows = (data as Record<string, unknown>[])
        .map((row) => normalizeEmployeeListRow(asObject(row)))
        .filter((row): row is PlantillaEmployeeListItem => row !== null);
      if (search && search.trim()) {
        const q = search.trim().toLowerCase();
        return rows.filter((r) =>
          [r.firstName, r.lastName, r.employeeNo, r.primaryStoreName, r.positionTitle]
            .filter(Boolean)
            .join(" ")
            .toLowerCase()
            .includes(q)
        );
      }
      return rows;
    }
  } catch {
    // Fallback
  }
  return [];
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

export type PlantillaAccountStatusCount = {
  accountId: string;
  status: string;
  rowCount: number;
};

export async function getPlantillaAccountStatusCounts(
  accountIds: string[],
): Promise<PlantillaAccountStatusCount[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_plantilla_account_status_counts", {
    p_account_ids: accountIds,
  });

  if (error) {
    throwPlantillaError(error);
  }

  return asArray(data).map((row) => {
    const obj = asObject(row);
    return {
      accountId: asString(obj.account_id) ?? "",
      status: asString(obj.status) ?? "",
      rowCount: asCount(obj.row_count),
    };
  });
}

// ---------------------------------------------------------------------------
// Lifecycle Action Mutation Types & Contracts
// ---------------------------------------------------------------------------

export type SeparationStatusType =
  | "Resigned"
  | "Endo"
  | "End of Contract"
  | "Terminated"
  | "AWOL"
  | "Others";

export interface UpdateSeparationParams {
  plantillaId: string;
  separationStatus: SeparationStatusType | string;
  effectiveDate: string; // YYYY-MM-DD
  remarks?: string | null;
  openVacancy?: boolean;
}

export type EmploymentStatusTarget = "Active" | "On Leave" | "Floating";

export interface UpdateEmploymentStatusParams {
  plantillaId: string;
  targetStatus: EmploymentStatusTarget;
  reason?: string | null;
  remarks?: string | null;
  expectedReturnDate?: string | null;
}

export interface CreateDeactivationRequestParams {
  plantillaId: string;
  reason?: string | null;
  remarks: string;
}

export type TransferReasonType =
  | "Store Initiated"
  | "Employee Requested"
  | "Operational Need"
  | "Annual Inventory"
  | "Store Closed Temporarily"
  | string;

export interface TransferPersonnelParams {
  plantillaId: string;
  targetStoreId: string;
  reason?: TransferReasonType | string | null;
  effectiveDate?: string | null; // YYYY-MM-DD
  targetPositionId?: string | null;
}

export interface DestinationStoreItem {
  id: string;
  storeName: string;
  vcode: string | null;
  accountId: string | null;
  accountName?: string | null;
  groupId?: string | null;
  groupName?: string | null;
  areaCity: string | null;
  province: string | null;
  areaProvince: string | null;
  islandGroup: string | null;
  isActive: boolean;
}

// ---------------------------------------------------------------------------
// Supabase RPC Calls for Plantilla Mutations
// ---------------------------------------------------------------------------

export async function updatePlantillaSeparation(params: UpdateSeparationParams) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("plantilla_update_separation", {
    p_plantilla_id: params.plantillaId,
    p_separation_status: params.separationStatus,
    p_effective_date: params.effectiveDate,
    p_remarks: params.remarks?.trim() || null,
    p_open_vacancy: params.openVacancy ?? true,
  });

  if (error) {
    throwPlantillaError(error);
  }

  return data;
}

export async function updatePlantillaEmploymentStatus(params: UpdateEmploymentStatusParams) {
  const supabase = createClient();

  if (params.targetStatus === "On Leave") {
    // Optional leave reason / return date formatted into remarks if supported
    const { data, error } = await supabase.rpc("set_plantilla_on_leave", {
      p_plantilla_id: params.plantillaId,
    });
    if (error) {
      throwPlantillaError(error);
    }
    return data;
  }

  if (params.targetStatus === "Active") {
    const { data, error } = await supabase.rpc("set_plantilla_active", {
      p_plantilla_id: params.plantillaId,
    });
    if (error) {
      throwPlantillaError(error);
    }
    return data;
  }

  if (params.targetStatus === "Floating") {
    const remarks = [
      params.reason ? `Reason: ${params.reason}` : null,
      params.remarks?.trim() ? `Remarks: ${params.remarks.trim()}` : null,
    ]
      .filter(Boolean)
      .join(" | ");

    const { data, error } = await supabase.rpc("set_plantilla_floating", {
      p_plantilla_id: params.plantillaId,
      p_remarks: remarks || null,
    });
    if (error) {
      throwPlantillaError(error);
    }
    return data;
  }

  throw new PlantillaDataError("retryable", `Unsupported employment status target: ${params.targetStatus}`);
}

export async function createDeactivationRequest(params: CreateDeactivationRequestParams) {
  const supabase = createClient();

  // Try authoritative create_deactivation_request
  const { data, error } = await supabase.rpc("create_deactivation_request", {
    p_plantilla_id: params.plantillaId,
  });

  if (error) {
    // Fallback: plantilla_request_deactivation
    const combinedRemarks = [
      params.reason ? `Reason: ${params.reason}` : null,
      params.remarks?.trim() ? `Justification: ${params.remarks.trim()}` : null,
    ]
      .filter(Boolean)
      .join(" | ");

    const { data: fallbackData, error: fallbackError } = await supabase.rpc("plantilla_request_deactivation", {
      p_plantilla_id: params.plantillaId,
      p_reason: combinedRemarks || null,
    });

    if (fallbackError) {
      throwPlantillaError(fallbackError);
    }

    return fallbackData;
  }

  return data;
}

export function deriveIslandGroup(provinceOrRegion: string | null | undefined): "Luzon" | "Visayas" | "Mindanao" | null {
  if (!provinceOrRegion) return null;
  const p = provinceOrRegion.trim().toLowerCase();

  const luzonList = [
    "metro manila", "ncr", "national capital region", "manila", "quezon city",
    "caloocan", "las piñas", "las pinas", "makati", "malabon", "mandaluyong",
    "marikina", "muntinlupa", "navotas", "parañaque", "paranaque",
    "pasay", "pasig", "pateros", "san juan", "taguig", "valenzuela",
    "car", "cordillera", "cordillera administrative region",
    "abra", "apayao", "benguet", "ifugao", "kalinga", "mountain province",
    "baguio", "baguio city",
    "region i", "ilocos region", "ilocos norte", "ilocos sur", "la union", "pangasinan",
    "region ii", "cagayan valley", "batanes", "cagayan", "isabela", "nueva vizcaya", "quirino",
    "region iii", "central luzon", "aurora", "bataan", "bulacan", "nueva ecija", "pampanga", "tarlac", "zambales",
    "region iv-a", "calabarzon", "batangas", "cavite", "laguna", "quezon", "rizal",
    "region iv-b", "mimaropa", "marinduque", "occidental mindoro", "oriental mindoro", "palawan", "romblon",
    "region v", "bicol region", "albay", "camarines norte", "camarines sur", "catanduanes", "masbate", "sorsogon",
    "luzon",
  ];

  const visayasList = [
    "region vi", "western visayas", "aklan", "antique", "capiz", "guimaras", "iloilo", "negros occidental",
    "region vii", "central visayas", "bohol", "cebu", "negros oriental", "siquijor",
    "region viii", "eastern visayas", "biliran", "eastern samar", "leyte", "northern samar", "samar", "southern leyte",
    "visayas",
  ];

  const mindanaoList = [
    "region ix", "zamboanga peninsula", "zamboanga del norte", "zamboanga del sur", "zamboanga sibugay",
    "region x", "northern mindanao", "bukidnon", "camiguin", "lanao del norte", "misamis occidental", "misamis oriental",
    "region xi", "davao region", "compostela valley", "davao de oro", "davao del norte", "davao del sur", "davao occidental", "davao oriental",
    "region xii", "soccsksargen", "cotabato", "north cotabato", "sarangani", "south cotabato", "sultan kudarat",
    "region xiii", "caraga", "agusan del norte", "agusan del sur", "dinagat islands", "surigao del norte", "surigao del sur",
    "barmm", "bangsamoro", "basilan", "lanao del sur", "maguindanao", "sulu", "tawi-tawi", "maguindanao del norte", "maguindanao del sur",
    "mindanao",
  ];

  if (luzonList.some((item) => p.includes(item))) return "Luzon";
  if (visayasList.some((item) => p.includes(item))) return "Visayas";
  if (mindanaoList.some((item) => p.includes(item))) return "Mindanao";

  return null;
}

export async function fetchDestinationStores(accountId?: string | null): Promise<DestinationStoreItem[]> {
  const supabase = createClient();

  let query = supabase
    .from("stores")
    .select(`
      id,
      store_name,
      vcode,
      account_id,
      group_id,
      area_city,
      province,
      area_province,
      island_group,
      is_active,
      accounts (
        account_name
      ),
      groups (
        group_name
      )
    `)
    .eq("is_active", true);

  if (accountId) {
    query = query.eq("account_id", accountId);
  }

  const { data, error } = await query.order("store_name", { ascending: true });

  if (error) {
    throwPlantillaError(error);
  }

  return asArray(data).map((row) => {
    const obj = asObject(row);
    const accountsObj = asObject(obj.accounts);
    const groupsObj = asObject(obj.groups);

    const prov = asString(obj.province) ?? asString(obj.area_province);
    const derivedIg = asString(obj.island_group) ?? deriveIslandGroup(prov);

    return {
      id: asString(obj.id) ?? "",
      storeName: asString(obj.store_name) ?? "Unnamed Store",
      vcode: asString(obj.vcode),
      accountId: asString(obj.account_id),
      accountName: asString(accountsObj.account_name),
      groupId: asString(obj.group_id),
      groupName: asString(groupsObj.group_name),
      areaCity: asString(obj.area_city),
      province: asString(obj.province),
      areaProvince: asString(obj.area_province),
      islandGroup: derivedIg,
      isActive: asBoolean(obj.is_active),
    };
  });
}

export async function transferPlantillaPersonnel(params: TransferPersonnelParams) {
  const supabase = createClient();

  const effectiveRemarks = [
    params.reason ? `Reason: ${params.reason}` : null,
    params.effectiveDate ? `Effective Date: ${params.effectiveDate}` : null,
  ]
    .filter(Boolean)
    .join(" | ");

  const rpcParams: Record<string, unknown> = {
    p_plantilla_id: params.plantillaId,
    p_target_store_id: params.targetStoreId,
    p_remarks: effectiveRemarks || null,
  };

  if (params.targetPositionId) {
    rpcParams.p_target_position_id = params.targetPositionId;
  }

  const { data, error } = await supabase.rpc("plantilla_transfer", rpcParams);

  if (error) {
    throwPlantillaError(error);
  }

  return data;
}

// ---------------------------------------------------------------------------
// Standardized Cache Invalidation Helper
// ---------------------------------------------------------------------------

function invalidatePlantillaCaches(
  queryClient: ReturnType<typeof useQueryClient>,
  plantillaId?: string,
) {
  queryClient.invalidateQueries({ queryKey: ["plantilla"] });
  if (plantillaId) {
    queryClient.invalidateQueries({ queryKey: ["plantilla", "detail", plantillaId] });
  }
  queryClient.invalidateQueries({ queryKey: ["plantilla-detail"] });
  queryClient.invalidateQueries({ queryKey: ["web-plantilla-summary"] });
  queryClient.invalidateQueries({ queryKey: ["store-staffing"] });
  queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
  queryClient.invalidateQueries({ queryKey: ["vacancies"] });
}

// ---------------------------------------------------------------------------
// React Query Mutation Hooks
// ---------------------------------------------------------------------------

export function useUpdateSeparationStatus() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateSeparationParams) => updatePlantillaSeparation(params),
    onSuccess: (_, variables) => {
      invalidatePlantillaCaches(queryClient, variables.plantillaId);
    },
  });
}

export function useUpdateEmploymentStatus() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateEmploymentStatusParams) =>
      updatePlantillaEmploymentStatus(params),
    onSuccess: (_, variables) => {
      invalidatePlantillaCaches(queryClient, variables.plantillaId);
    },
  });
}

export function useCreateDeactivationRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: CreateDeactivationRequestParams) =>
      createDeactivationRequest(params),
    onSuccess: (_, variables) => {
      invalidatePlantillaCaches(queryClient, variables.plantillaId);
    },
  });
}

export function useTransferPersonnel() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: TransferPersonnelParams) =>
      transferPlantillaPersonnel(params),
    onSuccess: (_, variables) => {
      invalidatePlantillaCaches(queryClient, variables.plantillaId);
    },
  });
}

// ---------------------------------------------------------------------------
// ADR-001 Slot Inspector & Audit Timeline Queries
// ---------------------------------------------------------------------------

export async function fetchPlantillaSlotDetail(slotId: string): Promise<PlantillaSlotItem> {
  if (!slotId) {
    throw new PlantillaDataError("retryable", "Missing slotId parameter");
  }

  const supabase = createClient();

  // 1. Fetch slot row
  const { data: slotRow, error: slotError } = await supabase
    .from("plantilla_slots")
    .select(`
      id,
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      slot_ordinal,
      legacy_vcode,
      source_hc_request_id,
      current_occupant_plantilla_id,
      created_at,
      updated_at,
      closed_at,
      closure_reason_code
    `)
    .eq("id", slotId)
    .maybeSingle();

  if (slotError) {
    throwPlantillaError(slotError);
  }

  if (!slotRow) {
    throw new PlantillaDataError("retryable", "Slot not found");
  }

  const slotObj = asObject(slotRow);
  const storeId = asString(slotObj.store_id);
  const accountId = asString(slotObj.account_id);
  const groupId = asString(slotObj.group_id);
  const occupantPlantillaId = asString(slotObj.current_occupant_plantilla_id);
  const legacyVcode = asString(slotObj.legacy_vcode);
  const slotStatus = asString(slotObj.slot_status) ?? "open";

  // 2. Concurrently enrich store, account, group, occupant, applicant, and quota
  let storeName: string | null = null;
  let storeCode: string | null = null;
  let accountName: string | null = null;
  let groupName: string | null = null;
  let occupant: PlantillaSlotOccupant | null = null;
  let candidate: PlantillaSlotCandidate | null = null;
  let requiredHeadcountQuota: number | null = null;

  const enrichmentPromises: Promise<void>[] = [];

  // Store lookup
  if (storeId) {
    enrichmentPromises.push(
      (async () => {
        try {
          const { data: sData } = await supabase
            .from("stores")
            .select("store_name, vcode")
            .eq("id", storeId)
            .maybeSingle();
          if (sData) {
            storeName = asString(sData.store_name);
            storeCode = asString(sData.vcode);
          }
        } catch {
          // non-blocking
        }
      })()
    );
  }

  // Account lookup
  if (accountId) {
    enrichmentPromises.push(
      (async () => {
        try {
          const { data: aData } = await supabase
            .from("accounts")
            .select("account_name")
            .eq("id", accountId)
            .maybeSingle();
          if (aData) {
            accountName = asString(aData.account_name);
          }
        } catch {
          // non-blocking
        }
      })()
    );
  }

  // Group lookup
  if (groupId) {
    enrichmentPromises.push(
      (async () => {
        try {
          const { data: gData } = await supabase
            .from("groups")
            .select("group_name")
            .eq("id", groupId)
            .maybeSingle();
          if (gData) {
            groupName = asString(gData.group_name);
          }
        } catch {
          // non-blocking
        }
      })()
    );
  }

  // Occupant lookup (if occupied)
  if (occupantPlantillaId) {
    enrichmentPromises.push(
      (async () => {
        try {
          const { data: pData } = await supabase
            .from("plantilla")
            .select("id, employee_no, employee_name, position, deployment_type, status")
            .eq("id", occupantPlantillaId)
            .maybeSingle();
          if (pData) {
            occupant = {
              id: asString(pData.id) ?? occupantPlantillaId,
              employeeNo: asString(pData.employee_no),
              employeeName: asString(pData.employee_name),
              position: asString(pData.position),
              deploymentType: asString(pData.deployment_type),
              status: asString(pData.status),
            };
          }
        } catch {
          // non-blocking
        }
      })()
    );
  }

  // Pipeline candidate lookup (if pipeline or hr_processing)
  if (slotStatus === "pipeline" || slotStatus === "hr_processing") {
    enrichmentPromises.push(
      (async () => {
        try {
          // First check applicants linked by slot_id
          const { data: appData } = await supabase
            .from("applicants")
            .select("id, full_name, first_name, last_name, status, contact_number, email_address")
            .eq("slot_id", slotId)
            .maybeSingle();

          if (appData) {
            const rawName = asString(appData.full_name) ||
              [asString(appData.first_name), asString(appData.last_name)].filter(Boolean).join(" ");
            candidate = {
              id: asString(appData.id) ?? "",
              name: rawName || "Active Candidate",
              status: asString(appData.status),
              contactNumber: asString(appData.contact_number),
              email: asString(appData.email_address),
            };
          } else if (legacyVcode) {
            // Fallback for VCode binding if slot_id is empty
            const { data: vApp } = await supabase
              .from("applicants")
              .select("id, full_name, first_name, last_name, status, contact_number, email_address")
              .eq("vacancy_vcode", legacyVcode)
              .order("created_at", { ascending: false })
              .limit(1)
              .maybeSingle();

            if (vApp) {
              const rawName = asString(vApp.full_name) ||
                [asString(vApp.first_name), asString(vApp.last_name)].filter(Boolean).join(" ");
              candidate = {
                id: asString(vApp.id) ?? "",
                name: rawName || "Active Candidate",
                status: asString(vApp.status),
                contactNumber: asString(vApp.contact_number),
                email: asString(vApp.email_address),
              };
            }
          }
        } catch {
          // non-blocking
        }
      })()
    );
  }

  // Vacancy Quota lookup
  if (legacyVcode) {
    enrichmentPromises.push(
      (async () => {
        try {
          const { data: vData } = await supabase
            .from("vacancies")
            .select("required_headcount")
            .eq("vcode", legacyVcode)
            .maybeSingle();
          if (vData) {
            requiredHeadcountQuota = Math.round(Number(vData.required_headcount ?? 1)) || 1;
          }
        } catch {
          // non-blocking
        }
      })()
    );
  }

  await Promise.all(enrichmentPromises);

  return {
    id: asString(slotObj.id) ?? slotId,
    storeId,
    storeName,
    storeCode,
    accountId,
    accountName,
    groupId,
    groupName,
    position: asString(slotObj.position) ?? "General Staff",
    employmentType: asString(slotObj.employment_type) ?? "Stationary",
    isRoving: asBoolean(slotObj.is_roving),
    slotStatus,
    slotOrdinal: Math.round(Number(slotObj.slot_ordinal ?? 1)) || 1,
    legacyVcode,
    sourceHcRequestId: asString(slotObj.source_hc_request_id),
    currentOccupantPlantillaId: occupantPlantillaId,
    occupant,
    candidate,
    requiredHeadcountQuota,
    createdAt: asString(slotObj.created_at) ?? new Date().toISOString(),
    updatedAt: asString(slotObj.updated_at) ?? new Date().toISOString(),
    closedAt: asString(slotObj.closed_at),
    closureReasonCode: asString(slotObj.closure_reason_code),
  };
}

export async function fetchSlotHistory(slotId: string): Promise<PlantillaSlotHistoryEvent[]> {
  if (!slotId) return [];

  const supabase = createClient();

  const { data, error } = await supabase
    .from("slot_history")
    .select(`
      id,
      slot_id,
      account_id,
      action_type,
      old_value,
      new_value,
      reason_code,
      performed_by,
      remarks,
      created_at
    `)
    .eq("slot_id", slotId)
    .order("created_at", { ascending: false });

  if (error) {
    throwPlantillaError(error);
  }

  const events = asArray(data).map((row) => {
    const obj = asObject(row);
    return {
      id: asString(obj.id) ?? "",
      slotId: asString(obj.slot_id) ?? slotId,
      accountId: asString(obj.account_id),
      actionType: asString(obj.action_type) ?? "status_change",
      oldValue: asString(obj.old_value),
      newValue: asString(obj.new_value),
      reasonCode: asString(obj.reason_code),
      performedBy: asString(obj.performed_by),
      performerName: null as string | null,
      remarks: asString(obj.remarks),
      createdAt: asString(obj.created_at) ?? new Date().toISOString(),
    };
  });

  // Resolve performer names where performed_by is available
  const performerIds = Array.from(
    new Set(events.map((e) => e.performedBy).filter((id): id is string => Boolean(id)))
  );

  if (performerIds.length > 0) {
    try {
      const { data: profiles } = await supabase
        .from("users_profile")
        .select("id, full_name")
        .in("id", performerIds);

      if (Array.isArray(profiles)) {
        const profileMap = new Map<string, string>();
        for (const p of profiles) {
          if (p.id && p.full_name) {
            profileMap.set(p.id, p.full_name);
          }
        }
        for (const ev of events) {
          if (ev.performedBy && profileMap.has(ev.performedBy)) {
            ev.performerName = profileMap.get(ev.performedBy) ?? null;
          }
        }
      }
    } catch {
      // Non-blocking performer name resolution
    }
  }

  return events;
}

export function usePlantillaSlotDetail(slotId: string | null) {
  return useQuery({
    queryKey: ["plantilla-slot-detail", slotId],
    queryFn: () => fetchPlantillaSlotDetail(slotId!),
    enabled: Boolean(slotId),
    retry: false,
  });
}

export function useSlotHistory(slotId: string | null) {
  return useQuery({
    queryKey: ["slot-history", slotId],
    queryFn: () => fetchSlotHistory(slotId!),
    enabled: Boolean(slotId),
    retry: false,
  });
}

export async function fetchStorePlantillaSlots(storeId: string): Promise<PlantillaSlotItem[]> {
  if (!storeId) return [];

  const supabase = createClient();

  const { data: slotRows, error: slotError } = await supabase
    .from("plantilla_slots")
    .select(`
      id,
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      slot_ordinal,
      legacy_vcode,
      source_hc_request_id,
      current_occupant_plantilla_id,
      created_at,
      updated_at,
      closed_at,
      closure_reason_code
    `)
    .eq("store_id", storeId)
    .order("legacy_vcode", { ascending: true })
    .order("slot_ordinal", { ascending: true });

  if (slotError) {
    throwPlantillaError(slotError);
  }

  const slots = asArray(slotRows).map((r) => asObject(r));
  if (slots.length === 0) return [];

  const occupantIds = slots
    .map((s) => asString(s.current_occupant_plantilla_id))
    .filter((id): id is string => Boolean(id));

  const slotIds = slots.map((s) => asString(s.id)).filter((id): id is string => Boolean(id));
  const vcodes = Array.from(new Set(slots.map((s) => asString(s.legacy_vcode)).filter((v): v is string => Boolean(v))));

  // Fetch occupants in batch
  const occupantMap = new Map<string, PlantillaSlotOccupant>();
  if (occupantIds.length > 0) {
    try {
      const { data: occupants } = await supabase
        .from("plantilla")
        .select("id, employee_no, employee_name, position, deployment_type, status")
        .in("id", occupantIds);

      for (const occ of occupants ?? []) {
        if (occ.id) {
          occupantMap.set(occ.id, {
            id: occ.id,
            employeeNo: asString(occ.employee_no),
            employeeName: asString(occ.employee_name),
            position: asString(occ.position),
            deploymentType: asString(occ.deployment_type),
            status: asString(occ.status),
          });
        }
      }
    } catch {
      // Non-blocking
    }
  }

  // Fetch candidate bindings in batch
  const candidateMap = new Map<string, PlantillaSlotCandidate>();
  if (slotIds.length > 0) {
    try {
      const { data: applicants } = await supabase
        .from("applicants")
        .select("id, slot_id, vacancy_vcode, full_name, first_name, last_name, status, contact_number, email_address")
        .in("slot_id", slotIds);

      for (const app of applicants ?? []) {
        if (app.slot_id) {
          const rawName = asString(app.full_name) ||
            [asString(app.first_name), asString(app.last_name)].filter(Boolean).join(" ");
          candidateMap.set(app.slot_id, {
            id: asString(app.id) ?? "",
            name: rawName || "Candidate",
            status: asString(app.status),
            contactNumber: asString(app.contact_number),
            email: asString(app.email_address),
          });
        }
      }
    } catch {
      // Non-blocking
    }
  }

  // Fetch quotas in batch
  const quotaMap = new Map<string, number>();
  if (vcodes.length > 0) {
    try {
      const { data: vacs } = await supabase
        .from("vacancies")
        .select("vcode, required_headcount")
        .in("vcode", vcodes);

      for (const v of vacs ?? []) {
        if (v.vcode) {
          quotaMap.set(v.vcode, Math.round(Number(v.required_headcount ?? 1)) || 1);
        }
      }
    } catch {
      // Non-blocking
    }
  }

  return slots.map((s) => {
    const slotObj = asObject(s);
    const sid = asString(slotObj.id) ?? "";
    const occId = asString(slotObj.current_occupant_plantilla_id);
    const vcode = asString(slotObj.legacy_vcode);

    return {
      id: sid,
      storeId: asString(slotObj.store_id),
      storeName: null,
      storeCode: null,
      accountId: asString(slotObj.account_id),
      accountName: null,
      groupId: asString(slotObj.group_id),
      groupName: null,
      position: asString(slotObj.position) ?? "General Staff",
      employmentType: asString(slotObj.employment_type) ?? "Stationary",
      isRoving: asBoolean(slotObj.is_roving),
      slotStatus: asString(slotObj.slot_status) ?? "open",
      slotOrdinal: Math.round(Number(slotObj.slot_ordinal ?? 1)) || 1,
      legacyVcode: vcode,
      sourceHcRequestId: asString(slotObj.source_hc_request_id),
      currentOccupantPlantillaId: occId,
      occupant: occId ? occupantMap.get(occId) ?? null : null,
      candidate: candidateMap.get(sid) ?? null,
      requiredHeadcountQuota: vcode ? quotaMap.get(vcode) ?? null : null,
      createdAt: asString(slotObj.created_at) ?? new Date().toISOString(),
      updatedAt: asString(slotObj.updated_at) ?? new Date().toISOString(),
      closedAt: asString(slotObj.closed_at),
      closureReasonCode: asString(slotObj.closure_reason_code),
    };
  });
}

export function useStorePlantillaSlots(storeId: string | null) {
  return useQuery({
    queryKey: ["store-plantilla-slots", storeId],
    queryFn: () => fetchStorePlantillaSlots(storeId!),
    enabled: Boolean(storeId),
    retry: false,
  });
}


