import test from "node:test";
import assert from "node:assert/strict";
import {
  sanitizeNotificationDeepLink,
  isValidAppRouterRoute,
  extractEntityCodeFromItem,
} from "../../notifications/deep_links.ts";

test("R2.1: /headcount-requests/* maps to /approvals?tab=headcount", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/headcount-requests/c545bc6c-7e82-411a-85b4-d53c394d6e90",
  });
  assert.equal(result1?.route, "/approvals?tab=headcount");
  assert.equal(result1?.label, "View in Approvals →");

  const result2 = sanitizeNotificationDeepLink({
    reference_type: "headcount_request",
    deep_link_route: "/legacy/hc/123",
  });
  assert.equal(result2?.route, "/approvals?tab=headcount");
});

test("R2.2: /vacancies/*/closure-request/* maps to /approvals?tab=vacancy_closures", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/vacancies/VCYG1_0001/closure-request/a894-uuid",
  });
  assert.equal(result1?.route, "/approvals?tab=vacancy_closures");
  assert.equal(result1?.label, "View in Approvals →");

  const result2 = sanitizeNotificationDeepLink({
    deep_link_route: "/vacancy-closure-requests/a894-uuid",
  });
  assert.equal(result2?.route, "/approvals?tab=vacancy_closures");
});

test("R2.3: /deactivation-requests/* maps to /approvals?tab=deactivations", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/deactivation-requests/uuid-1234",
  });
  assert.equal(result1?.route, "/approvals?tab=deactivations");
  assert.equal(result1?.label, "View in Approvals →");

  const result2 = sanitizeNotificationDeepLink({
    deep_link_route: "/deactivation/my-requests",
  });
  assert.equal(result2?.route, "/approvals?tab=deactivations");
});

test("R2.4: /hr-emploc/deletion-requests/* maps to /approvals?tab=hr_emploc_deletions", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/hr-emploc/deletion-requests/uuid-1234",
  });
  assert.equal(result1?.route, "/approvals?tab=hr_emploc_deletions");
  assert.equal(result1?.label, "View in Approvals →");

  const result2 = sanitizeNotificationDeepLink({
    deep_link_route: "/hr-emploc-deletion-requests/uuid-1234",
  });
  assert.equal(result2?.route, "/approvals?tab=hr_emploc_deletions");
});

test("R2.5: /requests/applicant-movement/* maps to /approvals?tab=applicant_movements", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/requests/applicant-movement/uuid-1234",
  });
  assert.equal(result1?.route, "/approvals?tab=applicant_movements");
  assert.equal(result1?.label, "View in Approvals →");

  const result2 = sanitizeNotificationDeepLink({
    deep_link_route: "/applicant-movement/uuid-1234",
  });
  assert.equal(result2?.route, "/approvals?tab=applicant_movements");
});

test("R2.6: /account-group-transfers/* maps to /approvals?tab=account_group_transfers", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/account-group-transfers/uuid-1234",
  });
  assert.equal(result1?.route, "/approvals?tab=account_group_transfers");
  assert.equal(result1?.label, "View in Approvals →");

  const result2 = sanitizeNotificationDeepLink({
    reference_type: "account_group_transfer_request",
    deep_link_route: "/account_transfer/123",
  });
  assert.equal(result2?.route, "/approvals?tab=account_group_transfers");
});

test("R2.7: /workforce/requests/* and /workforce/pool-requests/* map to /approvals?tab=relievers", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/workforce/requests/uuid-1234",
  });
  assert.equal(result1?.route, "/approvals?tab=relievers");
  assert.equal(result1?.label, "View in Approvals →");

  const result2 = sanitizeNotificationDeepLink({
    deep_link_route: "/workforce/pool-requests/uuid-1234",
  });
  assert.equal(result2?.route, "/approvals?tab=relievers");
});

test("R2.8: /vacancies/:vcode extracts code and maps to /vacancy?q=:vcode with URL encoding", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/vacancies/VCYG1_0001",
  });
  assert.equal(result1?.route, "/vacancy?q=VCYG1_0001");
  assert.equal(result1?.label, "Inspect Vacancy →");

  const result2 = sanitizeNotificationDeepLink({
    deep_link_route: "/vacancies/CPSAJV31",
  });
  assert.equal(result2?.route, "/vacancy?q=CPSAJV31");

  // Encodes spaces / special characters
  const result3 = sanitizeNotificationDeepLink({
    deep_link_route: "/vacancies/FO 001",
  });
  assert.equal(result3?.route, "/vacancy?q=FO%20001");

  // Flat /vacancies maps to /vacancy without query param
  const result4 = sanitizeNotificationDeepLink({
    deep_link_route: "/vacancies",
  });
  assert.equal(result4?.route, "/vacancy");

  const result5 = sanitizeNotificationDeepLink({
    deep_link_route: "/vacancies/",
  });
  assert.equal(result5?.route, "/vacancy");
});

test("R2.9: /transfers/* maps to /plantilla", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/transfers/uuid-1234",
  });
  assert.equal(result1?.route, "/plantilla");
  assert.equal(result1?.label, "Inspect Plantilla →");

  const result2 = sanitizeNotificationDeepLink({
    reference_type: "transfer",
    deep_link_route: "/transfer/123",
  });
  assert.equal(result2?.route, "/plantilla");
});

test("R2.10: /account-requests/* maps to /users", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/account-requests/uuid-1234",
  });
  assert.equal(result1?.route, "/users");
  assert.equal(result1?.label, "Review User Requests →");

  const result2 = sanitizeNotificationDeepLink({
    reference_type: "account_request",
    deep_link_route: "/account-requests",
  });
  assert.equal(result2?.route, "/users");
});

test("R2.11: /access-requests/* maps to /more", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/access-requests/uuid-1234",
  });
  assert.equal(result1?.route, "/more");
  assert.equal(result1?.label, "View in More →");

  const result2 = sanitizeNotificationDeepLink({
    reference_type: "temp_permission_override",
    deep_link_route: "/access-request/123",
  });
  assert.equal(result2?.route, "/more");
});

test("R2.12: /hr-emploc/:id/correction maps to /hr-emploc", () => {
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/hr-emploc/uuid-1234/correction",
  });
  assert.equal(result1?.route, "/hr-emploc");
  assert.equal(result1?.label, "Inspect Emploc →");

  const result2 = sanitizeNotificationDeepLink({
    reference_type: "hr_emploc_correction",
    deep_link_route: "/hr-emploc/uuid-1234/corrections",
  });
  assert.equal(result2?.route, "/hr-emploc");
});

test("R2.13: Safe fallback - unmapped routes never pass through or 404", () => {
  // Unmapped route with approvals fallback module
  const result1 = sanitizeNotificationDeepLink(
    { deep_link_route: "/legacy/broken/route/123" },
    "approvals"
  );
  assert.equal(result1?.route, "/approvals");
  assert.equal(result1?.label, "View in Approvals →");

  // Unmapped route with vacancy fallback module
  const result2 = sanitizeNotificationDeepLink(
    { deep_link_route: "/totally-unknown-path" },
    "vacancy"
  );
  assert.equal(result2?.route, "/vacancy");
  assert.equal(result2?.label, "Inspect Vacancy →");

  // Unmapped route with plantilla fallback module
  const result2b = sanitizeNotificationDeepLink(
    { deep_link_route: "/random-unmapped-link" },
    "plantilla"
  );
  assert.equal(result2b?.route, "/plantilla");

  // Unmapped route with hr_emploc fallback module
  const result2c = sanitizeNotificationDeepLink(
    { deep_link_route: "/random-unmapped-link" },
    "hr_emploc"
  );
  assert.equal(result2c?.route, "/hr-emploc");

  // Unmapped route with cencom fallback module
  const result2d = sanitizeNotificationDeepLink(
    { deep_link_route: "/random-unmapped-link" },
    "cencom"
  );
  assert.equal(result2d?.route, "/cencom");

  // Unmapped route with system fallback module
  const result2e = sanitizeNotificationDeepLink(
    { deep_link_route: "/random-unmapped-link" },
    "system"
  );
  assert.equal(result2e?.route, "/notifications");

  // Unmapped route with no module returns null (never passes through raw broken route!)
  const result3 = sanitizeNotificationDeepLink({
    deep_link_route: "/unmapped-broken-link/123",
  });
  assert.equal(result3, null);

  // Missing or empty routes return null
  assert.equal(sanitizeNotificationDeepLink({ deep_link_route: "" }), null);
  assert.equal(sanitizeNotificationDeepLink({ deep_link_route: null }), null);
  assert.equal(sanitizeNotificationDeepLink({}), null);
});

test("R2.14: Valid Next.js routes and query parameters are preserved without disruption", () => {
  // Valid App Router path with query param
  const result1 = sanitizeNotificationDeepLink({
    deep_link_route: "/approvals?tab=coverage&request_id=123",
  });
  assert.equal(result1?.route, "/approvals?tab=coverage&request_id=123");
  assert.equal(result1?.label, "View in Approvals →");

  // Valid dynamic route /plantilla/[id]
  const result2 = sanitizeNotificationDeepLink({
    deep_link_route: "/plantilla/c545bc6c-7e82-411a-85b4-d53c394d6e90",
  });
  assert.equal(result2?.route, "/plantilla/c545bc6c-7e82-411a-85b4-d53c394d6e90");
  assert.equal(result2?.label, "Inspect Plantilla →");

  // Valid import wizard route
  const result3 = sanitizeNotificationDeepLink({
    deep_link_route: "/hr-emploc/import",
  });
  assert.equal(result3?.route, "/hr-emploc/import");
  assert.equal(result3?.label, "Inspect Import Batch →");

  // Other valid top-level pages
  assert.equal(sanitizeNotificationDeepLink({ deep_link_route: "/users" })?.route, "/users");
  assert.equal(sanitizeNotificationDeepLink({ deep_link_route: "/more" })?.route, "/more");
  assert.equal(sanitizeNotificationDeepLink({ deep_link_route: "/dashboard" })?.route, "/dashboard");
});

test("R2.15: Helper extractEntityCodeFromItem and isValidAppRouterRoute", () => {
  assert.equal(isValidAppRouterRoute("/approvals"), true);
  assert.equal(isValidAppRouterRoute("/approvals?tab=headcount"), true);
  assert.equal(isValidAppRouterRoute("/plantilla/c545bc6c-7e82-411a-85b4-d53c394d6e90"), true);
  assert.equal(isValidAppRouterRoute("/headcount-requests/123"), false);
  assert.equal(isValidAppRouterRoute("/not-a-real-page"), false);
  assert.equal(isValidAppRouterRoute(""), false);

  assert.equal(
    extractEntityCodeFromItem({
      data: { vcode: "VCYG1_0001" },
    }),
    "VCYG1_0001"
  );
  assert.equal(
    extractEntityCodeFromItem({
      title: "New Request",
      message: "Please inspect AMR-1002 in approvals",
    }),
    "AMR-1002"
  );
});
