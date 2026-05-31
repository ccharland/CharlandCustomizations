function Set-CCFileSignature {
<#
.SYNOPSIS
    Sets Authenticode signature on PowerShell files.

.DESCRIPTION
    Signs files using a code signing certificate from the CurrentUser certificate store.
    Automatically selects the valid certificate with the longest time before expiration
    and determines the appropriate timestamp server based on the certificate issuer
    (Digicert or Sectigo).

.PARAMETER MyCert
    Code signing certificate to use. If not specified, automatically selects the valid
    codesign certificate with the longest time before expiration from the CurrentUser store.

.PARAMETER TimeStampServer
    URL of the timestamp server. If not specified, automatically determined based on the
    certificate issuer (Digicert or Sectigo).

.PARAMETER Path
    Path(s) to the file(s) to sign. Accepts pipeline input and the FullName property
    from Get-ChildItem output.

.INPUTS
    System.String[] - File paths to sign (via pipeline or parameter).

.OUTPUTS
    System.Management.Automation.Signature - The signature result for each file.

.EXAMPLE
    Set-CCFileSignature -Path .\MyScript.ps1
    Signs a single file using the auto-detected certificate.

.EXAMPLE
    Get-ChildItem .\Modules\*.psm1 | Set-CCFileSignature
    Signs all .psm1 files in the Modules directory via pipeline.

.EXAMPLE
    Set-CCFileSignature -Path .\MyScript.ps1 -TimeStampServer 'http://timestamp.digicert.com'
    Signs a file using an explicitly specified timestamp server.
#>
  [CmdletBinding()]
  param (
    [Parameter()]
    $MyCert = (Get-ChildItem cert:\currentuser\my -CodesigningCert |
        Where-Object { ($_.NotAfter -gt (Get-Date) ) -and ($_.HasPrivateKey -eq $true) }
      | Sort-Object -Descending NotAfter | Select-Object -First 1),

    [Parameter()]
    [String]$TimeStampServer = '',

    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('FullName')]
    [String[]]
    $Path
  )

  begin {
    if ($null -eq $MyCert) {
      throw 'No valid codesign certificate found'
    }
    Write-Verbose $($MyCert.Issuer)

    if ($TimeStampServer -eq '') {
      Write-Verbose "have a CN? $($MyCert.Issuer.StartsWith('CN'))"
      if ($MyCert.Issuer.StartsWith('CN=Digicert')) {
        Write-Verbose 'Digicert cert found'
        $TimeStampServer = 'http://timestamp.digicert.com'
      } elseif ($MyCert.Issuer.StartsWith('CN=Sect') ) {
        Write-Verbose 'Sectigo cert found'
        $TimeStampServer = 'http://timestamp.sectigo.com'
      } else {
        Write-Verbose "Issuer: $($MyCert.Issuer)"
        Write-Verbose "Digicert? $($MyCert.Issuer.StartsWith('CN=Digicert'))"
        Write-Verbose "Sectigo? $($MyCert.Issuer.StartsWith('CN=Sect'))"
        throw 'No Timestamp server could be set, aborting.'
      }
    } else {
      Write-Verbose "Timestamp server entered $($TimeStampServer)"
    }
    Write-Verbose "Mycert: $($MyCert)"
    Write-Verbose "Timestamp server: $($TimeStampServer)"
  }

  process {
    foreach ($file in $Path) {
      Write-Verbose "Signing: $file"
      Set-AuthenticodeSignature -FilePath $file -TimestampServer $TimeStampServer -Certificate $MyCert
    }
  }
}
