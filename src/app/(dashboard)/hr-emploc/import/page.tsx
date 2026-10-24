import { redirect } from "next/navigation";

export default function HrEmplocImportPage() {
  redirect("/more?tab=data_control&subtab=batch_imports&open=import_hr_emploc");
}
