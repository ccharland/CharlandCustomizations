function Install-ProfilesFromSource {
<#
.SYNOPSIS
    Installs or updates PowerShell profiles from a shared source location.

.DESCRIPTION
    Copies profile files to the proper system locations based on their filename.
    Expected filenames map to profile paths as follows:

    - AllUsersAllHosts       -> $PROFILE.AllUsersAllHosts
    - AllUsersCurrentHost    -> $PROFILE.AllUsersCurrentHost
    - CurrentUserAllHosts    -> $PROFILE.CurrentUserAllHosts
    - CurrentUserCurrentHost -> $PROFILE.CurrentUserCurrentHost

.PARAMETER Path
    Path to the directory containing profile source files.
    Defaults to the current working directory.

.INPUTS
    System.String - Directory path containing profile files.

.OUTPUTS
    None. Copies files to profile locations.

.NOTES
    Useful when profiles are kept under source control across multiple machines.
    Use -WhatIf to preview which files would be copied without making changes.

.EXAMPLE
    Install-ProfilesFromSource -Path C:\Users\MyFolder\GitHub\PowerShell\Profiles
    Copies matching profile files from the specified path to their system locations.

.EXAMPLE
    Install-ProfilesFromSource
    Uses the current directory as the source for profile files.
#>
  [CmdletBinding(SupportsShouldProcess)]
  param (
    [Parameter(ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, Position = 0)]
    [String]
    $Path = (Get-Location).Path
  )
  Write-Verbose "Source path: $Path"
  $ProfileNames = (Get-Member -InputObject $PROFILE -MemberType NoteProperty)

  foreach ($Source in $ProfileNames.Name) {
    Write-Verbose '===================='
    $SourceFile = Join-Path -Path $Path -ChildPath $Source
    $DestinationFile = $($PROFILE.$Source)
    Write-Verbose "Checking for: $SourceFile"
    Write-Verbose "DestinationFile: $DestinationFile"
    if (Test-Path $SourceFile) {
      if ($PSCmdlet.ShouldProcess($DestinationFile, "Copy profile from $SourceFile")) {
        Copy-Item $SourceFile $DestinationFile -Force
        Write-Verbose "Updated $DestinationFile"
      }
    } else {
      Write-Verbose "Not Found: $SourceFile Skipping."
    }
  }
}
