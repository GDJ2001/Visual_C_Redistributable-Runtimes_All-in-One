# Security Policy

## Supported Content

This project bundles Microsoft Visual C++ Redistributable installers and scripts that run or update them.

| Area | Support status |
| --- | --- |
| Root launcher scripts | Supported |
| Installer core workflow | Supported |
| Bundle verification script | Supported |
| GitHub update workflow | Supported |
| VC14 x86, x64, and ARM64 redistributables | Updated from Microsoft permalinks |
| VS 2017/v141, VS 2019/v142, VS 2022/v143 targets | Supported as VC14 compatibility aliases |
| Legacy redistributables | Bundled for compatibility only |
| Discontinued packages | Opt-in compatibility packages only |

Legacy redistributables are included because older software may still require them. Some legacy and discontinued runtime families are no longer serviced by Microsoft, so treat them as compatibility packages rather than actively maintained components.

## Trust Model

The repository is designed to stay offline-ready while still making updates reviewable.

- Bundled EXE hashes are published in `metadata/SHA256SUMS.txt`.
- `scripts/verify-bundle.ps1` checks metadata, paths, hashes, root EXE absence, file size limits, and Microsoft Authenticode signatures.
- The installer verifies selected packages before launching any EXE.
- The VS 2017/v141, VS 2019/v142, and VS 2022/v143 entries are compatibility targets for the shared VC14 runtime family, not duplicate runtime payloads.
- The update workflow downloads only from allowlisted Microsoft-controlled hosts and opens a pull request instead of pushing directly to `main`.
- Update pull requests include old and new versions plus full SHA256 hashes.

This project is not Microsoft software and is not affiliated with Microsoft. Vulnerabilities in Microsoft redistributable binaries should be reported to Microsoft.

## Reporting a Vulnerability

Please open a GitHub issue if you find a problem with:

- The batch installer workflow.
- The GitHub update workflow.
- Bundle verification behavior.
- Incorrect package metadata.
- Hash or signature validation.

When reporting an issue, include:

- The package or script name.
- Windows version and CPU architecture.
- The command you ran.
- Relevant log output from the installer summary.
- Any hash or Authenticode verification output.

Do not include secrets, personal access tokens, or private download credentials in issue text or screenshots.

## Local Verification

Run:

```powershell
pwsh -NoProfile -File scripts\verify-bundle.ps1
```

If verification fails, do not install from the bundle until the mismatch is understood and fixed.
