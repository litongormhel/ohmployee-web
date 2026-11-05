import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  normalizeSummary,
  normalizeListRow,
  normalizeDetailRow,
  normalizeCapabilities,
  normalizeAttachment,
  normalizeHrEmplocRemarks,
} from "../hr_emploc_normalizers.ts";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fixturesDir = path.resolve(__dirname, "../__fixtures__");

function loadFixture(filename) {
  const filepath = path.join(fixturesDir, filename);
  return JSON.parse(fs.readFileSync(filepath, "utf8"));
}

test("Contract: normalizeSummary parses real get_web_hr_emploc_summary response", () => {
  const fixture = loadFixture("hr_emploc_summary_fixture.json");
  assert.ok(fixture, "Fixture should load");

  const summary = normalizeSummary(fixture);
  assert.equal(typeof summary.pending, "number");
  assert.equal(typeof summary.forEmploc, "number");
  assert.equal(typeof summary.correction, "number");
  assert.equal(typeof summary.review, "number");
  assert.equal(typeof summary.deployed, "number");

  assert.equal(summary.pending, fixture.pending_count);
  assert.equal(summary.forEmploc, fixture.for_emploc_count);
  assert.equal(summary.correction, fixture.correction_count);
  assert.equal(summary.review, fixture.review_count);
  assert.equal(summary.deployed, fixture.ready_count ?? fixture.deployed_count);
});

test("Contract: normalizeListRow parses real get_web_hr_emplocs row", () => {
  const fixture = loadFixture("hr_emploc_list_fixture.json");
  assert.ok(Array.isArray(fixture) && fixture.length > 0, "List fixture should have rows");

  for (const rawRow of fixture) {
    const item = normalizeListRow(rawRow);
    assert.ok(item, "List row should normalize");
    assert.equal(item.id, rawRow.id ?? rawRow.hr_emploc_id);
    assert.ok(item.applicantName, "Should have applicantName");
    assert.equal(item.accountName, rawRow.account_name ?? rawRow.accountName);
    assert.equal(item.hrStatus, rawRow.hr_status);
    assert.equal(item.deploymentStatus, rawRow.status ?? rawRow.deployment_status);
    assert.equal(typeof item.rowCapabilities, "object");
    assert.equal(typeof item.rowCapabilities.can_upload_docs, "boolean");
    assert.equal(typeof item.rowCapabilities.can_assign_employee_no, "boolean");
    assert.equal(typeof item.rowCapabilities.can_submit_correction, "boolean");
    assert.equal(typeof item.rowCapabilities.can_review_approve, "boolean");
  }
});

test("Contract: normalizeDetailRow parses real get_web_hr_emploc_detail row", () => {
  const fixture = loadFixture("hr_emploc_detail_fixture.json");
  assert.ok(fixture, "Detail fixture should load");

  const detail = normalizeDetailRow(fixture);
  assert.ok(detail, "Detail row should normalize");
  assert.equal(detail.id, fixture.id ?? fixture.hr_emploc_id);
  assert.ok(detail.applicantName, "Should have applicantName");
  assert.equal(detail.accountName, fixture.account_name ?? fixture.accountName);
  assert.equal(detail.hrStatus, fixture.hr_status);
  assert.equal(detail.deploymentStatus, fixture.status ?? fixture.deployment_status);
  assert.equal(typeof detail.rowCapabilities, "object");
  assert.ok(Array.isArray(detail.attachments), "Attachments should be an array");
  assert.ok(Array.isArray(detail.coveredStores), "Covered stores should be an array");
  assert.ok(Array.isArray(detail.auditLogsTimeline), "Audit logs should be an array");
});

test("Contract: normalizeCapabilities parses all 25 role x queue combinations from A2", () => {
  const fixture = loadFixture("hr_emploc_a2_capabilities.json");
  assert.ok(Array.isArray(fixture), "A2 fixture should be an array");
  assert.equal(fixture.length, 25, "Should have exactly 25 rows (5 roles x 5 queues)");

  for (const entry of fixture) {
    const caps = normalizeCapabilities(entry.row_capabilities);
    assert.equal(typeof caps.can_upload_docs, "boolean", `can_upload_docs for ${entry.role}/${entry.queue}`);
    assert.equal(typeof caps.can_submit_requirements, "boolean", `can_submit_requirements for ${entry.role}/${entry.queue}`);
    assert.equal(typeof caps.can_assign_employee_no, "boolean", `can_assign_employee_no for ${entry.role}/${entry.queue}`);
    assert.equal(typeof caps.can_tag_deficiency, "boolean", `can_tag_deficiency for ${entry.role}/${entry.queue}`);
    assert.equal(typeof caps.can_submit_correction, "boolean", `can_submit_correction for ${entry.role}/${entry.queue}`);
    assert.equal(typeof caps.can_review_approve, "boolean", `can_review_approve for ${entry.role}/${entry.queue}`);
    assert.equal(typeof caps.can_review_return, "boolean", `can_review_return for ${entry.role}/${entry.queue}`);
    assert.equal(typeof caps.can_edit_emploc_no, "boolean", `can_edit_emploc_no for ${entry.role}/${entry.queue}`);
    assert.equal(typeof caps.can_revert_to_pending, "boolean", `can_revert_to_pending for ${entry.role}/${entry.queue}`);
    assert.equal(typeof caps.can_request_deletion, "boolean", `can_request_deletion for ${entry.role}/${entry.queue}`);
  }
});

test("Contract: normalizeAttachment parses attachment payloads with object_path and storage_path", () => {
  const mockAttachment = {
    id: "314046ec-34c4-4b85-bba2-d60188a00471",
    storage_path: "hr-corrections/emploc-docs/test_id/123_file.pdf",
    original_filename: "file.pdf",
    mime_type: "application/pdf",
    size_bytes: 204800,
    stage: "initial_requirements",
    uploaded_at: "2026-11-05T14:11:06.946Z",
    uploaded_by: "aa390efd-fd23-4995-8310-8c5bf877e95a",
  };

  const att = normalizeAttachment(mockAttachment);
  assert.equal(att.attachmentId, mockAttachment.id);
  assert.equal(att.fileUrl, mockAttachment.storage_path);
  assert.equal(att.fileName, mockAttachment.original_filename);
  assert.equal(att.fileSize, mockAttachment.size_bytes);
});

test("Contract: normalizeHrEmplocRemarks respects ops_remarks first precedence", () => {
  const rowWithAll = {
    ops_remarks: "Ops remark note",
    remarks: "General remark",
    notes: "Correction notes",
  };
  assert.equal(normalizeHrEmplocRemarks(rowWithAll), "Ops remark note");

  const rowWithoutOps = {
    ops_remarks: null,
    remarks: "General remark",
    notes: "Correction notes",
  };
  assert.equal(normalizeHrEmplocRemarks(rowWithoutOps), "General remark");

  const rowWithNotesOnly = {
    ops_remarks: "",
    remarks: "   ",
    notes: "Correction notes",
  };
  assert.equal(normalizeHrEmplocRemarks(rowWithNotesOnly), "Correction notes");

  const rowWithEmpty = {
    ops_remarks: "",
    remarks: "   ",
    notes: "   ",
  };
  assert.equal(normalizeHrEmplocRemarks(rowWithEmpty), null);
});
