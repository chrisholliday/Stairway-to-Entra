```powershell
param(
    [string]$AppName = "stairway-entra-app-001",    # must be globally unique
    [string]$ResourceGroup = "stairway-entra-rg",
    [string]$Location = "eastus",
    [string]$KeyVaultName = "<your-key-vault-name>",
    [string]$SecretName = "AzureAdClientSecret",
    [string]$TenantId = "<your-tenant-id>",
    [string]$ClientId = "<your-client-id>",
    [string]$Domain = "<your-domain>"
)

# Prerequisites: Install-Module Az, run Connect-AzAccount before executing this script.

Write-Host "1. Ensure logged in..."
# Connect-AzAccount # uncomment if not already connected

Write-Host "2. Creating Resource Group (if not exists)..."
if (-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroup -Location $Location | Out-Null
}

Write-Host "3. Creating App Service Plan (Linux, B1)..."
$planName = "$AppName-plan"
if (-not (Get-AzAppServicePlan -Name $planName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzAppServicePlan -Name $planName -ResourceGroupName $ResourceGroup -Location $Location -Tier "Basic" -NumberOfWorkers 1 -WorkerSize Small -Linux | Out-Null
}

Write-Host "4. Creating Web App (if not exists)..."
$webApp = Get-AzWebApp -Name $AppName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
if (-not $webApp) {
    $webApp = New-AzWebApp -Name $AppName -ResourceGroupName $ResourceGroup -Location $Location -AppServicePlan $planName -Runtime "DOTNET|6.0"
}

Write-Host "5. Setting Application Settings (including Key Vault reference)..."
$appSettings = @{
    "AzureAd__Instance"              = "https://login.microsoftonline.com/"
    "AzureAd__Domain"                = $Domain
    "AzureAd__TenantId"              = $TenantId
    "AzureAd__ClientId"              = $ClientId
    "AzureAd__CallbackPath"          = "/signin-oidc"
    "AzureAd__SignedOutCallbackPath" = "/signout-callback-oidc"
    "AzureAd__ClientSecret"          = "@Microsoft.KeyVault(SecretUri=https://$KeyVaultName.vault.azure.net/secrets/$SecretName/)"
}

# Merge with existing settings to avoid wiping others
$current = (Get-AzWebApp -ResourceGroupName $ResourceGroup -Name $AppName)
$existingSettings = @{}
if ($current.SiteConfig.AppSettings) {
    foreach ($s in $current.SiteConfig.AppSettings) { $existingSettings[$s.Name] = $s.Value }
}
foreach ($k in $appSettings.Keys) { $existingSettings[$k] = $appSettings[$k] }

Set-AzWebApp -ResourceGroupName $ResourceGroup -Name $AppName -AppSettings $existingSettings

Write-Host "6. Enabling System Assigned Managed Identity..."
$webApp = Set-AzWebApp -Name $AppName -ResourceGroupName $ResourceGroup -AssignIdentity $true

Write-Host "7. Granting Key Vault access to managed identity..."
$principalId = $webApp.Identity.PrincipalId
if (-not $principalId) {
    Write-Error "Failed to obtain managed identity principalId."
} else {
    Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ObjectId $principalId -PermissionsToSecrets get,list -ErrorAction Stop
}

Write-Host "8. Building and publishing application..."
dotnet publish -c Release -o ./publish
if (Test-Path ./publish.zip) { Remove-Item ./publish.zip -Force }
Compress-Archive -Path "./publish/*" -DestinationPath "./publish.zip" -Force

Write-Host "9. Deploying zip to Web App..."
Publish-AzWebApp -ResourceGroupName $ResourceGroup -Name $AppName -ArchivePath "./publish.zip"

Write-Host "Deployment and configuration complete."
```
