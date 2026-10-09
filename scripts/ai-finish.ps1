# ============================================================
#  OHMployee Web -- End-of-Task Orchestrator (PowerShell)
#  scripts/ai-finish.ps1
# ============================================================

$ErrorActionPreference = "Continue"

$ROOT = (git rev-parse --show-toplevel 2>&1).Trim()
$PROMPT_ID = if ($env:OHM_PROMPT_ID) { $env:OHM_PROMPT_ID } else { "ohm#w11b702e" }
$env:OHM_PROMPT_ID = $PROMPT_ID

# Set default in-scope untracked files if not already specified
if (-not $env:OHM_SCOPE_FILES) {
    $env:OHM_SCOPE_FILES = "docs/audit/:scripts/ai-finish.ps1:docs/audit/baseline_audit_architecture_theme_modules_2026-10-09.md:docs/audit/adr001_plantilla_account_gate_2026-07-11.md:docs/audit/web_mobile_parity_2026-07-11.md"
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
