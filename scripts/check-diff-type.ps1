Set-Location "C:\Users\dcoop\multi-ai-collab-fix"
$d = gh pr diff 1
Write-Host "Type: $($d.GetType().Name)"
Write-Host "IsArray: $($d -is [array])"
if ($d -is [array]) {
    Write-Host "Elements: $($d.Count)"
    Write-Host "Total chars: $(($d -join '').Length)"
} else {
    Write-Host "Length: $($d.Length)"
}
