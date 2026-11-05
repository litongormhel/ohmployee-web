import test from "node:test";
import assert from "node:assert/strict";

import { calculateTargetDimensions } from "../image_compression.ts";
import { normalizeHrEmplocRemarks } from "../../queries/hr_emploc_normalizers.ts";
import { normalizeQueue } from "../../../components/hr-emploc/useHrEmplocSavedViews.ts";

test("Dimension Math: never upscale when image is smaller than maxDimension", () => {
  const result = calculateTargetDimensions(800, 600, 1600);
  assert.equal(result.width, 800);
  assert.equal(result.height, 600);
  assert.equal(result.scaled, false);

  const squareSmall = calculateTargetDimensions(1200, 1200, 1600);
  assert.equal(squareSmall.width, 1200);
  assert.equal(squareSmall.height, 1200);
  assert.equal(squareSmall.scaled, false);
});

test("Dimension Math: scales down landscape images maintaining aspect ratio", () => {
  // 3200x2400 (4:3) scaled to max 1600 -> 1600x1200
  const result = calculateTargetDimensions(3200, 2400, 1600);
  assert.equal(result.width, 1600);
  assert.equal(result.height, 1200);
  assert.equal(result.scaled, true);
});

test("Dimension Math: scales down portrait images maintaining aspect ratio", () => {
  // 1800x2400 (3:4) scaled to max 1600 -> 1200x1600
  const result = calculateTargetDimensions(1800, 2400, 1600);
  assert.equal(result.width, 1200);
  assert.equal(result.height, 1600);
  assert.equal(result.scaled, true);
});

test("Dimension Math: scales down square images to exact maxDimension", () => {
  const result = calculateTargetDimensions(3000, 3000, 1600);
  assert.equal(result.width, 1600);
  assert.equal(result.height, 1600);
  assert.equal(result.scaled, true);
});

test("Legacy Saved-View Mapping: maps legacy queue identifiers correctly", () => {
  // Legacy 'ready' and 'complete' map to 'deployed'
  assert.equal(normalizeQueue("ready"), "deployed");
  assert.equal(normalizeQueue("complete"), "deployed");

  // Legacy 'deficiency' maps to 'correction'
  assert.equal(normalizeQueue("deficiency"), "correction");

  // Standard queues pass through untouched
  assert.equal(normalizeQueue("pending"), "pending");
  assert.equal(normalizeQueue("for_emploc"), "for_emploc");
  assert.equal(normalizeQueue("correction"), "correction");
  assert.equal(normalizeQueue("review"), "review");
  assert.equal(normalizeQueue("deployed"), "deployed");
  assert.equal(normalizeQueue("deletion_pending"), "deletion_pending");
  assert.equal(normalizeQueue("all"), "all");

  // Unknown fallback to 'deployed'
  assert.equal(normalizeQueue("unknown_queue"), "deployed");
  assert.equal(normalizeQueue(null), "deployed");
  assert.equal(normalizeQueue(undefined), "deployed");
});

test("Remarks Precedence: ops_remarks takes highest priority", () => {
  const row1 = {
    ops_remarks: "Ops note",
    remarks: "General remark",
    hr_remarks: "HR note",
    notes: "Review note",
  };
  assert.equal(normalizeHrEmplocRemarks(row1), "Ops note");

  const row2 = {
    ops_remarks: "   ",
    remarks: "General remark",
    hr_remarks: "HR note",
    notes: "Review note",
  };
  assert.equal(normalizeHrEmplocRemarks(row2), "General remark");

  const row3 = {
    ops_remarks: null,
    remarks: null,
    hr_remarks: "HR note",
    notes: "Review note",
  };
  assert.equal(normalizeHrEmplocRemarks(row3), "HR note");

  const row4 = {
    ops_remarks: "",
    remarks: "",
    hr_remarks: "",
    notes: "Review note",
  };
  assert.equal(normalizeHrEmplocRemarks(row4), "Review note");
});
