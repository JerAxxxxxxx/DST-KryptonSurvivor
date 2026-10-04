param()
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modRoot = Join-Path $projectRoot 'mod'
$distRoot = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
$info = Get-Content -LiteralPath (Join-Path $modRoot 'modinfo.lua') -Raw
if ($info -notmatch 'version\s*=\s*"([0-9.]+)"') { throw 'Mod version was not found.' }
$destination = Join-Path $distRoot ("KryptonSurvivor-{0}.zip" -f $Matches[1])
Compress-Archive -Path (Join-Path $modRoot '*') -DestinationPath $destination -Force
Write-Output $destination
