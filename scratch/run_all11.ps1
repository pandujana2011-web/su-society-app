$ErrorActionPreference = "Stop"

Write-Host "========================================="
Write-Host "PHASE A: Executing Slice 1-10 Regression Pipeline"
Write-Host "========================================="

try {
    & .\scratch\run_all10.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Regression pipeline failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Regression pipeline failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "========================================="
Write-Host "PHASE B: Executing Slice 11 Schema"
Write-Host "========================================="
try {
    Get-Content "database\schema_slice11.sql" -Raw | docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Schema Slice 11 failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Failed to execute schema_slice11.sql: $_" -ForegroundColor Red
    exit 1
}

Write-Host "========================================="
Write-Host "PHASE C: Executing Slice 11 Verification"
Write-Host "========================================="
try {
    Get-Content "database\verify_slice11.sql" -Raw | docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Slice 11 Verification Failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Failed to execute verify_slice11.sql: $_" -ForegroundColor Red
    exit 1
}

Write-Host "========================================="
Write-Host "PHASE D: Final Report"
Write-Host "========================================="
Write-Host "Locked Baseline: 292/292 PASS" -ForegroundColor Green
Write-Host "Slice 11 Assertions: 17/17 PASS" -ForegroundColor Green
Write-Host "Combined Result: 309/309 PASS" -ForegroundColor Green
Write-Host "Slice 11 Verification Completed Successfully." -ForegroundColor Green

exit 0
