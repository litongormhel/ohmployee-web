import test from "node:test";
import assert from "node:assert/strict";
import { parseHrEmplocError } from "../hr_emploc_errors.ts";

test("parses DETAIL code first", () => {
  const err = {
    message: "Some generic message",
    code: "22023",
    details: JSON.stringify({ code: "REQUIREMENTS_DOCS_MISSING", missing_count: 1 }),
  };
  const parsed = parseHrEmplocError(err);
  assert.equal(parsed.code, "REQUIREMENTS_DOCS_MISSING");
  assert.equal(parsed.title, "Requirements Missing");
  assert.equal(parsed.sqlstate, "22023");
  assert.equal(parsed.details?.missing_count, 1);
});

test("parses message token prefix when details has no code", () => {
  const err = {
    message: "DOC_INVALID_MIME_TYPE: Unsupported mime type application/pdf",
    code: "22023",
  };
  const parsed = parseHrEmplocError(err);
  assert.equal(parsed.code, "DOC_INVALID_MIME_TYPE");
  assert.equal(parsed.title, "Unsupported File Type");
  assert.equal(parsed.sqlstate, "22023");
});

test("parses SQLSTATE fallback when no token or detail", () => {
  const err = {
    message: "permission denied for table hr_emploc_correction_attachments",
    code: "42501",
  };
  const parsed = parseHrEmplocError(err);
  assert.equal(parsed.code, "FORBIDDEN_ROLE_OR_SCOPE");
  assert.equal(parsed.title, "Permission Denied");
});

test("parses REHIRE_CONFIRM_REQUIRED with display name and employee no", () => {
  const err = {
    message: "REHIRE_CONFIRM_REQUIRED: YAP, JAY was previously assigned number 2099-00001",
    code: "23505",
    details: { code: "REHIRE_CONFIRM_REQUIRED", employee_no: "2099-00001", display_name: "YAP, JAY" },
  };
  const parsed = parseHrEmplocError(err);
  assert.equal(parsed.code, "REHIRE_CONFIRM_REQUIRED");
  assert.equal(parsed.title, "Rehire Confirmation Required");
  assert.match(parsed.message, /YAP, JAY/);
  assert.match(parsed.message, /2099-00001/);
});

test("parses ACTION_LOCKED_PENDING_DELETION correctly", () => {
  const err = {
    message: "ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.",
    code: "P0001",
    details: '{"code": "ACTION_LOCKED_PENDING_DELETION"}',
  };
  const parsed = parseHrEmplocError(err);
  assert.equal(parsed.code, "ACTION_LOCKED_PENDING_DELETION");
  assert.equal(parsed.title, "Action Locked");
});

test("parses FIELD_REQUIRED_MISSING with field name", () => {
  const err = {
    message: "FIELD_REQUIRED_MISSING: hired_date is required",
    code: "22023",
    details: { code: "FIELD_REQUIRED_MISSING", field: "hired_date" },
  };
  const parsed = parseHrEmplocError(err);
  assert.equal(parsed.code, "FIELD_REQUIRED_MISSING");
  assert.match(parsed.message, /hired_date/);
});

test("parses DOC_FILE_TOO_LARGE", () => {
  const err = {
    message: "DOC_FILE_TOO_LARGE: file size exceeds limit",
    code: "22023",
    details: { code: "DOC_FILE_TOO_LARGE", max_bytes: 5242880 },
  };
  const parsed = parseHrEmplocError(err);
  assert.equal(parsed.code, "DOC_FILE_TOO_LARGE");
  assert.equal(parsed.title, "File Too Large");
});

test("parses FORBIDDEN_NOT_UPLOADER", () => {
  const err = {
    message: "FORBIDDEN_NOT_UPLOADER: only uploader can delete unverified document",
    code: "42501",
    details: { code: "FORBIDDEN_NOT_UPLOADER" },
  };
  const parsed = parseHrEmplocError(err);
  assert.equal(parsed.code, "FORBIDDEN_NOT_UPLOADER");
  assert.equal(parsed.title, "Cannot Delete Document");
});

test("parses INVALID_HR_STATUS_FOR_ASSIGN and INVALID_STATE_FOR_DEFICIENCY", () => {
  const errAssign = {
    message: "INVALID_HR_STATUS_FOR_ASSIGN: hr_status must be For Emploc",
    code: "P0001",
    details: { code: "INVALID_HR_STATUS_FOR_ASSIGN" },
  };
  assert.equal(parseHrEmplocError(errAssign).code, "INVALID_STATE_FOR_ASSIGN");

  const errDef = {
    message: "INVALID_STATE_FOR_DEFICIENCY: hr_status must be For Emploc",
    code: "P0001",
    details: { code: "INVALID_STATE_FOR_DEFICIENCY" },
  };
  assert.equal(parseHrEmplocError(errDef).code, "INVALID_STATE_FOR_DEFICIENCY");
});

test("parses EMPLOYEE_NO_FORMAT_INVALID and EMPLOYEE_NO_ALREADY_ASSIGNED", () => {
  const errFmt = {
    message: "EMPLOYEE_NO_FORMAT_INVALID: must be alphanumeric",
    code: "22023",
    details: { code: "EMPLOYEE_NO_FORMAT_INVALID" },
  };
  assert.equal(parseHrEmplocError(errFmt).code, "EMPLOYEE_NO_FORMAT_INVALID");

  const errDup = {
    message: "EMPLOYEE_NO_ALREADY_ASSIGNED: already in use",
    code: "23505",
    details: { code: "EMPLOYEE_NO_ALREADY_ASSIGNED" },
  };
  assert.equal(parseHrEmplocError(errDup).code, "EMPLOYEE_NO_ALREADY_ASSIGNED");
});

test("parses POSSIBLE_DUPLICATE_PERSON and MIDDLE_NAME_CONFIRM_REQUIRED", () => {
  const errDup = {
    message: "POSSIBLE_DUPLICATE_PERSON: identical person detected",
    code: "23505",
    details: { code: "POSSIBLE_DUPLICATE_PERSON", matched_name: "DOE, JOHN" },
  };
  const parsedDup = parseHrEmplocError(errDup);
  assert.equal(parsedDup.code, "POSSIBLE_DUPLICATE_PERSON");
  assert.equal(parsedDup.title, "Duplicate Candidate Detected");

  const errMid = {
    message: "MIDDLE_NAME_CONFIRM_REQUIRED: middle name mismatch",
    code: "23505",
    details: { code: "MIDDLE_NAME_CONFIRM_REQUIRED" },
  };
  const parsedMid = parseHrEmplocError(errMid);
  assert.equal(parsedMid.code, "MIDDLE_NAME_CONFIRM_REQUIRED");
  assert.equal(parsedMid.title, "Middle Name Mismatch Confirmation");
});

test("parses SLOT_UNAVAILABLE", () => {
  const err = {
    message: "SLOT_UNAVAILABLE: No slots available for this vacancy",
    code: "P0001",
    details: { code: "SLOT_UNAVAILABLE" },
  };
  const parsed = parseHrEmplocError(err);
  assert.equal(parsed.code, "SLOT_UNAVAILABLE");
  assert.equal(parsed.title, "Slot Unavailable");
});
