# ============================================================
#  OHMployee Web -- End-of-Task Orchestrator (PowerShell)
#  scripts/ai-finish.ps1
# ============================================================

$ErrorActionPreference = "Continue"

$ROOT = (git rev-parse --show-toplevel 2>&1).Trim()
$PROMPT_ID = if ($env:OHM_PROMPT_ID) { $env:OHM_PROMPT_ID } else { "ohm#w22a913d" }
$env:OHM_PROMPT_ID = $PROMPT_ID

# Set default in-scope untracked files if not already specified
if (-not $env:OHM_SCOPE_FILES) {
    $env:OHM_SCOPE_FILES = "src/components/vacancy/AddApplicantModal.tsx:src/components/modals/AddApplicantModal.tsx:src/components/vacancy/AdvancePipelineModal.tsx:src/components/vacancy/MarkHiredModal.tsx:src/components/vacancy/FailBackoutModal.tsx:src/components/vacancy/ReopenVacancyModal.tsx:src/components/vacancy/RequestVacancyClosureModal.tsx:src/components/vacancy/EditHiredDateModal.tsx:scripts/ai-finish.ps1"
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
