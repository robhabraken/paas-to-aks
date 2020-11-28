param (
    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string] $location,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string] $templateFile,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string] $templateParameterFile,

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string] $deploymentId,

    [Parameter(Mandatory=$False)]
    [ValidateNotNullOrEmpty()]
    [string] $storageAccountNameAfterPrefix = "armsolrlrs"
)

# check if resource group already exists, create one if not
Write-Host "Check if resource group already exists..."
$notPresent = Get-AzResourceGroup -Name $resourceGroupName -ev notPresent -ea 0;
  
if (!$notPresent) {
    Write-Host "Create resource group"
    New-AzResourceGroup -Name $resourceGroupName -Location $location;
}

# upload scripts & templates
$optionalParameters = New-Object -TypeName Hashtable
Set-Variable ArtifactsLocationName '_artifactsLocation' -Option ReadOnly -Force
Set-Variable ArtifactsLocationSasTokenName '_artifactsLocationSasToken' -Option ReadOnly -Force

$optionalParameters.Add($artifactsLocationName, $null)
$optionalParameters.Add($artifactsLocationSasTokenName, $null)

$currentPath = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($currentPath)) {
    $currentPath = (Get-Location).Path 
}

$storageContainerName= "armdeploy"

$storageAccountName = $deploymentId + $storageAccountNameAfterPrefix

if ($storageAccountName.length -gt 24) {
    $storageAccountName = $storageAccountName.Substring(0, 24)
}

$storageAccountName = $storageAccountName.ToLower();
$storageAccountName = $storageAccountName -replace '[\W]', ''

$storageAccount = (Get-AzStorageAccount | Where-Object{$_.StorageAccountName -eq $storageAccountName})

# create the storage account if it doesn't already exist
$stacc = Get-AzStorageAccount -Name $storageAccountName -resourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

if (-not $stacc) {

    New-AzStorageAccount -StorageAccountName $storageAccountName -Type 'Standard_LRS' -resourceGroupName $resourceGroupName -Location "$location"

    $StorageAccount = (Get-AzStorageAccount | Where-Object{$_.StorageAccountName -eq $storageAccountName})
    Write-Output "New Storage Account deployed: $storageAccountName"   

} else {

    Write-Output "Storage Account found: $storageAccountName"

}

$storageAccountKey = get-AzStorageAccountKey -resourceGroupName $resourceGroupName -Name $storageAccount.StorageAccountName
$storageAccountContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey.Item(0).Value 

# copy files from the local storage staging location to the storage account container
New-AzStorageContainer -Name $storageContainerName -Context $storageAccountContext -ErrorAction SilentlyContinue *>&1

$artifactFilePaths = Get-ChildItem $currentPath -Recurse -File -Exclude "*.ps1" | ForEach-Object -Process {$_.FullName} 
foreach ($sourcePath in $artifactFilePaths) {

    $BlobName = $SourcePath.Substring($CurrentPath.length + 1)
    Set-AzStorageBlobContent -File $sourcePath -Blob $blobName -Container $storageContainerName -Context $storageAccountContext -Force -ErrorAction Stop

}

# generate the value for artifacts location SAS token if it is not provided in the parameter file
$artifactsLocationSasToken = $optionalParameters[$artifactsLocationSasTokenName]
if ($null -eq $artifactsLocationSasToken) {

    # create a SAS token for the storage container - this gives temporary read-only access to the container
    $artifactsLocationSasToken = New-AzStorageContainerSASToken -Container $StorageContainerName -Context $storageAccountContext -Permission r -ExpiryTime (Get-Date).AddHours(2)
    $optionalParameters[$artifactsLocationSasTokenName] = $artifactsLocationSasToken

}

$baseUrl  = $storageAccount.PrimaryEndpoints.Blob + "$storageContainerName/"
$sasToken = $optionalParameters.Values

Write-Host $templatefile

New-AzResourceGroupDeployment -verbose `
                              -name "SOLR" `
                              -resourceGroupName $resourceGroupName `
                              -deploymentId $deploymentId `
                              -baseUrl $baseUrl `
                              -sasToken $sasToken `
                              -templateFile $templateFile `
                              -templateParameterFile $templateParameterFile

$getRGDeploy = Get-AzResourceGroupDeployment -resourceGroupName $resourceGroupName -Name "SOLR"

$outputParameterServerName = $getRgDeploy.Outputs.serverName.Value

$serverName = $null;
if ($null -eq $outputParameterServerName) {

    throw "No Parameter for ServerName found";

} else {

    $serverName = $outputParameterServerName

}

Write-Host "Restarting deployed VM"

Get-AzVm -resourceGroupName $resourceGroupName -Name $serverName  | Restart-AzVM
									   
