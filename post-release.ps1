$tag = $(git describe --tags --abbrev=0).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Failed to get the latest tag."
}
Write-Host "Preparing for tag '$tag'"

$utf8 = New-Object System.Text.UTF8Encoding $false

$bicepPath = Join-Path $PSScriptRoot "bicep/spot-workers.bicep"
Write-Host "Updating $bicepPath"
$bicep = Get-Content $bicepPath -Encoding UTF8 -Raw
$bicep = $bicep -replace "param gitHubReleaseName string = 'v[\d\.]+'", "param gitHubReleaseName string = '$tag'"
[IO.File]::WriteAllText($bicepPath, $bicep, $utf8)

$readmePath = Join-Path $PSScriptRoot "README.md"
Write-Host "Updating $readmePath"
$readme = Get-Content $readmePath -Encoding UTF8 -Raw
$readme = $readme -replace "az-func-vmss%2Fv[\d\.]+\%2Fbicep%2F", "az-func-vmss%2F$tag%2Fbicep%2F"
[IO.File]::WriteAllText($readmePath, $readme, $utf8)

Write-Host "Compiling Bicep to ARM JSON..." -ForegroundColor Green
az bicep build --file (Join-Path $PSScriptRoot "bicep/spot-workers.bicep") --outfile (Join-Path $PSScriptRoot "artifacts/spot-workers.deploymentTemplate.json") --verbose
if ($LASTEXITCODE -ne 0) {
    throw "Failed to compile the template."
}
