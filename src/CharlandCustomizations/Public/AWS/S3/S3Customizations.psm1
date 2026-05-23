<#
.SYNOPSIS
    S3 helper functions for AWS account maintenance.
#>

function Clear-S3Bucket {
    <#
    .SYNOPSIS
        Empties an S3 bucket by deleting all object versions and delete markers.

    .DESCRIPTION
        Deletes every object version and delete marker in a versioned S3 bucket.
        This is a high-impact operation. It requires explicit confirmation unless
        -Force is specified and supports -WhatIf to preview without deleting.

    .PARAMETER BucketName
        Name of the S3 bucket to empty.

    .PARAMETER Region
        AWS region of the bucket.

    .PARAMETER ProfileName
        AWS profile name.

    .PARAMETER DeleteBucket
        Delete the bucket itself after emptying it.

    .PARAMETER Force
        Skip the typed bucket-name confirmation prompt.

    .EXAMPLE
        Clear-S3Bucket -BucketName "123456789012-staging-us-east-1" -Region "us-east-1" -WhatIf

    .EXAMPLE
        Clear-S3Bucket -BucketName "123456789012-staging-us-east-1" -Region "us-east-1" -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BucketName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DeleteBucket
    )

    begin {
        $ErrorActionPreference = 'Stop'
    }

    process {
        $AWSParams = @{ Region = $Region }
        if ($ProfileName) {
            $AWSParams.ProfileName = $ProfileName
        }

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

        Write-Output "${DryRunLabel}Emptying bucket '$BucketName' in $Region..."

        do {
            $Params = @{
                BucketName = $BucketName
                MaxKey     = 1000
            }
            if ($KeyMarker) {
                $Params.KeyMarker = $KeyMarker
                $Params.VersionIdMarker = $VersionIdMarker
            }

            $Response = Get-S3Version @Params @AWSParams

            foreach ($Version in $Response.Versions) {
                $Target = "$($Version.Key) (VersionId: $($Version.VersionId))"
                if ($PSCmdlet.ShouldProcess($Target, 'Delete object version')) {
                    Remove-S3Object -BucketName $BucketName -Key $Version.Key -VersionId $Version.VersionId @AWSParams -Force
                    $DeletedVersions++
                }
            }

            foreach ($Marker in $Response.DeleteMarkers) {
                $Target = "$($Marker.Key) (VersionId: $($Marker.VersionId))"
                if ($PSCmdlet.ShouldProcess($Target, 'Delete delete marker')) {
                    Remove-S3Object -BucketName $BucketName -Key $Marker.Key -VersionId $Marker.VersionId @AWSParams -Force
                    $DeletedMarkers++
                }
            }

            $KeyMarker = $Response.NextKeyMarker
            $VersionIdMarker = $Response.NextVersionIdMarker
        } while ($Response.IsTruncated)

        Write-Output "${DryRunLabel}Complete: $DeletedVersions version(s), $DeletedMarkers delete marker(s) removed."

        if ($DeleteBucket) {
            if ($PSCmdlet.ShouldProcess($BucketName, 'Delete bucket')) {
                Remove-S3Bucket -BucketName $BucketName @AWSParams -Force
                Write-Output "${DryRunLabel}Bucket '$BucketName' deleted."
            }
        }

        return ($DeletedVersions + $DeletedMarkers)
    }
}

Export-ModuleMember -Function 'Clear-S3Bucket'