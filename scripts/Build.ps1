# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$TccRoot)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-WindowsX64
$root = Get-ProjectRoot
$config = Get-ProjectConfig
$compiler = Get-TccPath -TccRoot $TccRoot
$csc = Get-CscPath
$build = Join-Path $root 'build'
$artifacts = Join-Path $root 'artifacts'
[IO.Directory]::CreateDirectory($build) | Out-Null
[IO.Directory]::CreateDirectory($artifacts) | Out-Null
$nativeSource = Join-Path $root 'src\CopyPathCommand.c'
$oleDefinition = Join-Path $root 'src\ole32.def'
& $compiler -shared -O2 -Wall -o (Join-Path $build 'CopyPathCommand.dll') $nativeSource $oleDefinition -luser32 -lkernel32
if ($LASTEXITCODE -ne 0) { throw 'Native DLL compilation failed.' }
& $compiler -shared -O2 -Wall -DCOPY_PATH_TESTING -o (Join-Path $build 'CopyPathCommand.Test.dll') $nativeSource $oleDefinition -luser32 -lkernel32
if ($LASTEXITCODE -ne 0) { throw 'Native test DLL compilation failed.' }
& $compiler '-Wl,-subsystem=windows' -o (Join-Path $build 'CopyAbsolutePath.exe') (Join-Path $root 'src\Host.c') -lkernel32
if ($LASTEXITCODE -ne 0) { throw 'Package host compilation failed.' }
& $csc /nologo /platform:x64 ('/out:' + (Join-Path $build 'Pack.exe')) (Join-Path $root 'tools\Pack.cs')
if ($LASTEXITCODE -ne 0) { throw 'Packaging helper compilation failed.' }
& $csc /nologo /platform:x64 /r:System.Windows.Forms.dll ('/out:' + (Join-Path $build 'Verify.exe')) (Join-Path $root 'tests\Verify.cs')
if ($LASTEXITCODE -ne 0) { throw 'Verification helper compilation failed.' }
# A fresh stage prevents stale files from entering the package.
$stage = Join-Path $build ('stage-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'packaging\Assets') -Destination $stage -Recurse
Copy-Item -LiteralPath (Join-Path $build 'CopyPathCommand.dll'), (Join-Path $build 'CopyAbsolutePath.exe') -Destination $stage
$manifest = [IO.File]::ReadAllText((Join-Path $root 'packaging\AppxManifest.xml'))
$manifest = $manifest.Replace('@VERSION@', $config.version).Replace('@PUBLISHER@', [Security.SecurityElement]::Escape($config.publisher))
[IO.File]::WriteAllText((Join-Path $stage 'AppxManifest.xml'), $manifest, [Text.UTF8Encoding]::new($false))
$package = Get-ArtifactPath
& (Join-Path $build 'Pack.exe') $stage $package
if ($LASTEXITCODE -ne 0) { throw 'MSIX packaging failed.' }
Get-FileHash -LiteralPath $package -Algorithm SHA256 | Format-List Path, Hash
Write-Output 'Build complete. The package is unsigned; run scripts\Sign.ps1 before installation.'
