# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([switch]$RemoveCertificate, [string]$CertificatePath)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-WindowsX64
$config = Get-ProjectConfig
$certificate = $null
if ($RemoveCertificate) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'Certificate cleanup requires an elevated PowerShell under the same Windows account.' }
    if (-not $CertificatePath) { $CertificatePath = [IO.Path]::ChangeExtension((Get-ArtifactPath), '.cer') }
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new([IO.Path]::GetFullPath($CertificatePath))
    if ($certificate.Subject -ne $config.publisher) { throw 'Unexpected certificate subject.' }
}
Get-AppxPackage -Name $config.packageName | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName }
if ($certificate) {
    $trustedPath = 'Cert:\LocalMachine\TrustedPeople\' + $certificate.Thumbprint
    if (Test-Path -LiteralPath $trustedPath) { Remove-Item -LiteralPath $trustedPath }
    $privatePath = 'Cert:\CurrentUser\My\' + $certificate.Thumbprint
    if (Test-Path -LiteralPath $privatePath) {
        $privateCertificate = Get-Item -LiteralPath $privatePath
        if ($privateCertificate.FriendlyName -eq 'CopyAbsolutePath development (local)') { Remove-Item -LiteralPath $privatePath }
    }
}
Write-Output 'Copy absolute path has been uninstalled for the current user.'
