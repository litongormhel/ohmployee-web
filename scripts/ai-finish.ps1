# ============================================================
#  OHMployee Web -- End-of-Task Orchestrator (PowerShell)
#  scripts/ai-finish.ps1
# ============================================================

$ErrorActionPreference = "Continue"

$ROOT = (git rev-parse --show-toplevel 2>&1).Trim()
$PROMPT_ID = if ($env:OHM_PROMPT_ID) { $env:OHM_PROMPT_ID } else { "ohm#w80b681a" }
$env:OHM_PROMPT_ID = $PROMPT_ID

# Set default in-scope untracked files if not already specified
if (-not $env:OHM_SCOPE_FILES) {
    $env:OHM_SCOPE_FILES = "scripts/ai-finish.ps1:src/components/hr-emploc/HrEmplocSavedViewsModal.tsx:src/components/hr-emploc/TagDeficiencyModal.tsx:src/components/hr-emploc/useHrEmplocSavedViews.ts:supabase/migrations/20262606000041_fix_hr_emploc_summary_counter_and_list_hrco.sql"
}

Write-Host "======================================================"
Write-Host "  OHMployee Web -- Task Finish Orchestrator"
Write-Host "  Prompt ID : $PROMPT_ID"
Write-Host "  Root      : $ROOT"
Write-Host "======================================================"

# Execute Node finish script
& node "$ROOT/scripts/finish.js"
$FinishExit = $LASTEXITCODE

if ($FinishExit -ne 0) {
    Write-Host "  [FAIL] Finish orchestrator returned exit code $FinishExit"
    exit $FinishExit
}

exit 0
