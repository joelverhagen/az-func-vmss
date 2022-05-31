[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$RuntimeIdentifier = "win-x64"
)

Write-Host "Building the Azure Functions host..." -ForegroundColor Green
& (Join-Path $PSScriptRoot "scripts/Build-Host.ps1") -RuntimeIdentifier $RuntimeIdentifier

Write-Host "Building the app..." -ForegroundColor Green
dotnet publish (Join-Path $PSScriptRoot "app") --configuration Release --runtime $RuntimeIdentifier --self-contained false
if ($LASTEXITCODE -ne 0) {
    throw "Failed to publish the app."
}

Write-Host "Copying deployment scripts..." -ForegroundColor Green
Copy-Item (Join-Path $PSScriptRoot "scripts/Set-DeploymentFiles.ps1") (Join-Path $PSScriptRoot "artifacts/Set-DeploymentFiles.ps1") -Verbose
Copy-Item (Join-Path $PSScriptRoot "scripts/Install-Standalone.ps1") (Join-Path $PSScriptRoot "artifacts/Install-Standalone.ps1") -Verbose