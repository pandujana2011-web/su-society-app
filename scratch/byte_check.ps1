
# READ-ONLY byte analysis script — does not modify any locked file
Set-Location 'D:\Clients Applications\SU Society App'

$files = @(
    'SLICE21_FINAL_SECURITY_PLAN.md',
    'SLICE21_FINAL_FORENSIC_SECURITY_PLAN_REVISION_10.1.md',
    'SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN.md',
    'SLICE21_FINAL_PRE_IMPLEMENTATION_FORENSIC_SECURITY_PLAN_REVISION.md',
    'SLICE21_SECURITY_LOCK.md'
)

foreach ($fname in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($fname)
    $hasBOM = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $crCount = ($bytes | Where-Object { $_ -eq 13 }).Count
    $lfCount = ($bytes | Where-Object { $_ -eq 10 }).Count
    $lastByte = $bytes[$bytes.Length - 1]
    $hash = (Get-FileHash $fname -Algorithm SHA256).Hash
    Write-Host "--- $fname ---"
    Write-Host "  Bytes:     $($bytes.Length)"
    Write-Host "  SHA-256:   $hash"
    Write-Host "  BOM(UTF8): $hasBOM"
    Write-Host "  CR count:  $crCount"
    Write-Host "  LF count:  $lfCount"
    Write-Host "  LastByte:  $lastByte (10=LF, 13=CR)"
    Write-Host ""
}
