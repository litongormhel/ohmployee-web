export type VacancyStatus = "open" | "with_applicant" | "rejected" | "backout";

export type VacancyListItem = {
  id: string;
  vcode: string;
  position: string;
  department: string;
  status: VacancyStatus;
};

export async function getVacancies(
  status: VacancyStatus,
): Promise<{ data: VacancyListItem[] }> {
  void status;

  return { data: [] };
}
