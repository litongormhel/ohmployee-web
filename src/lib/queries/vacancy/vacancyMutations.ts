import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { formatPersonName } from "@/lib/utils/formatName";
import {
  type CandidateDuplicateCheckResult,
  type UpdateApplicantProfileParams,
  type UpdateApplicantProfileResult,
  type EndorseApplicantParams,
  type EndorseApplicantResult,
  type UpdateApplicantPipelineParams,
  type ConfirmApplicantOnboardParams,
  type FailBackoutParams,
  type ReopenVacancyParams,
  type DirectImportVacancyParams,
  type UpdateHiredDateParams,
  VacancyDataError,
} from "./types";
import { invalidateVacancyEcosystem } from "./vacancyHelpers";
import { fetchOccupiedStoreIdentifiers } from "./vacancyListing";

// ── Candidate Duplicate Verification ──────────────────────────

export async function checkCandidateDuplicate(params: {
  firstName: string;
  lastName: string;
  contactNumber?: string | null;
  currentApplicantId?: string | null;
}): Promise<CandidateDuplicateCheckResult> {
  const supabase = createClient();
  try {
    const { data, error } = await supabase.rpc("check_candidate_duplicate", {
      p_first_name: params.firstName.trim(),
      p_last_name: params.lastName.trim(),
      p_contact: params.contactNumber?.trim() || null,
      p_current_applicant_id: params.currentApplicantId || null,
    });
    if (error) {
      console.warn("check_candidate_duplicate RPC warning:", error.message);
      return { isBlocked: false };
    }
    if (data && typeof data === "object") {
      const res = data as Record<string, unknown>;
      return {
        isBlocked: res.is_blocked === true,
        conflictType: (res.conflict_type as CandidateDuplicateCheckResult["conflictType"]) ?? null,
        status: (res.status as string) ?? null,
        vcode: (res.vcode as string) ?? null,
        storeName: (res.store_name as string) ?? null,
        account: (res.account as string) ?? null,
        message: (res.message as string) ?? null,
      };
    }
    return { isBlocked: false };
  } catch (err) {
    console.warn("checkCandidateDuplicate exception (non-blocking):", err);
    return { isBlocked: false };
  }
}

// ── Edit Applicant Details (fn_update_applicant_profile_once) ──
export async function updateApplicantProfileOnce(
  params: UpdateApplicantProfileParams,
): Promise<UpdateApplicantProfileResult> {
  const supabase = createClient();
  const applicantId = params.applicantId.trim();
  const firstName = params.firstName.trim().toUpperCase();
  const lastName = params.lastName.trim().toUpperCase();
  const rawMiddle = params.middleName?.trim();
  const middleName =
    rawMiddle && !["", "NA", "N/A", "NONE", "N.A."].includes(rawMiddle.toUpperCase())
      ? rawMiddle.toUpperCase()
      : null;
  const reason = params.reason.trim();

  // Normalize contact number: 11 digits starting with 09
  const cleanContact = params.contactNumber.replace(/[^0-9]/g, "");
  const normalizedContact =
    cleanContact.length === 10 && cleanContact.startsWith("9")
      ? `0${cleanContact}`
      : cleanContact;

  if (!applicantId) {
    throw new VacancyDataError("validation", "Applicant ID is required.");
  }
  if (!firstName || !lastName) {
    throw new VacancyDataError("validation", "First Name and Last Name are required.");
  }
  if (!normalizedContact || !/^09[0-9]{9}$/.test(normalizedContact)) {
    throw new VacancyDataError(
      "validation",
      "Contact number must be 11 digits starting with 09 (e.g. 09171234567).",
    );
  }
  if (!reason) {
    throw new VacancyDataError("validation", "Reason / comments for editing profile are required.");
  }

  const { error } = await supabase.rpc("fn_update_applicant_profile_once", {
    p_applicant_id: applicantId,
    p_first_name: firstName,
    p_last_name: lastName,
    p_contact_number: normalizedContact,
    p_middle_name: middleName,
    p_reason: reason,
  });

  if (error) {
    if (error.code === "42501") {
      throw new VacancyDataError("access_denied", error.message || "Permission denied to edit applicant details.");
    }
    throw new VacancyDataError("generic", error.message);
  }

  // Propagate identity fields to other active pipeline rows with the same contact number
  let linkedPropagatedCount = 0;
  try {
    linkedPropagatedCount = await propagateApplicantIdentityToLinked({
      applicantId,
      firstName,
      lastName,
      middleName,
      contactNumber: normalizedContact,
    });
  } catch (propError) {
    console.warn("propagateApplicantIdentityToLinked error (non-fatal):", propError);
  }

  return {
    success: true,
    applicantId,
    linkedPropagatedCount,
  };
}

export async function propagateApplicantIdentityToLinked(params: {
  applicantId: string;
  firstName: string;
  lastName: string;
  middleName?: string | null;
  contactNumber: string;
}): Promise<number> {
  const supabase = createClient();
  const normalizedContact = params.contactNumber.trim();
  if (!normalizedContact) return 0;

  const lockedStatuses = [
    "confirmed_onboard",
    "transferred",
    "hired",
    "Confirmed Onboard",
    "Transferred",
    "Hired",
  ];

  const { data: rows, error: selectError } = await supabase
    .from("applicants")
    .select("id, status")
    .eq("contact_number", normalizedContact)
    .neq("id", params.applicantId)
    .or("is_archived.is.null,is_archived.eq.false");

  if (selectError || !Array.isArray(rows)) return 0;

  const eligibleIds = rows
    .filter((r) => !lockedStatuses.includes(String(r.status)))
    .map((r) => r.id as string)
    .filter(Boolean);

  if (eligibleIds.length === 0) return 0;

  const fullName = formatPersonName(params.firstName, params.lastName, params.middleName);

  const { error: updateError } = await supabase
    .from("applicants")
    .update({
      first_name: params.firstName,
      last_name: params.lastName,
      middle_name: params.middleName || null,
      contact_number: normalizedContact,
      full_name: fullName,
      updated_at: new Date().toISOString(),
    })
    .in("id", eligibleIds);

  if (updateError) {
    console.warn("propagateApplicantIdentityToLinked update failed:", updateError.message);
    return 0;
  }

  return eligibleIds.length;
}

export function useUpdateApplicantProfile() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateApplicantProfileParams) => updateApplicantProfileOnce(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      if (variables.vcode) {
        queryClient.invalidateQueries({
          queryKey: ["vacancy-detail", variables.vcode],
        });
      }
    },
  });
}

export async function endorseApplicant(
  params: EndorseApplicantParams,
): Promise<EndorseApplicantResult> {
  const supabase = createClient();
  const vcode = params.vcode.trim();
  const firstName = params.firstName.trim().toUpperCase();
  const lastName = params.lastName.trim().toUpperCase();
  const middleName = params.middleName?.trim().toUpperCase() || "";
  const fullName = formatPersonName(firstName, lastName, middleName);
  
  // Normalize contact number: must be 11 digits starting with 09
  const cleanContact = params.contactNumber.replace(/[^0-9]/g, "");
  const normalizedContact =
    cleanContact.length === 10 && cleanContact.startsWith("9")
      ? `0${cleanContact}`
      : cleanContact;

  if (!vcode) {
    throw new VacancyDataError("validation", "Target VCode is required.");
  }
  if (!firstName || !middleName || !lastName) {
    throw new VacancyDataError("validation", "First Name, Middle Name, and Last Name are required.");
  }
  if (!normalizedContact || !/^09[0-9]{9}$/.test(normalizedContact)) {
    throw new VacancyDataError(
      "validation",
      "Contact number must be 11 digits starting with 09 (e.g. 09171234567).",
    );
  }

  // 1. Verify vacancy exists and get its status
  const { data: vac, error: vacError } = await supabase
    .from("vacancies")
    .select("id, vcode, status, deleted_at, is_archived, has_pending_closure, required_headcount")
    .eq("vcode", vcode)
    .maybeSingle();

  if (vacError) {
    throw new VacancyDataError("generic", vacError.message);
  }
  if (!vac) {
    throw new VacancyDataError("not_found", `Vacancy with VCode ${vcode} not found.`);
  }
  if (vac.deleted_at || vac.is_archived) {
    throw new VacancyDataError("validation", `Vacancy ${vcode} is archived or inactive.`);
  }
  if (vac.has_pending_closure) {
    throw new VacancyDataError("validation", `Vacancy ${vcode} is locked pending closure.`);
  }

  // Pre-insert candidate duplicate check (Pipeline, HR Emploc, Plantilla)
  const dupCheck = await checkCandidateDuplicate({
    firstName,
    lastName,
    contactNumber: normalizedContact,
  });
  if (dupCheck.isBlocked) {
    throw new VacancyDataError(
      "validation",
      dupCheck.message ||
        "Candidate is already active in another requisition, HR Emploc processing, or Plantilla slot. Duplicate creation is blocked.",
    );
  }

  // 2. Capacity Guard & Requirement Resolution (Avail = Zero-Applicant Invariant)
  let targetRequirementId = params.vacancyRequirementId?.trim() || null;
  if (!targetRequirementId && vac.id) {
    try {
      const { data: autoReqs } = await supabase
        .from("vacancy_requirements")
        .select("id")
        .eq("vacancy_id", vac.id)
        .limit(2);
      if (autoReqs && autoReqs.length === 1 && autoReqs[0]?.id) {
        targetRequirementId = String(autoReqs[0].id);
      }
    } catch {
      // Non-blocking fallback
    }
  }

  if (targetRequirementId) {
    try {
      const { data: targetReq } = await supabase
        .from("vacancy_requirements")
        .select("id, hc_needed, hc_filled")
        .eq("id", targetRequirementId)
        .maybeSingle();

      if (targetReq) {
        const hcNeeded = Number(targetReq.hc_needed) || 1;
        const hcFilled = Number(targetReq.hc_filled) || 0;

        const { count: pipeCount } = await supabase
          .from("applicants")
          .select("id", { count: "exact", head: true })
          .eq("vacancy_requirement_id", targetRequirementId)
          .not("status", "in", '("Backout","backout","Failed","failed","Rejected","rejected","Did Not Report","did not report","confirmed_onboard","Confirmed Onboard","hired","Hired")')
          .eq("is_archived", false);

        const currentPipe = pipeCount || 0;
        const available = Math.max(0, hcNeeded - hcFilled - currentPipe);
        if (available <= 0) {
          throw new VacancyDataError(
            "validation",
            "This position requirement is already filled. Cannot add another applicant unless an active candidate backs out.",
          );
        }
      }
    } catch (e) {
      if (e instanceof VacancyDataError) throw e;
      console.error("[PostgREST Schema Error] endorseApplicant requirement capacity check:", e);
    }
  } else {
    try {
      const { count: totalPipeCount } = await supabase
        .from("applicants")
        .select("id", { count: "exact", head: true })
        .eq("vacancy_vcode", vcode)
        .not("status", "in", '("Backout","backout","Failed","failed","Rejected","rejected","Did Not Report","did not report","confirmed_onboard","Confirmed Onboard","hired","Hired")')
        .eq("is_archived", false);

      const reqHc = Number(vac.required_headcount) || 1;
      const hired = Number((vac as Record<string, unknown>).hc_filled ?? (vac as Record<string, unknown>).confirmed_onboard_count) || 0;
      const totalPipe = totalPipeCount || 0;
      const totalAvailable = Math.max(0, reqHc - hired - totalPipe);

      if (totalAvailable <= 0) {
        throw new VacancyDataError(
          "validation",
          `Vacancy ${vcode} is already fully allocated (${reqHc}/${reqHc} filled or in pipeline). Cannot add another applicant unless an active candidate backs out.`,
        );
      }
    } catch (e) {
      if (e instanceof VacancyDataError) throw e;
      console.error("[PostgREST Schema Error] endorseApplicant vacancy capacity check:", e);
    }
  }

  const applicantInsertPayload: Record<string, unknown> = {
    vacancy_vcode: vcode,
    first_name: firstName,
    last_name: lastName,
    middle_name: middleName,
    full_name: fullName,
    contact_number: normalizedContact,
    status: params.status || "New",
    remarks: params.hrcoRemarks?.trim() || null,
  };

  if (targetRequirementId) {
    applicantInsertPayload.vacancy_requirement_id = targetRequirementId;
  }

  if (params.targetOnboardDate) {
    applicantInsertPayload.interview_date = params.targetOnboardDate;
  }
  if (params.recruiterName) {
    applicantInsertPayload.recruited_by_name = params.recruiterName.trim();
  }
  if (params.recruiterId) {
    applicantInsertPayload.recruited_by_user_id = params.recruiterId;
  }

  const { data: insertedApp, error: insertError } = await supabase
    .from("applicants")
    .insert(applicantInsertPayload)
    .select("id, vacancy_vcode, full_name, status")
    .single();

  if (insertError) {
    if (insertError.code === "42501") {
      throw new VacancyDataError("access_denied", "You do not have permission to add applicants.");
    }
    throw new VacancyDataError("generic", insertError.message);
  }

  // 3. Status transition: Requisitions remain 'Open' until all required headcount is confirmed onboard.
  // We do not overwrite vacancies.status to 'Pipeline' so multi-headcount vacancies stay actionable in Open tab.

  return {
    id: insertedApp.id,
    vcode: insertedApp.vacancy_vcode,
    fullName: insertedApp.full_name,
    status: insertedApp.status ?? "New",
  };
}

export function useEndorseApplicant() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: EndorseApplicantParams) => endorseApplicant(params),
    onSuccess: (_data, variables) => {
      invalidateVacancyEcosystem(queryClient, variables.vcode);
    },
  });
}

// ── 1. Advance Pipeline / Update Applicant Status ─────────────
export async function updateApplicantPipeline(
  params: UpdateApplicantPipelineParams,
) {
  const supabase = createClient();

  const rpcParams: Record<string, unknown> = {
    p_applicant_id: params.applicantId,
    p_new_status: params.newStatus ?? null,
    p_recruitment_remarks: params.recruitmentRemarks ?? null,
    p_ops_remarks: params.opsRemarks ?? null,
    p_follow_up_date: params.followUpDate ?? null,
    p_reason_id: params.reasonId ?? null,
    p_reason_type: params.reasonType ?? null,
  };

  const { data, error } = await supabase.rpc(
    "fn_update_applicant_pipeline",
    rpcParams,
  );

  if (error) {
    // Fallback: direct table update if RPC fails
    console.warn("fn_update_applicant_pipeline error, attempting fallback update:", error.message);
    const updates: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };
    if (params.newStatus) updates.status = params.newStatus;
    if (params.recruitmentRemarks !== undefined) updates.recruitment_remarks = params.recruitmentRemarks;
    if (params.opsRemarks !== undefined) updates.ops_remarks = params.opsRemarks;
    if (params.followUpDate !== undefined) updates.follow_up_date = params.followUpDate;
    const isTerminal =
      params.newStatus?.toLowerCase() === "backout" ||
      params.newStatus?.toLowerCase() === "rejected" ||
      params.newStatus?.toLowerCase() === "failed";

    if (isTerminal) {
      updates.is_archived = true;
      updates.slot_id = null;
    }
    if (params.newStatus === "backout" || params.newStatus === "Backout") {
      updates.backout_date = new Date().toISOString().substring(0, 10);
    }

    const { error: fallbackError } = await supabase
      .from("applicants")
      .update(updates)
      .eq("id", params.applicantId);

    if (fallbackError) {
      throw new VacancyDataError("generic", fallbackError.message);
    }
    return { success: true };
  }

  return data;
}

export function useUpdateApplicantPipeline() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateApplicantPipelineParams) =>
      updateApplicantPipeline(params),
    onSuccess: (_data, variables) => {
      invalidateVacancyEcosystem(queryClient, variables.vcode);
    },
  });
}

// ── 2. Confirm Applicant Onboard / Mark Hired ─────────────────
export async function confirmApplicantOnboard(
  params: ConfirmApplicantOnboardParams,
) {
  const supabase = createClient();

  // Normalize contact number
  const cleanContact = params.contactNumber.replace(/[^0-9]/g, "");
  const normalizedContact =
    cleanContact.length === 10 && cleanContact.startsWith("9")
      ? `0${cleanContact}`
      : cleanContact;

  // If explicit Coverage Group store footprint selection was provided (partial or full roving store onboarding),
  // invoke confirm_coverage_group_onboarding so unselected stores remain in Pipeline ('For Requirements')
  // and selected stores advance to HR Emploc (or fast-track to Active Plantilla under Option A).
  if (Array.isArray(params.selectedStoreIds) && params.selectedStoreIds.length > 0) {
    if (params.endorsedByName || params.endorsedByDeployerId) {
      await supabase
        .from("applicants")
        .update({
          endorsed_by_deployer_id: params.endorsedByDeployerId || null,
          endorsed_by_name: params.endorsedByName || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", params.applicantId);
    }

    const { data: cgData, error: cgError } = await supabase.rpc(
      "confirm_coverage_group_onboarding",
      {
        p_applicant_id: params.applicantId,
        p_selected_store_ids: params.selectedStoreIds,
        p_hired_by_user_id: params.hiredByUserId || null,
        p_hired_date: params.hiredDate,
        p_remarks: params.remarks || null,
      },
    );

    if (cgError) {
      throw new VacancyDataError("generic", cgError.message);
    }

    return cgData;
  }

  const rpcParams: Record<string, unknown> = {
    p_applicant_id: params.applicantId,
    p_last_name: params.lastName,
    p_first_name: params.firstName,
    p_middle_name: params.middleName || null,
    p_full_name: params.fullName,
    p_contact_number: normalizedContact,
    p_remarks: params.remarks || null,
    p_roving_assignment_id: params.rovingAssignmentId || null,
    p_hired_by_user_id: params.hiredByUserId,
    p_hired_date: params.hiredDate,
    p_endorsed_by_deployer_id: params.endorsedByDeployerId || null,
    p_endorsed_by_name: params.endorsedByName || null,
  };

  if (params.vacancyRequirementId) {
    rpcParams.p_vacancy_requirement_id = params.vacancyRequirementId;
  }

  const { data, error } = await supabase.rpc(
    "confirm_applicant_onboard",
    rpcParams,
  );

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  return data;
}

export function useConfirmApplicantOnboard() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ConfirmApplicantOnboardParams) =>
      confirmApplicantOnboard(params),
    onSuccess: (_data, variables) => {
      invalidateVacancyEcosystem(queryClient, variables.vcode);
    },
  });
}

// ── 3. Fail / Backout Applicant ──────────────────────────────
export async function failBackoutApplicant(params: FailBackoutParams) {
  const supabase = createClient();
  const statusCode =
    params.status.toLowerCase() === "backout" ? "backout" : "rejected";

  // 1. Resolve target applicant ID defensively (if caller accidentally passed a vacancy ID)
  let targetApplicantId = params.applicantId;
  const { data: existingApp } = await supabase
    .from("applicants")
    .select("id, status, slot_id, vacancy_vcode")
    .eq("id", targetApplicantId)
    .maybeSingle();

  if (!existingApp && params.vcode) {
    const { data: activeApp } = await supabase
      .from("applicants")
      .select("id, status, slot_id, vacancy_vcode")
      .eq("vacancy_vcode", params.vcode)
      .eq("is_archived", false)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (activeApp) {
      targetApplicantId = activeApp.id;
    }
  }

  const prevStatus = existingApp?.status || null;
  const boundSlotId = existingApp?.slot_id || null;

  // 2. Mark applicant record strictly as terminal, archived, and unlink slot
  const { error } = await supabase
    .from("applicants")
    .update({
      status: params.status,
      backout_reason: params.reason,
      backout_date: new Date().toISOString().substring(0, 10),
      is_archived: true,
      archived_at: new Date().toISOString(),
      slot_id: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", targetApplicantId);

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  // 3. Record status history in applicant_status_history
  try {
    const { data: userRes } = await supabase.auth.getUser();
    let profileId: string | null = null;
    let profileName: string | null = null;

    if (userRes?.user?.id) {
      const { data: profile } = await supabase
        .from("users_profile")
        .select("id, full_name")
        .eq("auth_user_id", userRes.user.id)
        .maybeSingle();
      if (profile) {
        profileId = profile.id;
        profileName = profile.full_name;
      }
    }

    await supabase.from("applicant_status_history").insert({
      applicant_id: targetApplicantId,
      from_status: prevStatus,
      to_status: params.status,
      reason_id: params.reasonId || null,
      reason_type: statusCode,
      remarks: params.reason,
      changed_by: profileId,
      changed_by_name: profileName,
      source_module: "vacancy",
      update_type: "status_change",
      changed_field: "status",
      old_value: prevStatus,
      new_value: params.status,
    });
  } catch {
    // Non-fatal if history logging fails
  }

  // 4. Release bound slot and reconcile vacancy slots
  if (boundSlotId) {
    try {
      await supabase.rpc("fn_release_applicant_slot", {
        p_slot_id: boundSlotId,
        p_performed_by: null,
      });
    } catch {
      // Non-fatal
    }
  }

  try {
    await supabase.rpc("fn_sync_vacancy_slot_open_pipeline", {
      p_vcode: params.vcode,
      p_performed_by: null,
      p_source_fn: "failBackoutApplicant",
    });
  } catch {
    // Non-fatal
  }

  // 5. Quota-aware vacancy status transition:
  // If this vacancy now has 0 remaining active pipeline candidates, check if required quota is still unfilled before returning to 'Open'
  try {
    const { data: vac } = await supabase
      .from("vacancies")
      .select("id, required_headcount, status")
      .eq("vcode", params.vcode)
      .maybeSingle();

    if (vac) {
      const { data: activeApps } = await supabase
        .from("applicants")
        .select("id, status")
        .eq("vacancy_vcode", params.vcode)
        .eq("is_archived", false)
        .neq("id", targetApplicantId);

      const activeList = activeApps ?? [];
      const confirmedCount = activeList.filter(
        (a) => (a.status || "").toLowerCase().trim() === "confirmed onboard",
      ).length;

      const requiredHc = Number(vac.required_headcount ?? 1) || 1;

      // Multi-headcount rule: as long as confirmed onboard count < required headcount,
      // the requisition has remaining open slots and must stay/reappear in Open tab.
      if (confirmedCount < requiredHc) {
        await supabase
          .from("vacancies")
          .update({
            status: "Open",
            is_archived: false,
            archived_at: null,
            archived_by: null,
            updated_at: new Date().toISOString(),
          })
          .eq("vcode", params.vcode);
      } else {
        await supabase
          .from("vacancies")
          .update({
            status: "Filled",
            updated_at: new Date().toISOString(),
          })
          .eq("vcode", params.vcode);
      }
    }
  } catch {
    // Non-fatal if status check fails
  }

  return { success: true };
}

export function useFailBackoutApplicant() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: FailBackoutParams) => failBackoutApplicant(params),
    onSuccess: (_data, variables) => {
      invalidateVacancyEcosystem(queryClient, variables.vcode);
    },
  });
}

// ── 4. Reopen Vacancy Modal / Recycling to Open Queue ────────
export async function reopenVacancy(params: ReopenVacancyParams) {
  const supabase = createClient();
  const vcode = params.vcode.trim();

  // Reset status to Open and clear pending closure flags
  const updatePayload: Record<string, unknown> = {
    status: "Open",
    is_archived: false,
    has_pending_closure: false,
    updated_at: new Date().toISOString(),
  };

  if (params.vacantDate) {
    updatePayload.vacant_date = params.vacantDate;
  }

  const { data, error } = await supabase
    .from("vacancies")
    .update(updatePayload)
    .eq("vcode", vcode)
    .select()
    .single();

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  return data;
}

export function useReopenVacancy() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ReopenVacancyParams) => reopenVacancy(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({
        queryKey: ["vacancy-detail", variables.vcode],
      });
    },
  });
}



export async function directImportVacancy(params: DirectImportVacancyParams): Promise<void> {
  const supabase = createClient();
  const vcode = params.vcode.trim().toUpperCase();
  if (!vcode) throw new Error("VCODE is required for direct import.");
  if (!params.accountId) throw new Error("Account ID is required for direct import.");

  // Strict Vacancy Filter Guard: Never create vacancy for store/vcode with an active employee
  const { occupiedStoreIds, occupiedVcodes, occupiedStoreNames } = await fetchOccupiedStoreIdentifiers(params.accountId);
  const storeNameUpper = (params.storeName || "").trim().toUpperCase();
  const isOccupied =
    (params.storeId && occupiedStoreIds.has(params.storeId)) ||
    (vcode && occupiedVcodes.has(vcode)) ||
    (storeNameUpper && occupiedStoreNames.has(storeNameUpper));
  if (isOccupied) {
    throw new Error(
      `Cannot direct-import vacancy for ${vcode}: store slot is already occupied by an active employee.`
    );
  }

  let acctName = params.accountName || null;
  let grpId = params.groupId || null;
  let hrcoUserId: string | null = null;
  let hrcoName: string | null = null;

  if (params.accountId) {
    const { data: acct } = await supabase
      .from("accounts")
      .select("id, account_name, group_id, hrco_user_id")
      .eq("id", params.accountId)
      .maybeSingle();

    if (acct) {
      acctName = acct.account_name || acctName;
      grpId = grpId || acct.group_id;
      hrcoUserId = acct.hrco_user_id;
      if (hrcoUserId) {
        const { data: hrcoProfile } = await supabase
          .from("users_profile")
          .select("full_name")
          .eq("id", hrcoUserId)
          .maybeSingle();
        if (hrcoProfile?.full_name) {
          hrcoName = hrcoProfile.full_name;
        }
      }
    }
  }

  let storeId = params.storeId || null;
  let storeName = params.storeName || null;
  let areaCity = params.areaCity || null;
  let province = params.province || params.areaProvince || null;

  // Attempt store lookup by storeId or VCODE with store account/group inheritance
  let sQuery = supabase.from("stores").select("id, store_name, area_city, area_province, province, account_id, group_id");
  if (storeId) {
    sQuery = sQuery.eq("id", storeId);
  } else {
    sQuery = sQuery.eq("vcode", vcode).eq("status", "active");
  }
  const { data: storeData } = await sQuery.limit(1);
  if (storeData && storeData[0]) {
    const s = storeData[0];
    storeId = storeId || (s.id as string);
    storeName = storeName || (s.store_name as string);
    areaCity = areaCity || (s.area_city as string);
    province = province || ((s.area_province ?? s.province) as string);
    if (!grpId && s.group_id) {
      grpId = s.group_id as string;
    }
    if ((!acctName || acctName === "Unknown Account") && s.account_id) {
      const { data: storeAcct } = await supabase
        .from("accounts")
        .select("account_name, group_id")
        .eq("id", s.account_id)
        .maybeSingle();
      if (storeAcct) {
        acctName = storeAcct.account_name || acctName;
        grpId = grpId || storeAcct.group_id;
      }
    }
  }

  const resolvedAccountId = params.accountId || (storeData && storeData[0]?.account_id) || null;
  const areaName = [province, areaCity].filter(Boolean).join(" - ") || null;
  const position = (params.position || params.positionTitle)?.trim() || "Merchandiser";

  const { error } = await supabase
    .from("vacancies")
    .upsert(
      {
        vcode,
        account: acctName || "Unknown Account",
        position,
        store_name: storeName || vcode,
        store_id: storeId,
        account_id: resolvedAccountId,
        group_id: grpId,
        area_city: areaCity,
        province,
        area_name: areaName,
        required_headcount: params.requiredHeadcount || 1,
        status: "Open",
        source: "manual",
        hrco_user_id: hrcoUserId,
        hrco_name: hrcoName,
        vacant_date: new Date().toISOString().slice(0, 10),
        is_archived: false,
        deleted_at: null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "vcode" }
    );

  if (error) {
    throw new Error(error.message || "Failed to direct import vacancy.");
  }
}

export function useDirectImportVacancy() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: DirectImportVacancyParams) => directImportVacancy(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
    },
  });
}

// ── 6. Update Hired Applicant Date ───────────────────────────
export async function updateHiredApplicantDate(params: UpdateHiredDateParams) {
  const supabase = createClient();
  const hiredDate = new Date(params.hiredDate);
  const visibleUntil = new Date(
    hiredDate.getFullYear(),
    hiredDate.getMonth(),
    hiredDate.getDate() + 15,
  ).toISOString();

  const { error } = await supabase
    .from("applicants")
    .update({
      hired_date: params.hiredDate,
      hired_visible_until: visibleUntil,
    })
    .eq("id", params.applicantId);

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  return { success: true };
}

export function useUpdateHiredApplicantDate() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateHiredDateParams) =>
      updateHiredApplicantDate(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hired-applicants"] });
    },
  });
}

// ── 7. Fetch Reasons (Backout / Rejection) ───────────────────
export async function fetchBackoutReasons(): Promise<Array<{ id: string; reason: string }>> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("backout_reasons")
    .select("id, reason")
    .eq("is_active", true)
    .order("reason");

  if (error) {
    console.warn("fetchBackoutReasons error:", error.message);
    return [];
  }
  return data ?? [];
}

export async function fetchRejectedReasons(): Promise<Array<{ id: string; reason: string }>> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("rejected_reasons")
    .select("id, reason")
    .eq("is_active", true)
    .order("reason");

  if (error) {
    console.warn("fetchRejectedReasons error:", error.message);
    return [];
  }
  return data ?? [];
}

export async function fetchHiredApplicantsList(vcode?: string) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_hired_applicants", {
    p_vcode: vcode || null,
  });

  if (error) {
    console.warn("fetchHiredApplicants error:", error.message);
    return [];
  }
  return Array.isArray(data) ? data : [];
}

// ── 8. Full Unpaginated Vacancy Dataset Export ──────────────────

/**
 * Updates the effective vacancy date (vacant_date) of a vacancy slot.
 * Triggers reactive aging recalculation across Plantilla, Vacancy, and Dashboard.
 */
export async function updateEffectiveVacancyDate(params: {
  vacancyId?: string | null;
  vcode?: string | null;
  vacantDate: string;
}): Promise<void> {
  const supabase = createClient();
  let query = supabase.from("vacancies").update({
    vacant_date: params.vacantDate,
    updated_at: new Date().toISOString(),
  });

  if (params.vacancyId) {
    query = query.eq("id", params.vacancyId);
  } else if (params.vcode) {
    query = query.eq("vcode", params.vcode);
  } else {
    throw new Error("Vacancy ID or VCode is required to update effective vacancy date.");
  }

  const { error } = await query;
  if (error) {
    throw new Error(error.message || "Failed to update effective vacancy date.");
  }
}

/**
 * React hook mutation to update effective vacancy date and invalidate query caches.
 */
export function useUpdateEffectiveVacancyDate() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: updateEffectiveVacancyDate,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy_detail"] });
    },
  });
}



