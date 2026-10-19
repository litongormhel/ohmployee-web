import * as XLSX from "xlsx";

/**
 * Downloads tabular data as an XLSX workbook.
 */
export function exportToXlsx(
  data: Record<string, unknown>[],
  filename: string,
  sheetName = "Report"
): void {
  if (typeof window === "undefined" || !data.length) return;

  const ws = XLSX.utils.json_to_sheet(data);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, sheetName.substring(0, 31));
  XLSX.writeFile(wb, `${filename}.xlsx`);
}

/**
 * Downloads tabular data as a multi-sheet XLSX workbook.
 */
export function exportMultiSheetXlsx(
  sheets: { name: string; data: Record<string, unknown>[] }[],
  filename: string
): void {
  if (typeof window === "undefined" || !sheets.length) return;

  const wb = XLSX.utils.book_new();
  for (const sheet of sheets) {
    const ws = XLSX.utils.json_to_sheet(sheet.data.length ? sheet.data : [{ Note: "No data available" }]);
    XLSX.utils.book_append_sheet(wb, ws, sheet.name.substring(0, 31));
  }
  XLSX.writeFile(wb, `${filename}.xlsx`);
}

/**
 * Downloads tabular data as a CSV file.
 */
export function exportToCsv(
  data: Record<string, unknown>[],
  filename: string
): void {
  if (typeof window === "undefined" || !data.length) return;

  const ws = XLSX.utils.json_to_sheet(data);
  const csv = XLSX.utils.sheet_to_csv(ws);
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${filename}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
