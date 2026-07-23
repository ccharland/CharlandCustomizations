<#
.SYNOPSIS
    AWS Certificate Manager custom functions.
#>
Write-Verbose "Loading ACM-Customizations.psm1"

. "$PSScriptRoot/../../../Private/New-AWSParamSplat.ps1"

$script:GetPfxCertificateMaterial = {
  param(
    [Parameter(Mandatory)]
    [string]$PfxPath,

    [Parameter()]
    [SecureString]$Password
  )

  try {
    $resolvedPfxPath = (Resolve-Path -Path $PfxPath -ErrorAction Stop).ProviderPath
  }
  catch {
    throw "PFX file not found: $PfxPath"
  }

  $convertBytesToPem = {
    param(
      [Parameter(Mandatory)]
      [byte[]]$Bytes,

      [Parameter(Mandatory)]
      [string]$Label
    )

    $base64 = [System.Convert]::ToBase64String($Bytes)
    $lines = for ($offset = 0; $offset -lt $base64.Length; $offset += 64) {
      $length = [Math]::Min(64, $base64.Length - $offset)
      $base64.Substring($offset, $length)
    }

    @(
      "-----BEGIN $Label-----"
      $lines
      "-----END $Label-----"
    ) -join "`n"
  }

  $passwordText = $null
  if ($PSBoundParameters.ContainsKey('Password')) {
    $passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try {
      $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
    }
    finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
    }
  }

  $pfxBytes = [System.IO.File]::ReadAllBytes($resolvedPfxPath)
  $certCollection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
  $keyStorageFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
  $certCollection.Import($pfxBytes, $passwordText, $keyStorageFlags)

  $leafCertificate = $certCollection | Where-Object HasPrivateKey | Select-Object -First 1
  if (-not $leafCertificate) {
    throw 'No certificate with a private key was found in the PFX file.'
  }

  $certificatePem = & $convertBytesToPem -Bytes $leafCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert) -Label 'CERTIFICATE'

  $privateKeyBytes = $null
  $rsaPrivateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($leafCertificate)
  if ($rsaPrivateKey) {
    try {
      $privateKeyBytes = $rsaPrivateKey.ExportPkcs8PrivateKey()
    }
    finally {
      $rsaPrivateKey.Dispose()
    }
  }
  else {
    $ecdsaPrivateKey = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPrivateKey($leafCertificate)
    if ($ecdsaPrivateKey) {
      try {
        $privateKeyBytes = $ecdsaPrivateKey.ExportPkcs8PrivateKey()
      }
      finally {
        $ecdsaPrivateKey.Dispose()
      }
    }
  }

  if (-not $privateKeyBytes) {
    throw 'Unsupported private key algorithm. Only RSA and ECDSA private keys are supported.'
  }

  $privateKeyPem = & $convertBytesToPem -Bytes $privateKeyBytes -Label 'PRIVATE KEY'

  $chainPemEntries = @()
  foreach ($cert in $certCollection) {
    if ($cert.Thumbprint -eq $leafCertificate.Thumbprint) {
      continue
    }

    $chainPemEntries += & $convertBytesToPem -Bytes $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert) -Label 'CERTIFICATE'
  }

  [PSCustomObject]@{
    SourcePath          = $resolvedPfxPath
    CertificatePem      = $certificatePem
    PrivateKeyPem       = $privateKeyPem
    CertificateChainPem = if ($chainPemEntries.Count -gt 0) { $chainPemEntries -join "`n" } else { $null }
    IncludedChain       = $chainPemEntries.Count -gt 0
    CertificateSubject  = $leafCertificate.Subject
    CertificateNotAfter = $leafCertificate.NotAfter
  }
}

function Export-CHARPfxCertificatePem {
  <#
.SYNOPSIS
  Converts an exported PFX certificate into PEM files.

.DESCRIPTION
  Reads a local .pfx/.p12 file, extracts the leaf certificate, private key, and
  optional certificate chain, then writes PEM files to disk.

.PARAMETER PfxPath
  Path to the exported PFX/P12 file.

.PARAMETER Password
  Optional secure password used to open the PFX file.

.PARAMETER OutputPath
  Output directory for PEM files. Defaults to the current directory.

.EXAMPLE
  Export-CHARPfxCertificatePem -PfxPath .\site.pfx -Password (Read-Host -AsSecureString)

  Writes certificate, private key, and chain PEM files for a password-protected PFX.

.EXAMPLE
  Export-CHARPfxCertificatePem -PfxPath .\site.pfx -OutputPath .\acm-export

  Saves PEM files locally to the specified directory.
#>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PfxPath,

    [Parameter()]
    [SecureString]$Password,

    [Parameter()]
    [string]$OutputPath = '.'
  )

  process {
    try {
      $material = & $script:GetPfxCertificateMaterial -PfxPath $PfxPath -Password $Password

      Write-Warning 'The exported private key PEM file is not encrypted. Protect the output directory appropriately.'

      try {
        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
      }
      catch {
        throw "Invalid OutputPath: $OutputPath"
      }

      if (-not (Test-Path -LiteralPath $resolvedOutputPath)) {
        if ($PSCmdlet.ShouldProcess($resolvedOutputPath, 'Create output directory for PEM files')) {
          New-Item -Path $resolvedOutputPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
      }

      $savedFilePaths = @()
      $baseName = [System.IO.Path]::GetFileNameWithoutExtension($material.SourcePath)
      $certificatePemPath = Join-Path $resolvedOutputPath "$baseName-certificate.pem"
      $privateKeyPemPath = Join-Path $resolvedOutputPath "$baseName-private-key.pem"
      $chainPemPath = Join-Path $resolvedOutputPath "$baseName-chain.pem"

      if ($PSCmdlet.ShouldProcess($certificatePemPath, 'Write certificate PEM file')) {
        Set-Content -Path $certificatePemPath -Value $material.CertificatePem -Encoding ascii -NoNewline
        $savedFilePaths += $certificatePemPath
      }
      if ($PSCmdlet.ShouldProcess($privateKeyPemPath, 'Write private key PEM file')) {
        Set-Content -Path $privateKeyPemPath -Value $material.PrivateKeyPem -Encoding ascii -NoNewline
        $savedFilePaths += $privateKeyPemPath
      }

      $chainPemContent = if ($material.CertificateChainPem) {
        $material.CertificateChainPem
      }
      else {
        '# No additional chain certificates were present in the PFX.'
      }

      if ($PSCmdlet.ShouldProcess($chainPemPath, 'Write certificate chain PEM file')) {
        Set-Content -Path $chainPemPath -Value $chainPemContent -Encoding ascii -NoNewline
        $savedFilePaths += $chainPemPath
      }

      [PSCustomObject]@{
        CertificateArn      = $null
        SourcePath          = $material.SourcePath
        PemOutputPath       = $resolvedOutputPath
        SavedPemFiles       = @($savedFilePaths)
        IncludedChain       = $material.IncludedChain
        CertificateSubject  = $material.CertificateSubject
        CertificateNotAfter = $material.CertificateNotAfter
      }
    }
    catch {
      $PSCmdlet.ThrowTerminatingError($_)
    }
  }
}

function Import-CHARPfxCertificateToACM {
  <#
.SYNOPSIS
  Imports an exported PFX certificate into AWS ACM.

.DESCRIPTION
  Reads a local .pfx/.p12 file, extracts the leaf certificate, private key, and
  optional certificate chain, converts each to PEM, and imports them into
  AWS Certificate Manager using Import-ACMCertificate.

.PARAMETER PfxPath
  Path to the exported PFX/P12 file.

.PARAMETER Password
  Optional secure password used to open the PFX file.

.PARAMETER CertificateArn
  Optional ACM certificate ARN. When provided, ACM updates the existing
  certificate. When omitted, ACM creates a new certificate.

.PARAMETER Region
    AWS region. If not specified, uses the session default.

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

.EXAMPLE
  Import-CHARPfxCertificateToACM -PfxPath .\site.pfx -Password (Read-Host -AsSecureString)

  Imports a new certificate into ACM from a password-protected PFX file.

.EXAMPLE
  Import-CHARPfxCertificateToACM -PfxPath .\site.pfx -CertificateArn arn:aws:acm:us-east-1:123456789012:certificate/abc-def

  Re-imports (updates) an existing ACM certificate from a PFX file.
#>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PfxPath,

    [Parameter()]
    [SecureString]$Password,

    [Parameter()]
    [string]$CertificateArn,

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
    [object]$NetworkCredential,

    [Parameter()]
    [string]$ProfileLocation,

    [Parameter()]
    [string]$EndpointUrl
  )

  begin {
    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

    if (-not (Get-Command -Name 'Import-ACMCertificate' -ErrorAction SilentlyContinue)) {
      throw 'Import-ACMCertificate was not found. Install AWS.Tools.CertificateManager to use this function.'
    }
  }

  process {
    try {
      $material = & $script:GetPfxCertificateMaterial -PfxPath $PfxPath -Password $Password

      $importParams = @{
        Certificate = [System.Text.Encoding]::ASCII.GetBytes($material.CertificatePem)
        PrivateKey  = [System.Text.Encoding]::ASCII.GetBytes($material.PrivateKeyPem)
        ErrorAction = 'Stop'
      }

      if ($material.CertificateChainPem) {
        $importParams['CertificateChain'] = [System.Text.Encoding]::ASCII.GetBytes($material.CertificateChainPem)
      }
      if ($CertificateArn) {
        $importParams['CertificateArn'] = $CertificateArn
      }

      foreach ($key in $awsParams.Keys) {
        $importParams[$key] = $awsParams[$key]
      }

      $target = if ($CertificateArn) { "ACM certificate '$CertificateArn'" } else { 'a new ACM certificate' }
      if ($PSCmdlet.ShouldProcess($target, "Import certificate from '$($material.SourcePath)'")) {
        $result = Import-ACMCertificate @importParams
        return [PSCustomObject]@{
          CertificateArn      = if ($result.CertificateArn) { $result.CertificateArn } else { $CertificateArn }
          SourcePath          = $material.SourcePath
          PemOutputPath       = $null
          SavedPemFiles       = @()
          IncludedChain       = $material.IncludedChain
          CertificateSubject  = $material.CertificateSubject
          CertificateNotAfter = $material.CertificateNotAfter
        }
      }
    }
    catch {
      $PSCmdlet.ThrowTerminatingError($_)
    }
  }
}

try {
  Write-Verbose "Attempting to export ACM module members"
  Export-ModuleMember -Function @(
    'Export-CHARPfxCertificatePem'
    'Import-CHARPfxCertificateToACM'
  )
}
catch {
  Write-Verbose 'OK: someone is dot sourcing this script'
}
finally {
  Write-Verbose 'Finished loading ACM-Customizations.psm1'
}
