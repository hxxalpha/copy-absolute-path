# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$PackagePath, [string]$CertificatePath, [switch]$TrustCertificate, [switch]$ValidateOnly)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-WindowsX64
$config = Get-ProjectConfig
$package = Get-ArtifactPath -PackagePath $PackagePath
if (-not (Test-Path -LiteralPath $package)) { throw 'Package not found. Build and sign it first.' }
$identity = Get-PackageIdentity -PackagePath $package
if ($identity.Name -ne $config.packageName -or $identity.Publisher -ne $config.publisher -or $identity.ProcessorArchitecture -ne 'x64') { throw 'Unexpected package identity or architecture.' }
$signature = Get-AuthenticodeSignature -LiteralPath $package
if ($ValidateOnly) {
    [PSCustomObject]@{ Name = $identity.Name; Version = $identity.Version; Architecture = $identity.ProcessorArchitecture; SignatureStatus = $signature.Status }
    return
}
if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -ne $config.publisher -or $signature.Status -eq 'HashMismatch') { throw 'The package must have a matching signature. Run scripts\Sign.ps1 first.' }
$addedTrust = $false
$trustedPath = $null
$temporaryPackage = $null
try {
    if ($TrustCertificate) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) { throw 'Certificate trust requires an elevated PowerShell under the same Windows account. See the README.' }
        if (-not $CertificatePath) { $CertificatePath = [IO.Path]::ChangeExtension($package, '.cer') }
        $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new([IO.Path]::GetFullPath($CertificatePath))
        if ($certificate.Thumbprint -ne $signature.SignerCertificate.Thumbprint -or $certificate.Subject -ne $config.publisher) { throw 'The public certificate does not match the package signer.' }
        $trustedPath = 'Cert:\LocalMachine\TrustedPeople\' + $certificate.Thumbprint
        $addedTrust = -not (Test-Path -LiteralPath $trustedPath)
        if ($addedTrust) { Import-Certificate -FilePath $CertificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null }
    }
    $temporaryPackage = Join-Path $env:TEMP ('CopyAbsolutePath-' + [Guid]::NewGuid().ToString('N') + '.msix')
    Copy-Item -LiteralPath $package -Destination $temporaryPackage
    Add-AppxPackage -Path $temporaryPackage -ForceTargetApplicationShutdown
    $installed = Get-AppxPackage -Name $config.packageName
    if (-not $installed -or $installed.Version -ne [Version]$identity.Version) { throw 'Package registration could not be verified.' }
    Write-Output ('Installed for current user: ' + $installed.PackageFullName)
    Write-Output 'Right-click a file or folder and choose Copy absolute path.'
} catch {
    if ($addedTrust -and $trustedPath -and (Test-Path -LiteralPath $trustedPath)) { Remove-Item -LiteralPath $trustedPath }
    throw
} finally {
    if ($temporaryPackage -and (Test-Path -LiteralPath $temporaryPackage)) { Remove-Item -LiteralPath $temporaryPackage }
}
