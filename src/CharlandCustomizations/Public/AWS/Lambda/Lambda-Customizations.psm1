<#
.SYNOPSIS
    Lambda-focused helper functions.
#>
Write-Verbose "Loading Lambda-Customizations.psm1"

function Get-CCDeprecatedLMFunctionList {
    <#
    .SYNOPSIS
        Lists Lambda functions using deprecated runtimes.

    .DESCRIPTION
        Calls Get-LMFunctionList with the same common AWS parameters and filters
        the returned functions to only runtimes deprecated on or before -Date.

    .PARAMETER Date
        Comparison date used to determine whether a runtime is deprecated.
        Defaults to the current date.

    .PARAMETER Marker
        Pagination token for Get-LMFunctionList.

    .PARAMETER MaxItem
        Maximum number of functions to return from Get-LMFunctionList.

    .PARAMETER NoAutoIteration
        Disables automatic pagination for Get-LMFunctionList.

    .PARAMETER Region
        AWS region. If not specified, uses your default Region.

    .PARAMETER ProfileName
        AWS profile name. Optional.

    .PARAMETER AccessKey
        AWS access key. Optional.

    .PARAMETER SecretKey
        AWS secret key. Optional.

    .PARAMETER SessionToken
        AWS session token for temporary credentials. Optional.

    .PARAMETER Credential
        Pre-built AWS credential object. Optional.

    .PARAMETER ProfileLocation
        Custom credential file path. Optional.

    .PARAMETER EndpointUrl
        Custom AWS service endpoint URL. Optional.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [datetime]$Date = (Get-Date),

        [Parameter()]
        [string]$Marker,

        [Parameter()]
        [int]$MaxItem,

        [Parameter()]
        [switch]$NoAutoIteration,

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
        [object]$Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    process {
        $listParams = @{}
        foreach ($paramName in @('Marker', 'MaxItem', 'NoAutoIteration', 'Region', 'ProfileName', 'AccessKey', 'SecretKey', 'SessionToken', 'Credential', 'ProfileLocation', 'EndpointUrl')) {
            if ($PSBoundParameters.ContainsKey($paramName)) {
                $listParams[$paramName] = $PSBoundParameters[$paramName]
            }
        }

        $deprecatedRuntimeDates = @{
            'dotnetcore1.0' = [datetime]'2019-07-30'
            'dotnetcore2.0' = [datetime]'2019-05-30'
            'dotnetcore2.1' = [datetime]'2021-05-31'
            'dotnetcore3.1' = [datetime]'2023-04-03'
            'go1.x'         = [datetime]'2024-01-08'
            'nodejs'        = [datetime]'2016-10-31'
            'nodejs4.3'     = [datetime]'2018-03-05'
            'nodejs6.10'    = [datetime]'2019-08-12'
            'nodejs8.10'    = [datetime]'2020-03-06'
            'nodejs10.x'    = [datetime]'2021-07-30'
            'nodejs12.x'    = [datetime]'2023-03-31'
            'nodejs14.x'    = [datetime]'2023-11-27'
            'python2.7'     = [datetime]'2021-07-15'
            'python3.6'     = [datetime]'2022-08-29'
            'python3.7'     = [datetime]'2023-12-04'
            'ruby2.5'       = [datetime]'2021-07-30'
            'ruby2.7'       = [datetime]'2023-12-07'
        }

        @(Get-LMFunctionList @listParams) | Where-Object {
            $runtime = [string]$_.Runtime
            if ([string]::IsNullOrWhiteSpace($runtime)) {
                return $false
            }

            $runtimeKey = $runtime.ToLowerInvariant()
            $deprecatedRuntimeDates.ContainsKey($runtimeKey) -and $deprecatedRuntimeDates[$runtimeKey] -le $Date
        }
    }
}
