# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([switch]$Clipboard, [switch]$Registered)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-WindowsX64
$root = Get-ProjectRoot
$build = Join-Path $root 'build'
$verifier = Join-Path $build 'Verify.exe'
if (-not (Test-Path -LiteralPath $verifier)) { throw 'Run scripts\Build.ps1 first.' }
$arguments = @($build)
if ($Clipboard) { $arguments += '--clipboard' }
if ($Registered) { $arguments += '--registered' }
& $verifier @arguments
if ($LASTEXITCODE -ne 0) { throw 'Native integration tests failed.' }
$config = Get-ProjectConfig
$package = Get-ArtifactPath
$identity = Get-PackageIdentity -PackagePath $package
if ($identity.Name -ne $config.packageName -or $identity.Version -ne $config.version -or $identity.ProcessorArchitecture -ne 'x64') { throw 'Package identity does not match project.json.' }
$archive = [IO.Compression.ZipFile]::OpenRead($package)
try {
    $expected = @('AppxManifest.xml', 'AppxBlockMap.xml', '[Content_Types].xml', 'CopyPathCommand.dll', 'CopyAbsolutePath.exe', 'Assets/Logo44.png', 'Assets/Logo50.png', 'Assets/Logo150.png')
    foreach ($name in $expected) { if (-not $archive.GetEntry($name)) { throw ('Missing package file: ' + $name) } }
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName -match '(^|/)(Verify|Pack|.*\.Test)\.|\.pfx$|\.p12$|\.key$') { throw 'Development-only file found in the package.' }
    }
    $reader = [IO.StreamReader]::new($archive.GetEntry('AppxManifest.xml').Open())
    try { $manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ($manifest -notmatch 'windows.fileExplorerContextMenus' -or $manifest -notmatch $config.classId -or $manifest -match 'AllowExternalContent') { throw 'The package must contain a modern, fully packaged context menu extension.' }
    Write-Output 'PASS package identity, contents and modern context menu registration'
} finally { $archive.Dispose() }
Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' | ForEach-Object {
    $tokens = $null; $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) { throw ('PowerShell parse error: ' + $_.Name) }
}
Write-Output 'PASS PowerShell syntax'
