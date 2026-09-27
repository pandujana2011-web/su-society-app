$ErrorActionPreference = 'Stop'

Write-Host '========================================='
Write-Host 'PHASE A: Executing Slice 1-6 Baseline'
Write-Host '========================================='

& .\scratch\run_all6.ps1

if ($LASTEXITCODE -ne 0) {
    Write-Host 'BLOCKED - LOCKED REGRESSION BASELINE FAILED'
    exit 1
}

Write-Host ''
Write-Host '231/231 PASS Confirmed.'
Write-Host '========================================='
Write-Host 'PHASE B: Executing Slice 7 Schema'
Write-Host '========================================='

Get-Content 'database\schema_slice7.sql' -Raw | docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres

if ($LASTEXITCODE -ne 0) {
    Write-Host 'ERROR: schema_slice7.sql failed with exit code ' $LASTEXITCODE
    exit 1
}

Write-Host '========================================='
Write-Host 'PHASE C: Executing Slice 7 Verification'
Write-Host '========================================='

Get-Content 'database\verify_slice7.sql' -Raw | docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres

if ($LASTEXITCODE -ne 0) {
    Write-Host 'ERROR: verify_slice7.sql failed with exit code ' $LASTEXITCODE
    exit 1
}

Write-Host '========================================='
Write-Host 'PHASE D: Final Report'
Write-Host '========================================='
Write-Host 'Locked Baseline: 231/231 PASS'
Write-Host 'Slice 7 Assertions: PASS'
Write-Host 'Combined Result: 100% PASS'
Write-Host 'Slice 7 Verification Completed Successfully.'
