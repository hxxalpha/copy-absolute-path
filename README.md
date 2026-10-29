# Copy Absolute Path

[简体中文](README.zh-CN.md) · English

One feature: add **Copy absolute path** to the **Windows 11 first-level File Explorer context menu**.

Right-click a file or folder to copy its full filesystem path without quotation marks. Select several items to copy one path per line, in selection order. The menu label follows the Windows UI language: Chinese or English.

Requires **Windows 11 x64**. Uses a native C `IExplorerCommand` in a fully packaged MSIX. No background service or network access at runtime.

## Tell your agent

Copy this block into your agent:

```text
Install https://github.com/hxxalpha/copy-absolute-path for my current Windows user.
Read README.md and the scripts before running them. Use 64-bit PowerShell on Windows 11 x64.
Clone the repository, then run the following from its root:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sign.ps1 -Development
Install with the following command in an elevated PowerShell under the SAME Windows account; request Windows UAC consent when needed:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install.ps1 -TrustCertificate
Then verify:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1 -Registered -Clipboard
Confirm that Copy absolute path is in the first-level menu for files and folders.
Tell me the installed version and how to uninstall with scripts\Uninstall.ps1.
Keep private signing keys in the Windows certificate store. This task only installs this extension.
```

## Build and install

Clone this repository and open **64-bit PowerShell** in its directory:

```powershell
git clone https://github.com/hxxalpha/copy-absolute-path.git
cd copy-absolute-path
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sign.ps1 -Development
```

Build downloads pinned TinyCC 0.9.27 from its official distribution and verifies SHA-256. Signing downloads pinned Microsoft Windows SDK signing tools from NuGet and verifies both the archive checksum and SignTool's Microsoft signature. Both downloads stay in the ignored `.tools/` directory. The C# compiler comes from Windows' .NET Framework 4.x; Visual Studio is not required.

The unsigned build and the signed result use the same path: `artifacts/CopyAbsolutePath-1.0.2.0-x64.msix`. Signing also writes a **public certificate** alongside it; the private key is non-exportable and stays in your Windows certificate store.

Open an **administrator PowerShell under the same Windows account**, return to this repository, and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install.ps1 -TrustCertificate
```

`-TrustCertificate` explicitly imports that package's matching public certificate into the machine's **Trusted People** store. This is needed for the self-signed local build. Package registration is for the current user. No Developer Mode or global execution-policy changes are required.

Check the installed extension:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1 -Registered -Clipboard
```

Right-click a file or folder and select **Copy absolute path**. If Explorer has cached the old menu, restart File Explorer and try again.

## Uninstall

Remove the extension for the current user:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall.ps1
```

To also remove the exact development certificate exported with this build, run the following as administrator under the same account:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall.ps1 -RemoveCertificate
```

Keep the matching `.cer` file until certificate cleanup is complete. Source files and build outputs remain in the repository directory.

## Development

- `src/CopyPathCommand.c`: native command and clipboard handling.
- `packaging/AppxManifest.xml`: Windows 11 modern-menu registration.
- `tools/Pack.cs`: package creation through the Windows packaging API.
- `tests/Verify.cs`: native COM, path serialization, lifetime, and optional clipboard integration tests.
- `scripts/`: build, test, sign, install, and uninstall.

Ordinary tests leave the clipboard alone. `-Clipboard` temporarily changes clipboard contents and restores the previous data afterward. Tests use synthetic files only. A Windows CI template is provided in `ci/windows.yml`. It builds and tests unsigned packages; its artifacts must be signed before installation.

An existing compiler can be supplied with `Build.ps1 -TccRoot <directory-containing-tcc.exe>`. Signing can use an existing certificate with `Sign.ps1 -CertificateThumbprint <thumbprint>` and an installed SDK tool with `-SignToolPath <signtool.exe>`. A release signing certificate must match `publisher` in `project.json`. Development self-signing is for local builds; public releases should use an appropriate trusted signing certificate.

Architecture notes: [Microsoft's Windows 11 context-menu integration guide](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer). This project packages the DLL inside the MSIX so installation is independent of the source directory.

## License

[MIT](LICENSE). Build-tool licensing is documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
