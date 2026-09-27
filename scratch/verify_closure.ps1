
# Read-only verification script — modifies NO file
Set-Location 'D:\Clients Applications\SU Society App'

$fname = 'SLICE21_HASH_DISCREPANCY_GOVERNANCE_CLOSURE_OPTION_A.md'
$item  = Get-Item $fname
$bytes = [System.IO.File]::ReadAllBytes($fname)
$hash  = (Get-FileHash $fname -Algorithm SHA256).Hash
$hasBOM    = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$crCount   = ($bytes | Where-Object { $_ -eq 13 }).Count
$lfCount   = ($bytes | Where-Object { $_ -eq 10 }).Count
$lastByte  = $bytes[$bytes.Length - 1]
$lineCount = (Get-Content $fname).Count

Write-Host "AbsolutePath : $($item.FullName)"
Write-Host "Bytes        : $($bytes.Length)"
Write-Host "LineCount    : $lineCount"
Write-Host "SHA-256      : $hash"
Write-Host "BOM(UTF8)    : $hasBOM"
Write-Host "CR_count     : $crCount"
Write-Host "LF_count     : $lfCount"
Write-Host "LastByte_dec : $lastByte  (10=LF)"
