param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $AksName,
    
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $AcrName
)

# link AKS to ACR
Write-Host "--- Linking AKS to ACR ---" -ForegroundColor Cyan

$clientID = $(az aks show --resource-group $ResourceGroupName --name $AksName --query "servicePrincipalProfile.clientId" --output tsv)
$acrId = $(az acr show --name $AcrName --resource-group $ResourceGroupName --query "id" --output tsv)
az role assignment create --assignee $clientID --role acrpull --scope $acrId

Write-Host "--- Complete: AKS & ACR Linked ---" -ForegroundColor Green