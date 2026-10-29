# SPDX-License-Identifier: MIT
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:CopyPathProjectRoot = Split-Path -Parent $PSScriptRoot
function Get-ProjectRoot { return $script:CopyPathProjectRoot }
function Get-ProjectConfig { return Get-Content -LiteralPath (Join-Path (Get-ProjectRoot) 'project.json') -Raw | ConvertFrom-Json }
function Assert-WindowsX64 {
    if ($env:OS -ne 'Windows_NT' -or [IntPtr]::Size -ne 8 -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Run this project in 64-bit PowerShell on x64 Windows.' }
    if ([Environment]::OSVersion.Version.Build -lt 22000) { throw 'Windows 11 or later is required.' }
}
function Get-CscPath {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework 4.x C# compiler was not found.' }
    return $compiler
}
function Get-ArtifactPath {
    param([string]$PackagePath)
    if ($PackagePath) { return [IO.Path]::GetFullPath($PackagePath) }
    $config = Get-ProjectConfig
    return Join-Path (Get-ProjectRoot) ('artifacts\CopyAbsolutePath-' + $config.version + '-x64.msix')
}
function Get-PinnedArchive {
    param([string]$Uri, [string]$Destination, [string]$Sha256)
    if (-not (Test-Path -LiteralPath $Destination)) {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination)) | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
    }
    if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $Sha256) { throw ('Checksum mismatch: ' + $Destination) }
}
function Get-TccPath {
    param([string]$TccRoot)
    if ($TccRoot) {
        $compiler = Join-Path ([IO.Path]::GetFullPath($TccRoot)) 'tcc.exe'
        if (-not (Test-Path -LiteralPath $compiler)) { throw 'TccRoot must contain tcc.exe.' }
        return $compiler
    }
    $tools = Join-Path (Get-ProjectRoot) '.tools'
    $archive = Join-Path $tools 'tcc-0.9.27-win64-bin.zip'
    Get-PinnedArchive -Uri 'https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27-win64-bin.zip' -Destination $archive -Sha256 '34A721949A2583FDFF725312DA092FA0F5F1F284B702E6F811C6954714FAABB2'
    $compiler = Join-Path $tools 'compiler\tcc\tcc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $tools 'compiler') -Force }
    return $compiler
}
function Get-SignToolPath {
    param([string]$SignToolPath)
    if ($SignToolPath) {
        $path = [IO.Path]::GetFullPath($SignToolPath)
        if (-not (Test-Path -LiteralPath $path)) { throw 'SignToolPath does not exist.' }
    } else {
        $tools = Join-Path (Get-ProjectRoot) '.tools'
        $archive = Join-Path $tools 'windows-sdk-buildtools-10.0.26100.9169.zip'
        Get-PinnedArchive -Uri 'https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.buildtools/10.0.26100.9169/microsoft.windows.sdk.buildtools.10.0.26100.9169.nupkg' -Destination $archive -Sha256 '6000C971FC9155052A8359779B30B6682C39E091664D83B3852C4702AB6D238E'
        $path = Join-Path $tools 'sdk\bin\10.0.26100.0\x64\signtool.exe'
        if (-not (Test-Path -LiteralPath $path)) { Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $tools 'sdk') -Force }
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Corporation(,|$)') { throw 'SignTool must have a valid Microsoft signature.' }
    return $path
}
function Get-PackageIdentity {
    param([string]$PackagePath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $entry = $archive.GetEntry('AppxManifest.xml')
        if (-not $entry -or $entry.Length -gt 1048576) { throw 'Invalid package manifest.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $source = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.LoadXml($source)
        return $document.Package.Identity
    } finally { $archive.Dispose() }
}
