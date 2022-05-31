[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$RuntimeIdentifier
)

Write-Host "Building the Azure Functions host..." -ForegroundColor Green
& (Join-Path $PSScriptRoot "scripts/Build-Host.ps1") -RuntimeIdentifier $RuntimeIdentifier

Write-Host "Building the app..." -ForegroundColor Green
dotnet publish (Join-Path $PSScriptRoot "app") --configuration Release --runtime $RuntimeIdentifier --self-contained false
if ($LASTEXITCODE -ne 0) {
    throw "Failed to publish the app."
}

Write-Host "Copying deployment files..." -ForegroundColor Green
Copy-Item (Join-Path $PSScriptRoot "app/example-config.env") (Join-Path $PSScriptRoot "artifacts/example-config.env") -Verbose
Copy-Item (Join-Path $PSScriptRoot "scripts/Set-DeploymentFiles.ps1") (Join-Path $PSScriptRoot "artifacts/Set-DeploymentFiles.ps1") -Verbose
Copy-Item (Join-Path $PSScriptRoot "scripts/Install-Standalone.ps1") (Join-Path $PSScriptRoot "artifacts/Install-Standalone.ps1") -Verbose

Write-Host "Compiling Bicep to ARM JSON..." -ForegroundColor Green
az bicep build --file (Join-Path $PSScriptRoot "bicep/spot-workers.bicep") --outfile (Join-Path $PSScriptRoot "artifacts/spot-workers.deploymentTemplate.json") --verbose
if ($LASTEXITCODE -ne 0) {
    throw "Failed to compile the template."
}
