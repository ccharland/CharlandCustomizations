function New-AWSParamSplat {
    <#
    .SYNOPSIS
        Builds a splat hashtable from AWS common credential and region parameters.

    .DESCRIPTION
        Accepts the $PSBoundParameters dictionary from a calling function and returns
        a hashtable containing only the AWS common credential/region keys that were
        actually provided. This eliminates repetitive parameter-building code across
        all AWS functions in the module.

        Only keys present in $PSBoundParameters are included, which prevents
        overriding AWS session defaults when a parameter is not specified.

    .PARAMETER BoundParameters
        The $PSBoundParameters dictionary from the calling function. Pass this
        directly from the caller to filter out non-AWS parameters automatically.

    .EXAMPLE
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
        Get-CFNStack -StackName $StackName @awsParams

        Builds a splat hashtable from the caller's bound parameters and passes
        only the AWS common parameters to the AWS cmdlet.

    .EXAMPLE
        function Get-MyStacks {
            [CmdletBinding()]
            param(
                [string]$Region,
                [string]$ProfileName,
                [string]$StackName
            )
            begin {
                $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
            }
            process {
                Get-CFNStack @awsParams
            }
        }

        Shows the standard usage pattern. Only Region and ProfileName are passed
        through; StackName is excluded because it is not an AWS common parameter.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, object]]$BoundParameters
    )

    # Known AWS Tools for PowerShell common credential and region parameter names
    $awsParamNames = @(
        'Region'
        'ProfileName'
        'AccessKey'
        'SecretKey'
        'SessionToken'
        'Credential'
        'ProfileLocation'
        'EndpointUrl'
    )

    $splat = @{}

    foreach ($key in $BoundParameters.Keys) {
        if ($key -in $awsParamNames) {
            $value = $BoundParameters[$key]
            # Exclude null values and empty strings, but allow non-string objects
            if ($null -ne $value -and ($value -isnot [string] -or $value -ne '')) {
                $splat[$key] = $value
            }
        }
    }

    return $splat
}
