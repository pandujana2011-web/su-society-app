
Set-Location 'D:\Clients Applications\SU Society App'
$fname = 'SLICE22_FINAL_SECURITY_PLAN_V2.md'
$bytes = (Get-Item $fname).Length
$lines = (Get-Content $fname).Count
$hash  = (Get-FileHash $fname -Algorithm SHA256).Hash
$fullp = (Get-Item $fname).FullName
Write-Host "File:    $fullp"
Write-Host "Bytes:   $bytes"
Write-Host "Lines:   $lines"
Write-Host "SHA-256: $hash"
