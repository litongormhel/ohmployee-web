/**
 * Lean Display Contracts (Interface Segregation Principle)
 *
 * Provides minimal contracts for presentation components (cells, badges, tooltips)
 * so they don't depend on large server-side row models.
 */

export interface EmployeeIdentitySummary {
  id: string;
  employeeNo: string | null;
  displayName?: string | null;
  fullName?: string | null;
  firstName?: string | null;
  lastName?: string | null;
}

export interface EmployeeStoreDeploymentSummary {
  storeId?: string | null;
  storeName?: string | null;
  storeCode?: string | null;
  city?: string | null;
  province?: string | null;
}

export interface EmployeePositionSummary {
  positionTitle?: string | null;
  assignmentType?: string | null;
  accountName?: string | null;
}

export interface StoreStaffingSummary {
  storeId: string;
  storeName: string | null;
  storeCode?: string | null;
  requiredHeadcount: number;
  actualHeadcount: number;
  openVacancyCount: number;
}
