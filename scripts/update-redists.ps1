[CmdletBinding()]
param(
    [ValidateSet('all', 'modern', 'legacy', 'discontinued', 'everything')]
    [string] $PackageGroup = 'modern',

    [switch] $Force,

    [switch] $CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$MetadataPath = Join-Path $RepoRoot 'metadata/redists.json'
$HashPath = Join-Path $RepoRoot 'metadata/SHA256SUMS.txt'
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ('vc-redist-update-' + [guid]::NewGuid().ToString('N'))
$ReportPath = if ($env:RUNNER_TEMP) {
    Join-Path $env:RUNNER_TEMP 'redist-update-report.md'
} else {
    Join-Path $TempRoot 'redist-update-report.md'
}

$AllowedHosts = @(
    'aka.ms',
    'download.microsoft.com',
    'download.visualstudio.microsoft.com',
    'go.microsoft.com'
)

$MaxGitHubFileSize = 100MB

function Set-GitHubOutput {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Value
    )

    if ($env:GITHUB_OUTPUT) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Name=$Value"
    }
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

function Assert-RedistPath {
    param(
        [Parameter(Mandatory = $true)][string] $PackageId,
        [Parameter(Mandatory = $true)][string] $Path
    )

    $normalized = Normalize-RelativePath -Path $Path

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "$PackageId has an empty path."
    }

    if ([IO.Path]::IsPathRooted($Path) -or ($normalized -match '^[A-Za-z]:') -or $normalized.StartsWith('/')) {
        throw "$PackageId uses an absolute path: $Path"
    }

    if ($normalized -match '(^|/)\.\.(/|$)') {
        throw "$PackageId uses path traversal: $Path"
    }

    if (-not $normalized.StartsWith('redists/', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$PackageId must live under redists/: $Path"
    }

    if (-not $normalized.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$PackageId must point to an .exe file: $Path"
    }

    return $normalized
}

function Assert-AllowedUri {
    param(
        [Parameter(Mandatory = $true)][string] $PackageId,
        [Parameter(Mandatory = $true)][Uri] $Uri
    )

    if ($Uri.Scheme -ne 'https') {
        throw "$PackageId download URL must use HTTPS: $Uri"
    }

    if ($AllowedHosts -notcontains $Uri.Host.ToLowerInvariant()) {
        throw "Refusing to download $PackageId from unapproved host: $($Uri.Host)"
    }
}

function Get-FileVersionText {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    $version = (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
    if ([string]::IsNullOrWhiteSpace($version)) {
        return ''
    }

    return $version.Trim()
}

function ConvertTo-VersionOrNull {
    param([AllowNull()][string] $VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    if ($VersionText -notmatch '\d+(\.\d+){1,3}') {
        return $null
    }

    try {
        return [version] $Matches[0]
    } catch {
        return $null
    }
}

function Assert-MicrosoftSignature {
    param([Parameter(Mandatory = $true)][string] $Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid') {
        throw "Downloaded file failed Authenticode validation: $Path ($($signature.Status))"
    }

    if ($null -eq $signature.SignerCertificate) {
        throw "Downloaded file has no signer certificate: $Path"
    }

    $subject = $signature.SignerCertificate.Subject
    $issuer = $signature.SignerCertificate.Issuer
    if (($subject -notmatch 'Microsoft') -and ($issuer -notmatch 'Microsoft')) {
        throw "Downloaded file is not signed by Microsoft: $Path"
    }
}

function Assert-MetadataSafe {
    param([Parameter(Mandatory = $true)][object[]] $Packages)

    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $allowedSets = @('modern', 'legacy', 'discontinued')
    $allowedArchitectures = @('x86', 'x64', 'arm', 'arm64', 'ia64')

    foreach ($package in $Packages) {
        $required = @('id', 'family', 'displayName', 'architecture', 'path', 'installArgs', 'set', 'supportStatus', 'updateEnabled')
        foreach ($propertyName in $required) {
            if ($package.PSObject.Properties.Name -notcontains $propertyName) {
                throw "Package metadata is missing required property: $propertyName"
            }
        }

        $packageId = [string] $package.id
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            throw 'Package metadata contains an empty id.'
        }

        if (-not $ids.Add($packageId)) {
            throw "Duplicate package id: $packageId"
        }

        if ($allowedSets -notcontains [string] $package.set) {
            throw "$packageId has an invalid set: $($package.set)"
        }

        if ($allowedArchitectures -notcontains [string] $package.architecture) {
            throw "$packageId has an invalid architecture: $($package.architecture)"
        }

        $normalizedPath = Assert-RedistPath -PackageId $packageId -Path ([string] $package.path)
        if (-not $paths.Add($normalizedPath)) {
            throw "Duplicate package path: $normalizedPath"
        }

        if (-not [string]::IsNullOrWhiteSpace([string] $package.downloadUrl)) {
            $uri = [Uri] [string] $package.downloadUrl
            Assert-AllowedUri -PackageId $packageId -Uri $uri
        }

        if ([bool] $package.updateEnabled) {
            $isModernVc14 = ([string] $package.set -eq 'modern') -and
                ([string] $package.family -eq 'vc14') -and
                (-not [string]::IsNullOrWhiteSpace([string] $package.downloadUrl))

            if (-not $isModernVc14) {
                throw "$packageId has updateEnabled=true outside the active vc14 family."
            }
        }
    }
}

function Write-HashManifest {
    param([Parameter(Mandatory = $true)][string] $Root)

    Push-Location $Root
    try {
        $lines = Get-ChildItem -LiteralPath (Join-Path $Root 'redists') -Recurse -File -Filter '*.exe' |
            Sort-Object FullName |
            ForEach-Object {
                $relative = Resolve-Path -LiteralPath $_.FullName -Relative
                $relative = Normalize-RelativePath -Path $relative
                $hash = Get-Sha256Hash -Path $_.FullName
                "$hash  $relative"
            }
    } finally {
        Pop-Location
    }

    Set-Content -LiteralPath $HashPath -Value $lines -Encoding ascii
}

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

try {
    $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
    $packages = @($metadata.packages)
    Assert-MetadataSafe -Packages $packages

    if (($PackageGroup -ne 'all') -and ($PackageGroup -ne 'everything')) {
        $packages = @($packages | Where-Object { $_.set -eq $PackageGroup })
    }

    $packages = @($packages | Where-Object { $_.updateEnabled -eq $true })
    $changes = New-Object System.Collections.Generic.List[object]
    $checked = New-Object System.Collections.Generic.List[object]

    foreach ($package in $packages) {
        if ([string]::IsNullOrWhiteSpace([string] $package.downloadUrl)) {
            continue
        }

        $packageId = [string] $package.id
        $uri = [Uri] [string] $package.downloadUrl
        Assert-AllowedUri -PackageId $packageId -Uri $uri

        $normalizedPath = Assert-RedistPath -PackageId $packageId -Path ([string] $package.path)
        $destination = Join-Path $RepoRoot ($normalizedPath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $downloadPath = Join-Path $TempRoot ($packageId + '.exe')
        $oldVersion = Get-FileVersionText -Path $destination
        $oldHash = if (Test-Path -LiteralPath $destination -PathType Leaf) {
            Get-Sha256Hash -Path $destination
        } else {
            ''
        }

        Write-Host "Downloading $packageId from $($package.downloadUrl)"
        $response = Invoke-WebRequest -Uri $uri -OutFile $downloadPath -UseBasicParsing -MaximumRedirection 5 -PassThru
        try {
            $finalUri = $response.BaseResponse.RequestMessage.RequestUri
            if ($null -ne $finalUri) {
                Assert-AllowedUri -PackageId $packageId -Uri $finalUri
            }
        } catch {
            throw "Could not validate final download host for $packageId. $($_.Exception.Message)"
        }

        $downloadedFile = Get-Item -LiteralPath $downloadPath
        if ($downloadedFile.Length -gt $MaxGitHubFileSize) {
            throw "$packageId exceeds GitHub's 100 MB file limit after download."
        }

        Assert-MicrosoftSignature -Path $downloadPath

        $newVersion = Get-FileVersionText -Path $downloadPath
        $newHash = Get-Sha256Hash -Path $downloadPath
        $oldParsedVersion = ConvertTo-VersionOrNull -VersionText $oldVersion
        $newParsedVersion = ConvertTo-VersionOrNull -VersionText $newVersion

        if (($null -ne $oldParsedVersion) -and ($null -ne $newParsedVersion) -and ($newParsedVersion -lt $oldParsedVersion) -and (-not $Force.IsPresent)) {
            throw "$packageId download appears to be a downgrade: $oldVersion -> $newVersion. Re-run with -Force only after manual review."
        }

        $changed = ($oldHash -ne $newHash)
        $checked.Add([pscustomobject]@{
            Id = $packageId
            Path = $normalizedPath
            OldVersion = $oldVersion
            NewVersion = $newVersion
            OldHash = $oldHash
            NewHash = $newHash
            Changed = $changed
        }) | Out-Null

        if ($changed -or $Force.IsPresent) {
            if (-not $CheckOnly.IsPresent) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
                Copy-Item -LiteralPath $downloadPath -Destination $destination -Force
            }
        }

        if ($changed) {
            $changes.Add([pscustomobject]@{
                Id = $packageId
                Path = $normalizedPath
                OldVersion = $oldVersion
                NewVersion = $newVersion
                OldHash = $oldHash
                NewHash = $newHash
            }) | Out-Null
        }
    }

    if (($changes.Count -gt 0) -and (-not $CheckOnly.IsPresent)) {
        Write-HashManifest -Root $RepoRoot
    }

    $report = New-Object System.Collections.Generic.List[string]
    $report.Add('# Visual C++ Redistributable Update Report') | Out-Null
    $report.Add('') | Out-Null
    $report.Add(('- Package group: `{0}`' -f $PackageGroup)) | Out-Null
    $report.Add(('- Force update: `{0}`' -f $Force.IsPresent)) | Out-Null
    $report.Add(('- Check only: `{0}`' -f $CheckOnly.IsPresent)) | Out-Null
    $report.Add('') | Out-Null

    if ($checked.Count -eq 0) {
        $report.Add('No update-enabled redistributables matched this package group.') | Out-Null
    } elseif ($changes.Count -eq 0) {
        $report.Add('No redistributable changes were detected.') | Out-Null
    } else {
        $report.Add('| Package | Path | Old version | New version | Old SHA256 | New SHA256 |') | Out-Null
        $report.Add('| --- | --- | --- | --- | --- | --- |') | Out-Null
        foreach ($change in $changes) {
            $oldHash = if ($change.OldHash) { $change.OldHash } else { 'missing' }
            $newHash = if ($change.NewHash) { $change.NewHash } else { 'missing' }
            $report.Add(('| `{0}` | `{1}` | `{2}` | `{3}` | `{4}` | `{5}` |' -f $change.Id, $change.Path, $change.OldVersion, $change.NewVersion, $oldHash, $newHash)) | Out-Null
        }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
    Set-Content -LiteralPath $ReportPath -Value $report -Encoding utf8

    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($report -join [Environment]::NewLine)
    }

    $changedOutput = if ($changes.Count -gt 0) { 'true' } else { 'false' }
    Set-GitHubOutput -Name 'changed' -Value $changedOutput
    Set-GitHubOutput -Name 'report_path' -Value $ReportPath

    $report | ForEach-Object { Write-Host $_ }
} finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}
