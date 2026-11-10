/**
 * Sanitizes user search terms interpolated into PostgREST .or() filter strings for fuzzy search (ilike).
 * Strips only characters that alter PostgREST filter AST structure: `,`, `(`, `)`, `"`, and `\`.
 * Retains `.` to preserve decimal numbers and normal domain notation.
 */
export function sanitizeOrTerm(term?: string | null): string {
  if (!term || typeof term !== "string") return "";
  return term.replace(/[,()"\\]/g, "").trim();
}
