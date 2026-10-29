# Build tools

The repository does not vendor third-party compiler or SDK binaries.

- [TinyCC 0.9.27](https://bellard.org/tcc/) is downloaded from its official GNU Savannah distribution. Consult its bundled COPYING and runtime notices for the LGPL terms and applicable runtime exceptions. The compiler itself is not included in the MSIX.
- [Microsoft.Windows.SDK.BuildTools 10.0.26100.9169](https://www.nuget.org/packages/Microsoft.Windows.SDK.BuildTools/10.0.26100.9169) supplies SignTool when signing is requested. Its Microsoft license accompanies the NuGet package. SDK binaries are not included in the MSIX.
- Windows APIs and the .NET Framework compiler are supplied by the operating system.

Downloaded tools are cached in `.tools/` and excluded from Git. SHA-256 values are pinned in `scripts/Common.ps1`.
