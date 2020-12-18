<#
    .SYNOPSIS
        Script to set the Redis connection string in the corresponding Azure KeyVault secret.

    .DESCRIPTION
        As described in step 19 of https://www.robhabraken.nl/index.php/3653/paas-to-aks-an-overview/,
        the process of provisioning a new AKS cluster for a Sitecore K8s deployment requires
        setting the Redis connection string after the creation of the corresponding AKV secret.
        This script retrieves the primary key from the Redis cache to form a connection string
        and updates the corresponding KeyVault secret with the correct value.

    .PARAMETER ResourceGroupName
        Name of the Resource Group that contains the Redis cache.

    .PARAMETER RedisCacheName
        Name of the Redis cache resource (optional).

    .PARAMETER VaultName
        Name of the Azure KeyVault instance containing the secret to update.
#>

[CmdletBinding()]
Param (

    # Name of the Resource Group that contains the Redis cache
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ResourceGroupName,
    
    # Name of the Redis cache resource (optional)
    [ValidateNotNullOrEmpty()]
    [string] $RedisCacheName,

    # Name of the Azure KeyVault instance containing the secret to update
    [Parameter(Mandatory)]
    [string] $VaultName
)

Write-Host 'Constructing Redis connection string...'

# if Redis cache name is not provided, deduce from resource group name, based on default ARM naming convention
if ($RedisCacheName -eq '') {

    $RedisCacheName = "$ResourceGroup-redis"

}

# retrieve primary key from Redis cache instance
$PrimaryKey = az redis list-keys --name $RedisCacheName --resource-group $ResourceGroupName --query primaryKey --output tsv

# build up Redis connection string based on name and (primary) key
$RedisConnectionString = "$RedisCacheName.redis.cache.windows.net:6380,password=$PrimaryKey,ssl=True,abortConnect=False"

Write-Host $RedisConnectionString
Write-Host

Write-Host 'Update Key Vault with retrieved connection string...'

# update corresponding Azure Key Vault secret with retrieved connection string
az keyvault secret set --name 'sitecore-redis-connection-string' --vault-name $VaultName --value $RedisConnectionString

Write-Host 'Key Vault secret updated with Redis connection string value'