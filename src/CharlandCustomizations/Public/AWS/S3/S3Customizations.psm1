<#
.SYNOPSIS
    S3 helper functions for AWS account maintenance.
#>

# Load private helper functions needed by this nested module (added by Kiro, aws-common-params spec)
. "$PSScriptRoot/../../../Private/New-AWSParamSplat.ps1"
function Clear-CHARS3Bucket {
    <#
    .SYNOPSIS
        Empties an S3 bucket by deleting all object versions and delete markers.

    .DESCRIPTION
        Deletes every object version and delete marker in a versioned S3 bucket.
        This is a high-impact operation. It requires explicit confirmation unless
        -Force is specified and supports -WhatIf to preview without deleting.

    .PARAMETER BucketName
        Name of the S3 bucket to empty.

    .PARAMETER DeleteBucket
        Delete the bucket itself after emptying it.

    .PARAMETER Force
        Skip the typed bucket-name confirmation prompt.

    .PARAMETER Region
        AWS region override. If not specified, uses the default session region.

    .PARAMETER ProfileName
        AWS credential profile name.

    .PARAMETER AccessKey
        AWS IAM access key for explicit credentials.

    .PARAMETER SecretKey
        AWS IAM secret key for explicit credentials.

    .PARAMETER SessionToken
        AWS session token for temporary credentials.

    .PARAMETER Credential
        Pre-built AWS credential object (AWSCredentials).

    .PARAMETER ProfileLocation
        Path to a custom AWS credential file.

    .PARAMETER EndpointUrl
        Custom AWS service endpoint URL.

    .EXAMPLE
        Clear-CHARS3Bucket -BucketName "123456789012-staging-us-east-1" -Region "us-east-1" -WhatIf

    .EXAMPLE
        Clear-CHARS3Bucket -BucketName "123456789012-staging-us-east-1" -Region "us-east-1" -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BucketName,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DeleteBucket,

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        if (-not $Force -and -not $WhatIfPreference) {
            Write-Warning "This will permanently delete all objects and versions in bucket '$BucketName'."
            Write-Warning 'This action is irreversible.'
            $Confirmation = Read-Host 'Type the bucket name to confirm'
            if ($Confirmation -ne $BucketName) {
                Write-Output 'Confirmation failed. Aborting.'
                return 0
            }
        }

        $DryRunLabel = if ($WhatIfPreference) { '[DRY-RUN] ' } else { '' }
        $DeletedVersions = 0
        $DeletedMarkers = 0
        $KeyMarker = $null
        $VersionIdMarker = $null

        $RegionDisplay = if ($Region) { $Region } else { '(default)' }
        Write-Output "${DryRunLabel}Emptying bucket '$BucketName' in $RegionDisplay..."

        do {
            $Params = @{
                BucketName = $BucketName
                MaxKey     = 1000
            }
            if ($KeyMarker) {
                $Params.KeyMarker = $KeyMarker
                $Params.VersionIdMarker = $VersionIdMarker
            }

            $Response = Get-S3Version @Params @awsParams

            foreach ($Version in $Response.Versions) {
                $Target = "$($Version.Key) (VersionId: $($Version.VersionId))"
                if ($PSCmdlet.ShouldProcess($Target, 'Delete object version')) {
                    Remove-S3Object -BucketName $BucketName -Key $Version.Key -VersionId $Version.VersionId @awsParams -Force
                    $DeletedVersions++
                }
            }

            foreach ($Marker in $Response.DeleteMarkers) {
                $Target = "$($Marker.Key) (VersionId: $($Marker.VersionId))"
                if ($PSCmdlet.ShouldProcess($Target, 'Delete delete marker')) {
                    Remove-S3Object -BucketName $BucketName -Key $Marker.Key -VersionId $Marker.VersionId @awsParams -Force
                    $DeletedMarkers++
                }
            }

            $KeyMarker = $Response.NextKeyMarker
            $VersionIdMarker = $Response.NextVersionIdMarker
        } while ($Response.IsTruncated)

        Write-Output "${DryRunLabel}Complete: $DeletedVersions version(s), $DeletedMarkers delete marker(s) removed."

        if ($DeleteBucket) {
            if ($PSCmdlet.ShouldProcess($BucketName, 'Delete bucket')) {
                Remove-S3Bucket -BucketName $BucketName @awsParams -Force
                Write-Output "${DryRunLabel}Bucket '$BucketName' deleted."
            }
        }

        return ($DeletedVersions + $DeletedMarkers)
    }
}

Export-ModuleMember -Function 'Clear-CHARS3Bucket'