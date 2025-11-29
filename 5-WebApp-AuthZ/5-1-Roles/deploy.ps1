# Usage: ./deploy.ps1
# Ensure you are logged in with `Connect-AzAccount`

# --- Configuration ---
$appName = "stairwaytoentra" # Must be globally unique
$resourceGroup = "chris.holliday"
$location = "Central US"
$keyeyVaultName = "kv-cjh1"
$secretName = "AzureAdClientSecret"

# App Registration Details
$tenantId = "52e96e4e-8181-4e47-ae61-1a769a2fcfd1"
$clientId = "66449a5f-f702-4d33-afe6-7067b19e0b47"
$domain = "azuresmith.onmicrosoft.com"

# --- Deployment ---
<#
Write-Host "1. Creating Resource Group..."
New-AzResourceGroup -Name $resourceGroup -Location $location -Force

Write-Host "2. Creating App Service Plan (Linux)..."
New-AzAppServicePlan -Name "$appName-plan" -ResourceGroupName $resourceGroup -Location $location -Tier Basic -WorkerSize Small -Linux

Write-Host "3. Creating Web App..."
$webApp = New-AzWebApp -Name $appName -ResourceGroupName $resourceGroup -Location $location -AppServicePlan "$appName-plan"
#>
Write-Host "4. Configuring Application Settings..."
# Define the settings hash table
$appSettings = @{
    "AzureAd__Instance"              = "https://login.microsoftonline.com/"
    "AzureAd__Domain"                = $domain
    "AzureAd__TenantId"              = $tenantId
    "AzureAd__ClientId"              = $clientId
    "AzureAd__CallbackPath"          = "/signin-oidc"
    "AzureAd__SignedOutCallbackPath" = "/signout-callback-oidc"
    "AzureAd__ClientSecret"          = "@Microsoft.KeyVault(SecretUri=https://kv-cjh1.vault.azure.net/secrets/ClientSecret/65ff5cb5b16e4c93accbad322e8534cc)"
}

# Merge with existing settings to avoid overwriting defaults
$current = Get-AzWebApp -Name $appName -ResourceGroupName $resourceGroup

# Convert existing SiteConfig.AppSettings (array of Name/Value) to a hashtable
$Settings = @{}
if ($current.SiteConfig.AppSettings) {
    foreach ($s in $current.SiteConfig.AppSettings) {
        $Settings[$s.Name] = $s.Value
    }
}

# Merge/override with our desired settings
foreach ($key in $appSettings.Keys) {
    $Settings[$key] = $appSettings[$key]
}

# Pass a hashtable to -AppSettings
Set-AzWebApp -ResourceGroupName $resourceGroup -Name $appName -AppSettings $Settings

<#
Write-Host "5. Enabling Managed Identity..."
$webApp = Set-AzWebApp -Name $appName -ResourceGroupName $resourceGroup -AssignIdentity $true

Write-Host "6. Granting Key Vault Access..."
$principalId = $webApp.Identity.PrincipalId
Set-AzKeyVaultAccessPolicy -VaultName $keyeyVaultName -ObjectId $principalId -PermissionsToSecrets get,list
#>

Write-Host "7. Publishing Application..."
# Build and Publish locally, then zip and upload
dotnet publish -c Release -o ./publish
Compress-Archive -Path ./publish/* -DestinationPath ./publish.zip -Force
Publish-AzWebApp -ResourceGroupName $resourceGroup -Name $appName -ArchivePath ./publish.zip

Write-Host "Deployment Complete!"
