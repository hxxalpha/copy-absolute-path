# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([switch]$Development, [string]$CertificateThumbprint, [string]$SignToolPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-WindowsX64
$config = Get-ProjectConfig
$package = Get-ArtifactPath
if (-not (Test-Path -LiteralPath $package)) { throw 'Run scripts\Build.ps1 first.' }
if ($Development -and $CertificateThumbprint) { throw 'Choose Development or CertificateThumbprint.' }
if ($Development) {
    $certificate = New-SelfSignedCertificate -Type CodeSigningCert -Subject $config.publisher -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(2) -FriendlyName 'CopyAbsolutePath development (local)'
} elseif ($CertificateThumbprint -match '^[0-9a-fA-F]{40}$') {
    $certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $CertificateThumbprint)
} else { throw 'Use -Development for a local test certificate or -CertificateThumbprint for your own certificate.' }
if (-not $certificate.HasPrivateKey -or $certificate.Subject -ne $config.publisher) { throw 'The signing certificate must have a private key and match the configured publisher.' }
$signTool = Get-SignToolPath -SignToolPath $SignToolPath
& $signTool sign /fd SHA256 /sha1 $certificate.Thumbprint /s My $package
if ($LASTEXITCODE -ne 0) { throw 'Package signing failed.' }
$publicCertificate = [IO.Path]::ChangeExtension($package, '.cer')
Export-Certificate -Cert $certificate -FilePath $publicCertificate -Force | Out-Null
Write-Output ('Signed package: ' + $package)
Write-Output ('Public certificate only: ' + $publicCertificate)
Write-Output 'Private keys stay in the Windows certificate store. Trust is not changed by this script.'
