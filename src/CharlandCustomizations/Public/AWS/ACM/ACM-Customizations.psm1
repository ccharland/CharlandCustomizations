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
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Credential',
    Justification = 'Credential parameter accepts AWSCredentials object, not a password')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'NetworkCredential',
    Justification = 'NetworkCredential typed as [object] for pipeline compatibility')]
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
          CertificateArn      = if ($result -is [string]) { $result } elseif ($result.CertificateArn) { $result.CertificateArn } else { $CertificateArn }
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

function Test-CHARPfxCertificate {
  <#
.SYNOPSIS
  Inspects a local PFX/P12 certificate file.

.DESCRIPTION
  Reads a PFX/P12 file and returns certificate identity, validity, private-key,
  and chain-validation information without exporting certificate material.

.PARAMETER PfxPath
  Path to the PFX/P12 file to inspect.

.PARAMETER Password
  Optional secure password used to open the PFX file.

.EXAMPLE
  Test-CHARPfxCertificate -PfxPath .\site.pfx -Password (Read-Host -AsSecureString)
#>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [Alias('FullName')]
    [string]$PfxPath,

    [Parameter()]
    [SecureString]$Password
  )

  process {
    try {
      try {
        $resolvedPfxPath = (Resolve-Path -Path $PfxPath -ErrorAction Stop).ProviderPath
      }
      catch {
        throw "PFX file not found: $PfxPath"
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

      $certCollection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
      $certCollection.Import(
        [System.IO.File]::ReadAllBytes($resolvedPfxPath),
        $passwordText,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet
      )

      $leafCertificate = $certCollection | Where-Object HasPrivateKey | Select-Object -First 1
      if (-not $leafCertificate) {
        $leafCertificate = $certCollection | Select-Object -First 1
      }
      if (-not $leafCertificate) {
        throw 'No certificates were found in the PFX file.'
      }

      $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
      try {
        $chainIsValid = $chain.Build($leafCertificate)
        $chainStatus = @($chain.ChainStatus | ForEach-Object {
          [PSCustomObject]@{
            Status            = $_.Status.ToString()
            StatusInformation = $_.StatusInformation.Trim()
          }
        })
      }
      finally {
        $chain.Dispose()
      }

      $now = [DateTime]::Now
      $daysRemaining = [Math]::Floor(($leafCertificate.NotAfter - $now).TotalDays)

      [PSCustomObject]@{
        Path              = $resolvedPfxPath
        Subject           = $leafCertificate.Subject
        Issuer            = $leafCertificate.Issuer
        DnsName           = $leafCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::DnsName, $false)
        Thumbprint        = $leafCertificate.Thumbprint
        SerialNumber      = $leafCertificate.SerialNumber
        NotBefore         = $leafCertificate.NotBefore
        NotAfter          = $leafCertificate.NotAfter
        DaysRemaining     = [int]$daysRemaining
        HasPrivateKey     = $leafCertificate.HasPrivateKey
        IsExpired         = $leafCertificate.NotAfter -lt $now
        IsCurrentlyValid  = $leafCertificate.NotBefore -le $now -and $leafCertificate.NotAfter -ge $now
        ChainIsValid      = $chainIsValid
        ChainStatus       = $chainStatus
        CertificateCount  = $certCollection.Count
      }
    }
    catch {
      $PSCmdlet.ThrowTerminatingError($_)
    }
  }
}

function Test-CHARACMCertificate {
  <#
.SYNOPSIS
  Validates the status and remaining lifetime of an ACM certificate.

.DESCRIPTION
  Retrieves detailed ACM certificate metadata and reports whether the certificate
  is issued, unexpired, and valid for at least the requested number of days.

.PARAMETER CertificateArn
  ARN of the ACM certificate to validate.

.PARAMETER MinimumDaysRemaining
  Minimum acceptable remaining lifetime. Defaults to 30 days.

.EXAMPLE
  Test-CHARACMCertificate -CertificateArn $certificateArn -Region us-east-1
#>
  [CmdletBinding()]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Credential',
    Justification = 'Credential parameter accepts AWSCredentials object, not a password')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'NetworkCredential',
    Justification = 'NetworkCredential typed as [object] for pipeline compatibility')]
  param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$CertificateArn,

    [Parameter()]
    [ValidateRange(0, 36500)]
    [int]$MinimumDaysRemaining = 30,

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
    if (-not (Get-Command -Name 'Get-ACMCertificateDetail' -ErrorAction SilentlyContinue)) {
      throw 'Get-ACMCertificateDetail was not found. Install AWS.Tools.CertificateManager to use this function.'
    }
  }

  process {
    try {
      $detail = Get-ACMCertificateDetail -CertificateArn $CertificateArn @awsParams -ErrorAction Stop
      $now = [DateTime]::UtcNow
      $hasExpiration = $null -ne $detail.NotAfter -and ([DateTime]$detail.NotAfter) -gt [DateTime]::MinValue
      $daysRemaining = if ($hasExpiration) {
        [int][Math]::Floor((([DateTime]$detail.NotAfter).ToUniversalTime() - $now).TotalDays)
      }
      else {
        $null
      }
      $isIssued = [string]$detail.Status -eq 'ISSUED'
      $isExpired = $hasExpiration -and ([DateTime]$detail.NotAfter).ToUniversalTime() -lt $now
      $hasMinimumValidity = $hasExpiration -and $daysRemaining -ge $MinimumDaysRemaining
      $messages = @()
      if (-not $isIssued) {
        $messages += "Certificate status is '$($detail.Status)', not 'ISSUED'."
      }
      if (-not $hasExpiration) {
        $messages += 'Certificate expiration information is unavailable.'
      }
      elseif ($isExpired) {
        $messages += 'Certificate is expired.'
      }
      elseif (-not $hasMinimumValidity) {
        $messages += "Certificate has fewer than $MinimumDaysRemaining days remaining."
      }

      $certificateRegion = $Region
      if (-not $certificateRegion -and $CertificateArn -match '^arn:[^:]+:acm:([^:]+):') {
        $certificateRegion = $Matches[1]
      }

      [PSCustomObject]@{
        Region                = $certificateRegion
        CertificateArn        = $detail.CertificateArn
        DomainName            = $detail.DomainName
        Status                = [string]$detail.Status
        NotAfter              = if ($hasExpiration) { [DateTime]$detail.NotAfter } else { $null }
        DaysRemaining         = $daysRemaining
        InUseBy               = @($detail.InUseBy)
        IsIssued              = $isIssued
        IsExpired             = $isExpired
        HasMinimumValidity    = $hasMinimumValidity
        IsValid               = $isIssued -and -not $isExpired -and $hasMinimumValidity
        ValidationMessages    = @($messages)
      }
    }
    catch {
      $PSCmdlet.ThrowTerminatingError($_)
    }
  }
}

function Update-CHARPfxCertificateInACM {
  <#
.SYNOPSIS
  Replaces an imported ACM certificate with certificate material from a PFX file.

.DESCRIPTION
  Reimports certificate material into an existing ACM certificate ARN, preserving
  the ARN and its existing AWS service associations.

.EXAMPLE
  Update-CHARPfxCertificateInACM -CertificateArn $certificateArn -PfxPath .\renewed.pfx -Password (Read-Host -AsSecureString)
#>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Credential',
    Justification = 'Credential parameter accepts AWSCredentials object, not a password')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'NetworkCredential',
    Justification = 'NetworkCredential typed as [object] for pipeline compatibility')]
  param(
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$CertificateArn,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$PfxPath,

    [Parameter()]
    [SecureString]$Password,

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

  process {
    try {
      if ($PSCmdlet.ShouldProcess($CertificateArn, "Replace ACM certificate from '$PfxPath'")) {
        $replaceParams = @{
          CertificateArn = $CertificateArn
          PfxPath        = $PfxPath
          Confirm        = $false
        }
        if ($PSBoundParameters.ContainsKey('Password')) {
          $replaceParams['Password'] = $Password
        }

        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
        foreach ($key in $awsParams.Keys) {
          $replaceParams[$key] = $awsParams[$key]
        }

        Import-CHARPfxCertificateToACM @replaceParams
      }
    }
    catch {
      $PSCmdlet.ThrowTerminatingError($_)
    }
  }
}

function Get-CHARACMCertificateInventory {
  <#
.SYNOPSIS
  Returns an inventory of ACM certificates in an AWS region.

.DESCRIPTION
  Lists ACM certificates and retrieves each certificate's detailed status,
  expiration date, remaining lifetime, and service associations.

.EXAMPLE
  Get-CHARACMCertificateInventory -Region us-east-1 -ProfileName production
#>
  [CmdletBinding()]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Credential',
    Justification = 'Credential parameter accepts AWSCredentials object, not a password')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'NetworkCredential',
    Justification = 'NetworkCredential typed as [object] for pipeline compatibility')]
  param(
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
    foreach ($requiredCommand in 'Get-ACMCertificateList', 'Get-ACMCertificateDetail') {
      if (-not (Get-Command -Name $requiredCommand -ErrorAction SilentlyContinue)) {
        throw "$requiredCommand was not found. Install AWS.Tools.CertificateManager to use this function."
      }
    }
  }

  process {
    try {
      $certificateSummaries = @(Get-ACMCertificateList @awsParams -ErrorAction Stop)
      foreach ($summary in $certificateSummaries) {
        $detail = Get-ACMCertificateDetail -CertificateArn $summary.CertificateArn @awsParams -ErrorAction Stop
        $hasExpiration = $null -ne $detail.NotAfter -and ([DateTime]$detail.NotAfter) -gt [DateTime]::MinValue
        $daysRemaining = if ($hasExpiration) {
          [int][Math]::Floor((([DateTime]$detail.NotAfter).ToUniversalTime() - [DateTime]::UtcNow).TotalDays)
        }
        else {
          $null
        }

        $certificateRegion = $Region
        if (-not $certificateRegion -and $detail.CertificateArn -match '^arn:[^:]+:acm:([^:]+):') {
          $certificateRegion = $Matches[1]
        }

        [PSCustomObject]@{
          Region          = $certificateRegion
          CertificateArn  = $detail.CertificateArn
          DomainName      = $detail.DomainName
          Status          = [string]$detail.Status
          NotAfter        = if ($hasExpiration) { [DateTime]$detail.NotAfter } else { $null }
          DaysRemaining   = $daysRemaining
          InUseBy         = @($detail.InUseBy)
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
    'Get-CHARACMCertificateInventory'
    'Import-CHARPfxCertificateToACM'
    'Test-CHARACMCertificate'
    'Test-CHARPfxCertificate'
    'Update-CHARPfxCertificateInACM'
  )
}
catch {
  Write-Verbose 'OK: someone is dot sourcing this script'
}
finally {
  Write-Verbose 'Finished loading ACM-Customizations.psm1'
}
