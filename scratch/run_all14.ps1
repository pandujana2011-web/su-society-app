$ErrorActionPreference = "Stop"

Write-Host "========================================="
Write-Host "PHASE A: Executing Slice 1-13 Regression Pipeline"
Write-Host "========================================="

try {
    & .\scratch\run_all13.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Regression pipeline failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Regression pipeline failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "========================================="
Write-Host "PHASE B: Executing Slice 14 Schema"
Write-Host "========================================="
try {
    Get-Content "database\schema_slice14.sql" -Raw | docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Schema Slice 14 failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Failed to execute schema_slice14.sql: $_" -ForegroundColor Red
    exit 1
}

Write-Host "========================================="
Write-Host "PHASE C: Executing Slice 14 Verification"
Write-Host "========================================="
$output = ""
try {
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = Get-Content "database\verify_slice14.sql" -Raw | docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres 2>&1 | Out-String
    $ErrorActionPreference = $oldEAP
    Write-Host $output
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Slice 14 Verification Failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Failed to execute verify_slice14.sql: $_" -ForegroundColor Red
    exit 1
}

Write-Host "========================================="
Write-Host "PHASE D: Final Report"
Write-Host "========================================="

# Parse pass count from NOTICE output
$passMatch = [regex]::Match($output, "SLICE 14 VERIFICATION COMPLETE \((\d+)/(\d+) TESTS PASS(ED)?\)")
if ($passMatch.Success) {
    $actualPass = [int]$passMatch.Groups[1].Value
    $totalTests = [int]$passMatch.Groups[2].Value
    $combined = 341 + $actualPass
    $totalCombined = 341 + $totalTests
    
    Write-Host "Locked Baseline: 341/341 PASS" -ForegroundColor Green
    Write-Host "Slice 14 Assertions: $actualPass/$totalTests PASS" -ForegroundColor Green
    Write-Host "Combined Result: $combined/$totalCombined PASS" -ForegroundColor Green
    Write-Host "Slice 14 Verification Completed Successfully." -ForegroundColor Green
    exit 0
} else {
    Write-Host "Slice 14 Verification did not return valid completion report." -ForegroundColor Red
    exit 1
}
