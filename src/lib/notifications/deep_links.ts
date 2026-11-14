/**
 * src/lib/notifications/deep_links.ts
 *
 * Centralized, pure TypeScript utility for notification deep link parsing,
 * legacy/mobile route sanitization, query parameter preservation, and safe fallbacks.
 *
 * Zero dependencies on React or @/lib aliases to ensure 100% compatibility with
 * native Node.js ESM test runners (`node --test`).
 */

export interface ParsedDeepLink {
  route: string;
  referenceId?: string | null;
  requestId?: string | null;
  label: string;
}

export interface DeepLinkItemInput {
  deep_link_route?: string | null;
  reference_type?: string | null;
  reference_id?: string | null;
  title?: string;
  message?: string;
  data?: Record<string, unknown> | null;
}

export type FallbackModule =
  | "vacancy"
  | "plantilla"
  | "hr_emploc"
  | "approvals"
  | "cencom"
  | "system";

const VALID_TOP_LEVEL_PAGES = new Set([
  "/dashboard",
  "/approvals",
  "/vacancy",
  "/vacancies",
  "/plantilla",
  "/hr-emploc",
  "/cencom",
  "/team-directory",
  "/users",
  "/reports",
  "/settings",
  "/more",
  "/notifications",
]);

/**
 * Validates whether a given route points to a legitimate Next.js App Router page.
 */
export function isValidAppRouterRoute(route: string): boolean {
  if (!route || typeof route !== "string" || !route.startsWith("/")) return false;
  const pathname = route.split("?")[0].split("#")[0];

  if (VALID_TOP_LEVEL_PAGES.has(pathname)) return true;
  if (pathname === "/hr-emploc/import") return true;

  // Dedicated Employee Profile dynamic route: /plantilla/[id]
  if (/^\/plantilla\/[0-9a-fA-F-]+$/.test(pathname)) return true;

  return false;
}

/**
 * Extracts entity code from notification payload, reference_id, or text.
 */
export function extractEntityCodeFromItem(item: DeepLinkItemInput): string | null {
  const payload = (item.data || {}) as Record<string, unknown>;
  if (typeof payload.vcode === "string" && payload.vcode) return payload.vcode;
  if (typeof payload.entity_code === "string" && payload.entity_code) return payload.entity_code;
  if (typeof payload.request_number === "string" && payload.request_number) return payload.request_number;

  if (item.reference_id && !item.reference_id.includes("-") && item.reference_id.length <= 15) {
    return item.reference_id;
  }

  const text = `${item.title || ""} ${item.message || ""}`;
  const patterns = [
    /\b(VCYG\d+_\d+)\b/i,
    /\b([A-Z]{3,5}\d{2,})\b/,
    /\b(AMR-\d+)\b/i,
    /\b(AGT-\d{4}-\d+)\b/i,
    /\b(REQ-\d+)\b/i,
    /\b(BAT-[A-Z0-9]+)\b/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match?.[1]) {
      return match[1].toUpperCase();
    }
  }

  return null;
}

/**
 * Determines default label for a valid App Router route.
 */
function getLabelForRoute(route: string): string {
  if (route.includes("/approvals")) return "View in Approvals →";
  if (route.includes("/plantilla")) return "Inspect Plantilla →";
  if (route.includes("/vacancy") || route.includes("/vacancies")) return "Inspect Vacancy →";
  if (route.includes("/hr-emploc/import")) return "Inspect Import Batch →";
  if (route.includes("/hr-emploc")) return "Inspect Emploc →";
  if (route.includes("/users")) return "Review User Requests →";
  if (route.includes("/more")) return "View in More →";
  if (route.includes("/cencom")) return "View in CENCOM →";
  if (route.includes("/notifications")) return "View Notifications →";
  return "View Details →";
}

/**
 * Parses and sanitizes notification deep link routes, mapping legacy and mobile
 * URLs to valid Next.js App Router routes with query parameters.
 *
 * Implements a strict 3-tier fallback to permanently prevent 404 broken links:
 *   Tier 1: Valid App Router whitelist check (preserving valid query parameters).
 *   Tier 2: Module-based semantic fallback root for unmapped routes.
 *   Tier 3: Null termination so unmapped routes never render broken CTA links.
 */
export function sanitizeNotificationDeepLink(
  item: DeepLinkItemInput,
  fallbackModule?: FallbackModule
): ParsedDeepLink | null {
  const payload = (item.data || {}) as Record<string, unknown>;
  const rawRoute = (
    (payload.route as string) ||
    (payload.deep_link_route as string) ||
    item.deep_link_route ||
    ""
  ).trim();

  const refId = (payload.reference_id as string) || (payload.request_id as string) || item.reference_id || "";
  const reqId = (payload.request_id as string) || (payload.reference_id as string) || item.reference_id || "";
  const refType = (item.reference_type || "").toLowerCase();

  const normalizedRefId = refId ? String(refId) : null;
  const normalizedReqId = reqId ? String(reqId) : null;

  // Normalize route without trailing slash (unless root "/")
  const trimmedRoute = rawRoute.length > 1 ? rawRoute.replace(/\/+$/, "") : rawRoute;

  // 0A. Flat /vacancies normalization to /vacancy
  if (trimmedRoute === "/vacancies") {
    return {
      route: "/vacancy",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "Inspect Vacancy →",
    };
  }

  // 0B. If route is ALREADY a valid App Router route with query parameters
  // (e.g. /approvals?tab=coverage&request_id=123) or dynamic route /plantilla/[uuid],
  // preserve existing valid route and query parameters directly.
  if (
    trimmedRoute.includes("?") ||
    /^\/plantilla\/[0-9a-fA-F-]+$/i.test(trimmedRoute) ||
    trimmedRoute === "/hr-emploc/import"
  ) {
    if (isValidAppRouterRoute(trimmedRoute)) {
      return {
        route: trimmedRoute,
        referenceId: normalizedRefId,
        requestId: normalizedReqId,
        label: getLabelForRoute(trimmedRoute),
      };
    }
  }

  // 1. Vacancy Closures (Must be checked BEFORE generic /vacancies routes)
  // Backend patterns: /vacancies/:vcode/closure-request/:id or /vacancy-closure-requests/:id
  if (
    refType === "vacancy_closure" ||
    refType === "vacancy_closure_request" ||
    refType === "closure_request" ||
    /^\/vacancies\/[^\/]+\/closure-request(?:\/.*)?$/i.test(trimmedRoute) ||
    /^\/vacancy-closure-requests?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("closure-request") ||
    trimmedRoute.includes("vacancy_closure")
  ) {
    return {
      route: "/approvals?tab=vacancy_closures",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in Approvals →",
    };
  }

  // 2. Headcount Requests
  // Backend patterns: /headcount-requests/:id
  if (
    refType === "headcount_request" ||
    /^\/headcount-requests?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("headcount-request") ||
    trimmedRoute.includes("headcount")
  ) {
    return {
      route: "/approvals?tab=headcount",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in Approvals →",
    };
  }

  // 3. New Store Requests
  if (
    refType === "new_store_request" ||
    /^\/new[-_]store[-_]requests?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("new_store") ||
    trimmedRoute.includes("new-store")
  ) {
    return {
      route: "/approvals?tab=new_stores",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in Approvals →",
    };
  }

  // 4. Coverage Requests
  if (
    refType === "coverage_request" ||
    /^\/coverage-requests?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("coverage-request") ||
    trimmedRoute.includes("coverage_request") ||
    trimmedRoute.includes("coverage")
  ) {
    return {
      route: "/approvals?tab=coverage",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in Approvals →",
    };
  }

  // 5. HR Emploc Deletions
  // Backend patterns: /hr-emploc/deletion-requests/:id or /hr-emploc-deletion-requests/:id
  if (
    refType === "hr_emploc_deletion" ||
    /^\/hr-emploc\/deletion-requests?(?:\/.*)?$/i.test(trimmedRoute) ||
    /^\/hr-emploc-deletion-requests?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("deletion-request") ||
    (refType.includes("hr_emploc") && trimmedRoute.includes("deletion"))
  ) {
    return {
      route: "/approvals?tab=hr_emploc_deletions",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in Approvals →",
    };
  }

  // 6. Deactivations
  // Backend patterns: /deactivation-requests/:id or /deactivation/my-requests
  if (
    refType === "deactivation_request" ||
    refType === "deactivation_batch" ||
    refType === "deactivation" ||
    /^\/deactivation(?:-requests?)?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("deactivation")
  ) {
    return {
      route: "/approvals?tab=deactivations",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in Approvals →",
    };
  }

  // 7. Applicant Movements
  // Backend patterns: /requests/applicant-movement/:id or /applicant-movement/:id
  if (
    refType === "applicant_movement" ||
    /^\/(?:requests\/)?applicant-movements?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("applicant-movement") ||
    trimmedRoute.includes("applicant_movement")
  ) {
    return {
      route: "/approvals?tab=applicant_movements",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in Approvals →",
    };
  }

  // 8. Account Group Transfers
  // Backend patterns: /account-group-transfers/:id, /account_transfer/:id, /account-transfer/:id
  if (
    refType === "account_group_transfer_request" ||
    /^\/account-group-transfers?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("account-group-transfer") ||
    trimmedRoute.includes("account_transfer") ||
    trimmedRoute.includes("account-transfer")
  ) {
    return {
      route: "/approvals?tab=account_group_transfers",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in Approvals →",
    };
  }

  // 9. Workforce Requests & Workforce Pool Requests (Relievers)
  // Backend patterns: /workforce/requests/:id, /workforce/pool-requests/:id, /pool_requests/:id
  if (
    refType === "workforce_pool_request" ||
    refType === "workforce_request" ||
    refType.startsWith("workforce_") ||
    /^\/workforce\/(?:pool-)?requests?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("pool_request") ||
    trimmedRoute.includes("pool-request") ||
    trimmedRoute.includes("workforce/requests") ||
    trimmedRoute.includes("workforce/pool-requests")
  ) {
    return {
      route: "/approvals?tab=relievers",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in Approvals →",
    };
  }

  // 10. Account Requests -> Users
  // Backend patterns: /account-requests/:id
  if (
    refType === "account_request" ||
    /^\/account-requests?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("account-request")
  ) {
    return {
      route: "/users",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "Review User Requests →",
    };
  }

  // 11. Access Requests -> More
  // Backend patterns: /access-requests/:id
  if (
    refType === "access_request" ||
    refType === "temp_permission_override" ||
    /^\/access-requests?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("access-request")
  ) {
    return {
      route: "/more",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "View in More →",
    };
  }

  // 12. Transfers -> Plantilla
  // Backend patterns: /transfers/:id
  if (
    refType === "transfer" ||
    /^\/transfers?(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.startsWith("/transfers") ||
    trimmedRoute.startsWith("/transfer/")
  ) {
    return {
      route: "/plantilla",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "Inspect Plantilla →",
    };
  }

  // 13. Ghost Employees -> Plantilla
  if (refType === "ghost_employee" || /^\/ghost-employees?(?:\/.*)?$/i.test(trimmedRoute)) {
    return {
      route: "/plantilla",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "Inspect Plantilla →",
    };
  }

  // 14. HR Emploc Correction -> /hr-emploc
  // Backend patterns: /hr-emploc/:id/correction
  if (
    refType === "hr_emploc_correction" ||
    /^\/hr-emploc\/[^\/]+\/corrections?(?:\/.*)?$/i.test(trimmedRoute) ||
    (trimmedRoute.startsWith("/hr-emploc/") && trimmedRoute.includes("/correction"))
  ) {
    return {
      route: "/hr-emploc",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "Inspect Emploc →",
    };
  }

  // 15. Import Batches -> /hr-emploc/import
  if (
    refType === "plantilla_import_batch" ||
    refType === "vacancy_import_batch" ||
    refType === "mika_import" ||
    refType === "store_import" ||
    /^\/hr-emploc\/import(?:\/.*)?$/i.test(trimmedRoute) ||
    trimmedRoute.includes("import")
  ) {
    return {
      route: "/hr-emploc/import",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "Inspect Import Batch →",
    };
  }

  // 16. Vacancies / VCode Resolution
  // Case A: /vacancies/:vcode or /vacancy/:vcode (where subpath doesn't match flat /vacancies)
  const vacancySubpathMatch = trimmedRoute.match(/^\/vacanc(?:y|ies)\/([^/?#]+)$/i);
  if (vacancySubpathMatch?.[1]) {
    const rawVcode = decodeURIComponent(vacancySubpathMatch[1]).trim();
    if (rawVcode && rawVcode.toLowerCase() !== "page") {
      return {
        route: `/vacancy?q=${encodeURIComponent(rawVcode)}`,
        referenceId: normalizedRefId,
        requestId: normalizedReqId,
        label: "Inspect Vacancy →",
      };
    }
  }

  // Case B: General Vacancy route or type
  if (
    refType === "vacancy" ||
    refType === "vacancy_request" ||
    trimmedRoute === "/vacancies" ||
    trimmedRoute === "/vacancy" ||
    trimmedRoute.startsWith("/vacancy?") ||
    trimmedRoute.startsWith("/vacancies?")
  ) {
    if (trimmedRoute.includes("?q=")) {
      return {
        route: trimmedRoute.replace(/^\/vacancies\?/, "/vacancy?"),
        referenceId: normalizedRefId,
        requestId: normalizedReqId,
        label: "Inspect Vacancy →",
      };
    }

    const vcode = extractEntityCodeFromItem(item);
    return {
      route: vcode ? `/vacancy?q=${encodeURIComponent(vcode)}` : "/vacancy",
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: "Inspect Vacancy →",
    };
  }

  // 17. Valid App Router Flat Route Pass-Through (e.g. /approvals, /plantilla, /users, etc.)
  if (isValidAppRouterRoute(trimmedRoute)) {
    return {
      route: trimmedRoute,
      referenceId: normalizedRefId,
      requestId: normalizedReqId,
      label: getLabelForRoute(trimmedRoute),
    };
  }

  // 18. Semantic Module-Based Fallback for Unmapped Routes
  if (fallbackModule) {
    switch (fallbackModule) {
      case "approvals":
        return {
          route: "/approvals",
          referenceId: normalizedRefId,
          requestId: normalizedReqId,
          label: "View in Approvals →",
        };
      case "vacancy":
        return {
          route: "/vacancy",
          referenceId: normalizedRefId,
          requestId: normalizedReqId,
          label: "Inspect Vacancy →",
        };
      case "plantilla":
        return {
          route: "/plantilla",
          referenceId: normalizedRefId,
          requestId: normalizedReqId,
          label: "Inspect Plantilla →",
        };
      case "hr_emploc":
        return {
          route: "/hr-emploc",
          referenceId: normalizedRefId,
          requestId: normalizedReqId,
          label: "Inspect Emploc →",
        };
      case "cencom":
        return {
          route: "/cencom",
          referenceId: normalizedRefId,
          requestId: normalizedReqId,
          label: "View in CENCOM →",
        };
      case "system":
        return {
          route: "/notifications",
          referenceId: normalizedRefId,
          requestId: normalizedReqId,
          label: "View Notifications →",
        };
    }
  }

  // 19. Tier 3 Safe Termination: Unmapped routes return null to prevent rendering 404 links
  return null;
}

/**
 * Backward-compatible alias matching existing imports.
 */
export const parseNotificationDeepLink = sanitizeNotificationDeepLink;
