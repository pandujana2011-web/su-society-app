$ErrorActionPreference = "Stop"

$files = @(
    "database\schema_slice1.sql",
    "database\schema_slice2.sql",
    "database\schema_slice3.sql",
    "database\schema_slice4.sql",
    "database\verify_slice1.sql",
    "database\verify_slice2.sql",
    "database\verify_slice3.sql",
    "database\verify_slice4.sql"
)

foreach ($file in $files) {
    Write-Host "========================================="
    Write-Host "Running: $file"
    Write-Host "========================================="
    Get-Content $file -Raw | docker exec -i supabase_db_SU_Society_App psql -U postgres -d postgres
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: $file failed with exit code $LASTEXITCODE"
        exit 1
    }
}

Write-Host "Done."
