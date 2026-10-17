const SUFFIXES = new Set(["JR", "JR.", "SR", "SR.", "II", "III", "IV", "V"]);

/**
 * Standardizes person names strictly to UPPERCASE:
 * "LASTNAME, FIRSTNAME MIDDLENAME" (or "LASTNAME, FIRSTNAME" if middle name absent).
 *
 * Examples:
 *   formatPersonName("LINDSAY", "LOHAN", "TAN") => "LOHAN, LINDSAY TAN"
 *   formatPersonName("Lindsay", "Lohan") => "LOHAN, LINDSAY"
 *   formatPersonName(null, null, null, "LINDSAY TAN LOHAN") => "LOHAN, LINDSAY TAN"
 *   formatPersonName(null, null, null, "LOHAN, LINDSAY TAN") => "LOHAN, LINDSAY TAN"
 *   formatPersonName(null, null, null, "ALFREDO CUIZON CAMPAÑA JR") => "CAMPAÑA JR, ALFREDO CUIZON"
 */
export function formatPersonName(
  firstName?: string | null,
  lastName?: string | null,
  middleName?: string | null,
  fullName?: string | null,
): string {
  const f = firstName?.trim() || "";
  const l = lastName?.trim() || "";
  const m = middleName?.trim() || "";

  if (l && f) {
    if (!m && fullName?.trim()) {
      const parsedFromFull = parseFullNameString(fullName.trim());
      if (parsedFromFull.includes(",")) {
        const parts = parsedFromFull.split(",");
        const parsedFirstAndMiddle = parts.slice(1).join(" ").trim();
        if (
          parsedFirstAndMiddle.toUpperCase().startsWith(f.toUpperCase()) &&
          parsedFirstAndMiddle.length > f.length
        ) {
          return `${l}, ${parsedFirstAndMiddle}`.toUpperCase();
        }
      }
    }
    const fnPart = m ? `${f} ${m}` : f;
    return `${l}, ${fnPart}`.toUpperCase();
  }

  if (l && !f) {
    return l.toUpperCase();
  }

  if (f && !l) {
    return parseFullNameString(f);
  }

  const raw = fullName?.trim() || "";
  if (!raw) return "";

  return parseFullNameString(raw);
}

/**
 * Formats HRCO name strictly as "LASTNAME, FIRSTNAME" (e.g. "GOMEZ, SELENA").
 */
export function formatHrcoName(name?: string | null): string {
  if (!name) return "";
  const trimmed = name.trim();
  if (!trimmed || trimmed === "—" || trimmed === "-") return trimmed;
  if (trimmed.toLowerCase() === "unassigned") return "Unassigned";

  const formatted = parseFullNameString(trimmed);
  if (!formatted.includes(",")) {
    return formatted.toUpperCase();
  }

  const [lastName, ...restParts] = formatted.split(",");
  const rest = restParts.join(" ").trim();
  const tokens = rest.split(/\s+/).filter(Boolean);

  if (tokens.length <= 1) {
    return `${lastName.trim()}, ${rest}`.toUpperCase();
  }

  const lastToken = tokens[tokens.length - 1];
  if (lastToken.length <= 2 || lastToken.endsWith(".")) {
    tokens.pop();
  }

  return `${lastName.trim()}, ${tokens.join(" ")}`.toUpperCase();
}

/**
 * Parses an arbitrary full name string into uppercase "LASTNAME, FIRSTNAME MIDDLENAME".
 */
export function parseFullNameString(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) return "";

  const lower = trimmed.toLowerCase();
  if (
    lower.includes("vacant") ||
    lower === "unassigned" ||
    lower === "anonymous" ||
    lower === "candidate" ||
    lower === "hired worker" ||
    lower === "—" ||
    lower === "-"
  ) {
    return trimmed;
  }

  // If already contains comma: "LASTNAME, FIRSTNAME [MIDDLENAME]"
  if (trimmed.includes(",")) {
    const parts = trimmed.split(",");
    const lastPart = parts[0].trim();
    const rest = parts.slice(1).join(" ").trim();
    if (lastPart && rest) {
      return `${lastPart}, ${rest}`.toUpperCase();
    }
    return trimmed.toUpperCase();
  }

  // Space-separated: "FIRSTNAME [MIDDLENAME] LASTNAME [SUFFIX]"
  const tokens = trimmed.split(/\s+/).filter(Boolean);
  if (tokens.length <= 1) {
    return tokens[0] ? tokens[0].toUpperCase() : "";
  }

  // Check if last token is a recognized suffix (JR, SR, III, etc.)
  let lastIdx = tokens.length - 1;
  let suffix = "";
  if (tokens.length >= 3 && SUFFIXES.has(tokens[lastIdx].toUpperCase())) {
    suffix = ` ${tokens[lastIdx]}`;
    lastIdx--;
  }

  const lastPart = tokens[lastIdx] + suffix;
  const firstParts = tokens.slice(0, lastIdx).join(" ");

  return `${lastPart}, ${firstParts}`.toUpperCase();
}

/**
 * Formats multi-store displays compactly as "First Store Name +X more"
 * and provides a full comma-separated list of stores for hover tooltips.
 */
export function formatStoreDisplay(
  primaryStore: string | null | undefined,
  allStores?: string[] | null | undefined,
): {
  display: string;
  displayText: string;
  tooltip: string;
  hasMore: boolean;
  isMulti: boolean;
  firstStore: string;
  moreCount: number;
  extraCount: number;
} {
  const storeList: string[] = [];

  if (Array.isArray(allStores) && allStores.length > 0) {
    for (const s of allStores) {
      const clean = s?.trim();
      if (clean && !storeList.includes(clean)) {
        storeList.push(clean);
      }
    }
  }

  const rawPrimary = (primaryStore || "").trim();
  if (rawPrimary && rawPrimary !== "—" && rawPrimary !== "-") {
    // If primaryStore contains comma-separated stores
    if (rawPrimary.includes(",")) {
      const parts = rawPrimary.split(",").map((s) => s.trim()).filter(Boolean);
      for (const p of parts) {
        if (!storeList.includes(p)) {
          storeList.push(p);
        }
      }
    } else if (!storeList.includes(rawPrimary)) {
      storeList.unshift(rawPrimary);
    }
  }

  if (storeList.length > 1) {
    const firstStore = storeList[0];
    const moreCount = storeList.length - 1;
    const display = `${firstStore} +${moreCount} more`;
    return {
      display,
      displayText: display,
      tooltip: storeList.join(", "),
      hasMore: true,
      isMulti: true,
      firstStore,
      moreCount,
      extraCount: moreCount,
    };
  }

  if (storeList.length === 1) {
    return {
      display: storeList[0],
      displayText: storeList[0],
      tooltip: storeList[0],
      hasMore: false,
      isMulti: false,
      firstStore: storeList[0],
      moreCount: 0,
      extraCount: 0,
    };
  }

  const fallback = rawPrimary || "—";
  return {
    display: fallback,
    displayText: fallback,
    tooltip: rawPrimary || "Unassigned Outlet",
    hasMore: false,
    isMulti: false,
    firstStore: fallback,
    moreCount: 0,
    extraCount: 0,
  };
}
