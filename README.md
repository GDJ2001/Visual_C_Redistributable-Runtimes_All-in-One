# Visual C++ Redistributable Runtimes All-in-One

Offline-ready installer bundle for Microsoft Visual C++ Redistributable packages.

This repository keeps redistributable installers under `redists/`, keeps only small launchers and GitHub-standard files in the root, and uses verification scripts to check hashes and Microsoft Authenticode signatures before install or update.

## Quick Start

Run the correctly spelled launcher:

```bat
install_all_at_once.bat
```

When no options are passed, the installer opens an interactive CMD workflow. It auto-detects Windows architecture, installs x86 packages on every Windows system, installs x64 packages on x64 or ARM64 Windows, includes ARM64 VC14 packages on ARM64 Windows, and prevents automatic restarts by default.

## Command-Line Usage

```bat
install_all_at_once.bat /?
install_all_at_once.bat /verify-only
install_all_at_once.bat /dry-run
install_all_at_once.bat /passive /set:all /arch:auto
install_all_at_once.bat /silent /yes /set:modern
install_all_at_once.bat /silent /yes /set:v141
install_all_at_once.bat /silent /yes /set:v142
install_all_at_once.bat /silent /yes /set:v143
install_all_at_once.bat /dry-run /arch:arm64 /set:modern
install_all_at_once.bat /dry-run /arch:any /set:discontinued
install_all_at_once.bat /passive /mode:repair "/log-dir:C:\Temp\VC Logs"
```

Supported options:

| Option | Description |
| --- | --- |
| `/silent` | Run installers quietly where supported. |
| `/passive` | Show passive installer progress. This is the default. |
| `/dry-run` | Preview selected packages without installing. |
| `/verify-only` | Validate selected EXEs, SHA256 hashes, and Microsoft signatures without installing. |
| `/yes` or `/assume-yes` | Confirm prompts for automation. |
| `/no-restart` | Prevent redistributables from restarting Windows. This is the default. |
| `/arch:x86\|x64\|arm\|arm64\|ia64\|any\|auto` | Select package architecture. `auto` is the default. |
| `/set:all\|modern\|legacy\|discontinued\|everything` | Choose the safe default set, VC14 only, legacy only, discontinued only, or every bundled package. |
| `/set:v141\|v142\|v143\|2017\|2019\|2022` | Install the shared VC14 runtime for a specific Visual Studio toolset compatibility target. |
| `/mode:install\|repair` | Install or repair where supported. |
| `/log-dir:<path>` or `/log-dir <path>` | Write summary and package logs to a custom folder. Quote paths that contain spaces. |
| `/?` or `/help` | Show help. |

Dry runs, help, and verification do not require elevation. Real installs request administrator rights only after selected files pass the missing-file check and bundle verification.

## Package Sets

| Set | Included packages |
| --- | --- |
| `all` | Modern VC14 plus legacy x86/x64 packages. This is the default and excludes discontinued packages. |
| `modern` | Current VC14 x86, x64, and ARM64 redistributables. |
| `v141`, `2017`, `vs2017` | Compatibility alias for Visual Studio 2017 / v141 final. Installs the current VC14 packages for the selected architecture. |
| `v142`, `2019`, `vs2019` | Compatibility alias for Visual Studio 2019 / v142 final. Installs the current VC14 packages for the selected architecture. |
| `v143`, `2022`, `vs2022` | Compatibility alias for Visual Studio 2022 / v143 final. Installs the current VC14 packages for the selected architecture. |
| `legacy` | Visual C++ 2005, 2008, 2010, 2012, and 2013 x86/x64 redistributables. |
| `discontinued` | VS.NET-era security updates, IA64/ARM packages, and frozen Visual C++ 2015 Update 3 packages. |
| `everything` | All bundled packages, including discontinued packages. |

The `discontinued` and `everything` sets require confirmation unless `/silent`, `/yes`, or `/assume-yes` is used.

## Repository Layout

```text
.
|-- install_all_at_once.bat       # Correct launcher
|-- scripts/
|   |-- install-core.bat          # Main installer workflow
|   |-- update-redists.ps1        # Microsoft download/update helper
|   `-- verify-bundle.ps1         # Local bundle validation
|-- redists/                      # Bundled offline redistributables
|   |-- 2002/
|   |-- 2003/
|   |-- 2005/
|   |-- 2008/
|   |-- 2010/
|   |-- 2012/
|   |-- 2013/
|   |-- 2015/
|   `-- vc14/
`-- metadata/
    |-- redists.json
    `-- SHA256SUMS.txt
```

## Toolset Compatibility Targets

Visual Studio 2017, 2019, and 2022 use the shared VC14 redistributable family. These targets are included as installer aliases and metadata entries so users can choose the version their application mentions without storing duplicate EXEs.

| Target | Servicing baseline | Platform toolset | Installer set | Supported until |
| --- | --- | --- | --- | --- |
| Visual Studio 2017 / v141 final | 15.9 | v141 | `modern` / VC14 | 2027-04-13 |
| Visual Studio 2019 / v142 final | 16.11 | v142 | `modern` / VC14 | 2029-04-10 |
| Visual Studio 2022 / v143 final | 17.14 | v143 | `modern` / VC14 | 2032-01-13 |

Microsoft references:

- Latest supported VC++ redistributable downloads: `https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist`
- Visual Studio product lifecycle and servicing: `https://learn.microsoft.com/en-us/visualstudio/productinfo/vs-servicing`
- Visual Studio 2017 lifecycle: `https://learn.microsoft.com/en-us/lifecycle/products/visual-studio-2017`
- Visual Studio 2019 lifecycle: `https://learn.microsoft.com/en-us/lifecycle/products/visual-studio-2019`
- Visual Studio 2022 lifecycle: `https://learn.microsoft.com/en-us/lifecycle/products/visual-studio-2022`

## Bundled Packages

| Family | Architectures | Status |
| --- | --- | --- |
| Visual Studio .NET 2002 MFC70 security update | x86 | Discontinued, opt-in only |
| Visual Studio .NET 2003 MFC security update | x86 | Discontinued, opt-in only |
| Visual C++ 2005 | x86, x64 | Legacy bundled package |
| Visual C++ 2005 | IA64 | Discontinued architecture, opt-in only |
| Visual C++ 2008 | x86, x64 | Legacy bundled package |
| Visual C++ 2008 | IA64 | Discontinued architecture, opt-in only |
| Visual C++ 2010 | x86, x64 | Legacy bundled package |
| Visual C++ 2010 | IA64 | Discontinued architecture, opt-in only |
| Visual C++ 2012 | x86, x64 | Legacy bundled package |
| Visual C++ 2012 | ARM | Discontinued architecture, opt-in only |
| Visual C++ 2013 | x86, x64 | Legacy bundled package |
| Visual C++ 2015 Update 3 | x86, x64 | Frozen/discontinued, opt-in only |
| Visual C++ 2015-2026 / VC14 | x86, x64, ARM64 | Actively updated through Microsoft permalinks; covers VS 2017/v141, VS 2019/v142, and VS 2022/v143 compatibility targets |

The actively updated VC14 files use Microsoft download permalinks:

- `https://aka.ms/vc14/vc_redist.x86.exe`
- `https://aka.ms/vc14/vc_redist.x64.exe`
- `https://aka.ms/vc14/vc_redist.arm64.exe`

Microsoft notes that Visual Studio 2017 and later share the same VC14 redistributable family, and that the x64 VC14 package also contains ARM64 binaries for ARM64 devices. This repository still bundles the separate ARM64 installer so ARM64 Windows users can install it directly when needed.

## Verification

Run a full local verification:

```powershell
pwsh -NoProfile -File scripts\verify-bundle.ps1
```

The verifier checks:

- `metadata/redists.json` schema and package IDs.
- Paths stay under `redists/` and do not use path traversal.
- No redistributable EXEs are stored in the repository root.
- Every selected EXE exists, matches `metadata/SHA256SUMS.txt`, is under 100 MB, and has a valid Microsoft Authenticode signature.
- Update-enabled packages are limited to the active VC14 family.

## GitHub Cloud Updates

The workflow at `.github/workflows/update-redists.yml` runs weekly or manually. It reads `metadata/redists.json`, downloads update-enabled packages from Microsoft-controlled hosts, validates Microsoft signatures, compares versions and SHA256 hashes, regenerates `metadata/SHA256SUMS.txt`, verifies the final bundle, and opens a pull request when files change.

Repository setting needed:

1. Open GitHub repository settings.
2. Go to **Actions** > **General**.
3. Enable workflow write permissions for `GITHUB_TOKEN`.
4. Allow GitHub Actions to create pull requests.

Discontinued packages are kept for compatibility and are not automatically updated. The modern VC14 x86, x64, and ARM64 packages are the update-enabled packages.

## Trust Notes

This project is not Microsoft software and is not affiliated with Microsoft. It is a convenience bundle for Microsoft redistributable installers.

Before installing, the hardened workflow validates bundled files against the local SHA256 manifest and requires valid Microsoft Authenticode signatures. For maximum trust, review update pull requests before merging them and compare the changed versions and hashes in the PR body.

Author: GDJ2001
