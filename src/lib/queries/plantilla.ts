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

// ---------------------------------------------------------------------------
// Row capabilities
// ---------------------------------------------------------------------------

export type PlantillaRowCapabilities = {
  canViewDetail: boolean;
  canInitiateTransfer: boolean;
  canInitiateSeparation: boolean;
  canApproveClearance: boolean;
  canEditRovingStores: boolean;
  canToggleSuspend: boolean;
  canRequestAh: boolean;
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
  key: string;
  label: string;
  completed: boolean;
};

export type PlantillaClearanceDocument = {
  documentId: string;
  fileName: string;
  fileUrl: string;
  uploadedAt: string;
  uploadedBy: string;
};

export type PlantillaMovementRequest = {
  movementId: string;
  movementType: string;
  targetStoreName: string | null;
  requestedAt: string;
  requestedBy: string | null;
  status: string;
};

export type PlantillaAuditTimelineItem = {
  eventId: string;
  eventLabel: string;
  eventDescription: string | null;
  createdAt: string;
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
  slaStatus: PlantillaStaffingSlaStatus | null;
  vacancySlaBreached: boolean;
  vacanciesCount: number;
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
  budgetedTarget: number;
  activeBudgetedCount: number;
  activeAdditionalCount: number;
  vacanciesCount: number;
  staffingSlaStatus: PlantillaStaffingSlaStatus | null;
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
  storeId?: string;
  position?: string;
  plantillaType?: string;
  status?: string;
  search?: string;
  page: number;
  pageSize: number;
  sortBy?: string;
  sortDir?: "asc" | "desc";
};

export type PlantillaStoreStaffingListParams = {
  accountId?: string;
  region?: string;
  slaStatus?: string;
  search?: string;
  page: number;
  pageSize: number;
};

export type PlantillaSummaryParams = {
  accountId?: string;
  storeId?: string;
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

function asObject(value: unknown): Record<string, unknown> {
  return value && !Array.isArray(value) && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
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

function asCount(value: unknown): number {
  return Math.max(0, Math.trunc(asNumber(value) ?? 0));
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
    canInitiateTransfer: raw.can_initiate_transfer === true,
    canInitiateSeparation: raw.can_initiate_separation === true,
    canApproveClearance: raw.can_approve_clearance === true,
    canEditRovingStores: raw.can_edit_roving_stores === true,
    canToggleSuspend: raw.can_toggle_suspend === true,
    canRequestAh: raw.can_request_ah === true,
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

function normalizeCoveredStore(item: unknown): PlantillaCoveredStore {
  const obj = asObject(item);
  return {
    storeId: asString(obj.store_id ?? obj.storeId) ?? "",
    storeName: asString(obj.store_name ?? obj.storeName) ?? "Unknown Store",
    allocationPercent: asNumber(obj.allocation_percent ?? obj.allocationPercent),
    isPrimary: asBoolean(obj.is_primary ?? obj.isPrimary),
  };
}

function normalizeClearanceChecklistItem(item: unknown): PlantillaClearanceChecklistItem {
  const obj = asObject(item);
  return {
    key: asString(obj.key) ?? "",
    label: asString(obj.label) ?? "Checklist Item",
    completed: asBoolean(obj.completed),
  };
}

function normalizeClearanceDocument(item: unknown): PlantillaClearanceDocument {
  const obj = asObject(item);
  return {
    documentId: asString(obj.document_id ?? obj.documentId) ?? "",
    fileName: asString(obj.file_name ?? obj.fileName) ?? "unnamed_file",
    fileUrl: asString(obj.file_url ?? obj.fileUrl) ?? "",
    uploadedAt: asString(obj.uploaded_at ?? obj.uploadedAt) ?? new Date().toISOString(),
    uploadedBy: asString(obj.uploaded_by ?? obj.uploadedBy) ?? "Unknown User",
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
    requestedAt: asString(obj.requested_at ?? obj.requestedAt) ?? new Date().toISOString(),
    requestedBy: asString(obj.requested_by ?? obj.requestedBy),
    status: asString(obj.status) ?? "Pending",
  };
}

function normalizeAuditTimelineItem(item: unknown): PlantillaAuditTimelineItem {
  const obj = asObject(item);
  return {
    eventId: asString(obj.event_id ?? obj.eventId) ?? "",
    eventLabel: asString(obj.event_label ?? obj.eventLabel) ?? "Event",
    eventDescription: asString(obj.event_description ?? obj.eventDescription),
    createdAt: asString(obj.created_at ?? obj.createdAt) ?? new Date().toISOString(),
    profileName: asString(obj.profile_name ?? obj.profileName),
  };
}

function normalizeEmployeeListRow(row: PlantillaRpcRow): PlantillaEmployeeListItem | null {
  const id = asString(row.id);
  if (!id) return null;

  return {
    id,
    employeeNo: asString(row.employee_no) ?? "Uncoded",
    firstName: asString(row.first_name),
    lastName: asString(row.last_name),
    positionTitle: asString(row.position_title),
    accountName: asString(row.account_name),
    primaryStoreName: asString(row.primary_store_name),
    assignmentType: asString(row.assignment_type),
    coveredStoresCount: asCount(row.covered_stores_count),
    plantillaType: asString(row.plantilla_type),
    plantillaStatus: asString(row.plantilla_status),
    dateDeployed: asString(row.date_deployed),
    tenureDays: asCount(row.tenure_days),
    baseRateMasked: asString(row.base_rate_masked),
    slaBreached: asBoolean(row.sla_breached),
    rowCapabilities: normalizeEmployeeCapabilities(row.row_capabilities),
    totalCount: asCount(row.total_count),
  };
}

function normalizeStoreStaffingRow(row: PlantillaRpcRow): PlantillaStoreStaffingRow | null {
  const storeId = asString(row.store_id);
  if (!storeId) return null;

  return {
    storeId,
    storeCode: asString(row.store_code),
    storeName: asString(row.store_name),
    accountName: asString(row.account_name),
    region: asString(row.region),
    budgetedTarget: asCount(row.budgeted_target),
    activeBudgetedCount: asCount(row.active_budgeted_count),
    activeAdditionalCount: asCount(row.active_additional_count),
    vacanciesCount: asCount(row.vacancies_count),
    staffingSlaStatus: asString(row.staffing_sla_status),
    vacancySlaBreached: asBoolean(row.vacancy_sla_breached),
    rowCapabilities: normalizeStoreCapabilities(row.row_capabilities),
    totalCount: asCount(row.total_count),
  };
}

function normalizeDetailRow(row: PlantillaRpcRow): PlantillaDetailItem | null {
  const id = asString(row.id);
  if (!id) return null;

  const rawCoveredStores = Array.isArray(row.covered_stores) ? row.covered_stores : [];
  const coveredStores = rawCoveredStores.map(normalizeCoveredStore);

  const rawChecklist = Array.isArray(row.clearance_checklist) ? row.clearance_checklist : [];
  const clearanceChecklist = rawChecklist.map(normalizeClearanceChecklistItem);

  const rawDocuments = Array.isArray(row.clearance_documents) ? row.clearance_documents : [];
  const clearanceDocuments = rawDocuments.map(normalizeClearanceDocument);

  const rawTimeline = Array.isArray(row.audit_timeline) ? row.audit_timeline : [];
  const auditTimeline = rawTimeline.map(normalizeAuditTimelineItem);

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
    slaStatus: row.staffingSlaStatus,
    vacancySlaBreached: row.vacancySlaBreached,
    vacanciesCount: row.vacanciesCount,
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
  return rows[0]?.totalCount ?? 0;
}

function getStoreTotalCount(rows: PlantillaStoreStaffingRow[]): number {
  return rows[0]?.totalCount ?? 0;
}

// ---------------------------------------------------------------------------
// Public RPC wrappers
// ---------------------------------------------------------------------------

export async function getPlantillaSummary(
  params: PlantillaSummaryParams = {},
): Promise<PlantillaSummary> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_plantilla_summary", {
    p_account_id: params.accountId ?? null,
    p_store_id: params.storeId ?? null,
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
    p_account_id: params.accountId ?? null,
    p_store_id: params.storeId ?? null,
    p_position: params.position ?? null,
    p_plantilla_type: params.plantillaType ?? null,
    p_status: params.status ?? null,
    p_search: params.search?.trim() || null,
    p_limit: pageSize,
    p_offset: offset,
    p_sort_by: params.sortBy ?? "last_name",
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
    p_account_id: params.accountId ?? null,
    p_region: params.region ?? null,
    p_sla_status: params.slaStatus ?? null,
    p_search: params.search?.trim() || null,
    p_limit: pageSize,
    p_offset: offset,
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
    p_plantilla_id: plantillaId,
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
