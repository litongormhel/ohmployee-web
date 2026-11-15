// ============================================================================
// Payroll Reconciliation Engine (Pure Calculation & Matching Engine)
// ============================================================================

export interface PlantillaCheckRow {
  plantillaId: string;
  employeeNo: string;
  lastName: string;
  firstName: string;
  middleName: string;
  accountName: string;
  groupName: string;
  isActive: boolean;
}

export interface PayrollFinding {
  employeeNumber: string;
  payrollFullName?: string;
  plantillaFullName?: string;
  payrollAccountGroup?: string;
  plantillaAccountGroup?: string;
  findingType: "missingInPayroll" | "missingInPlantilla" | "paidInactive" | "mismatch" | "duplicate" | "clean";
}

export interface PayrollCheckResult {
  payrollRows: number;
  activePlantillaCount: number;
  missingInPayroll: PayrollFinding[];
  missingInPlantilla: PayrollFinding[];
  paidInactive: PayrollFinding[];
  mismatch: PayrollFinding[];
  duplicates: PayrollFinding[];
  clean: PayrollFinding[];
}

export function reconcilePayroll(
  payrollRows: { rowNumber: number; employeeNumber: string; fullName: string; accountGroup: string }[],
  plantillaRows: PlantillaCheckRow[]
): PayrollCheckResult {
  const plantillaByEmpNo = new Map<string, PlantillaCheckRow[]>();
  for (const p of plantillaRows) {
    const key = p.employeeNo.trim().toUpperCase();
    const existing = plantillaByEmpNo.get(key) ?? [];
    existing.push(p);
    plantillaByEmpNo.set(key, existing);
  }

  const activePlantillaCount = plantillaRows.filter((p) => p.isActive).length;

  const payrollCountByEmpNo = new Map<string, number>();
  for (const r of payrollRows) {
    const key = r.employeeNumber.trim().toUpperCase();
    payrollCountByEmpNo.set(key, (payrollCountByEmpNo.get(key) ?? 0) + 1);
  }

  const duplicateEmpNos = new Set(
    Array.from(payrollCountByEmpNo.entries())
      .filter(([, count]) => count > 1)
      .map(([empNo]) => empNo)
  );

  const payrollEmpNosProcessed = new Set<string>();

  const missingInPayroll: PayrollFinding[] = [];
  const missingInPlantilla: PayrollFinding[] = [];
  const paidInactive: PayrollFinding[] = [];
  const mismatch: PayrollFinding[] = [];
  const duplicates: PayrollFinding[] = [];
  const clean: PayrollFinding[] = [];

  for (const row of payrollRows) {
    const empNo = row.employeeNumber.trim().toUpperCase();

    if (duplicateEmpNos.has(empNo)) {
      duplicates.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        payrollAccountGroup: row.accountGroup,
        findingType: "duplicate",
      });
      continue;
    }

    payrollEmpNosProcessed.add(empNo);
    const matches = plantillaByEmpNo.get(empNo);

    if (!matches || matches.length === 0) {
      missingInPlantilla.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        payrollAccountGroup: row.accountGroup,
        findingType: "missingInPlantilla",
      });
      continue;
    }

    const p = matches[0];
    const pFullName = `${p.lastName.trim()}, ${p.firstName.trim()}${p.middleName.trim() ? " " + p.middleName.trim() : ""}`.toUpperCase();
    const pAccountGroup = `${p.accountName.trim()} / ${p.groupName.trim()}`.toUpperCase();

    if (!p.isActive) {
      paidInactive.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        plantillaFullName: pFullName,
        payrollAccountGroup: row.accountGroup,
        plantillaAccountGroup: pAccountGroup,
        findingType: "paidInactive",
      });
      continue;
    }

    const normPayName = row.fullName.replace(/[^A-Z0-9]/gi, "").toUpperCase();
    const normPlanName = pFullName.replace(/[^A-Z0-9]/gi, "").toUpperCase();
    const normPayAcct = row.accountGroup.replace(/[^A-Z0-9]/gi, "").toUpperCase();
    const normPlanAcct = pAccountGroup.replace(/[^A-Z0-9]/gi, "").toUpperCase();

    const nameDiffers = normPayName !== normPlanName;
    const acctDiffers = normPayAcct !== normPlanAcct;

    if (nameDiffers || acctDiffers) {
      mismatch.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        plantillaFullName: pFullName,
        payrollAccountGroup: row.accountGroup,
        plantillaAccountGroup: pAccountGroup,
        findingType: "mismatch",
      });
    } else {
      clean.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        plantillaFullName: pFullName,
        payrollAccountGroup: row.accountGroup,
        plantillaAccountGroup: pAccountGroup,
        findingType: "clean",
      });
    }
  }

  // Missing in Payroll
  for (const p of plantillaRows) {
    if (!p.isActive) continue;
    const empNo = p.employeeNo.trim().toUpperCase();
    if (!payrollEmpNosProcessed.has(empNo) && !duplicateEmpNos.has(empNo)) {
      const pFullName = `${p.lastName.trim()}, ${p.firstName.trim()}${p.middleName.trim() ? " " + p.middleName.trim() : ""}`.toUpperCase();
      const pAccountGroup = `${p.accountName.trim()} / ${p.groupName.trim()}`.toUpperCase();
      missingInPayroll.push({
        employeeNumber: empNo,
        plantillaFullName: pFullName,
        plantillaAccountGroup: pAccountGroup,
        findingType: "missingInPayroll",
      });
    }
  }

  return {
    payrollRows: payrollRows.length,
    activePlantillaCount,
    missingInPayroll,
    missingInPlantilla,
    paidInactive,
    mismatch,
    duplicates,
    clean,
  };
}
