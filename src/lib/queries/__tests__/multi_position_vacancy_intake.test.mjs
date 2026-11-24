import test from "node:test";
import assert from "node:assert/strict";

/**
 * ADR-001 / ADR-002: Multi-Position Store Vacancy Intake & Slot Disambiguation
 * Unit Test Suite
 */

function computeRequirementCapacity(hcNeeded, hcFilled, pipelineCount = 0) {
  const needed = Number(hcNeeded) || 1;
  const filled = Number(hcFilled) || 0;
  const pipeline = Number(pipelineCount) || 0;
  const availableSlots = Math.max(0, needed - filled - pipeline);
  const isFull = availableSlots <= 0;
  return { availableSlots, isFull };
}

function resolveApplicantIntakeSelection({
  requirements,
  selectedRequirementId,
  isSubmitted,
}) {
  if (!requirements || requirements.length === 0) {
    // Legacy single position without normalized requirements
    return {
      autoSelectedId: null,
      isValid: true,
      requiresSelection: false,
      error: null,
    };
  }

  if (requirements.length === 1) {
    // Exactly 1 position (e.g. Merchandiser only) - zero friction auto-select if open
    const single = requirements[0];
    const { isFull } = computeRequirementCapacity(
      single.hcNeeded,
      single.hcFilled,
      single.pipelineCount
    );
    return {
      autoSelectedId: isFull ? null : single.id,
      isValid: !isFull,
      requiresSelection: false,
      error: isFull ? "Position is already fully allocated." : null,
    };
  }

  // 2+ positions (e.g. Merchandiser and Salesman under 1 Store VCode)
  const chosen = requirements.find((r) => r.id === selectedRequirementId);
  if (!chosen) {
    return {
      autoSelectedId: null,
      isValid: false,
      requiresSelection: true,
      error: isSubmitted
        ? "Please select which position requirement this candidate fills."
        : null,
    };
  }

  const { isFull } = computeRequirementCapacity(
    chosen.hcNeeded,
    chosen.hcFilled,
    chosen.pipelineCount
  );
  if (isFull) {
    return {
      autoSelectedId: chosen.id,
      isValid: false,
      requiresSelection: true,
      error: `Position "${chosen.positionName}" is already full.`,
    };
  }

  return {
    autoSelectedId: chosen.id,
    isValid: true,
    requiresSelection: true,
    error: null,
  };
}

function resolveCandidateDisplayPosition({
  vacancyRequirementId,
  requirements,
  storeDefaultPosition,
}) {
  if (vacancyRequirementId && Array.isArray(requirements)) {
    const matched = requirements.find((r) => r.id === vacancyRequirementId);
    if (matched?.positionName) {
      return matched.positionName;
    }
  }
  return storeDefaultPosition || "—";
}

test("Capacity: accurately derives available slots and fullness per position including pipeline", () => {
  // 1/3 Hired requisition capacity progression:
  // 1 hired, needed 3:
  // When pipeline = 0 -> Avail = 2
  const zeroPipe = computeRequirementCapacity(3, 1, 0);
  assert.equal(zeroPipe.availableSlots, 2);
  assert.equal(zeroPipe.isFull, false);

  // When 1 is added as applicant in pipeline -> Avail = 1
  const onePipe = computeRequirementCapacity(3, 1, 1);
  assert.equal(onePipe.availableSlots, 1);
  assert.equal(onePipe.isFull, false);

  // When 2 are in pipeline -> Avail = 0
  const twoPipe = computeRequirementCapacity(3, 1, 2);
  assert.equal(twoPipe.availableSlots, 0);
  assert.equal(twoPipe.isFull, true);

  // Position with needed = 1:
  // 0 hired, 0 pipeline -> Avail = 1
  const openPos = computeRequirementCapacity(1, 0, 0);
  assert.equal(openPos.availableSlots, 1);
  assert.equal(openPos.isFull, false);

  // 0 hired, 1 in pipeline (e.g. Operations Manager) -> Avail = 0, isFull = true
  const pipePos = computeRequirementCapacity(1, 0, 1);
  assert.equal(pipePos.availableSlots, 0);
  assert.equal(pipePos.isFull, true);

  // Backout reopening: applicant backs out -> pipeline drops back to 0 -> Avail = 1, isFull = false
  const backoutReopenedPos = computeRequirementCapacity(1, 0, 0);
  assert.equal(backoutReopenedPos.availableSlots, 1);
  assert.equal(backoutReopenedPos.isFull, false);
});

test("Single-Position Store: auto-assigns requirement ID with zero user friction", () => {
  const requirements = [
    { id: "req-merch-01", positionName: "Merchandiser", hcNeeded: 1, hcFilled: 0, pipelineCount: 0 },
  ];

  const result = resolveApplicantIntakeSelection({
    requirements,
    selectedRequirementId: null,
    isSubmitted: true,
  });

  assert.equal(result.requiresSelection, false);
  assert.equal(result.autoSelectedId, "req-merch-01");
  assert.equal(result.isValid, true);
  assert.equal(result.error, null);
});

test("Single-Position Store: blocks auto-assign if position is already occupied in pipeline", () => {
  const requirements = [
    { id: "req-merch-01", positionName: "Merchandiser", hcNeeded: 1, hcFilled: 0, pipelineCount: 1 },
  ];

  const result = resolveApplicantIntakeSelection({
    requirements,
    selectedRequirementId: null,
    isSubmitted: true,
  });

  assert.equal(result.requiresSelection, false);
  assert.equal(result.autoSelectedId, null);
  assert.equal(result.isValid, false);
  assert.equal(result.error, "Position is already fully allocated.");
});

test("Multi-Position Store: blocks submission when position is unselected", () => {
  const requirements = [
    { id: "req-merch-01", positionName: "Merchandiser", hcNeeded: 1, hcFilled: 0, pipelineCount: 0 },
    { id: "req-sales-02", positionName: "Salesman", hcNeeded: 1, hcFilled: 0, pipelineCount: 0 },
  ];

  const unsubmitted = resolveApplicantIntakeSelection({
    requirements,
    selectedRequirementId: null,
    isSubmitted: false,
  });
  assert.equal(unsubmitted.requiresSelection, true);
  assert.equal(unsubmitted.isValid, false);
  assert.equal(unsubmitted.error, null);

  const submitted = resolveApplicantIntakeSelection({
    requirements,
    selectedRequirementId: null,
    isSubmitted: true,
  });
  assert.equal(submitted.requiresSelection, true);
  assert.equal(submitted.isValid, false);
  assert.equal(
    submitted.error,
    "Please select which position requirement this candidate fills."
  );
});

test("Multi-Position Store: accepts valid selection of non-full position", () => {
  const requirements = [
    { id: "req-merch-01", positionName: "Merchandiser", hcNeeded: 1, hcFilled: 0, pipelineCount: 0 },
    { id: "req-sales-02", positionName: "Salesman", hcNeeded: 1, hcFilled: 0, pipelineCount: 0 },
  ];

  const selectSalesman = resolveApplicantIntakeSelection({
    requirements,
    selectedRequirementId: "req-sales-02",
    isSubmitted: true,
  });

  assert.equal(selectSalesman.isValid, true);
  assert.equal(selectSalesman.autoSelectedId, "req-sales-02");
  assert.equal(selectSalesman.error, null);
});

test("Multi-Position Store: rejects selection of a position filled by pipeline applicant", () => {
  const requirements = [
    { id: "req-om-01", positionName: "Operations Manager", hcNeeded: 1, hcFilled: 0, pipelineCount: 1 }, // FULL due to active applicant
    { id: "req-crew-02", positionName: "Service Crew", hcNeeded: 1, hcFilled: 0, pipelineCount: 0 }, // OPEN
  ];

  const selectFullOm = resolveApplicantIntakeSelection({
    requirements,
    selectedRequirementId: "req-om-01",
    isSubmitted: true,
  });

  assert.equal(selectFullOm.isValid, false);
  assert.equal(selectFullOm.error, 'Position "Operations Manager" is already full.');

  const selectOpenCrew = resolveApplicantIntakeSelection({
    requirements,
    selectedRequirementId: "req-crew-02",
    isSubmitted: true,
  });

  assert.equal(selectOpenCrew.isValid, true);
  assert.equal(selectOpenCrew.error, null);
});

test("Pipeline Disambiguation: candidate displays specific tagged position", () => {
  const requirements = [
    { id: "req-merch-01", positionName: "Merchandiser", hcNeeded: 1, hcFilled: 0 },
    { id: "req-sales-02", positionName: "Salesman", hcNeeded: 1, hcFilled: 0 },
  ];

  const posCandidate1 = resolveCandidateDisplayPosition({
    vacancyRequirementId: "req-merch-01",
    requirements,
    storeDefaultPosition: "Store Personnel",
  });
  assert.equal(posCandidate1, "Merchandiser");

  const posCandidate2 = resolveCandidateDisplayPosition({
    vacancyRequirementId: "req-sales-02",
    requirements,
    storeDefaultPosition: "Store Personnel",
  });
  assert.equal(posCandidate2, "Salesman");

  const posLegacy = resolveCandidateDisplayPosition({
    vacancyRequirementId: null,
    requirements,
    storeDefaultPosition: "Store Personnel",
  });
  assert.equal(posLegacy, "Store Personnel");
});
