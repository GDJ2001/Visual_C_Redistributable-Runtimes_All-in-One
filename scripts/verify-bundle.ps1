[CmdletBinding()]
param(
    [ValidateSet('all', 'modern', 'legacy', 'discontinued', 'everything')]
    [string] $PackageGroup = 'everything',

    [ValidateSet('x86', 'x64', 'arm', 'arm64', 'ia64', 'any', 'auto')]
    [string] $Architecture = 'any',

    [switch] $SkipSignature
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$MetadataPath = Join-Path $RepoRoot 'metadata/redists.json'
$HashPath = Join-Path $RepoRoot 'metadata/SHA256SUMS.txt'
$MaxGitHubFileSize = 100MB

$AllowedHosts = @(
    'aka.ms',
    'download.microsoft.com',
    'download.visualstudio.microsoft.com',
    'go.microsoft.com'
)

$Errors = New-Object System.Collections.Generic.List[string]

function Add-VerificationError {
    param([Parameter(Mandatory = $true)][string] $Message)
    $script:Errors.Add($Message) | Out-Null
}

function Test-Property {
    param(
        [Parameter(Mandatory = $true)][object] $InputObject,
        [Parameter(Mandatory = $true)][string] $Name
    )

    return $InputObject.PSObject.Properties.Name -contains $Name
}

function Normalize-RelativePath {
    param([Parameter(Mandatory = $true)][string] $Path)

    return $Path.Trim().Replace('\', '/').TrimStart('./')
}

function Get-Sha256Hash {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (Get-Command -Name Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
    }

    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
            return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').ToUpperInvariant()
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Test-RedistPath {
    param(
        [Parameter(Mandatory = $true)][string] $PackageId,
        [Parameter(Mandatory = $true)][string] $Path
    )

    $normalized = Normalize-RelativePath -Path $Path

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        Add-VerificationError "$PackageId has an empty path."
        return $null
    }

    if ([IO.Path]::IsPathRooted($Path) -or ($normalized -match '^[A-Za-z]:') -or $normalized.StartsWith('/')) {
        Add-VerificationError "$PackageId uses an absolute path: $Path"
        return $null
    }

    if ($normalized -match '(^|/)\.\.(/|$)') {
        Add-VerificationError "$PackageId uses path traversal: $Path"
        return $null
    }

    if (-not $normalized.StartsWith('redists/', [StringComparison]::OrdinalIgnoreCase)) {
        Add-VerificationError "$PackageId must live under redists/: $Path"
        return $null
    }

    if (-not $normalized.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
        Add-VerificationError "$PackageId must point to an .exe file: $Path"
        return $null
    }

    return $normalized
}

function Resolve-TargetArchitectures {
    param([Parameter(Mandatory = $true)][string] $RequestedArchitecture)

    if ($RequestedArchitecture -eq 'auto') {
        $detected = 'x86'
        if ($env:PROCESSOR_ARCHITECTURE -match 'AMD64') { $detected = 'x64' }
        if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { $detected = 'arm64' }
        if ($env:PROCESSOR_ARCHITECTURE -match '^ARM$') { $detected = 'arm' }
        if ($env:PROCESSOR_ARCHITECTURE -match 'IA64') { $detected = 'ia64' }
        if ($env:PROCESSOR_ARCHITEW6432 -match 'AMD64') { $detected = 'x64' }
        if ($env:PROCESSOR_ARCHITEW6432 -match 'ARM64') { $detected = 'arm64' }
        if ($env:PROCESSOR_ARCHITEW6432 -match 'IA64') { $detected = 'ia64' }
        $RequestedArchitecture = $detected
    }

    switch ($RequestedArchitecture) {
        'x86' { return @('x86') }
        'x64' { return @('x86', 'x64') }
        'arm' { return @('arm') }
        'arm64' { return @('x86', 'x64', 'arm64') }
        'ia64' { return @('x86', 'ia64') }
        'any' { return @('x86', 'x64', 'arm', 'arm64', 'ia64') }
        default { throw "Unsupported architecture: $RequestedArchitecture" }
    }
}

function Read-HashManifest {
    param([Parameter(Mandatory = $true)][string] $Path)

    $hashes = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-VerificationError "Missing hash manifest: $Path"
        return $hashes
    }

    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -notmatch '^\s*([A-Fa-f0-9]{64})\s+\*?(.+?)\s*$') {
            Add-VerificationError "Invalid SHA256SUMS line $lineNumber."
            continue
        }

        $hash = $Matches[1].ToUpperInvariant()
        $relativePath = Normalize-RelativePath -Path $Matches[2]
        if ($hashes.ContainsKey($relativePath)) {
            Add-VerificationError "Duplicate SHA256SUMS entry: $relativePath"
            continue
        }

        $hashes.Add($relativePath, $hash)
    }

    return $hashes
}

function Assert-MicrosoftSignature {
    param(
        [Parameter(Mandatory = $true)][string] $PackageId,
        [Parameter(Mandatory = $true)][string] $Path
    )

    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
    } catch {
        Add-VerificationError "$PackageId could not be signature checked: $($_.Exception.Message)"
        return
    }

    if ($signature.Status -ne 'Valid') {
        Add-VerificationError "$PackageId has an invalid Authenticode signature: $($signature.Status)"
        return
    }

    if ($null -eq $signature.SignerCertificate) {
        Add-VerificationError "$PackageId has no signer certificate."
        return
    }

    $subject = $signature.SignerCertificate.Subject
    $issuer = $signature.SignerCertificate.Issuer
    if (($subject -notmatch 'Microsoft') -and ($issuer -notmatch 'Microsoft')) {
        Add-VerificationError "$PackageId is not signed by Microsoft. Subject: $subject"
    }
}

function Test-DownloadUrl {
    param(
        [Parameter(Mandatory = $true)][string] $PackageId,
        [AllowNull()][object] $DownloadUrl
    )

    if ($null -eq $DownloadUrl -or [string]::IsNullOrWhiteSpace([string] $DownloadUrl)) {
        return
    }

    try {
        $uri = [Uri] [string] $DownloadUrl
    } catch {
        Add-VerificationError "$PackageId has an invalid download URL: $DownloadUrl"
        return
    }

    if ($uri.Scheme -ne 'https') {
        Add-VerificationError "$PackageId download URL must use HTTPS: $DownloadUrl"
    }

    if ($AllowedHosts -notcontains $uri.Host.ToLowerInvariant()) {
        Add-VerificationError "$PackageId download host is not allowlisted: $($uri.Host)"
    }
}

if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
    Add-VerificationError "Missing metadata file: $MetadataPath"
}

$metadata = $null
if ($Errors.Count -eq 0) {
    try {
        $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
    } catch {
        Add-VerificationError "Could not parse metadata/redists.json: $($_.Exception.Message)"
    }
}

$packages = @()
if ($null -ne $metadata) {
    if (-not (Test-Property -InputObject $metadata -Name 'packages')) {
        Add-VerificationError 'metadata/redists.json is missing packages.'
    } else {
        $packages = @($metadata.packages)
    }
}

$ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$metadataPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$allowedSets = @('modern', 'legacy', 'discontinued')
$allowedArchitectures = @('x86', 'x64', 'arm', 'arm64', 'ia64')

foreach ($package in $packages) {
    $required = @('id', 'family', 'displayName', 'architecture', 'path', 'installArgs', 'set', 'supportStatus', 'updateEnabled')
    foreach ($propertyName in $required) {
        if (-not (Test-Property -InputObject $package -Name $propertyName)) {
            Add-VerificationError "Package entry is missing required property: $propertyName"
        }
    }

    if (-not (Test-Property -InputObject $package -Name 'id')) {
        continue
    }

    $packageId = [string] $package.id
    if ([string]::IsNullOrWhiteSpace($packageId)) {
        Add-VerificationError 'A package has an empty id.'
        continue
    }

    if (-not $ids.Add($packageId)) {
        Add-VerificationError "Duplicate package id: $packageId"
    }

    if (Test-Property -InputObject $package -Name 'set') {
        if ($allowedSets -notcontains [string] $package.set) {
            Add-VerificationError "$packageId has an invalid set: $($package.set)"
        }
    }

    if (Test-Property -InputObject $package -Name 'architecture') {
        if ($allowedArchitectures -notcontains [string] $package.architecture) {
            Add-VerificationError "$packageId has an invalid architecture: $($package.architecture)"
        }
    }

    if (Test-Property -InputObject $package -Name 'path') {
        $normalizedPath = Test-RedistPath -PackageId $packageId -Path ([string] $package.path)
        if ($normalizedPath) {
            if (-not $metadataPaths.Add($normalizedPath)) {
                Add-VerificationError "Duplicate package path in metadata: $normalizedPath"
            }
        }
    }

    if (Test-Property -InputObject $package -Name 'downloadUrl') {
        Test-DownloadUrl -PackageId $packageId -DownloadUrl $package.downloadUrl
    }

    if ((Test-Property -InputObject $package -Name 'updateEnabled') -and ([bool] $package.updateEnabled)) {
        $isModernVc14 = ((Test-Property -InputObject $package -Name 'set') -and ([string] $package.set -eq 'modern')) -and
            ((Test-Property -InputObject $package -Name 'family') -and ([string] $package.family -eq 'vc14')) -and
            ((Test-Property -InputObject $package -Name 'downloadUrl') -and -not [string]::IsNullOrWhiteSpace([string] $package.downloadUrl))

        if (-not $isModernVc14) {
            Add-VerificationError "$packageId has updateEnabled=true outside the active vc14 family."
        }
    }
}

$hashes = Read-HashManifest -Path $HashPath
$targetArchitectures = Resolve-TargetArchitectures -RequestedArchitecture $Architecture

$selectedPackages = @($packages | Where-Object {
    $packageForSelection = $_
    $includeSet = $false
    switch ($PackageGroup) {
        'all' { $includeSet = ($packageForSelection.set -ne 'discontinued') }
        'everything' { $includeSet = $true }
        default { $includeSet = ($packageForSelection.set -eq $PackageGroup) }
    }

    $includeSet -and ($targetArchitectures -contains [string] $packageForSelection.architecture)
})

foreach ($package in $selectedPackages) {
    $packageId = [string] $package.id
    $normalizedPath = Test-RedistPath -PackageId $packageId -Path ([string] $package.path)
    if (-not $normalizedPath) {
        continue
    }

    $absolutePath = Join-Path $RepoRoot ($normalizedPath.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        Add-VerificationError "$packageId is missing: $normalizedPath"
        continue
    }

    $file = Get-Item -LiteralPath $absolutePath
    if ($file.Length -gt $MaxGitHubFileSize) {
        Add-VerificationError "$packageId exceeds GitHub's 100 MB file limit: $normalizedPath"
    }

    $actualHash = Get-Sha256Hash -Path $absolutePath
    if (-not $hashes.ContainsKey($normalizedPath)) {
        Add-VerificationError "$packageId is missing from metadata/SHA256SUMS.txt: $normalizedPath"
    } elseif ($hashes[$normalizedPath] -ne $actualHash) {
        Add-VerificationError "$packageId hash mismatch for $normalizedPath. Expected $($hashes[$normalizedPath]); got $actualHash."
    }

    if (-not $SkipSignature.IsPresent) {
        Assert-MicrosoftSignature -PackageId $packageId -Path $absolutePath
    }
}

$rootExecutables = @(Get-ChildItem -LiteralPath $RepoRoot -File -Filter '*.exe')
foreach ($rootExe in $rootExecutables) {
    Add-VerificationError "Root-level executable is not allowed: $($rootExe.Name)"
}

$fullBundleMode = ($PackageGroup -eq 'everything') -and ($Architecture -eq 'any')
if ($fullBundleMode) {
    $redistExecutables = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'redists') -Recurse -File -Filter '*.exe')
    foreach ($redistExe in $redistExecutables) {
        $relativePath = Resolve-Path -LiteralPath $redistExe.FullName -Relative
        $relativePath = Normalize-RelativePath -Path $relativePath

        if (-not $metadataPaths.Contains($relativePath)) {
            Add-VerificationError "Unreferenced redistributable file: $relativePath"
        }

        if (-not $hashes.ContainsKey($relativePath)) {
            Add-VerificationError "Redistributable file is missing from SHA256SUMS: $relativePath"
        }
    }

    foreach ($manifestPath in $hashes.Keys) {
        $absolutePath = Join-Path $RepoRoot ($manifestPath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            Add-VerificationError "SHA256SUMS references a missing file: $manifestPath"
        }
    }
}

if ($Errors.Count -gt 0) {
    Write-Host 'Bundle verification failed:'
    foreach ($verificationError in $Errors) {
        Write-Host " - $verificationError"
    }
    exit 1
}

Write-Host ("Bundle verification passed. Packages checked: {0}. Group: {1}. Architecture: {2}." -f $selectedPackages.Count, $PackageGroup, $Architecture)
exit 0
