import test from "node:test";
import assert from "node:assert/strict";

/**
 * ADR-003: Unified Roving Headcount Requisition with Atomic Store Provisioning
 * Unit Test Suite
 */

function validateOperationalJustification(reason) {
  const trimmed = (reason || "").trim();
  if (trimmed.length < 20) {
    return {
      valid: false,
      error: "Operational justification is mandatory (minimum 20 characters).",
    };
  }
  return { valid: true };
}

function validateRovingStores(stores) {
  if (!Array.isArray(stores) || stores.length < 2) {
    return {
      valid: false,
      error: "Roving workforce requires selecting at least 2 stores.",
    };
  }
  if (stores.length > 20) {
    return {
      valid: false,
      error: "A maximum of 20 stores can be selected for roving deployment.",
    };
  }

  // Check island groups
  const islandGroups = new Set();
  for (const s of stores) {
    if (s.island_group) {
      islandGroups.add(s.island_group);
    }
  }

  if (islandGroups.size > 1) {
    return {
      valid: false,
      error: `Coverage Group cannot span multiple island groups (${Array.from(islandGroups).join(" + ")}).`,
    };
  }

  // Check duplicate store names
  const seenNames = new Set();
  for (const s of stores) {
    const key = (s.store_name || "").trim().toLowerCase();
    if (!key) {
      return { valid: false, error: "Store name cannot be empty." };
    }
    if (seenNames.has(key)) {
      return { valid: false, error: `Duplicate store name: ${s.store_name}` };
    }
    seenNames.add(key);
  }

  return { valid: true, islandGroup: Array.from(islandGroups)[0] || null };
}

function buildHeadcountPayload({
  accountId,
  positionId,
  workforceType,
  requestType,
  headcountNeeded,
  reason,
  stores,
  vacantDate,
  targetFillDate,
  urgency,
}) {
  const justificationCheck = validateOperationalJustification(reason);
  if (!justificationCheck.valid) {
    throw new Error(justificationCheck.error);
  }

  const payload = {
    account_id: accountId,
    position_id: positionId,
    workforce_type: workforceType,
    employment_type: workforceType === "roving" ? "Roving" : "Stationary",
    request_type: requestType,
    headcount_needed: headcountNeeded,
    reason: reason.trim(),
  };

  if (requestType !== "HC Reduction") {
    payload.vacant_date = vacantDate || null;
    payload.target_fill_date = targetFillDate || null;
    payload.urgency = urgency || "Medium";
  }

  if (workforceType === "roving") {
    const storeValidation = validateRovingStores(stores);
    if (!storeValidation.valid) {
      throw new Error(storeValidation.error);
    }

    payload.stores = stores.map((s) => {
      if (s.is_new_store) {
        return {
          is_new_store: true,
          store_name: s.store_name,
          area_province: s.area_province || s.province || "",
          area_city: s.area_city || "",
          island_group: s.island_group || undefined,
        };
      }
      return {
        is_new_store: false,
        store_id: s.id,
        store_name: s.store_name,
        area_province: s.area_province || s.province || "",
        area_city: s.area_city || "",
        island_group: s.island_group || undefined,
      };
    });

    payload.store_ids = stores
      .filter((s) => !s.is_new_store)
      .map((s) => s.id);
  }

  return payload;
}

test("ADR-003: Operational Justification mandatory minimum 20 characters", () => {
  assert.equal(validateOperationalJustification("").valid, false);
  assert.equal(validateOperationalJustification("Short note").valid, false);
  assert.equal(validateOperationalJustification("   Only 14 chars  ").valid, false);
  assert.equal(
    validateOperationalJustification("Valid business demand for expansion").valid,
    true
  );
  assert.equal(
    validateOperationalJustification("Emergency replacement for upcoming store opening").valid,
    true
  );
});

test("ADR-003: Roving store count boundaries (2 to 20 stores)", () => {
  const store1 = { id: "s1", store_name: "Store 1", island_group: "Luzon" };
  const store2 = { id: "s2", store_name: "Store 2", island_group: "Luzon" };

  assert.equal(validateRovingStores([]).valid, false);
  assert.equal(validateRovingStores([store1]).valid, false);
  assert.equal(validateRovingStores([store1, store2]).valid, true);

  const twentyOneStores = Array.from({ length: 21 }, (_, i) => ({
    id: `s-${i}`,
    store_name: `Store ${i}`,
    island_group: "Luzon",
  }));
  assert.equal(validateRovingStores(twentyOneStores).valid, false);

  const twentyStores = Array.from({ length: 20 }, (_, i) => ({
    id: `s-${i}`,
    store_name: `Store ${i}`,
    island_group: "Luzon",
  }));
  assert.equal(validateRovingStores(twentyStores).valid, true);
});

test("ADR-003: Multi-city roving within same island group is permitted", () => {
  const stores = [
    { id: "s1", store_name: "SM Megamall", area_city: "Mandaluyong", island_group: "Luzon" },
    { id: "s2", store_name: "SM North EDSA", area_city: "Quezon City", island_group: "Luzon" },
    {
      id: "s3-new",
      store_name: "Savemore Antipolo",
      area_city: "Antipolo",
      area_province: "Rizal",
      island_group: "Luzon",
      is_new_store: true,
    },
  ];

  const validation = validateRovingStores(stores);
  assert.equal(validation.valid, true);
  assert.equal(validation.islandGroup, "Luzon");
});

test("ADR-003: Island group span violation hard block", () => {
  const stores = [
    { id: "s1", store_name: "SM Megamall", area_city: "Mandaluyong", island_group: "Luzon" },
    { id: "s2", store_name: "SM City Cebu", area_city: "Cebu City", island_group: "Visayas" },
  ];

  const validation = validateRovingStores(stores);
  assert.equal(validation.valid, false);
  assert.match(validation.error, /multiple island groups/i);
});

test("ADR-003: Duplicate store name rejection within roving cluster", () => {
  const stores = [
    { id: "s1", store_name: "Puregold Taguig", island_group: "Luzon" },
    { id: "s2", store_name: "puregold taguig", island_group: "Luzon", is_new_store: true },
  ];

  const validation = validateRovingStores(stores);
  assert.equal(validation.valid, false);
  assert.match(validation.error, /duplicate store name/i);
});

test("ADR-003: Polymorphic payload formatting with new and existing stores", () => {
  const stores = [
    {
      id: "uuid-1",
      store_name: "SM Makati",
      area_province: "Metro Manila",
      area_city: "Makati",
      island_group: "Luzon",
      is_new_store: false,
    },
    {
      id: "temp-2",
      store_name: "Robinsons Cainta",
      area_province: "Rizal",
      area_city: "Cainta",
      island_group: "Luzon",
      is_new_store: true,
    },
  ];

  const payload = buildHeadcountPayload({
    accountId: "acct-uuid",
    positionId: "pos-uuid",
    workforceType: "roving",
    requestType: "Additional Headcount",
    headcountNeeded: 1,
    reason: "Opening new branch and cluster expansion covering Cainta & Makati",
    stores,
    vacantDate: "2026-12-01",
    targetFillDate: "2026-12-15",
    urgency: "Medium",
  });

  assert.equal(payload.workforce_type, "roving");
  assert.equal(payload.employment_type, "Roving");
  assert.equal(payload.headcount_needed, 1);
  assert.equal(payload.stores.length, 2);

  // Existing store mapped correctly
  assert.equal(payload.stores[0].is_new_store, false);
  assert.equal(payload.stores[0].store_id, "uuid-1");
  assert.equal(payload.stores[0].store_name, "SM Makati");

  // New store mapped correctly
  assert.equal(payload.stores[1].is_new_store, true);
  assert.equal(payload.stores[1].store_id, undefined);
  assert.equal(payload.stores[1].store_name, "Robinsons Cainta");
  assert.equal(payload.stores[1].area_city, "Cainta");
  assert.equal(payload.stores[1].area_province, "Rizal");

  // Backward-compatible store_ids array carries only existing store UUIDs
  assert.deepEqual(payload.store_ids, ["uuid-1"]);
});
