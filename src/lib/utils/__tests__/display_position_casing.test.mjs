import test from "node:test";
import assert from "node:assert/strict";
import { formatPosition, formatStoreName, formatCivilStatus, formatDeploymentType } from "../displayText.ts";

test("formatPosition: converts CAPSLOCK and lowercase to Proper Case", () => {
  assert.equal(formatPosition("MERCHANDISER"), "Merchandiser");
  assert.equal(formatPosition("merchandiser"), "Merchandiser");
  assert.equal(formatPosition("CASHIER"), "Cashier");
  assert.equal(formatPosition("cashier"), "Cashier");
  assert.equal(formatPosition("PROMODISER"), "Promodiser");
  assert.equal(formatPosition("ACCOUNTING STAFF"), "Accounting Staff");
  assert.equal(formatPosition("ADMIN ASSISTANT - TRAINING"), "Admin Assistant - Training");
  assert.equal(formatPosition("SERVICE CREW (COMMANDO)"), "Service Crew (Commando)");
});

test("formatPosition: 2 to 3 letter tokens are strictly UPPERCASE all", () => {
  assert.equal(formatPosition("fsr"), "FSR");
  assert.equal(formatPosition("FSR"), "FSR");
  assert.equal(formatPosition("smp"), "SMP");
  assert.equal(formatPosition("SMP"), "SMP");
  assert.equal(formatPosition("qa"), "QA");
  assert.equal(formatPosition("QA"), "QA");
  assert.equal(formatPosition("tl"), "TL");
  assert.equal(formatPosition("TL"), "TL");
  assert.equal(formatPosition("om"), "OM");
  assert.equal(formatPosition("OM"), "OM");
  assert.equal(formatPosition("atl"), "ATL");
  assert.equal(formatPosition("ATL"), "ATL");
  assert.equal(formatPosition("ar collector"), "AR Collector");
  assert.equal(formatPosition("AR COLLECTOR"), "AR Collector");
  assert.equal(formatPosition("gl merchandiser"), "GL Merchandiser");
  assert.equal(formatPosition("GL MERCHANDISER"), "GL Merchandiser");
  assert.equal(formatPosition("CASHIER (FSR BEFORE)"), "Cashier (FSR Before)");
  assert.equal(formatPosition("FIELD SALES REPRESENTATIVE/FSR"), "Field Sales Representative/FSR");
});

test("formatPosition: preserves known acronym allowlist with 4+ letters", () => {
  assert.equal(formatPosition("hrco"), "HRCO");
  assert.equal(formatPosition("HRCO"), "HRCO");
});

test("formatPosition: handles null, undefined, and empty string safely", () => {
  assert.equal(formatPosition(null), "");
  assert.equal(formatPosition(undefined), "");
  assert.equal(formatPosition(""), "");
  assert.equal(formatPosition("   "), "");
});

test("formatStoreName: formats Title Case and preserves uppercase retail/location acronyms", () => {
  assert.equal(formatStoreName("SM MAGUINDANAO"), "SM Maguindanao");
  assert.equal(formatStoreName("PUREGOLD MOA"), "Puregold MOA");
  assert.equal(formatStoreName("PUREGOLD NORTH EDSA"), "Puregold North EDSA");
  assert.equal(formatStoreName("SIOSON SUPERMARKET"), "Sioson Supermarket");
  assert.equal(formatStoreName("SSM JAZZ [roving]"), "SSM Jazz");
  assert.equal(formatStoreName("NCCC DAVAO"), "NCCC Davao");
  assert.equal(formatStoreName("S&R NEW MANILA"), "S&R New Manila");
});

test("formatCivilStatus: canonical Title Case and nullifies dirty artifacts", () => {
  assert.equal(formatCivilStatus("SINGLE"), "Single");
  assert.equal(formatCivilStatus("single"), "Single");
  assert.equal(formatCivilStatus("MARRIED"), "Married");
  assert.equal(formatCivilStatus("widowed"), "Widowed");
  assert.equal(formatCivilStatus("SEPARATED"), "Separated");
  assert.equal(formatCivilStatus("N/A"), "");
  assert.equal(formatCivilStatus("0"), "");
  assert.equal(formatCivilStatus(null), "");
});

test("formatDeploymentType: formats Stationary, Roving, Commando", () => {
  assert.equal(formatDeploymentType("stationary"), "Stationary");
  assert.equal(formatDeploymentType("roving"), "Roving");
  assert.equal(formatDeploymentType("commando"), "Commando");
  assert.equal(formatDeploymentType(null), "");
});
