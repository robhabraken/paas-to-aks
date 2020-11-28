[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [string] $Topology,

    [Parameter(Mandatory)]
    [string] $CertificatePassword
)

# retrieve the current script path and configure certificate path
$scriptPath = Split-Path $MyInvocation.MyCommand.Path
$certificatePath = "$scriptPath\..\resources\SitecoreIdentityTokenSigning-$Topology.pfx"

# generate self signed certificate
$newCert = New-SelfSignedCertificate -DnsName "localhost" -FriendlyName "Sitecore Identity Token Signing" -NotAfter (Get-Date).AddYears(5)
Export-PfxCertificate -Cert $newCert -FilePath $certificatePath -Password (ConvertTo-SecureString -String $CertificatePassword -Force -AsPlainText)

# convert certificate to base64 and output to k8s secrets
[System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Get-Item $certificatePath))) | Out-File -Encoding ascii -NoNewline -Confirm -FilePath $scriptPath\..\sitecore\k8s\$Topology\secrets\sitecore-identitycertificate.txt
