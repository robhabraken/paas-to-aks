param (
    [Parameter()]
    [string] $location,

    [Parameter()]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string] $templateFile,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string] $templateParameterFile,

    [Parameter()]
    [string] $deploymentId,

    [Parameter()]
    [string] $keyVaultName
)  

Install-Module -Name Az.ManagedServiceIdentity -Force

# check if resource group already exists, create one if not
Write-Host "Check if resource group already exists..."
$notPresent = Get-AzResourceGroup -Name $resourceGroupName -ev notPresent -ea 0;
  
if (!$notPresent) {
    Write-Host "Create resource group"
    New-AzResourceGroup -Name $resourceGroupName -Location $location;
}
 
# check if the managed identity exists, create one if not
$managedIdentity = Get-AzUserAssignedIdentity -ResourceGroupName $resourceGroupName | Where-Object { $_.name -eq "$deploymentId-managed-identity" }
  
if (!$managedIdentity) {
    Write-Host "Creating Managed Identity"
 
    try {
     
        New-AzUserAssignedIdentity -ResourceGroupName $resourceGroupName -Name "$deploymentId-managed-identity"
        $managedIdentity = Get-AzUserAssignedIdentity -ResourceGroupName $resourceGroupName | Where-Object { $_.name -eq "$deploymentId-managed-identity" }
 
    } catch {
 
        write-error $_.Exception.Message;
        Break;
 
    }
} else {
  
    Write-Host "Managed Identity already exists"
  
}
  
$managedIdentityPrincipalId = $managedIdentity.PrincipalId
$managedIdentityClientId = $managedIdentity.ClientId
$managedIdentityName = $managedIdentity.Name
  
Write-Host `n"Name": $managedIdentityName `n"PrincipalId": $managedIdentityPrincipalId `n"ClientId": $managedIdentityClientId `n
 
# with the managed identity present, a keyvault can now be created
# check if a keyvault with this name already exists, if not try to create one
if (!$keyvaultName) {

    $keyVaultName = "$deploymentId-keyvault"

} else {

    $keyvaultName = "$deploymentId-$keyVaultName"
}

$getKeyVault = Get-AzKeyVault -ResourceGroupName $resourceGroupName -VaultName $keyvaultName -ErrorAction SilentlyContinue
 
if (!$getKeyVault) {
 
    try {

        Write-Host "Start KeyVault creation"

        if(!$ArmParametersPath){
            New-AzResourceGroupDeployment   -verbose `
            -Name "KeyVault" `
            -deploymentId $deploymentId `
            -ResourceGroupName $resourceGroupName `
            -TemplateFile $ArmTemplatePath `
            -managedIdentityPrincipalId $managedIdentityPrincipalId
        } else {

            New-AzResourceGroupDeployment   -verbose `
            -Name "KeyVault" `
            -deploymentId $deploymentId `
            -ResourceGroupName $resourceGroupName `
            -TemplateFile $ArmTemplatePath `
            -TemplateParameterFile $ArmParametersPath `
            -managedIdentityPrincipalId $managedIdentityPrincipalId
        }

                                     
        Write-Host "KeyVault created"
 
    }
    catch {
 
        write-error $_.Exception.Message;
        Break;
    }
}
else {
 
    Write-Host "KeyVault already exists"
 
}
 
# set management permissions for the current account
try {
 
    write-host "Trying to set permissions for the current account"
    $AzContext = Get-AzContext
 
    Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName `
        -UserPrincipalName $azContext.Account `
        -PermissionsToCertificates get, list, delete, create, import, update, managecontacts, getissuers, listissuers, setissuers, deleteissuers, manageissuers, recover, purge, backup, restore `
        -PermissionsToKeys decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, import, delete, backup, restore, recover, purge `
        -PermissionsToSecrets get, list, set, delete, backup, restore, recover, purge
 
    write-host "setting permissions succesful"
 
}
catch {
 
    Write-Warning $_.Exception.Message;
    Write-Warning "Add yourself manually to the keyvault's access policies"
    Break;
 
}