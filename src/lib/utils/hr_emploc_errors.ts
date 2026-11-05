/**
 * Standardized Error Mapper for HR Emploc
 * Keyed by:
 *  1. DETAIL code (from Supabase/PostgreSQL detail json {"code": "..."})
 *  2. Message token prefix (e.g. "REQUIREMENTS_DOCS_MISSING:")
 *  3. SQLSTATE fallback (e.g. 22023, 23505, 42501, P0001, P0002)
 */

export interface ParsedHrEmplocError {
  code: string;
  title: string;
  message: string;
  sqlstate?: string;
  details?: Record<string, unknown>;
  rawMessage: string;
}

export interface EmplocErrorInput {
  message?: string;
  details?: string | Record<string, unknown> | null;
  code?: string; // SQLSTATE or Postgres error code
  hint?: string;
  [key: string]: unknown;
}

export function parseHrEmplocError(err: unknown): ParsedHrEmplocError {
  if (!err) {
    return {
      code: "UNKNOWN_ERROR",
      title: "Unknown Error",
      message: "An unexpected error occurred. Please try again.",
      rawMessage: "",
    };
  }

  const raw = typeof err === "object" ? (err as EmplocErrorInput) : { message: String(err) };
  const rawMessage = raw.message || String(err);
  const sqlstate = raw.code || undefined;

  // 1. Try extracting structured detail object
  let parsedDetail: Record<string, unknown> | null = null;
  if (raw.details) {
    if (typeof raw.details === "object") {
      parsedDetail = raw.details;
    } else if (typeof raw.details === "string") {
      try {
        parsedDetail = JSON.parse(raw.details);
      } catch {
        // Not JSON string
      }
    }
  }

  // 2. Identify error token code:
  // Priority A: parsedDetail.code
  // Priority B: message token prefix (e.g. "TOKEN_NAME: ...")
  let tokenCode = "";
  if (parsedDetail && typeof parsedDetail.code === "string") {
    tokenCode = parsedDetail.code;
  } else {
    const tokenMatch = rawMessage.match(/^([A-Z0-9_]{3,}):/);
    if (tokenMatch) {
      tokenCode = tokenMatch[1];
    }
  }

  // 3. Fallback to SQLSTATE if no token
  if (!tokenCode && sqlstate) {
    if (sqlstate === "42501") tokenCode = "FORBIDDEN_ROLE_OR_SCOPE";
    else if (sqlstate === "23505") tokenCode = "UNIQUE_VIOLATION";
    else if (sqlstate === "P0002") tokenCode = "RECORD_NOT_FOUND";
  }

  // 4. Map known tokens to friendly titles and messages
  switch (tokenCode) {
    case "REQUIREMENTS_DOCS_MISSING":
      return {
        code: tokenCode,
        title: "Requirements Missing",
        message: "At least one requirement document must be uploaded before moving this record to 'For Emploc'.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "DOC_INVALID_MIME_TYPE":
    case "INVALID_MIME_TYPE":
      return {
        code: "DOC_INVALID_MIME_TYPE",
        title: "Unsupported File Type",
        message: "Only PDF, JPEG, PNG, and WEBP files are allowed.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "DOC_FILE_TOO_LARGE":
    case "FILE_TOO_LARGE":
      return {
        code: "DOC_FILE_TOO_LARGE",
        title: "File Too Large",
        message: "Documents must not exceed 10 MB in file size.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "FORBIDDEN_ROLE_OR_SCOPE":
      return {
        code: tokenCode,
        title: "Permission Denied",
        message: "You do not have permission or are outside the store/account scope required for this action.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "FORBIDDEN_NOT_UPLOADER":
      return {
        code: tokenCode,
        title: "Cannot Delete Document",
        message: "You can only remove documents that you personally uploaded.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "INVALID_HR_STATUS_FOR_ASSIGN":
    case "INVALID_STATE_FOR_ASSIGN":
      return {
        code: "INVALID_STATE_FOR_ASSIGN",
        title: "Invalid Status for Assignment",
        message: "Employee ID can only be assigned when the record is in 'For Emploc' (or via Super Admin override).",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "INVALID_HR_STATUS_FOR_DEFICIENCY":
    case "INVALID_STATE_FOR_DEFICIENCY":
      return {
        code: "INVALID_STATE_FOR_DEFICIENCY",
        title: "Invalid Status for Deficiency",
        message: "Deficiencies can only be tagged on records that are currently in 'For Emploc'.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "INVALID_STAGE_FOR_UPLOAD":
      return {
        code: tokenCode,
        title: "Upload Not Allowed",
        message: "Documents can only be uploaded while the record is in 'Pending' or 'For Correction'.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "INVALID_STAGE_FOR_REMOVE":
      return {
        code: tokenCode,
        title: "Removal Not Allowed",
        message: "Documents can only be removed while the record is in 'Pending' or 'For Correction'.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "ACTION_LOCKED_PENDING_DELETION":
      return {
        code: tokenCode,
        title: "Action Locked",
        message: "An active deletion request exists for this record. Actions are locked until the deletion request is resolved.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "EMPLOYEE_NO_FORMAT_INVALID":
      return {
        code: tokenCode,
        title: "Invalid Employee ID Format",
        message: (parsedDetail?.employee_no
          ? `Employee ID "${parsedDetail.employee_no}" is invalid.`
          : "Invalid Employee ID format.") + " Expected YYYY-XXXXX (e.g. 2026-00001) or standard numeric format.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "EMPLOYEE_NO_ALREADY_ASSIGNED":
      return {
        code: tokenCode,
        title: "Employee ID Already Assigned",
        message: parsedDetail?.registered_to
          ? `Employee number ${parsedDetail.employee_no || ""} is already permanently assigned to ${parsedDetail.registered_to}.`
          : "This employee number is already assigned to another individual.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "EMPLOYEE_ALREADY_ACTIVE":
      return {
        code: tokenCode,
        title: "Applicant Already Active",
        message: parsedDetail?.person
          ? `${parsedDetail.person} already has an active placement or Plantilla record with number ${parsedDetail.employee_no || ""}.`
          : "This person is already actively deployed in another placement.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "REHIRE_CONFIRM_REQUIRED":
      return {
        code: tokenCode,
        title: "Rehire Confirmation Required",
        message: parsedDetail?.display_name
          ? `${parsedDetail.display_name} previously owned employee number ${parsedDetail.employee_no || ""}. Confirm rehire reuse with a valid reason.`
          : "This applicant previously owned this employee number. Confirmation with reason is required.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "POSSIBLE_DUPLICATE_PERSON":
      return {
        code: tokenCode,
        title: "Duplicate Candidate Detected",
        message: "An active Plantilla record matches this applicant's name and birthdate. Confirmation with reason is required.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "MIDDLE_NAME_CONFIRM_REQUIRED":
      return {
        code: tokenCode,
        title: "Middle Name Mismatch Confirmation",
        message: "Applicant matches existing records on first and last name, but a middle name is missing on one record. Confirm reuse with reason.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "FIELD_REQUIRED_MISSING":
      return {
        code: tokenCode,
        title: "Required Information Missing",
        message: parsedDetail?.field
          ? `Field "${parsedDetail.field}" is required before proceeding.`
          : cleanRawMessage(rawMessage),
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "SLOT_UNAVAILABLE":
      return {
        code: tokenCode,
        title: "Slot Unavailable",
        message: "The requested vacancy slot is already occupied, inactive, or unavailable.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "RECORD_NOT_FOUND":
      return {
        code: tokenCode,
        title: "Record Not Found",
        message: "The requested Emploc record was not found or has been archived.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "DOCUMENT_NOT_FOUND":
      return {
        code: tokenCode,
        title: "Document Not Found",
        message: "The document attachment was not found or was already removed.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "REVERT_GRACE_EXPIRED":
      return {
        code: tokenCode,
        title: "Revert Window Expired",
        message: "This record was deployed more than 3 days ago and cannot be reverted.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "FORBIDDEN_REVERT":
      return {
        code: tokenCode,
        title: "Revert Not Permitted",
        message: "Only Encoder, Head Admin, or Super Admin may revert deployed records.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    case "INVALID_ACTION":
      return {
        code: tokenCode,
        title: "Invalid Review Action",
        message: "Review action must be either 'approve' or 'return'.",
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };

    default:
      return {
        code: tokenCode || "GENERAL_ERROR",
        title: "Operation Failed",
        message: cleanRawMessage(rawMessage),
        sqlstate,
        details: parsedDetail || undefined,
        rawMessage,
      };
  }
}

function cleanRawMessage(msg: string): string {
  // Strip PostgreSQL prefix like "ERROR: 22023: " or token prefix
  return msg
    .replace(/^ERROR:\s+[A-Z0-9]+:\s+/i, "")
    .replace(/^[A-Z0-9_]+:\s+/, "")
    .trim();
}
