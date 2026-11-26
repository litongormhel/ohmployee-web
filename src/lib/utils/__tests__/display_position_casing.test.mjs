import test from "node:test";
import assert from "node:assert/strict";
import { formatPosition } from "../displayText.ts";

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
