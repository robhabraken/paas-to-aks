[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [string] $Topology
)

function ConvertTo-CompressedBase64String {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [ValidateScript( {
                if (-Not ($_ | Test-Path)) {
                    throw "The file or folder $_ does not exist"
                }
                if (-Not ($_ | Test-Path -PathType Leaf)) {
                    throw "The Path argument must be a file. Folder paths are not allowed."
                }
                return $true
            })]
        [string] $Path
    )
    $fileBytes = [System.IO.File]::ReadAllBytes($Path)
    [System.IO.MemoryStream] $memoryStream = New-Object System.IO.MemoryStream
    $gzipStream = New-Object System.IO.Compression.GzipStream $memoryStream, ([IO.Compression.CompressionMode]::Compress)
    $gzipStream.Write($fileBytes, 0, $fileBytes.Length)
    $gzipStream.Close()
    $memoryStream.Close()
    $compressedFileBytes = $memoryStream.ToArray()
    $encodedCompressedFileData = [Convert]::ToBase64String($compressedFileBytes)
    $gzipStream.Dispose()
    $memoryStream.Dispose()
    return $encodedCompressedFileData
}

# retrieve the current script path
$scriptPath = Split-Path $MyInvocation.MyCommand.Path

ConvertTo-CompressedBase64String -Path $scriptPath\..\resources\license.xml | Out-File -Encoding ascii -NoNewline -Confirm -FilePath $scriptPath\..\sitecore\k8s\$Topology\secrets\sitecore-license.txt
