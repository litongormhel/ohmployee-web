import test from "node:test";
import assert from "node:assert/strict";

/**
 * Global Search Navigation Deep-Linking Contract Tests
 * Validates direct routing to entity profiles (e.g. Dedicated Employee Profile /plantilla/[id])
 */

function getNavigationUrl(result) {
  const target = (result.navigationTarget || result.resultType).toLowerCase();
  const searchParam = encodeURIComponent(result.navigationId || result.primaryLabel);

  switch (target) {
    case "vacancy": {
      const vcode = encodeURIComponent(result.navigationId || result.primaryLabel);
      const idParam = result.recordId ? `&id=${encodeURIComponent(result.recordId)}` : "";
      const statusParam = result.status
        ? `&status=${encodeURIComponent(result.status.toLowerCase().replace(/\s+/g, "_"))}`
        : "";
      return `/vacancy?search=${vcode}&vcode=${vcode}${idParam}${statusParam}`;
    }
    case "plantilla": {
      if (result.recordId) {
        return `/plantilla/${encodeURIComponent(result.recordId)}`;
      }
      const statusParam = result.status
        ? `&status=${encodeURIComponent(result.status.toLowerCase().replace(/\s+/g, "_"))}`
        : "";
      return `/plantilla?search=${searchParam}${statusParam}`;
    }
    case "hr_emploc": {
      const idParam = result.recordId ? `&id=${encodeURIComponent(result.recordId)}` : "";
      const queueParam = result.status
        ? `&queue=${encodeURIComponent(result.status.toLowerCase().replace(/\s+/g, "_"))}`
        : "";
      return `/hr-emploc?search=${searchParam}${idParam}${queueParam}`;
    }
    case "applicant":
      return `/vacancy?tab=pipeline&search=${searchParam}&vcode=${searchParam}`;
    case "store": {
      const vcode = encodeURIComponent(result.navigationId || result.primaryLabel);
      const storeIdParam = result.recordId ? `&storeId=${encodeURIComponent(result.recordId)}` : "";
      const accountParam = result.accountName ? `&account=${encodeURIComponent(result.accountName)}` : "";
      return `/plantilla?view=store&search=${vcode}${storeIdParam}${accountParam}`;
    }
    case "cencom":
      return `/cencom?search=${searchParam}`;
    default:
      return `/${target}?search=${searchParam}`;
  }
}

test("GS-NAV-01: Plantilla result navigates directly to employee profile /plantilla/[id]", () => {
  const item = {
    resultType: "plantilla",
    recordId: "dcb39e11-6044-44f5-ae64-cd5b7a9401e3",
    primaryLabel: "ANTONELLI, ANDREA KIMI",
    secondaryLabel: "2026-0323232 · ACTISERVE",
    status: "On Leave",
    matchedField: "employee_name",
    navigationTarget: "plantilla",
    navigationId: "dcb39e11-6044-44f5-ae64-cd5b7a9401e3",
  };

  const url = getNavigationUrl(item);
  assert.equal(url, "/plantilla/dcb39e11-6044-44f5-ae64-cd5b7a9401e3");
});

test("GS-NAV-02: Fallback to /plantilla?search=... when recordId is missing", () => {
  const item = {
    resultType: "plantilla",
    recordId: "",
    primaryLabel: "ANTONELLI, ANDREA KIMI",
    secondaryLabel: "2026-0323232 · ACTISERVE",
    status: "Active",
    matchedField: "employee_name",
    navigationTarget: "plantilla",
    navigationId: "",
  };

  const url = getNavigationUrl(item);
  assert.equal(url, "/plantilla?search=ANTONELLI%2C%20ANDREA%20KIMI&status=active");
});

test("GS-NAV-03: Vacancy result deep links with vcode and id", () => {
  const item = {
    resultType: "vacancy",
    recordId: "vac-uuid-123",
    primaryLabel: "VCAG5_0056",
    secondaryLabel: "Cashier · SM AURORA",
    status: "Open",
    matchedField: "vcode",
    navigationTarget: "vacancy",
    navigationId: "VCAG5_0056",
  };

  const url = getNavigationUrl(item);
  assert.equal(url, "/vacancy?search=VCAG5_0056&vcode=VCAG5_0056&id=vac-uuid-123&status=open");
});

test("GS-NAV-04: HR Emploc result deep links with emploc id and queue", () => {
  const item = {
    resultType: "hr_emploc",
    recordId: "emploc-uuid-456",
    primaryLabel: "JOHN REY CHI",
    secondaryLabel: "2026-112233 · ALTURAS",
    status: "For Compliance",
    matchedField: "applicant_name",
    navigationTarget: "hr_emploc",
    navigationId: "emploc-uuid-456",
  };

  const url = getNavigationUrl(item);
  assert.equal(url, "/hr-emploc?search=emploc-uuid-456&id=emploc-uuid-456&queue=for_compliance");
});

test("GS-NAV-05: Store result deep links to /plantilla with view=store, storeId, and account", () => {
  const item = {
    resultType: "store",
    recordId: "store-uuid-789",
    primaryLabel: "SM CITY CEBU",
    secondaryLabel: "ZEBRA · VCEB_0001",
    status: "Active",
    matchedField: "store_name",
    navigationTarget: "store",
    navigationId: "VCEB_0001",
    accountName: "ZEBRA",
  };

  const url = getNavigationUrl(item);
  assert.equal(url, "/plantilla?view=store&search=VCEB_0001&storeId=store-uuid-789&account=ZEBRA");
});
