<#
    .SYNOPSIS
        Lifts Kubernetes secrets to an Azure KeyVault instance to keep them out of your repository.

    .DESCRIPTION
        Steps to perform before running this script:
        - Run ./scripts/compress-license-file.ps1 to compress the license file and to populate the relevant secret file.
        - Run ./scripts/create-identity-signing-certificate.ps1 to generate a self-signed certificate and to populate the relevant
            secret file and use the same certificate password for this script.
        - Run ./scripts/create-tls-https-certificates.bat in an elevated Command Prompt to generate the self-signed certificates
            required for the NGINX ingress controller.
        - Configure the Solr connection strings in 'sitecore-solr-connection-string.txt' and 'sitecore-solr-connection-string-xdb.txt'
            manually based on your External Data Services Solr installation.
        - Optional: you can manually populate some or all password (and username) files with specific secrets; if you opt for this,
            this script will lift them to the Azure KeyVault instance - if not, this script will auto-generate appropriate secret values.

    .PARAMETER VaultName
        Name of the Azure KeyVault instance to populate.

    .PARAMETER IdentityCertificatePassword
        Certificate password used for the Sitecore Identity Signing certificate.

    .PARAMETER DefaultSecretLength
        Default secret length for auto-generated secret values.

    .PARAMETER SecretsFolder
        Relative location of folder containing Kubernetes secret files.

    .NOTES
        Written by Rob Habraken under the MIT License
        Check https://github.com/robhabraken/paas-to-aks for updated versions of this script

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
#>

[CmdletBinding()]
Param (
    # Name of the Azure KeyVault instance to populate
    [Parameter(Mandatory)]
    [string] $VaultName,
    # Certificate password used for the Sitecore Identity Signing certificate
    [Parameter(Mandatory)]
    [string] $IdentityCertificatePassword,
    # Default secret length for auto-generated secret values
    [string] $DefaultSecretLength = 20,
    # Relative location of folder containing Kubernetes secret files
    [string] $SecretsFolder = '..\..\sitecore\k8s\xp1\secrets\'
)

# install module to be able to parse yaml files
Install-Module powershell-yaml
Import-Module powershell-yaml

# reads the contents of a file and returns them in a line separated string value
Function Read-File {
	
	[CmdletBinding()]
	Param (
        [string] $filename
	)

	Begin {
	}

	Process {
        
        $content = ''
        $newLine = ''
        [string[]]$fileContent = Get-Content $filename
        foreach ($line in $fileContent) {
            $content = $content + $newLine + $line
            $newLine = "`n"
        }

        Write-Output $content
	}	
}

# generates a random alphanumeric string of the given length
Function Get-RandomAlphanumericString {
	
	[CmdletBinding()]
	Param (
        [int] $length = 8
	)

	Begin {
	}

	Process {
        Write-Output ( -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count $length  | % {[char]$_}) )
	}	
}

# constructs a keyvault entry based on either the available or an auto-generated value
# and also populates the relevant secret file with a reference to said keyvault entry
Function Construct-KeyVaultReference {
	
	[CmdletBinding()]
	Param (
        [string] $filename
	)

	Begin {
	}

	Process {

        Write-Host 'Constructing key vault reference...'

        # define path and secret name / reference
        $fullPath = $SecretsFolder + $filename
        $secretName = $filename -replace '.txt', ''
        $reference = '$('+ $secretName + ')'

        # bump secrets to length of 64 as per Sitecore installation guide
        $secretLength = $DefaultSecretLength
        if ($secretName -like '*telerik*' -or `
            $secretName -like '*identitysecret*' -or `
            $secretName -like '*reportingapikey*') {
            $secretLength = 64
        }

        # generate random secret value
        $value = Get-RandomAlphanumericString -length $secretLength

        # non-empty original value overrides random value
        # this is specifically relevant for (default) usernames, connection strings, certificates and the license file
        # this also works for manually pre-filled secrets, it lifts them to the key vault
        $originalSecretValue = Read-File $fullPath
        if (-not ($originalSecretValue -eq '')) {
            $value = $originalSecretValue
        }

        # set the identity certificate password to the given value (input parameter)
        if ($secretName -eq 'sitecore-identitycertificatepassword') {
            $value = $IdentityCertificatePassword
        }

        # skip license file (too long for command line and tolerated in code repository)
        if ($secretName -eq 'sitecore-license') {
            Write-Host 'Skipping license file'
            Write-Host
            return;
        }

        # generate key vault secret
        az keyvault secret set --name $secretName --vault-name $VaultName --value $value

        # store reference key in secret file
        Set-Content -Path $fullPath -Value $reference

        # verbose output
        Write-Host 'Filename    : '$filename
        Write-Host 'Full path   : '$fullPath
        Write-Host 'Secret name : '$secretName
        Write-Host 'Reference   : '$reference
        Write-Host 'Value       : '$value
        Write-Host
	}	
}

# adds the required keyvault entries for Solr, using an auto-generated secret value as password
Function Add-SolrCredentials {
	
	[CmdletBinding()]
	Param (
	)

	Begin {
	}

	Process {

        Write-Host 'Add Solr credential secrets to key vault...'

        # generate random secret value
        $solrAdminPassword = Get-RandomAlphanumericString -length $DefaultSecretLength

        # generate key vault secret
        az keyvault secret set --name 'sitecore-solr-admin-username' --vault-name $VaultName --value 'solrAdmin'
        az keyvault secret set --name 'sitecore-solr-admin-password' --vault-name $VaultName --value $solrAdminPassword

        Write-Host
	}	
}


# read kustomization yaml file from file system into memory
$kustomization = Read-File -filename $SecretsFolder'kustomization.yaml'

# parse yaml file and retrieve secret definitions
$yaml = ConvertFrom-YAML $kustomization
$secretDefinitions = $yaml['secretGenerator']

# loop through key value pairs (alternating between 'name' and 'files')
foreach ($hashTable in $secretDefinitions) {

    # loop through all keys of the current hashtable (usually only one, eiter 'name' or 'files')
    foreach ($key in $hashTable.Keys) {

        # only parse file lists (value contains an array)
        if ($key -eq 'files') {

            $files = $hashTable.$key
            foreach ($fileName in $files) {

                # skip tls certificate files by filtering on 'txt' extension
                if ($fileName -like '*.txt*') {

                    # generate key vault secret and reference from file
                    Construct-KeyVaultReference -filename $fileName

                }
            }
        }
    }
}

# automatically add the required Key Vault secrets for the Solr Cloud instance
Add-SolrCredentials