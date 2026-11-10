import { useMemo } from "react";
import type { PostgrestError } from "@supabase/supabase-js";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { WebCurrentUserContext } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";
import { formatPersonName } from "@/lib/utils/formatName";

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
  vcode?: string | null;
  scheduleDays?: string | null;
  scheduleTime?: string | null;
  area?: string | null;
  city?: string | null;
  province?: string | null;
};

export type PlantillaGovernmentIds = {
  sss: string | null;
  philhealth: string | null;
  pagibig: string | null;
  tin: string | null;
  atmNumber?: string | null;
  atmNumberMasked?: string | null;
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
  fullName?: string | null;
  vcode?: string | null;
  cgCode?: string | null;
  assignedStores?: string[];
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
  separationType?: string | null;
  separationDate?: string | null;
  clearanceStatus?: string | null;
  separationRemarks?: string | null;
  isActive?: boolean;
  rowCapabilities: PlantillaRowCapabilities;
  totalCount: number;
  createdAt?: string | null;
  updatedAt?: string | null;
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
  vcode?: string | null;
  cgCode?: string | null;
  positionTitle: string | null;
  accountName: string | null;
  primaryStoreName: string | null;
  assignmentType: string | null;
  employmentType?: string | null;
  coveredStores: PlantillaCoveredStore[];
  plantillaType: PlantillaPlantillaType | null;
  plantillaStatus: PlantillaStatus | null;
  dateDeployed: string | null;
  dateHired?: string | null;
  tenureDescription: string | null;
  dailyRate?: string | null;
  coordinator?: string | null;
  hrcoName?: string | null;
  area?: string | null;
  lastMikaSyncedAt?: string | null;
  lastMikaSyncedBy?: string | null;
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
  scheduleDays?: string | null;
  scheduleTime?: string | null;
  dayoff?: string | null;
  birthDate?: string | null;
  civilStatus?: string | null;
  contactNumber?: string | null;
  residentialAddress?: string | null;
  rowCapabilities: PlantillaRowCapabilities;
};

// ---------------------------------------------------------------------------
// Query params
// ---------------------------------------------------------------------------

export type PlantillaEmployeeListParams = {
  accountId?: string;
  accountName?: string;
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
const MAX_PAGE_SIZE = 5000;
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
): { firstName: string | null; lastName: string | null; fullName: string | null } {
  const formatted = formatPersonName(firstName, lastName, middleName, fullName);
  if (!formatted) {
    return { firstName: null, lastName: null, fullName: null };
  }

  const commaIndex = formatted.indexOf(",");
  if (commaIndex !== -1) {
    const lastPart = formatted.substring(0, commaIndex).trim();
    const firstPart = formatted.substring(commaIndex + 1).trim();
    return {
      firstName: firstPart || null,
      lastName: lastPart || null,
      fullName: formatted,
    };
  }

  return { firstName: formatted, lastName: null, fullName: formatted };
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
    canTransferEmployee: raw.can_transfer_employee === true || raw.can_transfer === true,
    canSeparate: raw.can_separate === true || raw.can_resign === true || raw.can_endo === true || raw.can_update_employment_status === true,
    canUpdateStatus: raw.can_update_status === true || raw.can_separate === true || raw.can_update_employment_status === true,
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
    sss: asString(obj.sss ?? obj.sss_no),
    philhealth: asString(obj.philhealth ?? obj.philhealth_no),
    pagibig: asString(obj.pagibig ?? obj.pagibig_no),
    tin: asString(obj.tin ?? obj.tin_no),
    atmNumber: asString(obj.atm ?? obj.atm_no ?? obj.atm_number),
    atmNumberMasked: asString(obj.atm_no_masked ?? obj.atm_masked ?? obj.atmMasked),
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
    vcode: asString(obj.vcode ?? obj.store_code ?? obj.storeCode),
    scheduleDays: asString(obj.schedule_days ?? obj.scheduleDays ?? obj.schedule),
    scheduleTime: asString(obj.schedule_time ?? obj.scheduleTime),
    area: asString(obj.area),
    city: asString(obj.city),
    province: asString(obj.province),
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

  const rawVcode = asString(row.vcode);
  const isCg = rawVcode?.startsWith("CG-") || false;

  const rawStatus = asString(row.plantilla_status ?? row.status);
  const isActiveBool = row.is_active !== undefined ? asBoolean(row.is_active) : undefined;
  const resolvedStatus = rawStatus || (isActiveBool ? "Active" : "Inactive");

  return {
    id,
    employeeNo: asString(row.employee_no) ?? "Uncoded",
    firstName: nameObj.firstName,
    lastName: nameObj.lastName,
    fullName: nameObj.fullName,
    vcode: rawVcode,
    cgCode: isCg ? rawVcode : null,
    positionTitle: asString(row.position_title ?? row.position) ?? "Store Personnel",
    accountName: asString(row.account_name ?? row.account),
    primaryStoreName: asString(row.primary_store_name ?? row.store_name),
    assignmentType: asString(row.derived_employment_type ?? row.assignment_type ?? row.deployment_type) ?? (asCount(row.covered_stores_count ?? row.roving_store_count) > 1 ? "Roving" : "Stationary"),
    coveredStoresCount: asCount(row.covered_stores_count ?? row.roving_store_count),
    plantillaType: asString(row.plantilla_type),
    plantillaStatus: resolvedStatus,
    dateDeployed: asString(row.date_deployed ?? row.date_hired),
    tenureDays: asCount(row.tenure_days),
    baseRateMasked: asString(row.base_rate_masked),
    slaBreached: asBoolean(row.sla_breached),
    separationType: asString(row.separation_type ?? row.separationType ?? row.attrition_type ?? row.separation_status),
    separationDate: asString(
      row.separation_date ??
      row.separationDate ??
      row.date_separated ??
      row.resignation_date ??
      row.date_of_separation ??
      row.inactive_at ??
      row.updated_at
    ),
    clearanceStatus: asString(row.clearance_status ?? row.clearanceStatus),
    separationRemarks: asString(row.remarks ?? row.separation_remarks ?? row.separationRemarks),
    isActive: isActiveBool,
    rowCapabilities: normalizeEmployeeCapabilities(row.row_capabilities),
    totalCount: asCount(row.total_count),
    createdAt: asString(row.created_at ?? row.createdAt),
    updatedAt: asString(row.updated_at ?? row.updatedAt),
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

  const rawMasked = asObject(row.masked_fields);
  const coveredStores = asArray(row.covered_stores ?? row.roving_stores).map(normalizeCoveredStore);
  const clearanceChecklist = asArray(row.clearance_checklist).map(
    normalizeClearanceChecklistItem,
  );
  const clearanceDocuments = asArray(row.clearance_documents).map(
    normalizeClearanceDocument,
  );
  const auditTimeline = asArray(row.audit_timeline).map(normalizeAuditTimelineItem);

  const activeMovementRequest = normalizeMovementRequest(row.active_movement_req);

  const rawVcode = asString(row.vcode ?? rawMasked.vcode);
  const rawCgCode = asString(
    row.cg_code ??
      row.coverage_group_code_snapshot ??
      row.coverage_code ??
      rawMasked.cg_code ??
      rawMasked.coverage_group_code_snapshot
  );
  const isVcodeCg = rawVcode?.startsWith("CG-") || false;
  const resolvedCgCode = rawCgCode || (isVcodeCg ? rawVcode : null);
  const rawRate = row.rate ?? rawMasked.rate;
  const rawDailyRate = row.daily_rate ?? rawMasked.daily_rate;
  const derivedRate =
    rawRate != null && !isNaN(Number(rawRate))
      ? `₱${Number(rawRate).toFixed(2)}`
      : rawDailyRate != null && !isNaN(Number(rawDailyRate))
      ? `₱${Number(rawDailyRate).toFixed(2)}`
      : null;

  const govIds = normalizeGovernmentIds(row.government_ids ?? rawMasked.government_ids);
  if (!govIds.sss && (row.sss_no || rawMasked.sss_no)) govIds.sss = asString(row.sss_no ?? rawMasked.sss_no);
  if (!govIds.philhealth && (row.philhealth_no || rawMasked.philhealth_no)) govIds.philhealth = asString(row.philhealth_no ?? rawMasked.philhealth_no);
  if (!govIds.pagibig && (row.pagibig_no || rawMasked.pagibig_no)) govIds.pagibig = asString(row.pagibig_no ?? rawMasked.pagibig_no);
  if (!govIds.atmNumber && (row.atm_no || rawMasked.atm_no)) govIds.atmNumber = asString(row.atm_no ?? rawMasked.atm_no);
  if (!govIds.atmNumberMasked && (row.atm_no_masked || rawMasked.atm_no_masked)) govIds.atmNumberMasked = asString(row.atm_no_masked ?? rawMasked.atm_no_masked);

  const maskedFields: PlantillaMaskedFields = {
    baseRateMasked:
      asString(row.base_rate_masked ?? rawMasked.base_rate_masked) ?? derivedRate,
    contactNumber: asString(
      row.contact_number ?? rawMasked.contact_number ?? row.contact_no ?? rawMasked.contact_no,
    ),
    emailAddress: asString(row.email_address ?? rawMasked.email_address),
    residentialAddress: asString(
      row.residential_address ??
        rawMasked.residential_address ??
        row.address ??
        rawMasked.address ??
        row.area,
    ),
    governmentIds: govIds,
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
    vcode: rawVcode,
    cgCode: resolvedCgCode,
    positionTitle: asString(row.position_title),
    accountName: asString(row.account_name),
    primaryStoreName: asString(
      row.primary_store_name ?? rawMasked.primary_store_name ?? row.store_name,
    ),
    assignmentType: asString(row.derived_employment_type ?? row.assignment_type ?? row.deployment_type) ?? (coveredStores.length > 1 ? "Roving" : "Stationary"),
    employmentType: asString(row.employment_type ?? row.deployment_type ?? row.assignment_type),
    coveredStores,
    plantillaType: asString(row.plantilla_type),
    plantillaStatus: asString(row.plantilla_status ?? row.status),
    dateDeployed: asString(
      row.date_deployed ?? rawMasked.date_deployed ?? row.date_hired ?? rawMasked.date_hired,
    ),
    dateHired: asString(row.date_hired ?? rawMasked.date_hired ?? row.date_deployed),
    tenureDescription: asString(row.tenure_description),
    dailyRate: derivedRate ?? (rawDailyRate != null ? `₱${Number(rawDailyRate).toFixed(2)}` : null),
    coordinator: asString(row.coordinator ?? row.hrco_name),
    hrcoName: asString(row.hrco_name ?? row.coordinator),
    area: asString(row.area ?? row.province ?? row.area_province),
    lastMikaSyncedAt: asString(row.last_mika_synced_at ?? rawMasked.last_mika_synced_at),
    lastMikaSyncedBy: asString(row.last_mika_synced_by ?? rawMasked.last_mika_synced_by),
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
    scheduleDays: asString(row.schedule_days ?? row.schedule),
    scheduleTime: asString(row.schedule_time),
    dayoff: asString(row.dayoff ?? row.rest_day),
    birthDate: asString(
      row.birth_date ??
        row.date_of_birth ??
        row.birthdate ??
        rawMasked.birth_date ??
        rawMasked.date_of_birth ??
        rawMasked.birthdate
    ),
    civilStatus: asString(
      row.civil_status ??
        rawMasked.civil_status
    ),
    contactNumber: asString(
      row.contact_number ??
        rawMasked.contact_number ??
        row.contact_no ??
        rawMasked.contact_no ??
        row.phone ??
        row.mobile_number
    ),
    residentialAddress: asString(
      row.residential_address ??
        rawMasked.residential_address ??
        row.address ??
        rawMasked.address
    ),
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

/**
 * Calculates days elapsed in floating status since the effective separation/floating date.
 * Fallback priority: separationDate -> updatedAt -> createdAt.
 */
export function getFloatingDurationDays(emp: {
  separationDate?: string | null;
  updatedAt?: string | null;
  createdAt?: string | null;
}): number {
  const dateStr = emp.separationDate || emp.updatedAt || emp.createdAt;
  if (!dateStr) return 0;
  const start = new Date(dateStr).getTime();
  if (isNaN(start)) return 0;
  const diffMs = Date.now() - start;
  return Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
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
// Scoped Account Query
// ---------------------------------------------------------------------------

export interface PlantillaScopedAccountItem {
  id: string;
  name: string;
  groupId: string | null;
  hrcoUserId: string | null;
  groupName: string | null;
  isPoolAccount: boolean;
}

export async function fetchPlantillaScopedAccounts(
  currentUser: WebCurrentUserContext | null,
): Promise<PlantillaScopedAccountItem[]> {
  if (!currentUser) return [];

  const { mode: accountMode, ids: accountIds } = currentUser.accountScope;
  const { mode: groupMode, ids: groupIds } = currentUser.groupScope;

  if (accountMode === "none" || groupMode === "none") return [];

  const hasAllScope = accountMode === "all" && groupMode === "all";

  const supabase = createClient();
  let query = supabase
    .from("accounts")
    .select(`
      id,
      account_name,
      group_id,
      is_pool_account,
      hrco_user_id,
      groups (
        group_name
      )
    `)
    .eq("is_active", true);

  if (!hasAllScope) {
    if (groupMode === "scoped") {
      if (groupIds.length === 0) return [];
      query = query.in("group_id", groupIds);
    }

    if (accountMode === "scoped" && accountIds.length > 0) {
      query = query.in("id", accountIds);
    }
  }

  const { data, error } = await query.order("account_name");
  if (error) {
    throwPlantillaError(error);
  }

  return (data ?? []).map((row) => ({
    id: row.id as string,
    name: row.account_name as string,
    groupId: row.group_id as string | null,
    hrcoUserId: (row.hrco_user_id as string | null) ?? null,
    groupName: Array.isArray(row.groups)
      ? ((row.groups[0] as unknown as Record<string, unknown>)?.group_name as string | null)
      : row.groups && typeof row.groups === "object"
      ? ((row.groups as unknown as Record<string, unknown>).group_name as string | null)
      : null,
    isPoolAccount: !!row.is_pool_account,
  }));
}

// ---------------------------------------------------------------------------
// Public RPC wrappers
// ---------------------------------------------------------------------------

export async function getPlantillaSummary(
  params: PlantillaSummaryParams = {},
): Promise<PlantillaSummary> {
  const supabase = createClient();

  // If scoped to a specific account, prioritize v_account_allocation_kpi to ensure
  // 100% parity with the Directory card metrics (e.g. ALTURAS 754/755, 1 vacant).
  if (params.accountId) {
    try {
      const { data: kpiRows, error: kpiError } = await supabase
        .from("v_account_allocation_kpi")
        .select("actual_hc, slot_vacant_hc, pipeline_count, required_hc")
        .eq("account_id", params.accountId)
        .maybeSingle();

      if (!kpiError && kpiRows) {
        const actual = Number(kpiRows.actual_hc ?? 0);
        const vacant = Math.round(Number(kpiRows.slot_vacant_hc ?? 0));
        const hrProcess = Number(kpiRows.pipeline_count ?? 0);
        const required = Number(kpiRows.required_hc ?? (actual + vacant));
        if (actual > 0 || required > 0) {
          return {
            required,
            actual,
            hrProcess,
            vacant,
          };
        }
      }
    } catch {
      // Fall through to RPC if view query fails
    }
  }

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

  let rpcData: unknown = null;
  let rpcError: unknown = null;

  try {
    const res = await supabase.rpc("list_web_plantilla_employees", {
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
    rpcData = res.data;
    rpcError = res.error;
  } catch (err) {
    rpcError = err;
  }

  // If RPC errored and no accountId fallback is possible, throw error
  if (rpcError && !params.accountId) {
    throwPlantillaError(rpcError as PostgrestError);
  }

  let rows = (Array.isArray(rpcData) ? rpcData : [])
    .map((row) => normalizeEmployeeListRow(asObject(row)))
    .filter((row): row is PlantillaEmployeeListItem => row !== null);

  const initialTotalCount = getEmployeeTotalCount(rows);

  // If client requested more records than the DB RPC limit returned (e.g. 200 RPC cap vs 1000 requested),
  // fetch subsequent chunks concurrently to guarantee full account roster retention
  if (pageSize > rows.length && rows.length < initialTotalCount && !rpcError) {
    const chunkPromises: Promise<unknown>[] = [];
    const chunkSize = 200;
    for (
      let currentOffset = offset + rows.length;
      currentOffset < initialTotalCount && currentOffset < offset + pageSize;
      currentOffset += chunkSize
    ) {
      chunkPromises.push(
        Promise.resolve(
          supabase.rpc("list_web_plantilla_employees", {
            p_search: params.search?.trim() || null,
            p_account_id: params.accountId ?? null,
            p_group_id: params.groupId ?? null,
            p_store_id: params.storeId ?? null,
            p_employment_status: params.status ?? null,
            p_deployment: params.deployment ?? null,
            p_active_state: params.activeState ?? null,
            p_limit: Math.min(chunkSize, offset + pageSize - currentOffset),
            p_offset: currentOffset,
            p_sort_by: getAllowedSortField(
              params.sortBy,
              EMPLOYEE_SORT_FIELDS,
              DEFAULT_EMPLOYEE_SORT_BY,
            ),
            p_sort_dir: params.sortDir ?? "asc",
          }),
        ),
      );
    }

    try {
      const chunkResults = await Promise.all(chunkPromises);
      for (const chunk of chunkResults) {
        const res = chunk as { data?: unknown; error?: unknown };
        if (!res.error && Array.isArray(res.data)) {
          const parsed = res.data
            .map((row) => normalizeEmployeeListRow(asObject(row)))
            .filter((row): row is PlantillaEmployeeListItem => row !== null);
          rows = rows.concat(parsed);
        }
      }
    } catch {
      // Graceful fallback: continue with rows already fetched
    }
  }

  // Fallback: If RPC returned 0 rows or errored and an accountId was provided, query allocations / stores / tables directly
  // to prevent missing roster personnel due to RPC chunking, safe view scoping, or unlinked account_id fields.
  if (rows.length === 0 && params.accountId) {
    try {
      // 1. Resolve account name if not provided
      let accountName = params.accountName?.trim();
      if (!accountName) {
        const { data: acct } = await supabase
          .from("accounts")
          .select("account_name")
          .eq("id", params.accountId)
          .maybeSingle();
        accountName = (acct?.account_name as string | undefined)?.trim();
      }

      const safeRowsMap = new Map<string, Record<string, unknown>>();

      // 2. Fetch all stores under this account (canonical link for deployed store personnel)
      const { data: storeRows } = await supabase
        .from("stores")
        .select("id, store_name")
        .eq("account_id", params.accountId);

      const storeIds = (storeRows ?? [])
        .map((s) => s.id as string)
        .filter(Boolean);
      const storeNameMap = new Map<string, string>();
      for (const st of storeRows ?? []) {
        if (st.id && st.store_name) {
          storeNameMap.set(st.id as string, st.store_name as string);
        }
      }

      // 3. Fetch active allocations from employee_store_allocations
      // (100% parity with v_account_allocation_kpi canonical metrics)
      const { data: allocRows } = await supabase
        .from("employee_store_allocations")
        .select("id, plantilla_id, employee_no, store_id, store_name, filled_hc, vcode")
        .eq("account_id", params.accountId)
        .eq("is_active", true);

      const allocList = Array.isArray(allocRows) ? allocRows : [];
      const allocMap = new Map<string, Record<string, unknown>>();
      for (const a of allocList) {
        const pid = asString(a.plantilla_id);
        const eno = asString(a.employee_no);
        if (pid) allocMap.set(pid, a as Record<string, unknown>);
        if (eno) allocMap.set(eno, a as Record<string, unknown>);
      }

      const allocatedPlantillaIds = Array.from(
        new Set(
          allocList
            .map((r) => r.plantilla_id as string | undefined)
            .filter((id): id is string => Boolean(id))
        )
      );
      const allocatedEmployeeNos = Array.from(
        new Set(
          allocList
            .map((r) => r.employee_no as string | undefined)
            .filter((no): no is string => Boolean(no))
        )
      );

      const addRowsToMap = (records: unknown) => {
        if (!Array.isArray(records)) return;
        for (const item of records) {
          const rec = item as Record<string, unknown>;
          const key = (rec.id as string) || (rec.plantilla_id as string) || (rec.employee_no as string);
          if (key && !safeRowsMap.has(key)) {
            safeRowsMap.set(key, rec);
          }
        }
      };

      // Strategy A: Query by allocated plantilla_id in chunks using safe wildcard
      if (allocatedPlantillaIds.length > 0) {
        const chunkSize = 100;
        for (let i = 0; i < allocatedPlantillaIds.length; i += chunkSize) {
          const chunk = allocatedPlantillaIds.slice(i, i + chunkSize);

          // Try v_plantilla_safe first with safe wildcard
          const { data: safeData } = await supabase
            .from("v_plantilla_safe")
            .select("*")
            .in("id", chunk);
          addRowsToMap(safeData);

          // For any IDs in this chunk not resolved yet, query plantilla table directly
          const missingChunk = chunk.filter((id) => !safeRowsMap.has(id));
          if (missingChunk.length > 0) {
            const { data: tableData } = await supabase
              .from("plantilla")
              .select("*")
              .in("id", missingChunk);
            addRowsToMap(tableData);
          }
        }
      }

      // Strategy B: Query by allocated employee_no in chunks if any allocations are still missing
      if (allocatedEmployeeNos.length > 0 && safeRowsMap.size < allocatedEmployeeNos.length) {
        const chunkSize = 100;
        for (let i = 0; i < allocatedEmployeeNos.length; i += chunkSize) {
          const chunk = allocatedEmployeeNos.slice(i, i + chunkSize);
          const { data: safeData } = await supabase
            .from("v_plantilla_safe")
            .select("*")
            .in("employee_no", chunk);
          addRowsToMap(safeData);

          const missingChunk = chunk.filter((eno) => !safeRowsMap.has(eno));
          if (missingChunk.length > 0) {
            const { data: tableData } = await supabase
              .from("plantilla")
              .select("*")
              .in("employee_no", missingChunk);
            addRowsToMap(tableData);
          }
        }
      }

      // Strategy C: Query by store_ids under account
      if (safeRowsMap.size === 0 && storeIds.length > 0) {
        const chunkSize = 50;
        for (let i = 0; i < storeIds.length; i += chunkSize) {
          const chunk = storeIds.slice(i, i + chunkSize);
          const { data: safeData } = await supabase
            .from("v_plantilla_safe")
            .select("*")
            .in("store_id", chunk);
          addRowsToMap(safeData);

          if (safeRowsMap.size === 0) {
            const { data: tableData } = await supabase
              .from("plantilla")
              .select("*")
              .in("store_id", chunk);
            addRowsToMap(tableData);
          }
        }
      }

      // Strategy D: Query by account wildcard or account_id directly
      if (safeRowsMap.size === 0 && accountName) {
        const { data: safeData } = await supabase
          .from("v_plantilla_safe")
          .select("*")
          .ilike("account", `%${accountName}%`)
          .limit(pageSize);
        addRowsToMap(safeData);

        if (safeRowsMap.size === 0) {
          const { data: tableData } = await supabase
            .from("plantilla")
            .select("*")
            .ilike("account", `%${accountName}%`)
            .limit(pageSize);
          addRowsToMap(tableData);
        }
      }
      if (safeRowsMap.size === 0) {
        const { data: idSafeData } = await supabase
          .from("v_plantilla_safe")
          .select("*")
          .eq("account_id", params.accountId)
          .limit(pageSize);
        addRowsToMap(idSafeData);

        if (safeRowsMap.size === 0) {
          const { data: idTableData } = await supabase
            .from("plantilla")
            .select("*")
            .eq("account_id", params.accountId)
            .limit(pageSize);
          addRowsToMap(idTableData);
        }
      }

      // Strategy E: Headcount parity guarantee against employee_store_allocations
      // If any active allocation row was not resolved from plantilla tables, synthesize a valid row
      if (allocList.length > 0) {
        for (const alloc of allocList) {
          const pid = asString(alloc.plantilla_id);
          const eno = asString(alloc.employee_no);
          const found = (pid && safeRowsMap.has(pid)) || (eno && safeRowsMap.has(eno));
          if (!found) {
            const fallbackKey = pid || eno || asString(alloc.id);
            if (fallbackKey && !safeRowsMap.has(fallbackKey)) {
              safeRowsMap.set(fallbackKey, {
                id: fallbackKey,
                plantilla_id: pid || fallbackKey,
                employee_no: eno || "Uncoded",
                employee_name: `Employee ${eno || fallbackKey}`,
                store_id: alloc.store_id,
                store_name: alloc.store_name,
                vcode: alloc.vcode,
                account: accountName || "ALTURAS",
                status: "Active",
                is_active: true,
              });
            }
          }
        }
      }

      let safeRows = Array.from(safeRowsMap.values());

      // Client-side search filtering if search term passed
      if (params.search?.trim()) {
        const q = params.search.trim().toLowerCase();
        safeRows = safeRows.filter((r) => {
          const name = String(r.employee_name || "").toLowerCase();
          const empNo = String(r.employee_no || "").toLowerCase();
          const store = String(r.store_name || "").toLowerCase();
          const vcode = String(r.vcode || "").toLowerCase();
          return name.includes(q) || empNo.includes(q) || store.includes(q) || vcode.includes(q);
        });
      }

      // Client-side status filtering if status passed
      if (params.status) {
        const targetStatus = params.status.toLowerCase().trim();
        safeRows = safeRows.filter((r) => {
          const s = String(r.status || "").toLowerCase().trim();
          if (targetStatus === "active") {
            return (
              s === "active" ||
              s === "active deployed" ||
              s === "deployed" ||
              s === "" ||
              !r.status
            );
          }
          return s === targetStatus;
        });
      }

      // Sort rows according to requested sort direction
      safeRows.sort((a, b) => {
        const nameA = String(a.employee_name || "");
        const nameB = String(b.employee_name || "");
        return params.sortDir === "desc"
          ? nameB.localeCompare(nameA)
          : nameA.localeCompare(nameB);
      });

      if (safeRows.length > 0) {
        rows = safeRows
          .map((row) => {
            const s = String(row.status || "").toLowerCase().trim();
            const sep = String(row.separation_status || "").toLowerCase().trim();
            const is_active =
              !row.deactivated_at &&
              !row.date_of_separation &&
              !["inactive", "deactivated", "resigned", "separated", "endo", "terminated"].includes(s) &&
              !["inactive", "deactivated", "resigned", "separated", "endo", "terminated"].includes(sep);
            const is_inactive = !is_active;

            if (params.activeState === "active" && !is_active) return null;
            if (params.activeState === "inactive" && !is_inactive) return null;

            const rowStoreId = asString(row.store_id);
            const resolvedStoreName =
              asString(row.store_name) ||
              (rowStoreId ? storeNameMap.get(rowStoreId) : undefined) ||
              asString(allocMap.get(asString(row.id) ?? "")?.store_name) ||
              asString(allocMap.get(asString(row.employee_no) ?? "")?.store_name);

            const rowVcode =
              asString(row.vcode) ||
              asString(allocMap.get(asString(row.id) ?? "")?.vcode) ||
              asString(allocMap.get(asString(row.employee_no) ?? "")?.vcode);

            return normalizeEmployeeListRow({
              ...row,
              plantilla_id: row.id,
              vcode: rowVcode,
              position_title: row.position ?? row.position_title ?? "Store Personnel",
              account_name: row.account || row.account_name || accountName || "ALTURAS",
              primary_store_name: resolvedStoreName,
              store_name: resolvedStoreName,
              is_active,
              is_inactive,
              total_count: safeRows.length,
            });
          })
          .filter((row): row is PlantillaEmployeeListItem => row !== null);
      }
    } catch (err) {
      console.warn("[Plantilla] Fallback query resolution encountered non-fatal error:", err);
    }
  }

  // Enrich assigned stores for coverage group employees (e.g., CG-TG2-0006)
  const cgCodes = Array.from(
    new Set(
      rows
        .map((r) => r.vcode)
        .filter((v): v is string => Boolean(v && v.startsWith("CG-"))),
    ),
  );

  if (cgCodes.length > 0) {
    try {
      const { data: cgData } = await supabase
        .from("coverage_groups")
        .select("coverage_code, coverage_group_stores(stores(store_name))")
        .in("coverage_code", cgCodes)
        .is("archived_at", null);

      if (cgData) {
        const storeMap = new Map<string, string[]>();
        for (const item of cgData as Array<Record<string, unknown>>) {
          const code = asString(item.coverage_code);
          const cgs = Array.isArray(item.coverage_group_stores) ? item.coverage_group_stores : [];
          const stores: string[] = [];
          for (const s of cgs as Array<Record<string, unknown>>) {
            const stObj = (s as Record<string, unknown>).stores as Record<string, unknown> | null;
            const stName = asString(stObj?.store_name);
            if (stName) stores.push(stName);
          }
          if (code && stores.length > 0) {
            storeMap.set(code, stores);
          }
        }

        for (const r of rows) {
          if (r.vcode && storeMap.has(r.vcode)) {
            r.assignedStores = storeMap.get(r.vcode);
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

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
    if (!error && typeof data === "number" && data > 0) {
      return data;
    }
  } catch {
    // Fallback
  }

  try {
    const fallbackRes = await listWebPlantillaEmployees({
      page: 1,
      accountId,
      activeState: "active",
      pageSize: 1,
    });
    return fallbackRes.totalCount;
  } catch {
    return 0;
  }
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
    if (!error && Array.isArray(data) && data.length > 0) {
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

  try {
    const fallbackRes = await listWebPlantillaEmployees({
      page: 1,
      accountId,
      search: search?.trim() || undefined,
      activeState: "active",
      pageSize: 200,
    });
    return fallbackRes.data;
  } catch {
    return [];
  }
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
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(plantillaId);

  let rpcRow: Record<string, unknown> | null = null;
  let rpcError: PostgrestError | null = null;

  // 1. Try primary RPC
  if (isUuid) {
    try {
      const { data, error } = await supabase.rpc("get_web_plantilla_detail", {
        p_employee_id: plantillaId,
      });

      if (error) {
        rpcError = error;
        console.warn("[Plantilla] get_web_plantilla_detail RPC returned error, attempting fallback:", error);
      } else {
        const raw = Array.isArray(data) ? data[0] : data;
        if (raw && typeof raw === "object") {
          rpcRow = asObject(raw);
        }
      }
    } catch (err) {
      console.warn("[Plantilla] get_web_plantilla_detail exception, attempting fallback:", err);
    }
  }

  // 2. Normalize RPC row if found
  let normalized = rpcRow ? normalizeDetailRow(rpcRow) : null;

  // 3. Fallback: If RPC failed, threw 42501/RLS error, or returned no row, query table directly
  if (!normalized) {
    let directData: Record<string, unknown> | null = null;

    // Check v_plantilla_safe first
    try {
      let safeQuery = supabase.from("v_plantilla_safe").select("*");
      safeQuery = isUuid ? safeQuery.eq("id", plantillaId) : safeQuery.eq("employee_no", plantillaId);
      const { data: safeRow } = await safeQuery.maybeSingle();
      if (safeRow && typeof safeRow === "object") {
        directData = asObject(safeRow);
      }
    } catch {
      // Ignore and proceed to direct table
    }

    // Check public.plantilla directly
    if (!directData) {
      try {
        let tableQuery = supabase.from("plantilla").select("*");
        tableQuery = isUuid ? tableQuery.eq("id", plantillaId) : tableQuery.eq("employee_no", plantillaId);
        const { data: tableRow } = await tableQuery.maybeSingle();
        if (tableRow && typeof tableRow === "object") {
          directData = asObject(tableRow);
        }
      } catch {
        // Ignore and proceed
      }
    }

    // Check employee_store_allocations in case plantillaId was an allocation id
    if (!directData) {
      try {
        let allocQuery = supabase.from("employee_store_allocations").select("plantilla_id, employee_no");
        allocQuery = isUuid ? allocQuery.eq("id", plantillaId) : allocQuery.eq("employee_no", plantillaId);
        const { data: allocRow } = await allocQuery.maybeSingle();
        if (allocRow && typeof allocRow === "object") {
          const allocObj = asObject(allocRow);
          const resolvedId = asString(allocObj.plantilla_id) || asString(allocObj.employee_no);
          if (resolvedId) {
            const isResolvedUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(resolvedId);
            let allocTableQuery = supabase.from("plantilla").select("*");
            allocTableQuery = isResolvedUuid ? allocTableQuery.eq("id", resolvedId) : allocTableQuery.eq("employee_no", resolvedId);
            const { data: allocPlantilla } = await allocTableQuery.maybeSingle();
            if (allocPlantilla && typeof allocPlantilla === "object") {
              directData = asObject(allocPlantilla);
            }
          }
        }
      } catch {
        // Ignore
      }
    }

    if (directData) {
      // Ensure capabilities default to allowed for direct table reads
      if (!directData.row_capabilities) {
        directData.row_capabilities = {
          can_view_detail: true,
          can_request_deactivation: true,
          can_review_deactivation: true,
          can_request_deletion: true,
          can_review_deletion: true,
          can_transfer_employee: true,
          can_separate: true,
          can_update_status: true,
        };
      }
      normalized = normalizeDetailRow(directData);
    }
  }

  // 4. If all strategies failed, throw the RPC error or not-found
  if (!normalized) {
    if (rpcError) {
      throwPlantillaError(rpcError);
    }
    throw new PlantillaDataError("retryable", "No Plantilla detail record found");
  }

  // Always ensure schedule terms (schedule_time, schedule_days, rest_day, dayoff) are hydrated from plantilla
  // because get_web_plantilla_detail RPC does not project schedule_time in its return table.
  try {
    const schedQuery = supabase
      .from("plantilla")
      .select("schedule, schedule_days, schedule_time, rest_day, dayoff")
      .eq(isUuid ? "id" : "employee_no", plantillaId);
    const { data: schedData } = await schedQuery.maybeSingle();
    if (schedData) {
      if (schedData.schedule_time) {
        normalized.scheduleTime = asString(schedData.schedule_time);
      }
      if (schedData.schedule_days) {
        normalized.scheduleDays = asString(schedData.schedule_days);
      } else if (schedData.schedule) {
        normalized.scheduleDays = asString(schedData.schedule);
      }
      if (schedData.dayoff || schedData.rest_day) {
        normalized.dayoff = asString(schedData.dayoff ?? schedData.rest_day);
      }
    }
  } catch (err) {
    console.warn("[Plantilla] schedule hydration exception:", err);
  }

  // Guaranteed Hydration Guard: Ensures demographic, coverage group, remuneration, and store assignment fields
  // are completely hydrated across multiple resilient database tiers whenever missing from primary RPC output.
  const isMissingKeyFields =
    !normalized.birthDate ||
    !normalized.civilStatus ||
    !normalized.contactNumber ||
    !normalized.residentialAddress ||
    !normalized.cgCode ||
    !normalized.primaryStoreName ||
    !normalized.maskedFields.baseRateMasked ||
    !normalized.maskedFields.residentialAddress ||
    !normalized.vcode ||
    !normalized.maskedFields.governmentIds.atmNumberMasked;

  if (isMissingKeyFields) {
    // Tier 1: public.plantilla direct table query (verified table columns only)
    try {
      let directQuery = supabase
        .from("plantilla")
        .select("vcode, store_name, rate, daily_rate, address, date_hired, contact_no, coordinator, hrco_name, schedule, rest_day, atm_no, sss_no, philhealth_no, pagibig_no, last_mika_synced_at, last_mika_synced_by, area, civil_status, date_of_birth, birthdate, coverage_group_id");
      directQuery = isUuid ? directQuery.eq("id", plantillaId) : directQuery.eq("employee_no", plantillaId);
      const { data: directData } = await directQuery.maybeSingle();

      if (directData) {
        if (!normalized.vcode && directData.vcode) {
          normalized.vcode = directData.vcode;
        }
        if (!normalized.primaryStoreName && (directData.store_name || directData.vcode)) {
          normalized.primaryStoreName = directData.store_name || directData.vcode;
        }
        if (!normalized.dateDeployed && directData.date_hired) {
          normalized.dateDeployed = directData.date_hired;
        }
        if (!normalized.dateHired && directData.date_hired) {
          normalized.dateHired = directData.date_hired;
        }
        if (!normalized.coordinator && (directData.coordinator || directData.hrco_name)) {
          normalized.coordinator = directData.coordinator || directData.hrco_name;
        }
        if (!normalized.area && directData.area) {
          normalized.area = directData.area;
        }
        if (!normalized.lastMikaSyncedAt && directData.last_mika_synced_at) {
          normalized.lastMikaSyncedAt = directData.last_mika_synced_at;
        }
        if (!normalized.lastMikaSyncedBy && directData.last_mika_synced_by) {
          normalized.lastMikaSyncedBy = directData.last_mika_synced_by;
        }
        if (!normalized.dailyRate) {
          if (directData.daily_rate != null) {
            normalized.dailyRate = `₱${Number(directData.daily_rate).toFixed(2)}`;
          } else if (directData.rate != null) {
            normalized.dailyRate = `₱${Number(directData.rate).toFixed(2)}`;
          }
        }
        if (!normalized.maskedFields.baseRateMasked) {
          if (directData.rate != null) {
            normalized.maskedFields.baseRateMasked = `₱${Number(directData.rate).toFixed(2)}`;
          } else if (directData.daily_rate != null) {
            normalized.maskedFields.baseRateMasked = `₱${Number(directData.daily_rate).toFixed(2)}`;
          }
        }
        if (!normalized.maskedFields.residentialAddress && directData.address) {
          normalized.maskedFields.residentialAddress = directData.address;
        }
        if (!normalized.residentialAddress && directData.address) {
          normalized.residentialAddress = directData.address;
        }
        if (!normalized.maskedFields.contactNumber && directData.contact_no) {
          normalized.maskedFields.contactNumber = directData.contact_no;
        }
        if (!normalized.contactNumber && directData.contact_no) {
          normalized.contactNumber = directData.contact_no;
        }
        if (!normalized.civilStatus && directData.civil_status) {
          normalized.civilStatus = asString(directData.civil_status);
        }
        if (!normalized.birthDate) {
          normalized.birthDate = asString(directData.date_of_birth || directData.birthdate);
        }
        if (!normalized.cgCode && directData.coverage_group_id) {
          try {
            const { data: cgRow } = await supabase
              .from("coverage_groups")
              .select("coverage_code")
              .eq("id", directData.coverage_group_id)
              .maybeSingle();
            if (cgRow?.coverage_code) {
              normalized.cgCode = asString(cgRow.coverage_code);
            }
          } catch {
            // Graceful fallback
          }
        }
        if (!normalized.maskedFields.governmentIds.sss && directData.sss_no) {
          normalized.maskedFields.governmentIds.sss = directData.sss_no;
        }
        if (!normalized.maskedFields.governmentIds.philhealth && directData.philhealth_no) {
          normalized.maskedFields.governmentIds.philhealth = directData.philhealth_no;
        }
        if (!normalized.maskedFields.governmentIds.pagibig && directData.pagibig_no) {
          normalized.maskedFields.governmentIds.pagibig = directData.pagibig_no;
        }
        if (!normalized.maskedFields.governmentIds.atmNumber && directData.atm_no) {
          normalized.maskedFields.governmentIds.atmNumber = directData.atm_no;
        }
        if (!normalized.maskedFields.governmentIds.atmNumberMasked && directData.atm_no) {
          const raw = directData.atm_no.trim();
          normalized.maskedFields.governmentIds.atmNumberMasked =
            raw.length <= 4 ? "****" : `••••-••••-${raw.slice(-4)}`;
        }
        if (!normalized.maskedFields.governmentIds.tin && (directData as Record<string, unknown>).tin_no) {
          normalized.maskedFields.governmentIds.tin = asString((directData as Record<string, unknown>).tin_no);
        }
      }
    } catch (err) {
      console.warn("[Plantilla] direct table query exception:", err);
    }

    // Tier 1.5: Hydrate government IDs and demographic fields from latest mika_import_rows
    const empNoForMika = normalized.employeeNo && normalized.employeeNo !== "Uncoded" ? normalized.employeeNo : null;
    if (
      empNoForMika &&
      (!normalized.maskedFields.governmentIds.sss ||
        !normalized.maskedFields.governmentIds.philhealth ||
        !normalized.maskedFields.governmentIds.pagibig ||
        !normalized.maskedFields.governmentIds.tin ||
        !normalized.maskedFields.governmentIds.atmNumber)
    ) {
      try {
        const { data: mikaRow } = await supabase
          .from("mika_import_rows")
          .select("sss_no, philhealth_no, pagibig_no, tin_no, atm_no, civil_status, birthdate, address, contact_number")
          .eq("employee_no", empNoForMika)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        if (mikaRow) {
          if (!normalized.maskedFields.governmentIds.sss && mikaRow.sss_no) {
            normalized.maskedFields.governmentIds.sss = mikaRow.sss_no;
          }
          if (!normalized.maskedFields.governmentIds.philhealth && mikaRow.philhealth_no) {
            normalized.maskedFields.governmentIds.philhealth = mikaRow.philhealth_no;
          }
          if (!normalized.maskedFields.governmentIds.pagibig && mikaRow.pagibig_no) {
            normalized.maskedFields.governmentIds.pagibig = mikaRow.pagibig_no;
          }
          if (!normalized.maskedFields.governmentIds.tin && mikaRow.tin_no) {
            normalized.maskedFields.governmentIds.tin = mikaRow.tin_no;
          }
          if (!normalized.maskedFields.governmentIds.atmNumber && mikaRow.atm_no) {
            normalized.maskedFields.governmentIds.atmNumber = mikaRow.atm_no;
          }
          if (!normalized.maskedFields.governmentIds.atmNumberMasked && mikaRow.atm_no) {
            const raw = mikaRow.atm_no.trim();
            normalized.maskedFields.governmentIds.atmNumberMasked =
              raw.length <= 4 ? "****" : `••••-••••-${raw.slice(-4)}`;
          }
          if (!normalized.civilStatus && mikaRow.civil_status) {
            normalized.civilStatus = asString(mikaRow.civil_status);
          }
          if (!normalized.birthDate && mikaRow.birthdate) {
            normalized.birthDate = asString(mikaRow.birthdate);
          }
          if (!normalized.residentialAddress && mikaRow.address) {
            normalized.residentialAddress = asString(mikaRow.address);
          }
          if (!normalized.contactNumber && mikaRow.contact_number) {
            normalized.contactNumber = asString(mikaRow.contact_number);
          }
        }
      } catch (err) {
        console.warn("[Plantilla] mika_import_rows detail hydration exception:", err);
      }
    }

    // Tier 2: v_plantilla_safe view lookup
    if (!normalized.civilStatus || !normalized.birthDate) {
      try {
        const safeQuery = supabase
          .from("v_plantilla_safe")
          .select("civil_status, date_of_birth")
          .eq(isUuid ? "id" : "employee_no", plantillaId);
        const { data: safeRow } = await safeQuery.maybeSingle();
        if (safeRow) {
          if (!normalized.civilStatus && safeRow.civil_status) {
            normalized.civilStatus = asString(safeRow.civil_status);
          }
          if (!normalized.birthDate && safeRow.date_of_birth) {
            normalized.birthDate = asString(safeRow.date_of_birth);
          }
        }
      } catch (err) {
        console.warn("[Plantilla] v_plantilla_safe query exception:", err);
      }
    }

    // Tier 3: hr_emploc onboarding snapshots lookup
    if (!normalized.civilStatus || !normalized.birthDate || !normalized.contactNumber || !normalized.residentialAddress) {
      const empNo = normalized.employeeNo && normalized.employeeNo !== "Uncoded" ? normalized.employeeNo : null;
      if (empNo) {
        try {
          const { data: emplocRow } = await supabase
            .from("hr_emploc")
            .select("civil_status_snapshot, birthdate_snapshot, contact_number_snapshot, residential_address_snapshot")
            .eq("employee_no", empNo)
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();
          if (emplocRow) {
            if (!normalized.civilStatus && emplocRow.civil_status_snapshot) {
              normalized.civilStatus = asString(emplocRow.civil_status_snapshot);
            }
            if (!normalized.birthDate && emplocRow.birthdate_snapshot) {
              normalized.birthDate = asString(emplocRow.birthdate_snapshot);
            }
            if (!normalized.contactNumber && emplocRow.contact_number_snapshot) {
              normalized.contactNumber = asString(emplocRow.contact_number_snapshot);
            }
            if (!normalized.residentialAddress && emplocRow.residential_address_snapshot) {
              normalized.residentialAddress = asString(emplocRow.residential_address_snapshot);
            }
          }
        } catch (err) {
          console.warn("[Plantilla] hr_emploc demographic query exception:", err);
        }
      }
    }

    // Tier 4: employees master registry lookup
    if (
      !normalized.civilStatus ||
      !normalized.birthDate ||
      !normalized.contactNumber ||
      !normalized.residentialAddress ||
      !normalized.maskedFields.governmentIds.tin ||
      !normalized.maskedFields.governmentIds.sss ||
      !normalized.maskedFields.governmentIds.philhealth ||
      !normalized.maskedFields.governmentIds.pagibig ||
      !normalized.maskedFields.governmentIds.atmNumber
    ) {
      const empNo = normalized.employeeNo && normalized.employeeNo !== "Uncoded" ? normalized.employeeNo : null;
      if (empNo) {
        try {
          const { data: empRow } = await supabase
            .from("employees")
            .select("civil_status, date_of_birth, birthdate, contact_no, address, sss_no, philhealth_no, pagibig_no, tin_no, atm_no")
            .eq("employee_no", empNo)
            .maybeSingle();
          if (empRow) {
            if (!normalized.civilStatus && empRow.civil_status) {
              normalized.civilStatus = asString(empRow.civil_status);
            }
            if (!normalized.birthDate && (empRow.date_of_birth || empRow.birthdate)) {
              normalized.birthDate = asString(empRow.date_of_birth || empRow.birthdate);
            }
            if (!normalized.contactNumber && empRow.contact_no) {
              normalized.contactNumber = asString(empRow.contact_no);
            }
            if (!normalized.residentialAddress && empRow.address) {
              normalized.residentialAddress = asString(empRow.address);
            }
            if (!normalized.maskedFields.governmentIds.sss && empRow.sss_no) {
              normalized.maskedFields.governmentIds.sss = empRow.sss_no;
            }
            if (!normalized.maskedFields.governmentIds.philhealth && empRow.philhealth_no) {
              normalized.maskedFields.governmentIds.philhealth = empRow.philhealth_no;
            }
            if (!normalized.maskedFields.governmentIds.pagibig && empRow.pagibig_no) {
              normalized.maskedFields.governmentIds.pagibig = empRow.pagibig_no;
            }
            if (!normalized.maskedFields.governmentIds.tin && empRow.tin_no) {
              normalized.maskedFields.governmentIds.tin = empRow.tin_no;
            }
            if (!normalized.maskedFields.governmentIds.atmNumber && empRow.atm_no) {
              normalized.maskedFields.governmentIds.atmNumber = empRow.atm_no;
            }
            if (!normalized.maskedFields.governmentIds.atmNumberMasked && empRow.atm_no) {
              const raw = empRow.atm_no.trim();
              normalized.maskedFields.governmentIds.atmNumberMasked =
                raw.length <= 4 ? "****" : `••••-••••-${raw.slice(-4)}`;
            }
          }
        } catch (err) {
          console.warn("[Plantilla] employees demographic query exception:", err);
        }
      }
    }

    // Tier 5: plantilla_import_rows raw batch import lookup
    if (!normalized.civilStatus || !normalized.birthDate || !normalized.contactNumber || !normalized.residentialAddress) {
      const empNo = normalized.employeeNo && normalized.employeeNo !== "Uncoded" ? normalized.employeeNo : null;
      if (empNo) {
        try {
          const { data: importRow } = await supabase
            .from("plantilla_import_rows")
            .select("civil_status, birthdate_raw, contact_raw, address_raw")
            .eq("employee_no", empNo)
            .order("row_number", { ascending: false })
            .limit(1)
            .maybeSingle();
          if (importRow) {
            if (!normalized.civilStatus && importRow.civil_status) {
              normalized.civilStatus = asString(importRow.civil_status);
            }
            if (!normalized.birthDate && importRow.birthdate_raw) {
              normalized.birthDate = asString(importRow.birthdate_raw);
            }
            if (!normalized.contactNumber && importRow.contact_raw) {
              normalized.contactNumber = asString(importRow.contact_raw);
            }
            if (!normalized.residentialAddress && importRow.address_raw) {
              normalized.residentialAddress = asString(importRow.address_raw);
            }
          }
        } catch (err) {
          console.warn("[Plantilla] plantilla_import_rows demographic query exception:", err);
        }
      }
    }

    // Coverage group resolution for roving employees
    if (
      !normalized.cgCode &&
      (normalized.coveredStores.length > 1 || normalized.assignmentType?.toLowerCase() === "roving") &&
      normalized.accountId
    ) {
      try {
        const { data: cgRows } = await supabase
          .from("coverage_groups")
          .select("coverage_code, coverage_group_stores(store_id)")
          .eq("account_id", normalized.accountId)
          .is("archived_at", null);
        if (cgRows && cgRows.length > 0) {
          const assignedStoreIds = new Set(normalized.coveredStores.map((s) => s.storeId).filter(Boolean));
          for (const cg of cgRows as Array<Record<string, unknown>>) {
            const cgs = Array.isArray(cg.coverage_group_stores) ? cg.coverage_group_stores : [];
            const cgStoreIds = cgs.map((item: Record<string, unknown>) => item.store_id);
            if (cgStoreIds.some((id) => assignedStoreIds.has(String(id)))) {
              normalized.cgCode = asString(cg.coverage_code);
              break;
            }
          }
        }
      } catch (err) {
        console.warn("[Plantilla] coverage group store mapping query exception:", err);
      }
    }
  }

  // Augment store-level schedules and headcount share allocations from employee_store_allocations
  try {
    const hasForbiddenChars =
      (normalized.id && /[,()"\\]/.test(normalized.id)) ||
      (normalized.employeeNo && /[,()"\\]/.test(normalized.employeeNo));

    let allocQuery = supabase
      .from("employee_store_allocations")
      .select("id, store_id, store_name, vcode, filled_hc, schedule_days, schedule_time")
      .eq("is_active", true);

    if (hasForbiddenChars) {
      if (normalized.id && !/[,()"\\]/.test(normalized.id)) {
        allocQuery = allocQuery.eq("plantilla_id", normalized.id);
      } else if (normalized.employeeNo && !/[,()"\\]/.test(normalized.employeeNo)) {
        allocQuery = allocQuery.eq("employee_no", normalized.employeeNo);
      }
    } else if (normalized.id && normalized.employeeNo) {
      allocQuery = allocQuery.or(`plantilla_id.eq.${normalized.id},employee_no.eq.${normalized.employeeNo}`);
    } else if (normalized.id) {
      allocQuery = allocQuery.eq("plantilla_id", normalized.id);
    } else if (normalized.employeeNo) {
      allocQuery = allocQuery.eq("employee_no", normalized.employeeNo);
    }

    const { data: allocRows } = await allocQuery;

    if (allocRows && allocRows.length > 0) {
      normalized.coveredStores = allocRows.map((al, idx) => ({
        stableKey: `alloc-${al.id || idx}`,
        storeId: al.store_id || "",
        storeName: al.store_name || "Assigned Store",
        vcode: al.vcode || normalized?.vcode,
        allocationPercent: al.filled_hc != null ? Math.round(Number(al.filled_hc) * 100) : Math.round(100 / allocRows.length),
        isPrimary: idx === 0,
        scheduleDays: al.schedule_days || normalized?.scheduleDays || "MON-SAT",
        scheduleTime: al.schedule_time || normalized?.scheduleTime || "08:00 AM - 05:00 PM",
      }));
    }
  } catch {
    // Graceful fallback to existing coveredStores
  }

  // Fallback: If coveredStores is still empty, populate primary store record
  if (!normalized.coveredStores || normalized.coveredStores.length === 0) {
    normalized.coveredStores = [
      {
        stableKey: `primary-store-${normalized.id}`,
        storeId: normalized.storeId || "",
        storeName: normalized.primaryStoreName || "Primary Store Assignment",
        vcode: normalized.vcode,
        allocationPercent: 100,
        isPrimary: true,
        scheduleDays: normalized.scheduleDays || "MON-SAT",
        scheduleTime: normalized.scheduleTime || "08:00 AM - 05:00 PM",
      },
    ];
  }

  // -------------------------------------------------------------------------
  // Resilient Universal Audit Timeline Aggregator
  // Hydrates employment status updates (On Leave, Active, Floating, Separated),
  // transfers, schedules, HRCO assignments, MIKA sync, and deactivations
  // -------------------------------------------------------------------------
  try {
    const timelineItems: PlantillaAuditTimelineItem[] = [...normalized.auditTimeline];
    const actorIds = new Set<string>();

    // 1. Check public.audit_logs for comprehensive operational field mutations
    type AuditLogRow = {
      id: string;
      action: string;
      actor_id: string | null;
      role: string | null;
      old_data: Record<string, unknown> | null;
      new_data: Record<string, unknown> | null;
      timestamp: string;
    };
    let rawAuditLogs: AuditLogRow[] = [];
    try {
      const { data: auditData } = await supabase
        .from("audit_logs")
        .select("id, action, actor_id, role, old_data, new_data, timestamp")
        .eq("record_id", normalized.id)
        .order("timestamp", { ascending: false })
        .limit(50);

      if (auditData && auditData.length > 0) {
        rawAuditLogs = auditData as unknown as AuditLogRow[];
        for (const log of rawAuditLogs) {
          if (log.actor_id) {
            actorIds.add(asString(log.actor_id) || "");
          }
        }
      }
    } catch (err) {
      console.warn("[Plantilla] audit_logs query exception:", err);
    }

    // 2. Check public.employee_transfers for store movements
    type TransferRow = {
      id: string;
      from_store: string | null;
      to_store: string | null;
      transfer_date: string | null;
      reason: string | null;
      requested_by: string | null;
      status: string | null;
      reviewed_by: string | null;
      reviewed_at: string | null;
      created_at: string;
      approved_by_user_id: string | null;
    };
    let rawTransfers: TransferRow[] = [];
    try {
      const { data: transfers } = await supabase
        .from("employee_transfers")
        .select("id, from_store, to_store, transfer_date, reason, requested_by, status, reviewed_by, reviewed_at, created_at, approved_by_user_id")
        .eq("plantilla_id", normalized.id)
        .order("created_at", { ascending: false });

      if (transfers && transfers.length > 0) {
        rawTransfers = transfers as unknown as TransferRow[];
        for (const tr of rawTransfers) {
          if (tr.approved_by_user_id) actorIds.add(asString(tr.approved_by_user_id) || "");
        }
      }
    } catch (err) {
      console.warn("[Plantilla] employee_transfers query exception:", err);
    }

    // 3. Check employee_deactivation_audit_log for authoritative deactivation trail
    type DeactLogRow = {
      id: string;
      action: string;
      performed_at: string;
      metadata: Record<string, unknown> | null;
      performed_by_profile_id: string | null;
    };
    let rawDeactLogs: DeactLogRow[] = [];
    try {
      const { data: deactLogs } = await supabase
        .from("employee_deactivation_audit_log")
        .select("id, action, performed_at, metadata, performed_by_profile_id")
        .eq("plantilla_id", normalized.id)
        .order("performed_at", { ascending: false });

      if (deactLogs && deactLogs.length > 0) {
        rawDeactLogs = deactLogs as unknown as DeactLogRow[];
        for (const dLog of rawDeactLogs) {
          if (dLog.performed_by_profile_id) {
            actorIds.add(asString(dLog.performed_by_profile_id) || "");
          }
        }
      }
    } catch (err) {
      console.warn("[Plantilla] employee_deactivation_audit_log query exception:", err);
    }

    // 4. Check employee_deactivation_requests
    type DeactReqRow = {
      id: string;
      status: string;
      created_at: string;
      updated_at: string | null;
      reason: string | null;
      remarks: string | null;
      requestor_profile_id: string | null;
      processed_by_profile_id: string | null;
    };
    let rawDeactReqs: DeactReqRow[] = [];
    try {
      const { data: deactReqs } = await supabase
        .from("employee_deactivation_requests")
        .select("id, status, created_at, updated_at, reason, remarks, requestor_profile_id, processed_by_profile_id")
        .eq("plantilla_id", normalized.id)
        .order("created_at", { ascending: false });

      if (deactReqs && deactReqs.length > 0) {
        rawDeactReqs = deactReqs as unknown as DeactReqRow[];
        for (const req of rawDeactReqs) {
          if (req.requestor_profile_id) actorIds.add(asString(req.requestor_profile_id) || "");
          if (req.processed_by_profile_id) actorIds.add(asString(req.processed_by_profile_id) || "");
        }
      }
    } catch (err) {
      console.warn("[Plantilla] employee_deactivation_requests query exception:", err);
    }

    // 5. Fallback to direct plantilla record milestones
    type PlantillaAuditRow = {
      deactivated_at: string | null;
      for_deactivation_at: string | null;
      inactive_at: string | null;
      date_of_separation: string | null;
      separation_status: string | null;
      remarks: string | null;
      deactivation_reason: string | null;
      status: string | null;
      date_deployed: string | null;
      date_hired: string | null;
      updated_at: string | null;
      updated_by: string | null;
      last_mika_synced_at: string | null;
      last_mika_synced_by: string | null;
      for_deactivation_by: string | null;
      deactivated_by: string | null;
      inactive_by: string | null;
    };
    let rawPRec: PlantillaAuditRow | null = null;
    try {
      const { data: pRec } = await supabase
        .from("plantilla")
        .select("deactivated_at, for_deactivation_at, inactive_at, date_of_separation, separation_status, remarks, deactivation_reason, status, date_deployed, date_hired, updated_at, updated_by, last_mika_synced_at, last_mika_synced_by, for_deactivation_by, deactivated_by, inactive_by")
        .eq(isUuid ? "id" : "employee_no", plantillaId)
        .maybeSingle();

      if (pRec) {
        rawPRec = pRec as unknown as PlantillaAuditRow;
        if (rawPRec.updated_by) actorIds.add(asString(rawPRec.updated_by) || "");
        if (rawPRec.last_mika_synced_by) actorIds.add(asString(rawPRec.last_mika_synced_by) || "");
        if (rawPRec.for_deactivation_by) actorIds.add(asString(rawPRec.for_deactivation_by) || "");
        if (rawPRec.deactivated_by) actorIds.add(asString(rawPRec.deactivated_by) || "");
        if (rawPRec.inactive_by) actorIds.add(asString(rawPRec.inactive_by) || "");
      }
    } catch (err) {
      console.warn("[Plantilla] direct plantilla audit query exception:", err);
    }

    // Resolve actor names from users_profile
    const actorNameMap = new Map<string, string>();
    const validActorIds = Array.from(actorIds).filter(Boolean);
    if (validActorIds.length > 0) {
      try {
        const { data: userProfiles } = await supabase
          .from("users_profile")
          .select("id, full_name, email, auth_user_id")
          .in("id", validActorIds);

        if (userProfiles && userProfiles.length > 0) {
          for (const p of userProfiles) {
            const profileRec = p as { id?: string; full_name?: string | null; email?: string | null; auth_user_id?: string | null };
            const name = profileRec.full_name || profileRec.email;
            if (profileRec.id && name) actorNameMap.set(profileRec.id, name);
            if (profileRec.auth_user_id && name) actorNameMap.set(profileRec.auth_user_id, name);
          }
        }

        // Check if any actor ID was stored as auth_user_id
        const missingActorIds = validActorIds.filter((id) => !actorNameMap.has(id));
        if (missingActorIds.length > 0) {
          const { data: authProfiles } = await supabase
            .from("users_profile")
            .select("id, full_name, email, auth_user_id")
            .in("auth_user_id", missingActorIds);

          if (authProfiles && authProfiles.length > 0) {
            for (const p of authProfiles) {
              const profileRec = p as { id?: string; full_name?: string | null; email?: string | null; auth_user_id?: string | null };
              const name = profileRec.full_name || profileRec.email;
              if (profileRec.auth_user_id && name) actorNameMap.set(profileRec.auth_user_id, name);
              if (profileRec.id && name) actorNameMap.set(profileRec.id, name);
            }
          }
        }
      } catch (err) {
        console.warn("[Plantilla] Error resolving actor profiles for timeline:", err);
      }
    }

    // Helper to push deduplicated timeline items
    const pushTimelineItem = (item: PlantillaAuditTimelineItem) => {
      const isDuplicate = timelineItems.some((existing) => {
        if (existing.eventLabel !== item.eventLabel) return false;
        const timeDiff = Math.abs(
          new Date(existing.createdAt || 0).getTime() - new Date(item.createdAt || 0).getTime()
        );
        return timeDiff < 60000; // within 1 minute
      });
      if (!isDuplicate) {
        timelineItems.push(item);
      }
    };

    // A. Hydrate items from public.audit_logs
    for (const log of rawAuditLogs) {
      const oldData = asObject(log.old_data);
      const newData = asObject(log.new_data);
      const actorName = (log.actor_id ? actorNameMap.get(log.actor_id) : null) || null;

      // Status mutations
      const oldStatus = asString(oldData.status);
      const newStatus = asString(newData.status);
      if (newStatus && (!oldStatus || newStatus !== oldStatus)) {
        let eventLabel = `Status Changed: ${newStatus}`;
        let eventDescription: string | null = null;
        const leaveRemarks = asString(newData.remarks ?? newData.reason);

        if (newStatus === "On Leave") {
          eventLabel = "Tagged as On Leave";
          eventDescription = leaveRemarks ? `Reason/Remarks: ${leaveRemarks}` : "Personnel employment status updated to On Leave.";
        } else if (newStatus === "Active") {
          eventLabel = "Returned to Active";
          eventDescription = "Personnel employment status returned to Active.";
        } else if (newStatus === "Floating") {
          eventLabel = "Transferred to Floating";
          eventDescription = leaveRemarks ? `Remarks: ${leaveRemarks}` : "Personnel transitioned to floating status.";
        } else if (newStatus === "Resigned" || newStatus === "AWOL" || newStatus === "Terminated") {
          eventLabel = `Personnel Separated (${newStatus})`;
          eventDescription = leaveRemarks ? `Remarks: ${leaveRemarks}` : `Personnel separation processed as ${newStatus}.`;
        } else if (newStatus === "Deactivated") {
          eventLabel = "Personnel Deactivated";
          eventDescription = leaveRemarks ? `Deactivation finalized (${leaveRemarks})` : "Personnel deactivated and offboarded.";
        }

        pushTimelineItem({
          stableKey: `audit-status-${log.id}`,
          eventId: log.id,
          eventLabel,
          eventDescription,
          createdAt: asString(log.timestamp),
          profileName: actorName,
        });
      }

      // Schedule & Allocation updates
      const oldDays = asString(oldData.schedule_days ?? oldData.schedule);
      const newDays = asString(newData.schedule_days ?? newData.schedule);
      const oldTime = asString(oldData.schedule_time);
      const newTime = asString(newData.schedule_time);
      const oldDayoff = asString(oldData.dayoff ?? oldData.rest_day);
      const newDayoff = asString(newData.dayoff ?? newData.rest_day);
      if (
        (newDays && newDays !== oldDays) ||
        (newTime && newTime !== oldTime) ||
        (newDayoff && newDayoff !== oldDayoff)
      ) {
        pushTimelineItem({
          stableKey: `audit-sched-${log.id}`,
          eventId: log.id,
          eventLabel: "Work Schedule & Allocation Updated",
          eventDescription: `Schedule: ${newDays || "—"} (${newTime || "—"}) • Rest Day: ${newDayoff || "—"}`,
          createdAt: asString(log.timestamp),
          profileName: actorName,
        });
      }

      // Store transfer via audit_logs
      const oldStore = asString(oldData.store_name);
      const newStore = asString(newData.store_name);
      if (newStore && oldStore && newStore !== oldStore) {
        pushTimelineItem({
          stableKey: `audit-transfer-${log.id}`,
          eventId: log.id,
          eventLabel: "Personnel Transferred",
          eventDescription: `Transferred from ${oldStore} to ${newStore}.`,
          createdAt: asString(log.timestamp),
          profileName: actorName,
        });
      }

      // HR Coordinator Reassignment via audit_logs
      const oldHrco = asString(oldData.coordinator ?? oldData.hrco_name);
      const newHrco = asString(newData.coordinator ?? newData.hrco_name);
      if (newHrco && oldHrco && newHrco !== oldHrco) {
        pushTimelineItem({
          stableKey: `audit-hrco-${log.id}`,
          eventId: log.id,
          eventLabel: "HR Coordinator Reassigned",
          eventDescription: `Assigned to ${newHrco}.`,
          createdAt: asString(log.timestamp),
          profileName: actorName,
        });
      }

      // MIKA Synchronized via audit_logs
      const oldMika = asString(oldData.last_mika_synced_at);
      const newMika = asString(newData.last_mika_synced_at);
      if (newMika && newMika !== oldMika) {
        pushTimelineItem({
          stableKey: `audit-mika-${log.id}`,
          eventId: log.id,
          eventLabel: "Synchronized from MIKA",
          eventDescription: "Personnel details synchronized with external HRIS master record.",
          createdAt: asString(log.timestamp),
          profileName: actorName,
        });
      }
    }

    // B. Hydrate items from public.employee_transfers
    for (const tr of rawTransfers) {
      if (tr.status === "Approved") {
        pushTimelineItem({
          stableKey: `transfer-approved-${tr.id}`,
          eventId: tr.id,
          eventLabel: "Personnel Transfer Approved",
          eventDescription: `Transferred from ${tr.from_store || "Store"} to ${tr.to_store || "Store"}${tr.reason ? ` (Reason: ${tr.reason})` : ""}`,
          createdAt: asString(tr.reviewed_at ?? tr.created_at),
          profileName: (tr.approved_by_user_id ? actorNameMap.get(tr.approved_by_user_id) : null) || tr.reviewed_by || null,
        });
      } else {
        pushTimelineItem({
          stableKey: `transfer-req-${tr.id}`,
          eventId: tr.id,
          eventLabel: "Personnel Transfer Requested",
          eventDescription: `Transfer to ${tr.to_store || "Store"} requested${tr.reason ? ` (Reason: ${tr.reason})` : ""}`,
          createdAt: asString(tr.created_at),
          profileName: tr.requested_by || null,
        });
      }
    }

    // C. Hydrate items from employee_deactivation_audit_log
    if (rawDeactLogs.length > 0) {
      for (const dLog of rawDeactLogs) {
        const action = asString(dLog.action);
        let eventLabel = "Deactivation Event";
        let eventDescription = "Personnel offboarding audit event.";
        const meta = asObject(dLog.metadata);
        const reason = asString(meta.reason ?? meta.deactivation_reason ?? meta.remarks);

        if (action === "REQUEST_CREATED") {
          eventLabel = "Deactivation Requested";
          eventDescription = reason ? `Reason: ${reason}` : "Deactivation request submitted for operations review.";
        } else if (action === "APPROVED") {
          eventLabel = "Personnel Deactivated";
          eventDescription = reason ? `Deactivation finalized (${reason})` : "Personnel successfully deactivated and offboarded.";
        } else if (action === "REJECTED") {
          eventLabel = "Deactivation Request Rejected";
          eventDescription = reason ? `Rejection rationale: ${reason}` : "Deactivation request was rejected.";
        } else if (action === "RESUBMITTED") {
          eventLabel = "Deactivation Request Resubmitted";
          eventDescription = reason ? `Resubmission note: ${reason}` : "Deactivation request resubmitted.";
        } else if (action === "ARCHIVED") {
          eventLabel = "Personnel Archived";
          eventDescription = "Personnel offboarding archive finalized.";
        }

        const performerId = asString(dLog.performed_by_profile_id);
        const resolvedName =
          asString(meta.performed_by_name ?? meta.performer_name) ||
          (performerId ? actorNameMap.get(performerId) : null) ||
          null;

        pushTimelineItem({
          stableKey: `deact-log-${dLog.id}`,
          eventId: asString(dLog.id) || "",
          eventLabel,
          eventDescription,
          createdAt: asString(dLog.performed_at),
          profileName: resolvedName,
        });
      }
    }

    // D. Hydrate items from employee_deactivation_requests
    if (rawDeactReqs.length > 0) {
      for (const req of rawDeactReqs) {
        const reqStatus = asString(req.status);
        const reason = asString(req.reason ?? req.remarks);
        if (
          (reqStatus === "Approved" || reqStatus === "Deactivated") &&
          !timelineItems.some((t) => t.eventLabel === "Personnel Deactivated")
        ) {
          const processorId = asString(req.processed_by_profile_id);
          pushTimelineItem({
            stableKey: `deact-req-appr-${req.id}`,
            eventId: asString(req.id) || "",
            eventLabel: "Personnel Deactivated",
            eventDescription: reason ? `Deactivation finalized (${reason})` : "Personnel successfully deactivated and offboarded.",
            createdAt: asString(req.updated_at ?? req.created_at),
            profileName: (processorId ? actorNameMap.get(processorId) : null) || null,
          });
        }
        if (!timelineItems.some((t) => t.eventLabel === "Deactivation Requested")) {
          const requestorId = asString(req.requestor_profile_id);
          pushTimelineItem({
            stableKey: `deact-req-${req.id}`,
            eventId: asString(req.id) || "",
            eventLabel: "Deactivation Requested",
            eventDescription: reason ? `Reason: ${reason}` : "Deactivation request submitted for operations review.",
            createdAt: asString(req.created_at),
            profileName: (requestorId ? actorNameMap.get(requestorId) : null) || null,
          });
        }
      }
    }

    // E. Fallbacks for current active state milestones
    const s = asString(rawPRec?.status ?? normalized.status)?.toLowerCase() ?? "";

    // On Leave milestone
    if (s === "on leave" && !timelineItems.some((t) => t.eventLabel === "Tagged as On Leave")) {
      const updaterId = asString(rawPRec?.updated_by);
      pushTimelineItem({
        stableKey: `current-on-leave-${normalized.id}`,
        eventId: "on-leave",
        eventLabel: "Tagged as On Leave",
        eventDescription: normalized.remarks ? `Reason/Remarks: ${normalized.remarks}` : "Personnel employment status updated to On Leave.",
        createdAt: asString(rawPRec?.updated_at ?? normalized.updatedAt ?? new Date().toISOString()),
        profileName: (updaterId ? actorNameMap.get(updaterId) : null) || null,
      });
    }

    // Floating milestone
    if (s === "floating" && !timelineItems.some((t) => t.eventLabel === "Transferred to Floating")) {
      const updaterId = asString(rawPRec?.updated_by);
      pushTimelineItem({
        stableKey: `current-floating-${normalized.id}`,
        eventId: "floating",
        eventLabel: "Transferred to Floating",
        eventDescription: normalized.remarks ? `Remarks: ${normalized.remarks}` : "Personnel transitioned to floating status.",
        createdAt: asString(rawPRec?.updated_at ?? normalized.updatedAt ?? new Date().toISOString()),
        profileName: (updaterId ? actorNameMap.get(updaterId) : null) || null,
      });
    }

    // MIKA Sync milestone
    const mikaSyncedAt = asString(rawPRec?.last_mika_synced_at ?? normalized.lastMikaSyncedAt);
    if (mikaSyncedAt && !timelineItems.some((t) => t.eventLabel === "Synchronized from MIKA")) {
      const syncerId = asString(rawPRec?.last_mika_synced_by ?? normalized.lastMikaSyncedBy);
      pushTimelineItem({
        stableKey: `current-mika-${normalized.id}`,
        eventId: "mika-sync",
        eventLabel: "Synchronized from MIKA",
        eventDescription: "Personnel details synchronized with external HRIS master record.",
        createdAt: mikaSyncedAt,
        profileName: (syncerId ? actorNameMap.get(syncerId) : null) || null,
      });
    }

    // Populate from direct plantilla record if milestones are not yet captured
    if (rawPRec) {
      const isDeact = s === "deactivated" || s.includes("deactivated") || Boolean(rawPRec.deactivated_at);
      const reason = asString(rawPRec.deactivation_reason ?? rawPRec.remarks);

      // Deactivated milestone
      if (isDeact && !timelineItems.some((t) => t.eventLabel === "Personnel Deactivated")) {
        const deactId = asString(rawPRec.deactivated_by ?? rawPRec.inactive_by);
        pushTimelineItem({
          stableKey: `plantilla-deact-${normalized.id}`,
          eventId: "deactivated",
          eventLabel: "Personnel Deactivated",
          eventDescription: reason ? `Deactivation finalized (${reason})` : "Personnel successfully deactivated and offboarded.",
          createdAt: asString(rawPRec.deactivated_at ?? rawPRec.inactive_at ?? rawPRec.updated_at ?? normalized.dateDeployed ?? new Date().toISOString()),
          profileName: (deactId ? actorNameMap.get(deactId) : null) || null,
        });
      }

      // Deactivation requested milestone
      if (
        (rawPRec.for_deactivation_at || s.includes("pending") || s.includes("for deactivation")) &&
        !timelineItems.some((t) => t.eventLabel === "Deactivation Requested")
      ) {
        const reqId = asString(rawPRec.for_deactivation_by);
        pushTimelineItem({
          stableKey: `plantilla-for-deact-${normalized.id}`,
          eventId: "for-deactivation",
          eventLabel: "Deactivation Requested",
          eventDescription: reason ? `Reason: ${reason}` : "Deactivation request submitted for operations review.",
          createdAt: asString(rawPRec.for_deactivation_at ?? rawPRec.inactive_at ?? normalized.dateDeployed),
          profileName: (reqId ? actorNameMap.get(reqId) : null) || null,
        });
      }

      // Separation milestone
      const sepStatus = asString(rawPRec.separation_status);
      if (
        (sepStatus || rawPRec.date_of_separation) &&
        !timelineItems.some((t) => t.eventLabel.startsWith("Personnel Separated"))
      ) {
        const sepLabel = sepStatus || (s === "resigned" ? "Resigned" : s === "awol" ? "AWOL" : s === "terminated" ? "Terminated" : "Separated");
        const sepActorId = asString(rawPRec.inactive_by ?? rawPRec.deactivated_by);
        pushTimelineItem({
          stableKey: `plantilla-sep-${normalized.id}`,
          eventId: "separated",
          eventLabel: `Personnel Separated (${sepLabel})`,
          eventDescription: reason ? `Remarks: ${reason}` : `Personnel marked as ${sepLabel}.`,
          createdAt: asString(rawPRec.date_of_separation ?? rawPRec.inactive_at ?? rawPRec.deactivated_at),
          profileName: (sepActorId ? actorNameMap.get(sepActorId) : null) || null,
        });
      }
    }

    // F. Initial store deployment milestone
    if (!timelineItems.some((t) => t.eventLabel.startsWith("Personnel deployed to Plantilla"))) {
      pushTimelineItem({
        stableKey: `deployed-${normalized.id}`,
        eventId: "deployed",
        eventLabel: `Personnel deployed to Plantilla — ${normalized.primaryStoreName || normalized.storeName || "Store"}`,
        eventDescription: "Initial operational deployment to store branch.",
        createdAt: asString(normalized.dateDeployed || normalized.dateHired),
        profileName: normalized.coordinator || normalized.hrcoName || null,
      });
    }

    // G. Sort newest first (descending)
    timelineItems.sort((a, b) => {
      const dateA = a.createdAt ? new Date(a.createdAt).getTime() : 0;
      const dateB = b.createdAt ? new Date(b.createdAt).getTime() : 0;
      return dateB - dateA;
    });

    normalized.auditTimeline = timelineItems;
  } catch (err) {
    console.warn("[Plantilla] universal audit timeline aggregation exception:", err);
  }

  return normalized;
}

export async function syncPlantillaMika(plantillaId: string): Promise<void> {
  const supabase = createClient();
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(plantillaId);

  // 1. Resolve employee_no and id from plantilla
  let pQuery = supabase.from("plantilla").select("id, employee_no");
  pQuery = isUuid ? pQuery.eq("id", plantillaId) : pQuery.eq("employee_no", plantillaId);
  const { data: pRow } = await pQuery.maybeSingle();

  const targetId = pRow?.id ?? (isUuid ? plantillaId : null);
  const employeeNo = pRow?.employee_no ?? (!isUuid ? plantillaId : null);

  // 2. Fetch latest MIKA row for this employee from mika_import_rows
  let mikaRow: Record<string, unknown> | null = null;
  if (employeeNo) {
    const { data } = await supabase
      .from("mika_import_rows")
      .select("*")
      .eq("employee_no", employeeNo)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    mikaRow = data;
  }

  // 3. Fallback to employees table if mika_import_rows is missing or incomplete
  let empRow: Record<string, unknown> | null = null;
  if (employeeNo) {
    const { data } = await supabase
      .from("employees")
      .select("*")
      .eq("employee_no", employeeNo)
      .maybeSingle();
    empRow = data;
  }

  const sss = asString(mikaRow?.sss_no ?? empRow?.sss_no);
  const philhealth = asString(mikaRow?.philhealth_no ?? empRow?.philhealth_no);
  const pagibig = asString(mikaRow?.pagibig_no ?? empRow?.pagibig_no);
  const tin = asString(mikaRow?.tin_no ?? empRow?.tin_no);
  const atm = asString(mikaRow?.atm_no ?? empRow?.atm_no);
  const civilStatus = asString(mikaRow?.civil_status ?? empRow?.civil_status);
  const birthdate = asString(mikaRow?.birthdate ?? empRow?.birthdate ?? empRow?.date_of_birth);
  const address = asString(mikaRow?.address ?? empRow?.address);
  const contactNo = asString(mikaRow?.contact_number ?? empRow?.contact_no);

  // 4. Update plantilla record directly with latest available MIKA data
  if (targetId || employeeNo) {
    const updates: Record<string, unknown> = {
      last_mika_synced_at: new Date().toISOString(),
    };
    if (sss) updates.sss_no = sss;
    if (philhealth) updates.philhealth_no = philhealth;
    if (pagibig) updates.pagibig_no = pagibig;
    if (atm) updates.atm_no = atm;
    if (civilStatus) updates.civil_status = civilStatus;
    if (birthdate) updates.date_of_birth = birthdate;
    if (address) updates.address = address;
    if (contactNo) updates.contact_no = contactNo;

    let updateQuery = supabase.from("plantilla").update(updates);
    updateQuery = targetId ? updateQuery.eq("id", targetId) : updateQuery.eq("employee_no", employeeNo!);
    const { error: updateErr } = await updateQuery;
    if (updateErr) {
      console.warn("[Plantilla] direct plantilla update notice in syncPlantillaMika:", updateErr);
    }
  }

  // 5. Update employees table with tin_no and statutory numbers
  if (tin && employeeNo) {
    try {
      await supabase
        .from("employees")
        .update({
          tin_no: tin,
          ...(sss ? { sss_no: sss } : {}),
          ...(philhealth ? { philhealth_no: philhealth } : {}),
          ...(pagibig ? { pagibig_no: pagibig } : {}),
          ...(atm ? { atm_no: atm } : {}),
        })
        .eq("employee_no", employeeNo);
    } catch {
      // Graceful fallback if employee record does not exist
    }
  }

  // 6. Invoke RPC if targetId is UUID to trigger database audit logs and audit triggers
  if (targetId && isUuid) {
    try {
      await supabase.rpc("plantilla_sync_mika", {
        p_plantilla_id: targetId,
        p_sss: sss ?? null,
        p_philhealth: philhealth ?? null,
        p_pagibig: pagibig ?? null,
        p_atm: atm ?? null,
        p_civil_status: civilStatus ?? null,
        p_date_of_birth: birthdate ?? null,
      });
    } catch (rpcErr) {
      // 5-minute cooldown or permission error on RPC is logged as warning since direct table sync already succeeded
      console.warn("[Plantilla] plantilla_sync_mika RPC notice:", rpcErr);
    }
  }
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

export type EmploymentStatusTarget =
  | "Active"
  | "On Leave"
  | "Floating"
  | "Resigned"
  | "AWOL"
  | "Terminated";

export interface UpdateEmploymentStatusParams {
  plantillaId: string;
  targetStatus: EmploymentStatusTarget;
  reason?: string | null;
  remarks?: string | null;
  expectedReturnDate?: string | null;
  effectiveDate?: string | null; // Required for Resigned, AWOL, Terminated
}

export interface CreateDeactivationRequestParams {
  plantillaId: string;
  reason?: string | null;
  remarks?: string | null;
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

    if (params.reason || params.expectedReturnDate || params.remarks) {
      const formattedRemarks = [
        params.reason ? `Reason: ${params.reason}` : null,
        params.expectedReturnDate ? `EDR: ${params.expectedReturnDate}` : null,
        params.remarks?.trim() ? `Remarks: ${params.remarks.trim()}` : null,
      ]
        .filter(Boolean)
        .join(" | ");

      try {
        await supabase
          .from("plantilla")
          .update({ remarks: formattedRemarks })
          .eq("id", params.plantillaId);
      } catch (e) {
        console.warn("Could not persist leave remarks:", e);
      }
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

  if (
    params.targetStatus === "Resigned" ||
    params.targetStatus === "AWOL" ||
    params.targetStatus === "Terminated"
  ) {
    return updatePlantillaSeparation({
      plantillaId: params.plantillaId,
      separationStatus: params.targetStatus,
      effectiveDate: params.effectiveDate || new Date().toISOString().substring(0, 10),
      remarks: params.remarks?.trim() || null,
      openVacancy: true,
    });
  }

  throw new PlantillaDataError("retryable", `Unsupported employment status target: ${params.targetStatus}`);
}

export interface StoreAllocationInput {
  storeId?: string | null;
  storeName: string;
  vcode?: string | null;
  scheduleDays?: string | null;
  scheduleTime?: string | null;
  allocationPercent: number; // e.g. 50 = 0.50 HC, 100 = 1.00 HC
}

export interface UpdatePlantillaScheduleParams {
  plantillaId: string;
  employeeNo?: string | null;
  scheduleDays?: string | null;
  scheduleTime?: string | null;
  dayoff?: string | null;
  storeAllocations?: StoreAllocationInput[];
}

export async function updatePlantillaSchedule(params: UpdatePlantillaScheduleParams): Promise<void> {
  const supabase = createClient();

  // 1. Authoritative path: Call SECURITY DEFINER RPC update_plantilla_schedule
  try {
    const { error: rpcError } = await supabase.rpc("update_plantilla_schedule", {
      p_plantilla_id: params.plantillaId,
      p_schedule_days: params.scheduleDays ?? null,
      p_schedule_time: params.scheduleTime ?? null,
      p_dayoff: params.dayoff ?? null,
      p_store_allocations:
        params.storeAllocations && params.storeAllocations.length > 0
          ? params.storeAllocations.map((a) => ({
              storeId: a.storeId || null,
              storeName: a.storeName || null,
              vcode: a.vcode || null,
              scheduleDays: a.scheduleDays || params.scheduleDays || null,
              scheduleTime: a.scheduleTime || params.scheduleTime || null,
              allocationPercent: a.allocationPercent,
            }))
          : null,
    });

    if (!rpcError) {
      return;
    }
    console.warn("[Plantilla] update_plantilla_schedule RPC failed, applying direct table fallback:", rpcError);
  } catch (err) {
    console.warn("[Plantilla] update_plantilla_schedule RPC exception, applying direct table fallback:", err);
  }

  // 2. Resilient fallback: Direct table mutation on public.plantilla
  const updatePayload: Record<string, unknown> = {
    schedule_days: params.scheduleDays ?? null,
    schedule: params.scheduleDays ?? null,
    schedule_time: params.scheduleTime ?? null,
    dayoff: params.dayoff ?? null,
    rest_day: params.dayoff ?? null,
    updated_at: new Date().toISOString(),
  };

  if (params.storeAllocations && params.storeAllocations.length > 0) {
    if (params.storeAllocations.length > 1) {
      updatePayload.deployment_type = "Roving";
    } else {
      updatePayload.deployment_type = "Stationary";
    }
  }

  const { error } = await supabase
    .from("plantilla")
    .update(updatePayload)
    .eq("id", params.plantillaId);

  if (error) {
    throwPlantillaError(error);
  }

  // Update employee_store_allocations
  if (params.storeAllocations && params.storeAllocations.length > 0) {
    for (const alloc of params.storeAllocations) {
      const filledHc = Number((alloc.allocationPercent / 100).toFixed(4));
      let query = supabase
        .from("employee_store_allocations")
        .update({
          filled_hc: filledHc,
          schedule_days: alloc.scheduleDays ?? params.scheduleDays ?? null,
          schedule_time: alloc.scheduleTime ?? params.scheduleTime ?? null,
          vcode: alloc.vcode ?? null,
          is_active: true,
        });

      if (alloc.storeId) {
        query = query.eq("store_id", alloc.storeId);
      } else {
        query = query.eq("store_name", alloc.storeName);
      }
      if (params.employeeNo && !/[,()"\\]/.test(params.employeeNo) && !/[,()"\\]/.test(params.plantillaId)) {
        query = query.or(`plantilla_id.eq.${params.plantillaId},employee_no.eq.${params.employeeNo}`);
      } else if (!/[,()"\\]/.test(params.plantillaId)) {
        query = query.eq("plantilla_id", params.plantillaId);
      } else if (params.employeeNo && !/[,()"\\]/.test(params.employeeNo)) {
        query = query.eq("employee_no", params.employeeNo);
      } else {
        continue;
      }
      try {
        await query;
      } catch {
        // Ignore RLS or constraint errors on secondary table
      }
    }
  } else if (params.employeeNo || params.plantillaId) {
    try {
      let query = supabase
        .from("employee_store_allocations")
        .update({
          schedule_days: params.scheduleDays ?? null,
          schedule_time: params.scheduleTime ?? null,
        });
      if (params.employeeNo && !/[,()"\\]/.test(params.employeeNo) && !/[,()"\\]/.test(params.plantillaId)) {
        query = query.or(`plantilla_id.eq.${params.plantillaId},employee_no.eq.${params.employeeNo}`);
      } else if (!/[,()"\\]/.test(params.plantillaId)) {
        query = query.eq("plantilla_id", params.plantillaId);
      } else if (params.employeeNo && !/[,()"\\]/.test(params.employeeNo)) {
        query = query.eq("employee_no", params.employeeNo);
      } else {
        return;
      }
      await query;
    } catch {
      // Ignore
    }
  }
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
    .eq("is_active", true)
    .neq("status", "archived");

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
  queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
  queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
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

export function usePlantillaInactiveRemarks(employeeIds: string[]) {
  const supabase = createClient();
  const sortedIds = useMemo(
    () => Array.from(new Set(employeeIds)).filter(Boolean).sort(),
    [employeeIds]
  );

  return useQuery({
    queryKey: ["plantilla", "inactive-remarks", sortedIds],
    queryFn: async (): Promise<Map<string, string>> => {
      const remarksMap = new Map<string, string>();
      if (sortedIds.length === 0) return remarksMap;

      const chunkSize = 100;

      // 1. Fetch remarks from public.plantilla
      for (let i = 0; i < sortedIds.length; i += chunkSize) {
        const chunk = sortedIds.slice(i, i + chunkSize);
        try {
          const { data: plantillaRows, error: pErr } = await supabase
            .from("plantilla")
            .select("id, remarks")
            .in("id", chunk);

          if (!pErr && Array.isArray(plantillaRows)) {
            for (const row of plantillaRows) {
              const r = asString(row.remarks)?.trim();
              if (r) {
                remarksMap.set(row.id as string, r);
              }
            }
          }
        } catch (err) {
          console.warn("Failed fetching plantilla remarks chunk:", err);
        }
      }

      // 2. For IDs that still have no remarks, check audit_logs (new_data->remarks / notes / reason)
      const missingIds = sortedIds.filter((id) => !remarksMap.has(id));
      if (missingIds.length > 0) {
        for (let i = 0; i < missingIds.length; i += chunkSize) {
          const chunk = missingIds.slice(i, i + chunkSize);
          try {
            const { data: auditRows, error: aErr } = await supabase
              .from("audit_logs")
              .select("record_id, new_data, timestamp")
              .in("record_id", chunk)
              .order("timestamp", { ascending: false });

            if (!aErr && Array.isArray(auditRows)) {
              for (const aRow of auditRows) {
                const recId = asString(aRow.record_id);
                if (recId && !remarksMap.has(recId)) {
                  const newData = asObject(aRow.new_data);
                  const rem = asString(
                    newData.remarks ??
                    newData.p_remarks ??
                    newData.separation_remarks ??
                    newData.separationRemarks ??
                    newData.notes ??
                    newData.reason
                  )?.trim();
                  if (rem) {
                    remarksMap.set(recId, rem);
                  }
                }
              }
            }
          } catch (err) {
            console.warn("Failed fetching audit_logs remarks chunk:", err);
          }
        }
      }

      return remarksMap;
    },
    enabled: sortedIds.length > 0,
    staleTime: 60000,
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
            .neq("status", "archived")
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

// ---------------------------------------------------------------------------
// On-Leave Reliever Coverage & Floating Store Assignment Helpers
// ---------------------------------------------------------------------------

export interface ActiveCoverageItem {
  assignmentId: string;
  employeeId: string;
  employeeName: string;
  employeeNumber: string;
  coveredPlantillaId: string;
  startDate: string | null;
  endDate: string | null;
  status: string;
}

export async function fetchActiveCoverageForAccount(accountId: string): Promise<ActiveCoverageItem[]> {
  if (!accountId) return [];
  const supabase = createClient();
  const { data, error } = await supabase
    .from("v_workforce_store_temporary_coverage")
    .select("assignment_id, employee_id, employee_name, employee_number, covered_plantilla_id, start_date, end_date, status")
    .eq("account_id", accountId)
    .in("status", ["Active", "Approved"]);

  if (error) {
    console.warn("[Plantilla] Could not fetch active temporary coverage:", error);
    return [];
  }

  return (data ?? []).map((row) => ({
    assignmentId: String(row.assignment_id),
    employeeId: String(row.employee_id),
    employeeName: String(row.employee_name ?? ""),
    employeeNumber: String(row.employee_number ?? ""),
    coveredPlantillaId: String(row.covered_plantilla_id),
    startDate: row.start_date ? String(row.start_date) : null,
    endDate: row.end_date ? String(row.end_date) : null,
    status: String(row.status ?? "Active"),
  }));
}

export async function assignRelieverCoverage({
  employeeId,
  poolTypeId,
  coveredPlantillaId,
  assignedAccountId,
  assignedStoreId,
  startDate,
  endDate,
  notes,
}: {
  employeeId: string;
  poolTypeId?: string | null;
  coveredPlantillaId: string;
  assignedAccountId: string;
  assignedStoreId: string;
  startDate: string;
  endDate: string;
  notes?: string | null;
}) {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("workforce_assignments")
    .insert({
      employee_id: employeeId,
      pool_type_id: poolTypeId || null,
      covered_plantilla_id: coveredPlantillaId,
      assigned_account_id: assignedAccountId,
      assigned_store_id: assignedStoreId,
      deployment_type: "Reliever",
      priority: "Normal",
      status: "Active",
      is_primary: true,
      start_date: startDate,
      end_date: endDate,
      notes: notes || "Temporary reliever coverage",
    })
    .select()
    .single();

  if (error) {
    throwPlantillaError(error);
  }
  return data;
}

export async function assignFloatingEmployeeToStore({
  plantillaId,
  storeId,
  storeName,
  area,
  assignmentType = "Stationary",
  vcode,
}: {
  plantillaId: string;
  storeId: string;
  storeName: string;
  area?: string | null;
  assignmentType?: "Stationary" | "Roving";
  vcode?: string | null;
}) {
  const supabase = createClient();
  const updatePayload: Record<string, unknown> = {
    store_id: storeId,
    store_name: storeName,
    area: area || null,
    deployment_type: assignmentType || "Stationary",
    status: "Active",
    separation_status: null,
    inactive_at: null,
    inactive_by: null,
    date_of_separation: null,
    resignation_date: null,
    remarks: null,
    deactivation_reason: null,
    for_deactivation_at: null,
    for_deactivation_by: null,
    deactivated_at: null,
    deactivated_by: null,
    updated_at: new Date().toISOString(),
  };

  if (vcode !== undefined) {
    updatePayload.vcode = vcode;
  }

  const { data, error } = await supabase
    .from("plantilla")
    .update(updatePayload)
    .eq("id", plantillaId)
    .select()
    .single();

  if (error) {
    throwPlantillaError(error);
  }

  // If there's an open vacancy at this store, decrement/fill it
  try {
    const { data: openVacancies } = await supabase
      .from("vacancies")
      .select("id")
      .eq("store_id", storeId)
      .eq("status", "open")
      .limit(1);

    if (openVacancies && openVacancies.length > 0) {
      await supabase
        .from("vacancies")
        .update({
          status: "hired",
          updated_at: new Date().toISOString(),
        })
        .eq("id", openVacancies[0].id);
    }
  } catch (vacErr) {
    console.warn("Could not decrement vacancy:", vacErr);
  }

  return data;
}

// ---------------------------------------------------------------------------
// Account Governance & Lifecycle Operations (Add Account, Archive, Absorb)
// ---------------------------------------------------------------------------

export interface CreateAccountParams {
  accountName: string;
  accountCode?: string | null;
  groupId: string;
  createdBy?: string | null;
}

export async function createAccount(params: CreateAccountParams) {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("accounts")
    .insert({
      account_name: params.accountName.trim(),
      account_code: params.accountCode?.trim() || null,
      group_id: params.groupId,
      status: "Active",
      is_active: true,
      created_by: params.createdBy || null,
    })
    .select()
    .single();

  if (error) {
    throwPlantillaError(error);
  }
  return data;
}

export interface RequestAccountArchiveParams {
  accountId: string;
  accountName: string;
  remarks: string;
  requestedBy?: string | null;
  requestedByName?: string | null;
  authUserId?: string | null;
  actual?: number;
  vacant?: number;
  required?: number;
  groupName?: string | null;
}

export async function requestAccountArchive(params: RequestAccountArchiveParams) {
  const supabase = createClient();

  const formattedMessage = `Requester: ${params.requestedByName || "Admin"} | Active: ${params.actual ?? 0} | Vacant: ${params.vacant ?? 0} | Remarks: ${params.remarks}`;

  // Call database SECURITY DEFINER RPC notify_user
  const { error: rpcError } = await supabase.rpc("notify_user", {
    p_recipient_user_id: params.authUserId ?? null,
    p_recipient_role: "Super Admin",
    p_title: `Account Archive Request: ${params.accountName}`,
    p_message: formattedMessage,
    p_notification_type: "approval",
    p_event_type: "account_archive_request",
    p_reference_type: "account",
    p_reference_id: params.accountId,
    p_deep_link_route: "/approvals?tab=account_archives",
    p_sla_level: null,
  });

  if (rpcError) {
    console.error("Failed to create archive notification via notify_user:", rpcError);
    throw new Error(rpcError.message || "Failed to create archive notification");
  }

  // Record audit log conforming to audit_logs schema
  try {
    await supabase.from("audit_logs").insert({
      module: "plantilla",
      action: "UPDATE",
      record_id: params.accountId,
      new_data: {
        event: "ARCHIVE_ACCOUNT_REQUESTED",
        account_name: params.accountName,
        remarks: params.remarks,
        requested_by: params.requestedBy,
      },
    });
  } catch (auditErr) {
    console.warn("Failed to insert audit log for archive request:", auditErr);
  }

  return { success: true };
}

export interface AbsorbEmployeesParams {
  sourceAccountId: string;
  sourceAccountName: string;
  targetAccountId: string;
  targetAccountName: string;
  employees: {
    id: string;
    employeeNo: string;
    name: string;
    vcode?: string | null;
    primaryStoreName?: string | null;
  }[];
  isDirectExecution: boolean;
  requestedBy?: string | null;
  requestedByRole?: string | null;
  notes?: string | null;
}

export async function absorbEmployees(params: AbsorbEmployeesParams) {
  const supabase = createClient();

  if (params.isDirectExecution) {
    // Direct DB update for SA/HA
    const employeeIds = params.employees.map((e) => e.id);
    const employeeNos = params.employees.map((e) => e.employeeNo).filter(Boolean);

    // 1. Update plantilla records
    const { error: plantillaError } = await supabase
      .from("plantilla")
      .update({
        account: params.targetAccountName,
        account_id: params.targetAccountId,
        updated_at: new Date().toISOString(),
      })
      .in("id", employeeIds);

    if (plantillaError) {
      throwPlantillaError(plantillaError);
    }

    // 2. Update hr_emploc records if applicable
    if (employeeNos.length > 0) {
      try {
        await supabase
          .from("hr_emploc")
          .update({
            account: params.targetAccountName,
          })
          .in("emploc_no", employeeNos);
      } catch (hrErr) {
        console.warn("Failed to update hr_emploc during direct absorption:", hrErr);
      }
    }

    // 3. Record completed transfers
    try {
      const transfers = params.employees.map((e) => ({
        emploc_no: e.employeeNo || "N/A",
        employee_name: e.name,
        from_account: params.sourceAccountName,
        to_account: params.targetAccountName,
        from_store: e.primaryStoreName || null,
        from_vcode: e.vcode || null,
        requested_by: params.requestedBy || "Admin",
        requested_by_role: params.requestedByRole || "Admin",
        status: "Approved",
        reason: params.notes || "Employee absorption",
        reviewed_by: params.requestedBy || "Admin",
        reviewed_at: new Date().toISOString(),
      }));

      await supabase.from("employee_transfers").insert(transfers);
    } catch (txErr) {
      console.warn("Failed to insert employee_transfers audit rows:", txErr);
    }

    return { direct: true, count: params.employees.length };
  } else {
    // Pending record creation for Encoder
    const transfers = params.employees.map((e) => ({
      emploc_no: e.employeeNo || "N/A",
      employee_name: e.name,
      from_account: params.sourceAccountName,
      to_account: params.targetAccountName,
      from_store: e.primaryStoreName || null,
      from_vcode: e.vcode || null,
      requested_by: params.requestedBy || "Encoder",
      requested_by_role: params.requestedByRole || "Encoder",
      status: "Pending",
      reason: params.notes || "Batch employee absorption request",
    }));

    const { error: transferError } = await supabase
      .from("employee_transfers")
      .insert(transfers);

    if (transferError) {
      throwPlantillaError(transferError);
    }

    // Create notification for SA / HA
    try {
      await supabase.from("notifications").insert({
        title: "Employee Absorption Request",
        message: `Encoder requested absorption of ${params.employees.length} employees from "${params.sourceAccountName}" to "${params.targetAccountName}".`,
        notification_type: "approval",
        event_type: "employee_absorption_request",
        reference_type: "account_transfer",
        reference_id: params.sourceAccountId,
      });
    } catch (notifErr) {
      console.warn("Failed to notify admins of absorption request:", notifErr);
    }

    return { direct: false, count: params.employees.length };
  }
}

// ---------------------------------------------------------------------------
// Workforce Pool & Workforce Analytics Re-exports
// ---------------------------------------------------------------------------
export * from "./workforcePool";
export * from "./workforceAnalytics";



