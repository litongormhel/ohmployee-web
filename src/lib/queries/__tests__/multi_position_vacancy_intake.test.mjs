import test from "node:test";
import assert from "node:assert/strict";

/**
 * ADR-001 / ADR-002: Multi-Position Store Vacancy Intake & Slot Disambiguation
 * Unit Test Suite
 */

function computeRequirementCapacity(hcNeeded, hcFilled) {
  const needed = Number(hcNeeded) || 1;
  const filled = Number(hcFilled) || 0;
  const availableSlots = Math.max(0, needed - filled);
  const isFull = filled >= needed;
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
    // Exactly 1 position (e.g. Merchandiser only) - zero friction auto-select
    const single = requirements[0];
    const { isFull } = computeRequirementCapacity(single.hcNeeded, single.hcFilled);
    return {
      autoSelectedId: single.id,
      isValid: !isFull,
      requiresSelection: false,
      error: isFull ? "Position is already fully hired." : null,
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

  const { isFull } = computeRequirementCapacity(chosen.hcNeeded, chosen.hcFilled);
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

test("Capacity: accurately derives available slots and fullness per position", () => {
  const openCap = computeRequirementCapacity(2, 0);
  assert.equal(openCap.availableSlots, 2);
  assert.equal(openCap.isFull, false);

  const partialCap = computeRequirementCapacity(3, 2);
  assert.equal(partialCap.availableSlots, 1);
  assert.equal(partialCap.isFull, false);

  const fullCap = computeRequirementCapacity(1, 1);
  assert.equal(fullCap.availableSlots, 0);
  assert.equal(fullCap.isFull, true);

  const overfillCap = computeRequirementCapacity(1, 2);
  assert.equal(overfillCap.availableSlots, 0);
  assert.equal(overfillCap.isFull, true);
});

test("Single-Position Store: auto-assigns requirement ID with zero user friction", () => {
  const requirements = [
    { id: "req-merch-01", positionName: "Merchandiser", hcNeeded: 1, hcFilled: 0 },
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

test("Multi-Position Store: blocks submission when position is unselected", () => {
  const requirements = [
    { id: "req-merch-01", positionName: "Merchandiser", hcNeeded: 1, hcFilled: 0 },
    { id: "req-sales-02", positionName: "Salesman", hcNeeded: 1, hcFilled: 0 },
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
    { id: "req-merch-01", positionName: "Merchandiser", hcNeeded: 1, hcFilled: 0 },
    { id: "req-sales-02", positionName: "Salesman", hcNeeded: 1, hcFilled: 0 },
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

test("Multi-Position Store: rejects selection of a position that is already full", () => {
  const requirements = [
    { id: "req-merch-01", positionName: "Merchandiser", hcNeeded: 1, hcFilled: 1 }, // FULL
    { id: "req-sales-02", positionName: "Salesman", hcNeeded: 1, hcFilled: 0 }, // OPEN
  ];

  const selectFullMerch = resolveApplicantIntakeSelection({
    requirements,
    selectedRequirementId: "req-merch-01",
    isSubmitted: true,
  });

  assert.equal(selectFullMerch.isValid, false);
  assert.equal(selectFullMerch.error, 'Position "Merchandiser" is already full.');

  const selectOpenSales = resolveApplicantIntakeSelection({
    requirements,
    selectedRequirementId: "req-sales-02",
    isSubmitted: true,
  });

  assert.equal(selectOpenSales.isValid, true);
  assert.equal(selectOpenSales.error, null);
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
