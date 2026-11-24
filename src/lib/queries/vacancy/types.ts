export type VacancyStatus =
  | "open"
  | "pipeline"
  | "hired"
  | "closure"
  | "failed_backout"
  | "with_applicant"
  | "rejected"
  | "backout";

export type VacancyAgingBucket =
  | "advance"
  | "1_15"
  | "16_30"
  | "31_60"
  | "61_120"
  | "gt121";

export type VacancyPipelineStatus = "Open" | "Pipeline";

export type VacancySortField =
  | "aging_days"
  | "vacant_date"
  | "target_fill_date"
  | "urgency"
  | "account_name"
  | "group_name"
  | "store_name"
  | "position_title"
  | "vacancy_status"
  | "pipeline_status"
  | "vcode";

export type VacancySortDirection = "asc" | "desc";

export type VacancyRowCapabilities = {
  canViewDetail: boolean;
  canApprove: boolean;
  canUpdateApplicantStatus: boolean;
  canRequestClosure: boolean;
  raw: Record<string, boolean>;
};

export type AssignedStoreDetail = {
  storeId?: string;
  storeName: string;
  vcode?: string | null;
  isAnchor?: boolean;
  slotFraction?: string | null;
};

export type VacancyListItem = {
  id: string;
  vcode: string;
  cgCode?: string | null;
  assignedStores?: string[];
  assignedStoreDetails?: AssignedStoreDetail[];
  accountId: string | null;
  accountName: string | null;
  groupId: string | null;
  groupName: string | null;
  storeId: string | null;
  storeName: string | null;
  storeLocation: string | null;
  position_title: string | null;
  department: string | null;
  employmentType: string | null;
  vacancyStatus: string | null;
  pipelineStatus: VacancyPipelineStatus | string | null;
  derivedStatus: string | null;
  activeApplicantCount: number;
  confirmedOnboardCount: number;
  hasRecentHire: boolean;
  hasPendingClosure: boolean;
  closureRequestStatus: string | null;
  vacantDate: string | null;
  agingDays: number | null;
  agingBucket: VacancyAgingBucket | string | null;
  targetFillDate: string | null;
  urgencyLevel: string | null;
  hrcoName: string | null;
  applicantId?: string | null;
  applicantName: string | null;
  applicantFirstName?: string | null;
  applicantLastName?: string | null;
  applicantMiddleName?: string | null;
  contactNumber?: string | null;
  recruiterName?: string | null;
  recruiterId?: string | null;
  endorsedByName?: string | null;
  hiredDate?: string | null;
  daysToFill?: number | null;
  stageBadge?: string | null;
  remarks?: string | null;
  opsRemarks?: string | null;
  recruitmentRemarks?: string | null;
  hrRemarks?: string | null;
  closureReason?: string | null;
  closureRequestedBy?: string | null;
  closureRequestedAt?: string | null;
  closureRequestId?: string | null;
  dropoutReason?: string | null;
  dropoutDate?: string | null;
  hasPenalty: boolean;
  penaltyExposure: number;
  penaltyAmount: number | null;
  headcount?: number;
  hcFilled?: number;
  hcTotal?: number;
  hcDisplay?: string;
  slotOrdinal?: number | null;
  parentVacancyId?: string | null;
  slotFraction?: string | null;
  slotShare?: number | null;
  hrProcessingCount?: number;
  slotsList?: Array<{ slotId: string; slotOrdinal: number; position: string; slotStatus: string }>;
  activeApplicantsList?: ActiveApplicantItem[];
  vacancyRequirementId?: string | null;
  lastActivityAt: string | null;
  rowCapabilities: VacancyRowCapabilities;
  profileEditCount?: number | null;
  totalCount: number;
};

export type ActiveApplicantItem = {
  applicantId: string;
  displayName: string;
  lastName: string | null;
  firstName: string | null;
  middleName?: string | null;
  contactNumber: string | null;
  statusLabel: string;
  onboardDate: string | null;
  updatedAt: string | null;
  recruiterName: string | null;
  remarks?: string | null;
  slotId?: string | null;
  slotOrdinal?: number | null;
  deployedByName?: string | null;
  profileEditCount?: number | null;
  createdAt?: string | null;
  agingDays?: number | null;
  position?: string | null;
  vacancyRequirementId?: string | null;
};

export type ActivityHistoryItem = {
  eventId: string;
  eventLabel: string;
  eventDescription: string | null;
  createdAt: string | null;
  profileName: string | null;
};

export type VacancyRequirementItem = {
  id: string;
  positionName: string;
  employmentType?: string | null;
  hcNeeded: number;
  hcFilled: number;
  pipelineCount: number;
};

export type VacancyDetailItem = {
  vacancyId: string;
  vcode: string;
  cgCode?: string | null;
  assignedStores?: string[];
  assignedStoreDetails?: AssignedStoreDetail[];
  source?: string | null;
  vacancyType?: string | null;
  createdAt?: string | null;
  requirements?: VacancyRequirementItem[];
  accountId: string | null;
  accountName: string | null;
  groupId: string | null;
  groupName: string | null;
  storeId: string | null;
  storeName: string | null;
  position_title: string | null;
  department: string | null;
  employmentType: string | null;
  vacancyStatus: string | null;
  pipelineStatus: string | null;
  derivedStatus: string | null;
  activeApplicantCount: number;
  confirmedOnboardCount: number;
  hasRecentHire: boolean;
  hasPendingClosure: boolean;
  closureRequestStatus: string | null;
  vacantDate: string | null;
  agingDays: number | null;
  agingBucket: string | null;
  targetFillDate: string | null;
  urgencyLevel: string | null;
  hrcoName: string | null;
  lastActivityAt: string | null;
  rowCapabilities: VacancyRowCapabilities;

  // Supplementary fields from official sheet schema
  contactNumber: string | null;
  onboardDate: string | null;
  daysToFill?: number | null;
  relieverOnDuty: string | null;
  hasReliever: boolean;
  hrcoRemarks: string | null;
  recruiterName: string | null;
  deployedByName?: string | null;
  hasPenalty: boolean;
  penaltyExposure: number;
  penaltyAmount: number | null;
  headcount?: number;
  hcFilled?: number;
  hcTotal?: number;
  hcDisplay?: string;
  applicantId?: string | null;
  applicantLastName: string | null;
  applicantFirstName: string | null;
  applicantMiddleName: string | null;
  applicantName: string | null;
  storeLocation: string | null;
  areaCity: string | null;
  areaProvince: string | null;
  storeBranch: string | null;
  omName?: string | null;
  tlName?: string | null;
  atlName?: string | null;

  // Detail-specific fields
  requestedById: string | null;
  requestedByName: string | null;
  triggeredByName?: string | null;
  approvedById: string | null;
  approvedByName: string | null;
  approvedAt: string | null;
  headcountRequestId: string | null;
  vacancyReason: string | null;
  jobDescription: string | null;
  closureRequestedAt: string | null;
  closureRequestedBy: string | null;
  closureReason: string | null;
  profileEditCount?: number | null;
  activeApplicantsList: ActiveApplicantItem[];
  activityHistory: ActivityHistoryItem[];
};

export type VacancyListParams = {
  status?: VacancyStatus;
  search?: string;
  agingBucket?: string;
  accountId?: string;
  groupId?: string;
  position?: string;
  urgency?: string;
  vacantFrom?: string;
  vacantTo?: string;
  page: number;
  pageSize: number;
  sortBy?: string;
  sortDir?: "asc" | "desc";
  consolidateCoverageGroups?: boolean;
};

export type VacancySummary = {
  open: number;
  pipeline: number;
  hired: number;
  closure: number;
  failedBackout: number;
  withApplicant: number;
  rejected: number;
  backout: number;
  pendingReview: number;
  agingWatch: number;
  total: number;
};

export type VacancyDataErrorKind =
  | "access_denied"
  | "retryable"
  | "validation"
  | "not_found"
  | "generic";

export class VacancyDataError extends Error {
  kind: VacancyDataErrorKind;

  constructor(kind: VacancyDataErrorKind, message: string) {
    super(message);
    this.name = "VacancyDataError";
    this.kind = kind;
  }
}

export type VacancyRpcRow = Record<string, unknown>;

export type CandidateDuplicateCheckResult = {
  isBlocked: boolean;
  conflictType?: "Pipeline" | "HR Emploc" | "Plantilla" | null;
  status?: string | null;
  vcode?: string | null;
  storeName?: string | null;
  account?: string | null;
  message?: string | null;
  isDuplicate?: boolean;
  duplicateCandidateId?: string | null;
  duplicateCandidateName?: string | null;
  currentStoreName?: string | null;
  currentPositionTitle?: string | null;
};

export type UpdateApplicantProfileParams = {
  applicantId: string;
  firstName: string;
  lastName: string;
  middleName?: string | null;
  contactNumber: string;
  reason: string;
  vcode?: string;
  updatedBy?: string;
  recruiterId?: string | null;
  onboardDate?: string | null;
  deploymentType?: string | null;
  sourceType?: string | null;
};

export type UpdateApplicantProfileResult = {
  success: boolean;
  applicantId: string;
  fullName?: string;
  profileEditCount?: number;
  linkedPropagatedCount?: number;
};

export type EndorseApplicantParams = {
  vcode: string;
  firstName: string;
  middleName: string;
  lastName: string;
  contactNumber: string;
  targetOnboardDate?: string | null;
  recruiterName?: string | null;
  recruiterId?: string | null;
  hrcoRemarks?: string | null;
  status?: string;
  vacancyId?: string;
  applicantLastName?: string;
  applicantFirstName?: string;
  applicantMiddleName?: string | null;
  notes?: string | null;
  endorsedByUserId?: string | null;
  stageBadge?: string | null;
  onboardDate?: string | null;
  targetDeploymentType?: string | null;
  targetSlotId?: string | null;
  vacancyRequirementId?: string | null;
};

export type EndorseApplicantResult = {
  id: string;
  vcode: string;
  fullName: string;
  status: string;
  success?: boolean;
  applicantId?: string;
  vacancyId?: string;
  candidateName?: string;
};

export type UpdateApplicantPipelineParams = {
  applicantId: string;
  newStatus?: string | null;
  recruitmentRemarks?: string | null;
  opsRemarks?: string | null;
  followUpDate?: string | null;
  reasonId?: string | null;
  reasonType?: string | null;
  vcode?: string;
  vacancyId?: string;
  notes?: string | null;
  updatedByUserId?: string | null;
};

export type ConfirmApplicantOnboardParams = {
  applicantId: string;
  lastName: string;
  firstName: string;
  middleName?: string | null;
  fullName: string;
  contactNumber: string;
  hiredByUserId?: string | null;
  hiredDate: string; // YYYY-MM-DD
  endorsedByDeployerId?: string | null;
  endorsedByName?: string | null;
  remarks?: string | null;
  rovingAssignmentId?: string | null;
  vacancyRequirementId?: string | null;
  vcode?: string;
  vacancyId?: string;
  actualHiredDate?: string;
  employeeNo?: string;
  confirmedByUserId?: string;
};

export type FailBackoutParams = {
  applicantId: string;
  reason: string;
  reasonId?: string | null;
  status: "Backout" | "Failed" | "Rejected";
  vcode: string;
  vacancyId?: string;
  failureType?: "Failed" | "Backout";
  reasonText?: string;
  notes?: string;
  actionByUserId?: string;
};

export type ReopenVacancyParams = {
  vcode: string;
  reason?: string;
  vacantDate?: string;
  vacancyId?: string;
  notes?: string;
  reopenedByUserId?: string;
};

export type OccupiedStoreIdentifiers = {
  occupiedStoreIds: Set<string>;
  occupiedVcodes: Set<string>;
  occupiedStoreNames: Set<string>;
};

export type DirectImportVacancyParams = {
  vcode: string;
  storeName?: string | null;
  storeId?: string | null;
  accountId?: string | null;
  accountName?: string | null;
  groupId?: string | null;
  position?: string | null;
  positionId?: string | null;
  positionTitle?: string | null;
  employmentType?: string | null;
  headcountNeeded?: number;
  requiredHeadcount?: number;
  areaCity?: string | null;
  province?: string | null;
  areaProvince?: string | null;
  vacantDate?: string | null;
  targetFillDate?: string | null;
  urgencyLevel?: string | null;
  applicantLastName?: string | null;
  applicantFirstName?: string | null;
  applicantMiddleName?: string | null;
  contactNumber?: string | null;
  stageBadge?: string | null;
  notes?: string | null;
  status?: string | null;
  recruiterId?: string | null;
};

export type RequestVacancyClosureParams = {
  vcode: string;
  reason: string;
  details?: string;
  requestedBy: string;
  requestedByRole?: string;
  requestedByUserId?: string | null;
};

export type ReviewClosureRequestParams = {
  requestId: string;
  status: "Approved" | "Rejected";
  reviewedBy: string;
  remarks?: string;
  vcode?: string;
};

export type WithdrawVacancyClosureParams = {
  vcode: string;
  userId?: string | null;
};

export type UpdateHiredDateParams = {
  applicantId: string;
  hiredDate: string;
  vacancyId?: string;
  remarks?: string;
  updatedByUserId?: string;
};

export type VacancyExportFilters = {
  status?: VacancyStatus;
  search?: string;
  agingBucket?: string;
  accountId?: string;
  groupId?: string;
  position?: string;
  urgency?: string;
  vacantFrom?: string;
  vacantTo?: string;
  sortBy?: string;
  sortDir?: "asc" | "desc";
  dateFrom?: string;
  dateTo?: string;
  aging?: string;
};

export type VacancyExportResult = {
  csv: string;
  filename: string;
  rowCount: number;
  scopeTitle?: string;
};

export interface VacancyExportRowData {
  vcode: string;
  positionTitle?: string;
  lifecycleStatus?: string;
  accountName: string;
  groupName: string;
  storeName: string;
  storeLocation: string;
  hrcoName: string;
  agingDays: number | string;
  urgencyLevel: string;
  createdDate?: string;
  department?: string;
  employmentType?: string;
  vacancyStatus?: string;
  pipelineStatus?: string;
  activeApplicantCount?: number;
  vacantDate?: string;
  targetFillDate?: string;
  agingBucket?: string;
  applicantName?: string;
  contactNumber?: string;
  recruiterName?: string;
  stageBadge?: string;
  remarks?: string;
  penaltyExposure?: number;
}
