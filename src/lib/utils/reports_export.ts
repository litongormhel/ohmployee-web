import ExcelJS from "exceljs";

function triggerXlsxDownload(buffer: ArrayBuffer, filename: string): void {
  const blob = new Blob([buffer], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${filename}.xlsx`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function appendJsonSheet(
  wb: ExcelJS.Workbook,
  rows: Record<string, unknown>[],
  sheetName: string,
): void {
  const ws = wb.addWorksheet(sheetName.substring(0, 31));
  const safeRows = rows.length ? rows : [{ Note: "No data available" }];
  const headers = Array.from(
    new Set(safeRows.flatMap((row) => Object.keys(row))),
  );
  ws.addRow(headers);
  for (const row of safeRows) {
    ws.addRow(headers.map((h) => row[h] ?? ""));
  }
}

/**
 * Downloads tabular data as an XLSX workbook.
 */
export async function exportToXlsx(
  data: Record<string, unknown>[],
  filename: string,
  sheetName = "Report",
): Promise<void> {
  if (typeof window === "undefined" || !data.length) return;

  const wb = new ExcelJS.Workbook();
  appendJsonSheet(wb, data, sheetName);
  const buffer = await wb.xlsx.writeBuffer();
  triggerXlsxDownload(buffer, filename);
}

/**
 * Downloads tabular data as a multi-sheet XLSX workbook.
 */
export async function exportMultiSheetXlsx(
  sheets: { name: string; data: Record<string, unknown>[] }[],
  filename: string,
): Promise<void> {
  if (typeof window === "undefined" || !sheets.length) return;

  const wb = new ExcelJS.Workbook();
  for (const sheet of sheets) {
    appendJsonSheet(wb, sheet.data, sheet.name);
  }
  const buffer = await wb.xlsx.writeBuffer();
  triggerXlsxDownload(buffer, filename);
}

function escapeCsvCell(val: unknown): string {
  if (val === null || val === undefined) return "";
  let str = String(val);
  // Exempt pure-numeric strings (e.g. "+123", "-45.67", "0")
  if (!/^[+-]?\d+(\.\d+)?$/.test(str.trim())) {
    // Prefix single quote if string starts with formula trigger (=, +, -, @, tab, CR)
    if (/^[=+\-@\t\r]/.test(str)) {
      str = `'${str}`;
    }
  }
  if (/[",\r\n]/.test(str)) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

/**
 * Downloads tabular data as a CSV file.
 */
export function exportToCsv(
  data: Record<string, unknown>[],
  filename: string,
): void {
  if (typeof window === "undefined" || !data.length) return;

  const headers = Array.from(new Set(data.flatMap((row) => Object.keys(row))));
  const lines = [
    headers.map(escapeCsvCell).join(","),
    ...data.map((row) => headers.map((h) => escapeCsvCell(row[h])).join(",")),
  ];

  const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${filename}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
